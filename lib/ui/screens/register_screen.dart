import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

import '../../services/camera_service.dart';
import '../../services/face_detector_service.dart';
import '../../services/ml_service.dart';
import '../widgets/face_painter.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({Key? key}) : super(key: key);
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with SingleTickerProviderStateMixin {

  final CameraService       _cameraService       = CameraService();
  final FaceDetectorService _faceDetectorService = FaceDetectorService();
  final MLService           _mlService           = MLService();

  final _nameCtrl  = TextEditingController();
  final _deptCtrl  = TextEditingController();
  final _classCtrl = TextEditingController();
  final _divCtrl   = TextEditingController();
  final _formKey   = GlobalKey<FormState>();

  bool _isFrameBusy   = false;
  bool _isCapturing   = false;
  bool _isInitialized = false;
  bool _isFrontCamera = true;

  bool          _faceDetected = false;
  List<double>? _embedding;

  bool      _reviewMode    = false;
  bool      _isSaving      = false;
  img.Image? _capturedImage;
  File?      _capturedFile;

  late final AnimationController _boxAnimController;
  Rect? _targetRect;
  Rect? _displayRect;
  Size? _imageSize;

  @override
  void initState() {
    super.initState();
    _boxAnimController = AnimationController(
        vsync: this, duration: const Duration(seconds: 1))
      ..addListener(_interpolateBox)
      ..repeat();
    _startUp();
  }

  void _interpolateBox() {
    if (!mounted) return;
    if (_targetRect == null) {
      if (_displayRect != null) {
        _displayRect = Rect.lerp(_displayRect,
            Rect.fromCenter(center: _displayRect!.center, width: 0, height: 0), 0.15);
        if (_displayRect!.width < 2) _displayRect = null;
      }
    } else {
      _displayRect = _displayRect == null
          ? _targetRect
          : Rect.lerp(_displayRect, _targetRect, 0.18);
    }
  }

  Future<void> _startUp() async {
    await _cameraService.initialize();

    final ctrl = _cameraService.cameraController;
    if (ctrl != null) {
      _isFrontCamera = ctrl.description.lensDirection == CameraLensDirection.front;
    }

    _faceDetectorService.initialize();
    await _mlService.initialize();

    if (mounted) {
      setState(() => _isInitialized = true);
      _startStream();
    }
  }

  void _startStream() {
    _cameraService.cameraController?.startImageStream((CameraImage image) {
      if (!_isFrameBusy && !_reviewMode && !_isCapturing) {
        _processFrame(image);
      }
    });
  }

  Future<void> _processFrame(CameraImage image) async {
    _isFrameBusy = true;
    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final Size imageSize = Size(image.width.toDouble(), image.height.toDouble());
      final int sensorOrientation = _cameraService.cameraController!.description.sensorOrientation;
      final InputImageRotation imageRotation = InputImageRotationValue.fromRawValue(sensorOrientation) ?? InputImageRotation.rotation270deg;
      final InputImageFormat inputImageFormat = InputImageFormatValue.fromRawValue(image.format.raw) ?? InputImageFormat.yuv420;

      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: imageSize,
          rotation: imageRotation,
          format: inputImageFormat,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );

      final faces = await _faceDetectorService.getFaces(inputImage);

      if (faces.isNotEmpty) {
        final face = faces.reduce((a, b) => (a.boundingBox.width * a.boundingBox.height) >= (b.boundingBox.width * b.boundingBox.height) ? a : b);

        final bool isPortrait = imageRotation == InputImageRotation.rotation90deg || imageRotation == InputImageRotation.rotation270deg;
        _imageSize = isPortrait ? Size(image.height.toDouble(), image.width.toDouble()) : imageSize;
        _targetRect = face.boundingBox;

        if (mounted) setState(() => _faceDetected = true);
      } else {
        _targetRect = null;
        if (mounted) setState(() => _faceDetected = false);
      }
    } catch (e) {
      debugPrint('Stream frame error: $e');
    } finally {
      await Future.delayed(const Duration(milliseconds: 100));
      _isFrameBusy = false;
    }
  }

  // --- THE FIX: Bulletproof Capture Sequence ---
  Future<void> _capture() async {
    if (!_faceDetected || _isCapturing) return;

    setState(() => _isCapturing = true);

    try {
      // 1. Safely stop the stream if it's running
      if (_cameraService.cameraController?.value.isStreamingImages ?? false) {
        await _cameraService.cameraController?.stopImageStream();
      }

      // 2. MASSIVE DELAY: Allow the Samsung hardware pipeline to completely clear
      await Future.delayed(const Duration(milliseconds: 800));

      // 3. Take the picture
      final XFile file = await _cameraService.cameraController!.takePicture();

      final rawBytes = await File(file.path).readAsBytes();
      img.Image? decoded = img.decodeImage(rawBytes);
      if (decoded == null) throw Exception("Failed to decode image pixels");
      decoded = img.bakeOrientation(decoded);

      // Verify the face is still in the frame
      final faces = await _faceDetectorService.getFaces(InputImage.fromFilePath(file.path));
      if (faces.isEmpty) {
        _snack('Face moved — try again', error: true);
        _retake();
        return;
      }

      // Generate embedding
      final emb = _mlService.predict(decoded);

      // Save to temporary storage for Firebase
      final tempFile = File('${Directory.systemTemp.path}/reg_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await tempFile.writeAsBytes(img.encodeJpg(decoded, quality: 90));

      if (mounted) {
        setState(() {
          _capturedImage = decoded;
          _capturedFile  = tempFile;
          _embedding     = emb;
          _reviewMode    = true;
          _isCapturing   = false;
        });
      }
    } catch (e) {
      debugPrint('Capture error: $e');
      // THIS WILL SHOW YOU EXACTLY WHY IT FAILED ON SCREEN
      String errorMsg = e.toString().replaceAll('Exception:', '').trim();
      _snack('Error: $errorMsg', error: true);
      _retake();
    }
  }

  void _retake() {
    try { _capturedFile?.deleteSync(); } catch (_) {}
    setState(() {
      _capturedImage = null;
      _capturedFile  = null;
      _reviewMode    = false;
      _faceDetected  = false;
      _isCapturing   = false;
    });
    _startStream();
  }

  Future<void> _upload() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_capturedFile == null || _embedding == null) {
      _snack('No photo — please retake', error: true); return;
    }
    setState(() => _isSaving = true);

    try {
      final docId = DateTime.now().millisecondsSinceEpoch.toString();

      final ref = FirebaseStorage.instance.ref().child('student_photos/$docId.jpg');
      final snap = await ref.putFile(_capturedFile!, SettableMetadata(contentType: 'image/jpeg'));
      final photoUrl = await snap.ref.getDownloadURL();

      await FirebaseFirestore.instance.collection('students').doc(docId).set({
        'id':            docId,
        'name':          _nameCtrl.text.trim(),
        'department':    _deptCtrl.text.trim(),
        'class':         _classCtrl.text.trim(),
        'division':      _divCtrl.text.trim(),
        'photoUrl':      photoUrl,
        'faceEmbedding': _embedding,
        'registeredAt':  FieldValue.serverTimestamp(),
      });

      _snack("'${_nameCtrl.text.trim()}' registered!", error: false);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint('Upload: $e');
      _snack('Upload failed — check connection', error: true);
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _snack(String msg, {required bool error}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.redAccent : Colors.green.shade700,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  @override
  void dispose() {
    _cameraService.cameraController?.stopImageStream().catchError((e){});
    _boxAnimController.dispose();
    _nameCtrl.dispose(); _deptCtrl.dispose();
    _classCtrl.dispose(); _divCtrl.dispose();
    try { _capturedFile?.deleteSync(); } catch (_) {}
    _cameraService.dispose();
    _faceDetectorService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized || _cameraService.cameraController == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.greenAccent),
            SizedBox(height: 16),
            Text('Starting camera…', style: TextStyle(color: Colors.white70)),
          ],
        )),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _reviewMode ? 'Review & Submit' : 'Register Student',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          if (_reviewMode)
            TextButton.icon(
              onPressed: _isSaving ? null : _retake,
              icon: const Icon(Icons.refresh, color: Colors.orangeAccent),
              label: const Text('Retake', style: TextStyle(color: Colors.orangeAccent)),
            ),
        ],
      ),
      body: _reviewMode ? _buildReview() : _buildScanner(),
    );
  }

  Widget _buildScanner() => Column(children: [
    Expanded(child: Stack(fit: StackFit.expand, children: [
      CameraPreview(_cameraService.cameraController!),

      if (_imageSize != null)
        AnimatedBuilder(
          animation: _boxAnimController,
          builder: (_, __) => CustomPaint(
            painter: FacePainter(
              animatedRect:  _displayRect,
              imageSize:     _imageSize!,
              boxColor:      _faceDetected ? Colors.greenAccent : Colors.orangeAccent,
              isFrontCamera: _isFrontCamera,
            ),
          ),
        ),

      if (!_faceDetected)
        IgnorePointer(child: Center(child: Container(
          width: 190, height: 250,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(120),
            border: Border.all(color: Colors.white30, width: 1.5),
          ),
        ))),

      Positioned(top: 16, left: 0, right: 0,
        child: Center(child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _Pill(key: ValueKey(_faceDetected), detected: _faceDetected),
        )),
      ),

      Positioned(bottom: 28, left: 0, right: 0,
        child: Center(child: GestureDetector(
          onTap: _faceDetected && !_isCapturing ? _capture : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 72, height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _faceDetected ? Colors.greenAccent : Colors.white24,
              boxShadow: _faceDetected ? [BoxShadow(color: Colors.greenAccent.withOpacity(0.45), blurRadius: 22, spreadRadius: 4)] : [],
            ),
            child: _isCapturing
                ? const CircularProgressIndicator(color: Colors.black)
                : Icon(Icons.camera_alt, color: _faceDetected ? Colors.black : Colors.white38, size: 32),
          ),
        )),
      ),
    ])),

    Container(
      color: const Color(0xFF12121F),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
      child: Row(children: [
        Icon(Icons.tips_and_updates_outlined, color: Colors.amber.shade300, size: 16),
        const SizedBox(width: 10),
        const Expanded(child: Text('Look straight at camera in good lighting, then tap the button.', style: TextStyle(color: Colors.white54, fontSize: 12))),
      ]),
    ),
  ]);

  Widget _buildReview() => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
    child: Form(
      key: _formKey,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(child: Stack(alignment: Alignment.bottomRight, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: _capturedImage != null
                ? Image.memory(Uint8List.fromList(img.encodeJpg(_capturedImage!)), width: 160, height: 200, fit: BoxFit.cover)
                : Container(width: 160, height: 200, color: Colors.white12, child: const Icon(Icons.person, size: 64, color: Colors.white30)),
          ),
          Container(
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: Colors.greenAccent, borderRadius: BorderRadius.circular(8)),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.check, size: 12, color: Colors.black),
              SizedBox(width: 4),
              Text('Face OK', style: TextStyle(fontSize: 11, color: Colors.black, fontWeight: FontWeight.bold)),
            ]),
          ),
        ])),
        const SizedBox(height: 24),
        const Text('STUDENT DETAILS', style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w600)),
        const SizedBox(height: 14),
        _field(_nameCtrl,  'Full Name',  Icons.person,    required: true),
        const SizedBox(height: 12),
        _field(_deptCtrl,  'Department', Icons.business,  required: true),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _field(_classCtrl, 'Class',    Icons.class_,  required: true)),
          const SizedBox(width: 12),
          Expanded(child: _field(_divCtrl,   'Division', Icons.group,   required: true)),
        ]),
        const SizedBox(height: 28),
        ElevatedButton.icon(
          onPressed: _isSaving ? null : _upload,
          icon: _isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black)) : const Icon(Icons.cloud_upload_outlined),
          label: Text(_isSaving ? 'Uploading…' : 'Register Student'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.greenAccent, foregroundColor: Colors.black,
            disabledBackgroundColor: Colors.greenAccent.withOpacity(0.4),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        if (_isSaving) ...[
          const SizedBox(height: 14),
          const Center(child: Text('Uploading photo & saving to Firestore…', style: TextStyle(color: Colors.white54, fontSize: 13))),
        ],
      ]),
    ),
  );

  Widget _field(TextEditingController ctrl, String label, IconData icon, {bool required = false}) =>
      TextFormField(
        controller: ctrl,
        style: const TextStyle(color: Colors.white),
        textCapitalization: TextCapitalization.words,
        validator: required ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null : null,
        decoration: InputDecoration(
          labelText: label, labelStyle: const TextStyle(color: Colors.grey),
          filled: true, fillColor: Colors.white10,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.greenAccent, width: 1.5)),
          errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.redAccent, width: 1.5)),
          prefixIcon: Icon(icon, color: Colors.greenAccent, size: 20),
        ),
      );
}

class _Pill extends StatelessWidget {
  final bool detected;
  const _Pill({Key? key, required this.detected}) : super(key: key);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
    decoration: BoxDecoration(
      color: Colors.black.withOpacity(0.65),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: detected ? Colors.greenAccent : Colors.orangeAccent, width: 1.5),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(detected ? Icons.check_circle : Icons.face, color: detected ? Colors.greenAccent : Colors.orangeAccent, size: 16),
      const SizedBox(width: 8),
      Text(detected ? 'Face detected — tap shutter  to capture' : 'Position your face in the frame', style: TextStyle(color: detected ? Colors.greenAccent : Colors.orangeAccent, fontWeight: FontWeight.w600, fontSize: 13)),
    ]),
  );
}