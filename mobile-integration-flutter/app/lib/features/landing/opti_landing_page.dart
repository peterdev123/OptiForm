import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Opening screen inspired by the provided mockup.
///
/// Layer order:
/// 1) Gradient background
/// 2) Large staggered decorative text (OPTI / FORM)
/// 3) Hero model image
/// 4) Bottom CTA card
class OptiLandingPage extends StatelessWidget {
  const OptiLandingPage({
    required this.onStartNow,
    super.key,
  });

  /// Update this to your local transparent PNG/WebP asset.
  static const String heroAssetPath = 'assets/images/squat_model.png';

  final VoidCallback onStartNow;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final shortestSide = math.min(size.width, size.height);
          final cardHeight = math.max(180.0, size.height * 0.27);
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
            size.height * 0.10,
            math.min(
              midpointBetweenWords - (heroHeight * 0.52),
              size.height - cardHeight - heroHeight + (size.height * 0.08),
            ),
          );

          return Stack(
            clipBehavior: Clip.none,
            children: [
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xFF73DDD9),
                        Color(0xFF8ED5E8),
                        Color(0xFFA9C7F6),
                        Color(0xFFB3BDFB),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -0.35),
                      radius: 1.0,
                      colors: [
                        Colors.white.withValues(alpha: 0.10),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              SafeArea(
                bottom: false,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    margin: const EdgeInsets.only(top: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.30),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(7),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.8),
                              width: 1.3,
                            ),
                          ),
                        ),
                        const SizedBox(width: 5),
                        const Text(
                          'OF',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                            letterSpacing: 0.4,
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
                top: heroTop,
                child: IgnorePointer(
                  child: SizedBox(
                    width: heroWidth * 0.95,
                    height: heroHeight,
                    child: Image.asset(
                      heroAssetPath,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                      errorBuilder: (context, _, __) {
                        return Center(
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 18),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text(
                              'Add your transparent model image at:\nassets/images/squat_model.png',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white, fontSize: 12),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
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
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _BottomCtaCard(
                  height: cardHeight,
                  horizontalPadding: sidePadding,
                  onStartNow: onStartNow,
                ),
              ),
            ],
          );
        },
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
        color: Colors.white.withValues(alpha: 0.88),
        fontSize: fontSize,
        fontWeight: FontWeight.w800,
        fontFamily: 'Roboto',
        fontFamilyFallback: ['Arial', 'Helvetica', 'sans-serif'],
        letterSpacing: -0.9,
        fontStyle: FontStyle.italic,
        height: 0.92,
      ),
    );
  }
}

class _BottomCtaCard extends StatelessWidget {
  const _BottomCtaCard({
    required this.height,
    required this.horizontalPadding,
    required this.onStartNow,
  });

  final double height;
  final double horizontalPadding;
  final VoidCallback onStartNow;

  @override
  Widget build(BuildContext context) {
    final buttonWidth = math.max(108.0, horizontalPadding * 1.95);
    return SafeArea(
      top: false,
      child: Container(
        height: height,
        padding: EdgeInsets.fromLTRB(horizontalPadding, 28, horizontalPadding, 16),
        decoration: const BoxDecoration(
          color: Color(0xFF1F1F23),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(32),
            topRight: Radius.circular(32),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'FIND YOUR\nOPTIMAL FORM',
              style: TextStyle(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.8,
                height: 0.93,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: onStartNow,
              style: OutlinedButton.styleFrom(
                fixedSize: Size(buttonWidth, 38),
                side: const BorderSide(color: Colors.white, width: 1.2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                foregroundColor: Colors.white,
                padding: EdgeInsets.zero,
                textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
              ),
              child: const Text('Start Now'),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}
