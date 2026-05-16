import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:optiform/theme/app_colors.dart';

/// First-launch welcome: brand gradient, pose illustration, focused CTA.
class OptiLandingPage extends StatefulWidget {
  const OptiLandingPage({
    required this.onStartNow,
    super.key,
  });

  final VoidCallback onStartNow;

  @override
  State<OptiLandingPage> createState() => _OptiLandingPageState();
}

class _OptiLandingPageState extends State<OptiLandingPage> with SingleTickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  );

  late final Animation<double> _fadeIn = CurvedAnimation(
    parent: _intro,
    curve: Curves.easeOut,
  );

  @override
  void initState() {
    super.initState();
    _intro.forward();
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  void _handleStart() {
    HapticFeedback.lightImpact();
    widget.onStartNow();
  }

  @override
  Widget build(BuildContext context) {
    final viewPadding = MediaQuery.paddingOf(context);
    final textScaler = MediaQuery.textScalerOf(context).clamp(
      minScaleFactor: 1.0,
      maxScaleFactor: 1.25,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: const Color(0xFF141A30),
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarContrastEnforced: false,
      ),
      child: Scaffold(
        body: LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest;
            final shortestSide = math.min(size.width, size.height);
            final sidePadding = shortestSide * 0.07;
            final cardMinHeight = math.max(220.0, size.height * 0.30);
            final brandSize = (shortestSide * 0.14).clamp(42.0, 56.0);
            final taglineSize = (shortestSide * 0.042).clamp(14.0, 18.0);
            final heroSize = math.min(size.width * 0.72, size.height * 0.34);

            return FadeTransition(
              opacity: _fadeIn,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFFF4F7FF),
                            Color(0xFFE7EDFF),
                            Color(0xFFD4F5F3),
                            Color(0xFF74E3DE),
                          ],
                          stops: [0.0, 0.35, 0.7, 1.0],
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: const Alignment(0.0, -0.5),
                          radius: 1.0,
                          colors: [
                            AppColors.primary.withValues(alpha: 0.18),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        sidePadding,
                        8,
                        sidePadding,
                        cardMinHeight + viewPadding.bottom + 16,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.22),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.fitness_center_rounded,
                                  color: Color(0xFF4AB8C6),
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Squat form coach',
                                style: TextStyle(
                                  color: const Color(0xFF5A678A),
                                  fontWeight: FontWeight.w600,
                                  fontSize: textScaler.scale(13),
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
                          ),
                          const Spacer(flex: 2),
                          Text(
                            'OptiForm',
                            style: TextStyle(
                              color: const Color(0xFF171C2F),
                              fontSize: brandSize,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1.2,
                              height: 1.0,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Perform with certainty.\nGrow with safety.',
                            style: TextStyle(
                              color: const Color(0xFF4AB8C6),
                              fontSize: taglineSize,
                              fontWeight: FontWeight.w700,
                              height: 1.25,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Center(
                            child: _HeroIllustrationCard(size: heroSize),
                          ),
                          const Spacer(flex: 3),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _BottomCtaCard(
                      minHeight: cardMinHeight,
                      horizontalPadding: sidePadding,
                      textScaler: textScaler,
                      onStartNow: _handleStart,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Side-view squat silhouette with pose joints — no image asset required.
class _HeroIllustrationCard extends StatelessWidget {
  const _HeroIllustrationCard({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size * 0.92,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.8)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4AB8C6).withValues(alpha: 0.12),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: CustomPaint(
          painter: _SquatPosePainter(),
          size: Size(size, size * 0.92),
        ),
      ),
    );
  }
}

class _SquatPosePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Normalized joint positions (side-view squat, bottom of ROM).
    final joints = <Offset>[
      Offset(w * 0.52, h * 0.14), // head
      Offset(w * 0.50, h * 0.26), // shoulder
      Offset(w * 0.48, h * 0.40), // hip
      Offset(w * 0.62, h * 0.52), // knee
      Offset(w * 0.58, h * 0.78), // ankle
      Offset(w * 0.56, h * 0.86), // heel
    ];

    final connections = <List<int>>[
      [0, 1],
      [1, 2],
      [2, 3],
      [3, 4],
      [4, 5],
    ];

    final linePaint = Paint()
      ..color = const Color(0xFF9AA8FF).withValues(alpha: 0.85)
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final jointPaint = Paint()
      ..color = const Color(0xFF74E3DE)
      ..style = PaintingStyle.fill;

    final jointRing = Paint()
      ..color = const Color(0xFF4AB8C6)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final torsoPaint = Paint()
      ..color = const Color(0xFF171C2F).withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;

    // Soft torso guide arc.
    final torsoPath = Path()
      ..moveTo(joints[0].dx, joints[0].dy)
      ..quadraticBezierTo(
        joints[1].dx - w * 0.06,
        (joints[1].dy + joints[2].dy) / 2,
        joints[2].dx,
        joints[2].dy,
      );
    canvas.drawPath(torsoPath, torsoPaint..strokeWidth = 18..style = PaintingStyle.stroke);

    for (final pair in connections) {
      canvas.drawLine(joints[pair[0]], joints[pair[1]], linePaint);
    }

    for (final joint in joints) {
      canvas.drawCircle(joint, 7, jointPaint);
      canvas.drawCircle(joint, 9, jointRing);
    }

    // Barbell hint across shoulders.
    final barY = joints[1].dy - 4;
    canvas.drawLine(
      Offset(w * 0.22, barY),
      Offset(w * 0.78, barY),
      Paint()
        ..color = const Color(0xFF171C2F).withValues(alpha: 0.35)
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );

    // Floor line.
    canvas.drawLine(
      Offset(w * 0.12, h * 0.90),
      Offset(w * 0.88, h * 0.90),
      Paint()
        ..color = const Color(0xFF5A678A).withValues(alpha: 0.25)
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _BottomCtaCard extends StatelessWidget {
  const _BottomCtaCard({
    required this.minHeight,
    required this.horizontalPadding,
    required this.textScaler,
    required this.onStartNow,
  });

  final double minHeight;
  final double horizontalPadding;
  final TextScaler textScaler;
  final VoidCallback onStartNow;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Material(
      color: const Color(0xFF141A30),
      elevation: 20,
      shadowColor: Colors.black.withValues(alpha: 0.35),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: minHeight + bottomInset),
        child: Padding(
          padding: EdgeInsets.fromLTRB(horizontalPadding, 22, horizontalPadding, 14 + bottomInset),
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: textScaler),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Rep-level squat feedback on your phone.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontSize: textScaler.scale(17),
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 14),
                const Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _BenefitChip(icon: Icons.videocam_outlined, label: 'Video analysis'),
                    _BenefitChip(icon: Icons.check_circle_outline, label: 'Form flags'),
                    _BenefitChip(icon: Icons.chat_bubble_outline, label: 'AI coaching'),
                  ],
                ),
                const SizedBox(height: 20),
                Semantics(
                  button: true,
                  label: 'Get started with OptiForm',
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton(
                      onPressed: onStartNow,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: const Color(0xFF0C1226),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          letterSpacing: 0.2,
                        ),
                      ),
                      child: const Text('Get started'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BenefitChip extends StatelessWidget {
  const _BenefitChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppColors.primary),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.88),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
