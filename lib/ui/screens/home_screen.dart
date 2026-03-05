import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'recognition_screen.dart';
import 'register_screen.dart';
import 'student_login_screen.dart';

// ─── Design tokens (shared with recognition & register screens) ───────────────
const Color _kGreen  = Color(0xFF00E676);
const Color _kBlue   = Color(0xFF448AFF);
const Color _kPurple = Color(0xFFAA77FF);
const Color _kBg     = Color(0xFF050510);
const Color _kSurf   = Color(0xFF0D0D1C);

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {

  // Radar sweep
  late final AnimationController _radarCtrl;
  // Pulse rings
  late final AnimationController _pulseCtrl;
  // Staggered entry
  late final AnimationController _entryCtrl;

  static const int _items = 5; // brand + headline + 3 cards

  late final List<Animation<double>> _entryFade;
  late final List<Animation<Offset>>  _entrySlide;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);

    _radarCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 6))
      ..repeat();

    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2800))
      ..repeat();

    _entryCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600));

    _entryFade = List.generate(_items, (i) {
      final s = i * 0.14;
      final e = (s + 0.42).clamp(0.0, 1.0);
      return Tween<double>(begin: 0, end: 1).animate(
          CurvedAnimation(parent: _entryCtrl,
              curve: Interval(s, e, curve: Curves.easeOut)));
    });

    _entrySlide = List.generate(_items, (i) {
      final s = i * 0.14;
      final e = (s + 0.50).clamp(0.0, 1.0);
      return Tween<Offset>(
          begin: const Offset(0, 0.16), end: Offset.zero)
          .animate(CurvedAnimation(parent: _entryCtrl,
          curve: Interval(s, e, curve: Curves.easeOutCubic)));
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _entryCtrl.forward());
  }

  @override
  void dispose() {
    _radarCtrl.dispose();
    _pulseCtrl.dispose();
    _entryCtrl.dispose();
    super.dispose();
  }

  void _go(Widget screen) {
    HapticFeedback.mediumImpact();
    Navigator.push(context, _pageRoute(screen));
  }

  Route _pageRoute(Widget screen) => PageRouteBuilder(
    pageBuilder: (_, __, ___) => screen,
    transitionDuration: const Duration(milliseconds: 450),
    reverseTransitionDuration: const Duration(milliseconds: 320),
    transitionsBuilder: (_, a, __, child) => SlideTransition(
      position: Tween<Offset>(
          begin: const Offset(1, 0), end: Offset.zero)
          .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
      child: child,
    ),
  );

  Widget _reveal(int i, Widget child) => FadeTransition(
    opacity: _entryFade[i],
    child: SlideTransition(position: _entrySlide[i], child: child),
  );

  @override
  Widget build(BuildContext context) {
    final size   = MediaQuery.of(context).size;
    final bottom = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: _kBg,
      body: Stack(children: [
        // ── Animated background ──────────────────────────────────────────────
        Positioned.fill(
          child: AnimatedBuilder(
            animation: Listenable.merge([_radarCtrl, _pulseCtrl]),
            builder: (_, __) => CustomPaint(
              painter: _RadarBgPainter(
                radar: _radarCtrl.value * 2 * math.pi,
                pulse: _pulseCtrl.value,
                size:  size,
              ),
            ),
          ),
        ),

        // ── Scrollable content ───────────────────────────────────────────────
        SafeArea(
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    const SizedBox(height: 16),

                    // Brand bar
                    _reveal(0, _BrandBar(radarCtrl: _radarCtrl)),

                    const SizedBox(height: 30),

                    // Headline
                    _reveal(1, const _Headline()),

                    const SizedBox(height: 32),

                    // Card 1 — Mark Attendance
                    _reveal(2, _CommandCard(
                      tag:     'RECOGNITION',
                      title:   'Mark Attendance',
                      subtitle: 'Live camera kiosk · face scan',
                      icon:    Icons.radar_rounded,
                      accent:  _kGreen,
                      chips:   const ['LIVE', 'ML KIT', '192-DIM'],
                      onTap:   () => _go(const RecognitionScreen()),
                    )),

                    const SizedBox(height: 14),

                    // Card 2 — Enroll
                    _reveal(3, _CommandCard(
                      tag:     'REGISTRATION',
                      title:   'Add New Face',
                      subtitle: 'Capture · embed · store to cloud',
                      icon:    Icons.person_add_alt_1_rounded,
                      accent:  _kBlue,
                      chips:   const ['PHOTO', 'FIRESTORE', 'SECURE'],
                      onTap:   () => _go(const RegisterScreen()),
                    )),

                    const SizedBox(height: 14),

                    // Card 3 — Analytics
                    _reveal(4, _CommandCard(
                      tag:     'ANALYTICS',
                      title:   'View Analytics',
                      subtitle: 'Personal logs · attendance history',
                      icon:    Icons.analytics_rounded,
                      accent:  _kPurple,
                      chips:   const ['LOGS', 'SEARCH', 'EXPORT'],
                      onTap:   () => _go(const StudentLoginScreen()),
                    )),

                    SizedBox(height: bottom + 28),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}

// ─── Radar background painter ─────────────────────────────────────────────────
class _RadarBgPainter extends CustomPainter {
  final double radar, pulse;
  final Size   size;
  _RadarBgPainter({required this.radar, required this.pulse, required this.size});

  @override
  void paint(Canvas canvas, Size cs) {
    // Radar origin — top-right quadrant
    final cx = cs.width * 0.78;
    final cy = cs.height * 0.14;

    final ringPaint = Paint()..style = PaintingStyle.stroke..strokeWidth = 0.6;

    // Static concentric rings
    for (int i = 1; i <= 7; i++) {
      ringPaint.color = _kGreen.withOpacity(0.028 + (i == 4 ? 0.02 : 0));
      canvas.drawCircle(Offset(cx, cy), i * 56.0, ringPaint);
    }

    // Crosshair
    final cross = Paint()..color = _kGreen.withOpacity(0.04)..strokeWidth = 0.6;
    canvas.drawLine(Offset(cx - 450, cy), Offset(cx + 450, cy), cross);
    canvas.drawLine(Offset(cx, cy - 450), Offset(cx, cy + 450), cross);

    // Expanding pulse rings
    for (int i = 0; i < 3; i++) {
      final p  = (pulse + i / 3) % 1.0;
      final r  = p * 420.0;
      final op = (1 - p) * 0.08;
      canvas.drawCircle(
        Offset(cx, cy), r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = _kGreen.withOpacity(op),
      );
    }

    // Sweep wedge
    canvas.drawCircle(
      Offset(cx, cy), 420,
      Paint()
        ..shader = SweepGradient(
          center: Alignment.center,
          startAngle: radar - 1.4,
          endAngle:   radar,
          colors: [Colors.transparent, _kGreen.withOpacity(0.14)],
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: 420))
        ..style = PaintingStyle.fill,
    );

    // Sweep leading edge line
    canvas.drawLine(
      Offset(cx, cy),
      Offset(cx + 420 * math.cos(radar), cy + 420 * math.sin(radar)),
      Paint()..color = _kGreen.withOpacity(0.28)..strokeWidth = 1.2,
    );

    // Center dot
    canvas.drawCircle(Offset(cx, cy), 3.5,
        Paint()..color = _kGreen.withOpacity(0.55));
    canvas.drawCircle(Offset(cx, cy), 9,
        Paint()..color = _kGreen.withOpacity(0.07));

    // Bottom-left subtle mesh grid
    final grid = Paint()..color = _kBlue.withOpacity(0.022)..strokeWidth = 0.5;
    for (double x = 0; x < cs.width * 0.5; x += 28) {
      canvas.drawLine(Offset(x, cs.height * 0.5), Offset(x, cs.height), grid);
    }
    for (double y = cs.height * 0.5; y < cs.height; y += 28) {
      canvas.drawLine(Offset(0, y), Offset(cs.width * 0.5, y), grid);
    }
  }

  @override
  bool shouldRepaint(_RadarBgPainter old) =>
      old.radar != radar || old.pulse != pulse;
}

// ─── Brand bar ────────────────────────────────────────────────────────────────
class _BrandBar extends StatelessWidget {
  final AnimationController radarCtrl;
  const _BrandBar({required this.radarCtrl});

  @override
  Widget build(BuildContext context) => Row(children: [
    // Spinning radar logo
    AnimatedBuilder(
      animation: radarCtrl,
      builder: (_, __) => Transform.rotate(
        angle: radarCtrl.value * 2 * math.pi,
        child: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: _kGreen.withOpacity(0.5), width: 1.5),
          ),
          child: const Icon(Icons.radar, color: _kGreen, size: 18),
        ),
      ),
    ),
    const SizedBox(width: 11),
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('VisionSync',
          style: TextStyle(color: Colors.white, fontSize: 20,
              fontWeight: FontWeight.w800, letterSpacing: -0.2)),
      Text('Attendance Intelligence',
          style: TextStyle(color: Colors.white.withOpacity(0.28),
              fontSize: 10, letterSpacing: 1.1)),
    ]),
    const Spacer(),
    _LivePill(),
  ]);
}

