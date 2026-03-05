import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

import '../../services/camera_service.dart';
import '../../services/face_detector_service.dart';
import '../../services/ml_service.dart';
import '../../utils/image_converter.dart';
import '../widgets/face_painter.dart';

// ─── Constants ───────────────────────────────────────────────────────────────
const double _kMatchThreshold = 1.25;
const int    _kConfirmFrames  = 2;
const Map<String, int> _mfgOffset = {'huawei': 90, 'honor': 90};

// Shared theme tokens
const Color _kGreen  = Color(0xFF00E676);
const Color _kBg     = Color(0xFF030308);
const Color _kSurface = Color(0xFF0D0D14);

// ─── Helpers ─────────────────────────────────────────────────────────────────
InputImageRotation _toRotation(int deg) {
  switch (deg) {
    case 90:  return InputImageRotation.rotation90deg;
    case 180: return InputImageRotation.rotation180deg;
    case 270: return InputImageRotation.rotation270deg;
    default:  return InputImageRotation.rotation0deg;
  }
}

InputImage _buildInputImage(CameraImage image, int sensorDeg, String brand) {
  if (Platform.isIOS) {
    return InputImage.fromBytes(
      bytes: image.planes[0].bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: InputImageRotation.rotation0deg,
        format: InputImageFormat.bgra8888,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );
  }
  final WriteBuffer buf = WriteBuffer();
  for (final p in image.planes) buf.putUint8List(p.bytes);
  final bytes    = buf.done().buffer.asUint8List();
  final rotation = _toRotation((sensorDeg + (_mfgOffset[brand] ?? 0)) % 360);
  return InputImage.fromBytes(
    bytes: bytes,
    metadata: InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation,
      format: InputImageFormatValue.fromRawValue(image.format.raw) ?? InputImageFormat.yuv420,
      bytesPerRow: image.planes[0].bytesPerRow,
    ),
  );
}

double _euclidean(List<double> a, List<double> b) {
  if (a.length != b.length) return double.maxFinite;
  double sum = 0;
  for (int i = 0; i < a.length; i++) {
    final d = a[i] - b[i];
    sum += d * d;
  }
  return math.sqrt(sum);
}

// ─── Data models ─────────────────────────────────────────────────────────────
class _Student {
  final String       docId, name, department, className, division, photoUrl;
  final List<double> embedding;
  const _Student({
    required this.docId, required this.name, required this.department,
    required this.className, required this.division, required this.photoUrl,
    required this.embedding,
  });
}

enum _ScanState { loadingDB, emptyDB, scanning, noEntry, found }

class _Result {
  final _ScanState state;
  final String?    name, department, className, division, photoUrl;
  final DateTime?  time;
  final double?    distance;

  const _Result._({required this.state, this.name, this.department,
    this.className, this.division, this.photoUrl, this.time, this.distance});
  const _Result.loadingDB() : this._(state: _ScanState.loadingDB);
  const _Result.emptyDB()   : this._(state: _ScanState.emptyDB);
  const _Result.scanning()  : this._(state: _ScanState.scanning);
  const _Result.noEntry()   : this._(state: _ScanState.noEntry);
  _Result.found(_Student s, DateTime t, double dist) : this._(
    state: _ScanState.found, name: s.name, department: s.department,
    className: s.className, division: s.division, photoUrl: s.photoUrl,
    time: t, distance: dist,
  );
}

// ─── Screen ──────────────────────────────────────────────────────────────────
class RecognitionScreen extends StatefulWidget {
  const RecognitionScreen({Key? key}) : super(key: key);
  @override
  State<RecognitionScreen> createState() => _RecognitionScreenState();
}

