import 'dart:math' as math;

import 'package:optiform/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// First-launch welcome screen: gradient hero, motion, and a focused CTA.
///
/// Layer order:
/// 1) Gradient background
/// 2) Large staggered decorative text (OPTI / FORM)
/// 3) Hero model image
/// 4) Bottom CTA card
class OptiLandingPage extends StatefulWidget {
  const OptiLandingPage({
    required this.onStartNow,
    super.key,
  });

  /// Update this to your local transparent PNG/WebP asset.
  static const String heroAssetPath = 'assets/images/squat_model.png';

  final VoidCallback onStartNow;

  @override
  State<OptiLandingPage> createState() => _OptiLandingPageState();
}

class _OptiLandingPageState extends State<OptiLandingPage> with SingleTickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  late final Animation<double> _badgeOpacity = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.0, 0.22, curve: Curves.easeOut),
  );
  late final Animation<double> _wordsOpacity = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.08, 0.42, curve: Curves.easeOut),
  );
  late final Animation<Offset> _wordsSlide = Tween<Offset>(
    begin: const Offset(0, 0.08),
    end: Offset.zero,
  ).animate(CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.08, 0.48, curve: Curves.easeOutCubic),
  ));
  late final Animation<double> _heroOpacity = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.12, 0.52, curve: Curves.easeOut),
  );
  late final Animation<double> _heroScale = Tween<double>(begin: 0.94, end: 1.0).animate(
    CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.12, 0.58, curve: Curves.easeOutCubic),
    ),
  );
  late final Animation<double> _cardOpacity = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.32, 1.0, curve: Curves.easeOut),
  );
  late final Animation<Offset> _cardSlide = Tween<Offset>(
    begin: const Offset(0, 0.12),
    end: Offset.zero,
  ).animate(CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.32, 1.0, curve: Curves.easeOutCubic),
  ));

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
        systemNavigationBarColor: const Color(0xFF1A1A1F),
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarContrastEnforced: false,
      ),
      child: Scaffold(
        body: LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest;
            final shortestSide = math.min(size.width, size.height);
            final cardMinHeight = math.max(200.0, size.height * 0.28);
            final sidePadding = shortestSide * 0.07;
            final titleFontSize = shortestSide * 0.30;
            final heroWidth = size.width * 1.04;
            final heroHeight = size.height * 0.50;
            final optiTop = size.height * 0.12;
            final formTop = size.height * 0.39;
            final optiCenterY = optiTop + (titleFontSize * 0.46);
            final formCenterY = formTop + (titleFontSize * 0.95 * 0.46);
            final midpointBetweenWords = (optiCenterY + formCenterY) / 2;
            final heroTop = math.max(
              viewPadding.top + size.height * 0.04,
              math.min(
                midpointBetweenWords - (heroHeight * 0.52),
                size.height - cardMinHeight - heroHeight + (size.height * 0.06),
              ),
            );
            final headlineSize = (size.width * 0.092).clamp(24.0, 36.0);

            return Stack(
              clipBehavior: Clip.none,
              children: [
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF5FD4D0),
                          Color(0xFF73DDD9),
                          Color(0xFF8ED5E8),
                          Color(0xFFA9C7F6),
                          Color(0xFFC4B8FF),
                        ],
                        stops: [0.0, 0.22, 0.45, 0.72, 1.0],
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(0.15, -0.42),
                        radius: 1.15,
                        colors: [
                          Colors.white.withValues(alpha: 0.14),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.06),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  bottom: false,
                  child: FadeTransition(
                    opacity: _badgeOpacity,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.12),
                                blurRadius: 18,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.white.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(999),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.auto_awesome_rounded,
                                    size: 18,
                                    color: Colors.white.withValues(alpha: 0.95),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'OptiForm',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.96),
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: heroTop,
                  left: 0,
                  right: 0,
                  child: FadeTransition(
                    opacity: _heroOpacity,
                    child: ScaleTransition(
                      scale: _heroScale,
                      child: IgnorePointer(
                        child: SizedBox(
                          width: heroWidth * 0.95,
                          height: heroHeight,
                          child: Image.asset(
                            OptiLandingPage.heroAssetPath,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                            errorBuilder: (context, error, stackTrace) {
                              return Center(
                                child: Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 18),
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.45),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    'Add your transparent model image at:\nassets/images/squat_model.png',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.95),
                                      fontSize: textScaler.scale(12),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: SlideTransition(
                    position: _wordsSlide,
                    child: FadeTransition(
                      opacity: _wordsOpacity,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned(
                            top: optiTop,
                            left: sidePadding,
                            child: _LandingWord(
                              text: 'OPTI',
                              fontSize: titleFontSize,
                            ),
                          ),
                          Positioned(
                            top: formTop,
                            left: sidePadding + (shortestSide * 0.10),
                            child: _LandingWord(
                              text: 'FORM',
                              fontSize: titleFontSize * 0.95,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: SlideTransition(
                    position: _cardSlide,
                    child: FadeTransition(
                      opacity: _cardOpacity,
                      child: _BottomCtaCard(
                        minHeight: cardMinHeight,
                        horizontalPadding: sidePadding,
                        headlineSize: headlineSize,
                        textScaler: textScaler,
                        onStartNow: _handleStart,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LandingWord extends StatelessWidget {
  const _LandingWord({
    required this.text,
    required this.fontSize,
  });

  final String text;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.90),
        fontSize: fontSize,
        fontWeight: FontWeight.w800,
        fontFamily: 'Roboto',
        fontFamilyFallback: const ['Arial', 'Helvetica', 'sans-serif'],
        letterSpacing: -0.9,
        fontStyle: FontStyle.italic,
        height: 0.92,
        shadows: [
          Shadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
    );
  }
}

class _BottomCtaCard extends StatelessWidget {
  const _BottomCtaCard({
    required this.minHeight,
    required this.horizontalPadding,
    required this.headlineSize,
    required this.textScaler,
    required this.onStartNow,
  });

  final double minHeight;
  final double horizontalPadding;
  final double headlineSize;
  final TextScaler textScaler;
  final VoidCallback onStartNow;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return SafeArea(
      top: false,
      child: Material(
        color: const Color(0xFF1A1A1F),
        elevation: 24,
        shadowColor: Colors.black.withValues(alpha: 0.45),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight + bottomInset),
          child: Padding(
            padding: EdgeInsets.fromLTRB(horizontalPadding, 22, horizontalPadding, 14 + bottomInset),
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: textScaler),
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Find your\noptimal form',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: headlineSize,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1.0,
                        height: 0.98,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: const [
                        _BenefitChip(
                          icon: Icons.sensors_rounded,
                          label: 'On-device pose',
                        ),
                        _BenefitChip(
                          icon: Icons.analytics_outlined,
                          label: 'Rep insights',
                        ),
                        _BenefitChip(
                          icon: Icons.chat_bubble_outline_rounded,
                          label: 'Your backend',
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Semantics(
                      button: true,
                      label: 'Get started with OptiForm',
                      child: SizedBox(
                        width: double.infinity,
                        height: 48,
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
                              fontSize: 15,
                              letterSpacing: 0.2,
                            ),
                          ),
                          child: const Text('Get started'),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Set your coaching server in Settings when ready.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.62),
                        fontSize: 12,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
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