// ─── Live pill ────────────────────────────────────────────────────────────────
class _LivePill extends StatefulWidget {
  @override
  State<_LivePill> createState() => _LivePillState();
}

class _LivePillState extends State<_LivePill> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
  AnimationController(vsync: this, duration: const Duration(milliseconds: 950))
    ..repeat(reverse: true);
  late final Animation<double> _a =
  Tween<double>(begin: 0.25, end: 1.0)
      .animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut));

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _a,
    builder: (_, __) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _kGreen.withOpacity(0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kGreen.withOpacity(0.22)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 6, height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _kGreen.withOpacity(_a.value),
            boxShadow: [
              BoxShadow(color: _kGreen.withOpacity(_a.value * 0.9), blurRadius: 5)
            ],
          ),
        ),
        const SizedBox(width: 6),
        const Text('LIVE',
            style: TextStyle(color: _kGreen, fontSize: 10,
                fontWeight: FontWeight.w800, letterSpacing: 1.3,
                fontFamily: 'monospace')),
      ]),
    ),
  );
}

// ─── Headline ─────────────────────────────────────────────────────────────────
class _Headline extends StatelessWidget {
  const _Headline();
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // Eyebrow
      Row(children: [
        Container(width: 20, height: 1.5,
            color: _kGreen.withOpacity(0.6)),
        const SizedBox(width: 8),
        Text('COMMAND CENTER',
            style: TextStyle(color: _kGreen.withOpacity(0.7),
                fontSize: 10, letterSpacing: 2.0,
                fontWeight: FontWeight.w700, fontFamily: 'monospace')),
      ]),
      const SizedBox(height: 10),
      // Big title
      Text('Welcome\nDashboard',
          style: TextStyle(
            color: Colors.white,
            fontSize: 40,
            fontWeight: FontWeight.w900,
            height: 1.06,
            letterSpacing: -1.2,
            shadows: [
              Shadow(color: _kGreen.withOpacity(0.2), blurRadius: 24),
            ],
          )),
      const SizedBox(height: 10),
      Text('Select an operation below to manage the classroom.',
          style: TextStyle(color: Colors.white.withOpacity(0.38),
              fontSize: 14, height: 1.5)),
    ],
  );
}