class _RecognitionScreenState extends State<RecognitionScreen>
    with TickerProviderStateMixin {

  final CameraService       _cam = CameraService();
  final FaceDetectorService _fd  = FaceDetectorService();
  final MLService           _ml  = MLService();

  List<_Student> _students    = [];
  _Result        _result      = const _Result.loadingDB();

  bool   _isProcessing  = false;
  bool   _isInitialized = false;
  bool   _streamRunning = false;
  bool   _isFrontCamera = true;
  bool   _showTelemetry = true;
  String _brand         = '';

  String?   _pendingDocId;
  int       _confirmCount   = 0;
  DateTime? _coolDownUntil;

  // ── Animation controllers ──
  late final AnimationController _boxCtrl;       // drives bounding-box lerp tick
  late final AnimationController _colorCtrl;     // face-box color transition
  late final AnimationController _pulseCtrl;     // enrolled-badge heartbeat
  late final AnimationController _scanlineCtrl;  // sweep line across camera
  late final AnimationController _resultCtrl;    // card slide-in

  late Animation<Color?>  _colorAnim;
  late Animation<double>  _pulseAnim;
  late Animation<double>  _scanlineAnim;
  late Animation<Offset>  _resultSlideAnim;
  late Animation<double>  _resultFadeAnim;

  Rect? _targetRect;
  Rect? _displayRect;
  Size? _imageSize;

  // Telemetry values (updated without full rebuild via separate state)
  String _debugState = 'Initialising…';
  double _debugDist  = 999.0;
  String _debugMatch = '—';

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);

    _boxCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))
      ..addListener(_lerpBox)
      ..repeat();

    _colorCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _setColor(_kGreen, _kGreen);

    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.92, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _scanlineCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 3))
      ..repeat();
    _scanlineAnim = Tween<double>(begin: 0.0, end: 1.0).animate(_scanlineCtrl);

    _resultCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 480));
    _resultSlideAnim = Tween<Offset>(begin: const Offset(0, 0.35), end: Offset.zero)
        .animate(CurvedAnimation(parent: _resultCtrl, curve: Curves.easeOutCubic));
    _resultFadeAnim = CurvedAnimation(parent: _resultCtrl, curve: Curves.easeOut);

    _startUp();
  }

  // ── Frame interpolation ──
  void _lerpBox() {
    if (!mounted) return;
    if (_targetRect == null) {
      if (_displayRect != null) {
        _displayRect = Rect.lerp(
          _displayRect,
          Rect.fromCenter(center: _displayRect!.center, width: 0, height: 0),
          0.18,
        );
        if (_displayRect!.width < 2) _displayRect = null;
      }
    } else {
      _displayRect = _displayRect == null
          ? _targetRect
          : Rect.lerp(_displayRect, _targetRect, 0.22);
    }
  }

  void _setColor(Color from, Color to) {
    _colorAnim = ColorTween(begin: from, end: to).animate(
        CurvedAnimation(parent: _colorCtrl, curve: Curves.easeOut));
    _colorCtrl.forward(from: 0);
  }

  // ── Boot sequence ──
  Future<void> _startUp() async {
    _brand = Platform.isIOS ? 'apple' : () {
      final v = Platform.operatingSystemVersion.toLowerCase();
      for (final b in _mfgOffset.keys) if (v.contains(b)) return b;
      return '';
    }();

    await _cam.initialize();
    final ctrl = _cam.cameraController;
    if (ctrl != null) {
      _isFrontCamera = ctrl.description.lensDirection == CameraLensDirection.front;
      final res = ctrl.value.previewSize;
      if (res != null) _imageSize = Size(res.height, res.width);
    }

    _fd.initialize();
    await _ml.initialize();
    if (mounted) setState(() => _isInitialized = true);

    await _loadDB();
    if (mounted) _startStream();
  }

  Future<void> _loadDB() async {
    if (mounted) setState(() {
      _result     = const _Result.loadingDB();
      _debugState = 'Syncing database…';
    });
    try {
      final snap   = await FirebaseFirestore.instance.collection('students').get();
      final loaded = <_Student>[];
      for (final doc in snap.docs) {
        final d    = doc.data();
        final name = (d['name'] as String?)?.trim() ?? '';
        final raw  = d['faceEmbedding'];
        if (name.isEmpty || raw == null) continue;
        List<double> emb;
        try { emb = List<double>.from(raw as List); } catch (_) { continue; }
        if (emb.length != 192) continue;
        loaded.add(_Student(
          docId:      doc.id,       name:      name,
          department: (d['department'] as String?) ?? '',
          className:  (d['class']      as String?) ?? '',
          division:   (d['division']   as String?) ?? '',
          photoUrl:   (d['photoUrl']   as String?) ?? '',
          embedding:  emb,
        ));
      }
      if (mounted) {
        setState(() {
          _students   = loaded;
          _result     = loaded.isEmpty ? const _Result.emptyDB() : const _Result.scanning();
          _debugState = '${loaded.length} profiles loaded';
        });
        _resultCtrl.forward(from: 0);
      }
    } catch (e) {
      if (mounted) setState(() => _result = const _Result.emptyDB());
    }
  }

  void _startStream() {
    _streamRunning = true;
    _cam.cameraController?.startImageStream((CameraImage image) {
      // Skip frames while busy — no queue buildup
      if (!_isProcessing && _streamRunning) _processFrame(image);
    });
  }

  Future<void> _processFrame(CameraImage image) async {
    _isProcessing = true;
    try {
      final sensorDeg = _cam.cameraController!.description.sensorOrientation;
      final faces     = await _fd.getFaces(_buildInputImage(image, sensorDeg, _brand));

      if (faces.isEmpty) {
        _targetRect   = null;
        _pendingDocId = null;
        _confirmCount = 0;
        _setColor(_colorAnim.value ?? _kGreen, _kGreen);
        if (mounted) setState(() {
          _result     = _students.isEmpty ? const _Result.emptyDB() : const _Result.scanning();
          _debugState = 'Awaiting face…';
          _debugDist  = 999.0;
          _debugMatch = '—';
        });
        return;
      }

      // Largest face wins
      final face = faces.reduce((a, b) =>
      a.boundingBox.width * a.boundingBox.height >=
          b.boundingBox.width * b.boundingBox.height ? a : b);

      final rotation = _toRotation((sensorDeg + (_mfgOffset[_brand] ?? 0)) % 360);
      final portrait = rotation == InputImageRotation.rotation90deg ||
          rotation == InputImageRotation.rotation270deg;
      _targetRect = face.boundingBox;
      _imageSize  = portrait
          ? Size(image.height.toDouble(), image.width.toDouble())
          : Size(image.width.toDouble(), image.height.toDouble());

      if (_students.isEmpty) { if (mounted) setState(() => _result = const _Result.emptyDB()); return; }
      if (_coolDownUntil != null && DateTime.now().isBefore(_coolDownUntil!)) return;

      // Convert + rotate frame
      img.Image? rgbFrame = ImageConverter.convertCameraImage(image);
      if (rgbFrame == null) throw Exception('Frame decode failed');
      final rotAngle = (sensorDeg + (_mfgOffset[_brand] ?? 0)) % 360;
      if (!Platform.isIOS && rotAngle != 0) {
        rgbFrame = img.copyRotate(rgbFrame, angle: rotAngle);
      }

      // Crop face region — feed only face pixels to model
      final r  = face.boundingBox;
      final cx = r.left.toInt().clamp(0, rgbFrame.width);
      final cy = r.top.toInt().clamp(0, rgbFrame.height);
      final cw = r.width.toInt().clamp(1, rgbFrame.width  - cx);
      final ch = r.height.toInt().clamp(1, rgbFrame.height - cy);
      final cropped = img.copyCrop(rgbFrame, x: cx, y: cy, width: cw, height: ch);

      // Embed + nearest-neighbour search
      final liveEmb = _ml.predict(cropped);
      _Student? best;
      double    minDist = double.maxFinite;
      for (final s in _students) {
        final d = _euclidean(liveEmb, s.embedding);
        if (d < minDist) { minDist = d; best = s; }
      }

      if (mounted) setState(() {
        _debugDist  = minDist;
        _debugMatch = best?.name ?? 'Unknown';
        _debugState = minDist < _kMatchThreshold ? 'Confirming…' : 'No match';
      });

      if (best != null && minDist <= _kMatchThreshold) {
        if (_pendingDocId == best.docId) {
          _confirmCount++;
        } else {
          _pendingDocId = best.docId;
          _confirmCount = 1;
        }
        _setColor(_colorAnim.value ?? _kGreen, _kGreen);

        if (_confirmCount >= _kConfirmFrames) {
          final t = await _logAttendance(best);
          _coolDownUntil = DateTime.now().add(const Duration(seconds: 5));
          _pendingDocId  = null;
          _confirmCount  = 0;
          if (mounted) {
            HapticFeedback.mediumImpact();
            setState(() => _result = _Result.found(best!, t, minDist));
            _resultCtrl.forward(from: 0);
          }
        } else {
          if (mounted) setState(() => _result = const _Result.scanning());
        }
      } else {
        _pendingDocId = null;
        _confirmCount = 0;
        _setColor(_colorAnim.value ?? _kGreen, Colors.redAccent);
        if (mounted) setState(() => _result = const _Result.noEntry());
      }
    } catch (e) {
      final msg = e.toString().replaceAll('Exception:', '').trim();
      if (mounted) setState(() => _debugState = msg.length > 46 ? '${msg.substring(0, 43)}…' : msg);
    } finally {
      // 100 ms cooldown — avoids thrashing while keeping response snappy
      await Future.delayed(const Duration(milliseconds: 100));
      _isProcessing = false;
    }
  }

  Future<DateTime> _logAttendance(_Student s) async {
    final now = DateTime.now();
    final ymd = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    try {
      await FirebaseFirestore.instance.collection('attendance').add({
        'studentId':   s.docId,       'studentName': s.name,
        'department':  s.department,  'class':       s.className,
        'division':    s.division,    'photoUrl':    s.photoUrl,
        'timestamp':   FieldValue.serverTimestamp(),
        'date':        ymd,
      });
    } catch (_) {}
    return now;
  }

  @override
  void dispose() {
    _streamRunning = false;
    _cam.cameraController?.stopImageStream().catchError((_) {});
    for (final c in [_boxCtrl, _colorCtrl, _pulseCtrl, _scanlineCtrl, _resultCtrl]) {
      c.dispose();
    }
    _cam.dispose();
    _fd.dispose();
    super.dispose();
  }

  // ─── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (!_isInitialized || _cam.cameraController == null) {
      return const _BootScreen();
    }

    final topPad = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      body: Stack(fit: StackFit.expand, children: [

        // ── Live camera ──
        CameraPreview(_cam.cameraController!),

        // ── Radial vignette ──
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center, radius: 1.05,
                colors: [Colors.transparent, Colors.black.withOpacity(0.55)],
                stops: const [0.5, 1.0],
              ),
            ),
          ),
        ),

        // ── Scanline sweep ──
        IgnorePointer(
          child: AnimatedBuilder(
            animation: _scanlineAnim,
            builder: (_, __) => CustomPaint(
              painter: _ScanlinePainter(_scanlineAnim.value),
            ),
          ),
        ),

        // ── Face bounding box ──
        if (_imageSize != null)
          AnimatedBuilder(
            animation: Listenable.merge([_boxCtrl, _colorCtrl]),
            builder: (_, __) => SizedBox.expand(
              child: CustomPaint(
                painter: FacePainter(
                  animatedRect:  _displayRect,
                  imageSize:     _imageSize!,
                  boxColor:      _colorAnim.value ?? _kGreen,
                  isFrontCamera: _isFrontCamera,
                  label: _result.state == _ScanState.found ? _result.name : null,
                ),
              ),
            ),
          ),

        // ── Top app bar ──
        Positioned(
          top: 0, left: 0, right: 0,
          child: _TopBar(
            topPad:      topPad,
            enrolled:    _students.length,
            pulseAnim:   _pulseAnim,
            showTelemetry: _showTelemetry,
            onToggleTelemetry: () => setState(() => _showTelemetry = !_showTelemetry),
            onReload: () async {
              _streamRunning = false;
              await _cam.cameraController?.stopImageStream().catchError((_) {});
              await _loadDB();
              if (mounted) _startStream();
            },
            onEnroll: () async {
              _streamRunning = false;
              await _cam.cameraController?.stopImageStream().catchError((_) {});
              await Navigator.pushNamed(context, '/register');
              await _loadDB();
              if (mounted) _startStream();
            },
          ),
        ),

        // ── Telemetry HUD ──
        Positioned(
          top: topPad + 68, left: 12, right: 12,
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            offset: _showTelemetry ? Offset.zero : const Offset(0, -0.3),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 280),
              opacity: _showTelemetry ? 1.0 : 0.0,
              child: _TelemetryHUD(
                state: _debugState,
                match: _debugMatch,
                dist:  _debugDist,
                limit: _kMatchThreshold,
              ),
            ),
          ),
        ),

        // ── Status card ──
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: SlideTransition(
            position: _resultSlideAnim,
            child: FadeTransition(
              opacity: _resultFadeAnim,
              child: _StatusCard(result: _result),
            ),
          ),
        ),
      ]),
    );
  }
}

// ─── Top App Bar ─────────────────────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  final double   topPad;
  final int      enrolled;
  final Animation<double> pulseAnim;
  final bool     showTelemetry;
  final VoidCallback onToggleTelemetry, onReload, onEnroll;

  const _TopBar({
    required this.topPad, required this.enrolled, required this.pulseAnim,
    required this.showTelemetry, required this.onToggleTelemetry,
    required this.onReload, required this.onEnroll,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(top: topPad),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Colors.black.withOpacity(0.72), Colors.transparent],
        ),
      ),
      child: SizedBox(
        height: 56,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            // Logo
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: _kGreen.withOpacity(0.7), width: 1.5),
              ),
              child: const Icon(Icons.radar, color: _kGreen, size: 17),
            ),
            const SizedBox(width: 10),
            const Text('VisionSync',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800,
                    fontSize: 17, letterSpacing: 0.3)),
            const Spacer(),
            // Enrolled indicator
            AnimatedBuilder(
              animation: pulseAnim,
              builder: (_, __) => Transform.scale(
                scale: enrolled > 0 ? pulseAnim.value : 1.0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: enrolled > 0 ? _kGreen.withOpacity(0.1) : Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: enrolled > 0 ? _kGreen.withOpacity(0.5) : Colors.white12,
                    ),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 5, height: 5,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: enrolled > 0 ? _kGreen : Colors.white24,
                        boxShadow: enrolled > 0
                            ? [BoxShadow(color: _kGreen.withOpacity(0.8), blurRadius: 4)]
                            : null,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text('$enrolled',
                        style: TextStyle(
                          color: enrolled > 0 ? _kGreen : Colors.white38,
                          fontSize: 12, fontWeight: FontWeight.w800, fontFamily: 'monospace',
                        )),
                  ]),
                ),
              ),
            ),
            const SizedBox(width: 4),
            // Telemetry toggle
            _iconBtn(
              icon: showTelemetry ? Icons.developer_mode : Icons.developer_mode_outlined,
              color: showTelemetry ? _kGreen : Colors.white38,
              onTap: onToggleTelemetry,
            ),
            // Reload
            _iconBtn(icon: Icons.refresh_rounded, color: Colors.white60, onTap: onReload),
            // Enroll CTA
            GestureDetector(
              onTap: onEnroll,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: _kGreen.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _kGreen.withOpacity(0.45)),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.person_add_alt_1_rounded, color: _kGreen, size: 14),
                  SizedBox(width: 5),
                  Text('Enroll', style: TextStyle(color: _kGreen, fontSize: 12,
                      fontWeight: FontWeight.w700, letterSpacing: 0.2)),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _iconBtn({required IconData icon, required Color color, required VoidCallback onTap}) =>
      GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: color, size: 20),
        ),
      );
}