// ─── Command Card ─────────────────────────────────────────────────────────────
class _CommandCard extends StatefulWidget {
  final String       tag, title, subtitle;
  final IconData     icon;
  final Color        accent;
  final List<String> chips;
  final VoidCallback onTap;

  const _CommandCard({
    required this.tag, required this.title, required this.subtitle,
    required this.icon, required this.accent, required this.chips,
    required this.onTap,
  });

  @override
  State<_CommandCard> createState() => _CommandCardState();
}

class _CommandCardState extends State<_CommandCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 160));
  late final Animation<double> _scale = Tween<double>(begin: 1.0, end: 0.97)
      .animate(CurvedAnimation(parent: _press, curve: Curves.easeOut));
  late final Animation<double> _glow  = Tween<double>(begin: 0.0, end: 1.0)
      .animate(CurvedAnimation(parent: _press, curve: Curves.easeOut));

  @override
  void dispose() { _press.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;

    return GestureDetector(
      onTapDown:   (_) => _press.forward(),
      onTapUp:     (_) { _press.reverse(); widget.onTap(); },
      onTapCancel: ()  => _press.reverse(),
      child: AnimatedBuilder(
        animation: _press,
        builder: (_, __) => Transform.scale(
          scale: _scale.value,
          child: Container(
            decoration: BoxDecoration(
              color: Color.lerp(_kSurf, accent.withOpacity(0.07), _glow.value),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Color.lerp(
                    accent.withOpacity(0.20), accent.withOpacity(0.55), _glow.value)!,
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withOpacity(0.07 + _glow.value * 0.13),
                  blurRadius: 22 + _glow.value * 12,
                  spreadRadius: -4,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(children: [
                // Corner radial glow
                Positioned(
                  top: -24, right: -24,
                  child: Container(
                    width: 110, height: 110,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(colors: [
                        accent.withOpacity(0.13 + _glow.value * 0.09),
                        Colors.transparent,
                      ]),
                    ),
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                      children: [

                        // ── Top row ──────────────────────────────────────────────
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Tag badge
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: accent.withOpacity(0.10),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: accent.withOpacity(0.22)),
                              ),
                              child: Text(widget.tag,
                                  style: TextStyle(
                                      color: accent,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.5,
                                      fontFamily: 'monospace')),
                            ),
                            const Spacer(),
                            // Icon box
                            Container(
                              width: 50, height: 50,
                              decoration: BoxDecoration(
                                color: accent.withOpacity(0.10),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: accent.withOpacity(0.22)),
                              ),
                              child: Icon(widget.icon, color: accent, size: 24),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // ── Title & subtitle ─────────────────────────────────────
                        Text(widget.title,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 21,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.4)),
                        const SizedBox(height: 4),
                        Text(widget.subtitle,
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.4),
                                fontSize: 13,
                                height: 1.4)),

                        const SizedBox(height: 18),

                        // ── Divider ──────────────────────────────────────────────
                        Container(height: 1,
                            color: accent.withOpacity(0.10 + _glow.value * 0.08)),

                        const SizedBox(height: 14),

                        // ── Chips + arrow ────────────────────────────────────────
                        Row(children: [
                          // Chips
                          Expanded(
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: widget.chips.map((c) => _Chip(
                                  label: c, accent: accent)).toList(),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Arrow button
                          Container(
                            width: 34, height: 34,
                            decoration: BoxDecoration(
                              color: accent
                                  .withOpacity(0.10 + _glow.value * 0.10),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: accent.withOpacity(
                                      0.25 + _glow.value * 0.20)),
                            ),
                            child: Icon(Icons.arrow_forward_rounded,
                                color: accent
                                    .withOpacity(0.75 + _glow.value * 0.25),
                                size: 16),
                          ),
                        ]),
                      ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Chip ─────────────────────────────────────────────────────────────────────
class _Chip extends StatelessWidget {
  final String label;
  final Color  accent;
  const _Chip({required this.label, required this.accent});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: accent.withOpacity(0.07),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: accent.withOpacity(0.15)),
    ),
    child: Text(label,
        style: TextStyle(
            color: accent.withOpacity(0.75),
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            fontFamily: 'monospace')),
  );
}