// ─── Scanline painter ────────────────────────────────────────────────────────
class _ScanlinePainter extends CustomPainter {
  final double t;
  _ScanlinePainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height * t;
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          _kGreen.withOpacity(0.05),
          _kGreen.withOpacity(0.13),
          _kGreen.withOpacity(0.05),
          Colors.transparent,
        ],
        stops: const [0, 0.25, 0.5, 0.75, 1],
      ).createShader(Rect.fromLTWH(0, y - 50, size.width, 100));
    canvas.drawRect(Rect.fromLTWH(0, y - 50, size.width, 100), paint);
  }

  @override
  bool shouldRepaint(_ScanlinePainter old) => old.t != t;
}

// ─── Telemetry HUD ───────────────────────────────────────────────────────────
class _TelemetryHUD extends StatelessWidget {
  final String state, match;
  final double dist, limit;
  const _TelemetryHUD({required this.state, required this.match,
    required this.dist, required this.limit});

  @override
  Widget build(BuildContext context) {
    final hit  = dist <= limit && dist < 999;
    final dStr = dist >= 999 ? '——' : dist.toStringAsFixed(4);
    final dColor = hit ? _kGreen : Colors.redAccent;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(13, 9, 13, 11),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.07)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            // Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: _kGreen.withOpacity(0.1),
                borderRadius: BorderRadius.circular(5),
              ),
              child: const Text('AI TELEMETRY',
                  style: TextStyle(color: _kGreen, fontSize: 9,
                      fontWeight: FontWeight.w800, letterSpacing: 1.6,
                      fontFamily: 'monospace')),
            ),
            const Spacer(),
            _LiveDot(),
          ]),
          const SizedBox(height: 7),
          _hudRow('STATUS', state,       Colors.white70),
          const SizedBox(height: 3),
          _hudRow('MATCH',  match,       Colors.white70),
          const SizedBox(height: 3),
          _hudRow('DIST',   '$dStr  /  $limit', dColor),
        ]),
      ),
    );
  }

  Widget _hudRow(String k, String v, Color vc) => Row(children: [
    SizedBox(width: 50, child: Text(k,
        style: TextStyle(color: Colors.white.withOpacity(0.28), fontSize: 10,
            fontFamily: 'monospace', letterSpacing: 0.8))),
    Text('›', style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 10)),
    const SizedBox(width: 5),
    Expanded(child: Text(v, overflow: TextOverflow.ellipsis,
        style: TextStyle(color: vc, fontSize: 11,
            fontWeight: FontWeight.w600, fontFamily: 'monospace'))),
  ]);
}

class _LiveDot extends StatefulWidget {
  @override
  State<_LiveDot> createState() => _LiveDotState();
}
class _LiveDotState extends State<_LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
  AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  late final Animation<double> _a = Tween<double>(begin: 0.3, end: 1.0)
      .animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut));

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _a,
    builder: (_, __) => Row(children: [
      Container(width: 5, height: 5,
        decoration: BoxDecoration(shape: BoxShape.circle,
            color: _kGreen.withOpacity(_a.value),
            boxShadow: [BoxShadow(color: _kGreen.withOpacity(_a.value * 0.8), blurRadius: 4)]),
      ),
      const SizedBox(width: 4),
      Text('LIVE', style: TextStyle(color: Colors.white.withOpacity(0.25),
          fontSize: 9, letterSpacing: 1.0, fontFamily: 'monospace')),
    ]),
  );
}

// ─── Status card ─────────────────────────────────────────────────────────────
class _StatusCard extends StatelessWidget {
  final _Result result;
  const _StatusCard({required this.result});

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 380),
    switchInCurve:  Curves.easeOutCubic,
    switchOutCurve: Curves.easeIn,
    transitionBuilder: (child, anim) => FadeTransition(
      opacity: anim,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero)
            .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: child,
      ),
    ),
    child: _buildCard(context),
  );

  Widget _buildCard(BuildContext context) {
    switch (result.state) {
      case _ScanState.loadingDB:
        return _CardShell(key: const ValueKey('loading'), accent: Colors.white24,
            child: _Row(icon: Icons.cloud_sync_rounded, iconColor: Colors.white38,
                title: 'Syncing database…', titleColor: Colors.white54));

      case _ScanState.emptyDB:
        return _CardShell(key: const ValueKey('empty'), accent: Colors.amber,
            child: _Row(icon: Icons.warning_amber_rounded, iconColor: Colors.amber,
                title: 'No students enrolled', titleColor: Colors.amber,
                subtitle: 'Tap Enroll to add the first student.',
                subtitleColor: Colors.amber.shade300));

      case _ScanState.scanning:
        return _CardShell(key: const ValueKey('scanning'), accent: Colors.white24,
            child: _Row(icon: Icons.face_retouching_natural, iconColor: Colors.white38,
                title: 'Scanning…', titleColor: Colors.white70));

      case _ScanState.noEntry:
        return _CardShell(key: const ValueKey('noEntry'), accent: Colors.redAccent,
            child: _Row(icon: Icons.person_off_rounded, iconColor: Colors.redAccent,
                title: 'Not recognised', titleColor: Colors.redAccent,
                subtitle: 'This face is not enrolled in the system.',
                subtitleColor: Colors.red.shade300));

      case _ScanState.found:
        final t   = result.time!;
        final p   = (int v) => v.toString().padLeft(2, '0');
        final ts  = '${p(t.hour)}:${p(t.minute)}:${p(t.second)} '
            '${t.hour < 12 ? 'AM' : 'PM'}  ·  ${t.day}/${t.month}/${t.year}';
        final meta = [
          if ((result.department ?? '').isNotEmpty) result.department!,
          if ((result.className  ?? '').isNotEmpty) 'Class ${result.className}',
          if ((result.division   ?? '').isNotEmpty) 'Div ${result.division}',
          if (result.distance    != null)           'dist ${result.distance!.toStringAsFixed(3)}',
        ].join('  ·  ');

        return _CardShell(key: ValueKey('found_${result.name}'), accent: _kGreen,
            child: _Row(
              photoUrl: result.photoUrl,
              icon: Icons.check_circle_rounded, iconColor: _kGreen,
              title: result.name ?? '', titleColor: Colors.white,
              subtitle: '✓  Attendance recorded  ·  $ts${meta.isNotEmpty ? '\n$meta' : ''}',
              subtitleColor: _kGreen.withOpacity(0.85),
            ));
    }
  }
}

class _CardShell extends StatelessWidget {
  final Color  accent;
  final Widget child;
  const _CardShell({Key? key, required this.accent, required this.child})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      margin: EdgeInsets.fromLTRB(12, 0, 12, bottom + 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF080810).withOpacity(0.94),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: accent.withOpacity(0.4), width: 1.5),
        boxShadow: [
          BoxShadow(color: accent.withOpacity(0.1), blurRadius: 28, spreadRadius: -2),
        ],
      ),
      child: child,
    );
  }
}

class _Row extends StatelessWidget {
  final String?  photoUrl;
  final IconData icon;
  final Color    iconColor, titleColor;
  final String   title;
  final String?  subtitle;
  final Color?   subtitleColor;

  const _Row({
    this.photoUrl, required this.icon, required this.iconColor,
    required this.title, required this.titleColor,
    this.subtitle, this.subtitleColor,
  });

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      if (photoUrl != null && photoUrl!.isNotEmpty)
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(photoUrl!, width: 56, height: 56, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _iconBox()),
        )
      else
        _iconBox(),
      const SizedBox(width: 14),
      Expanded(child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: titleColor, fontSize: 18,
              fontWeight: FontWeight.w700, letterSpacing: -0.2)),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: TextStyle(color: subtitleColor ?? Colors.white54,
                fontSize: 11, height: 1.55)),
          ],
        ],
      )),
    ],
  );

  Widget _iconBox() => Container(
    width: 56, height: 56,
    decoration: BoxDecoration(
      color: iconColor.withOpacity(0.08),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: iconColor.withOpacity(0.18)),
    ),
    child: Icon(icon, color: iconColor, size: 26),
  );
}

// ─── Boot screen ─────────────────────────────────────────────────────────────
class _BootScreen extends StatelessWidget {
  const _BootScreen();
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _kBg,
    body: Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 68, height: 68,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: _kGreen.withOpacity(0.35), width: 1.5),
          ),
          child: const Icon(Icons.radar, color: _kGreen, size: 30),
        ),
        const SizedBox(height: 28),
        const SizedBox(
          width: 100,
          child: LinearProgressIndicator(
            color: _kGreen, backgroundColor: Colors.white10, minHeight: 1.5,
          ),
        ),
        const SizedBox(height: 18),
        Text('Initialising…',
            style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12,
                fontFamily: 'monospace', letterSpacing: 0.8)),
      ]),
    ),
  );
}