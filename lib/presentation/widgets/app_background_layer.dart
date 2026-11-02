import 'package:flutter/material.dart';
import 'fade_in_background_image.dart';

/// A reusable, high-performance background layer for EventXPro screens.
///
/// Combines:
/// 1. Hardware-accelerated fade-in background image (`assets/images/bg.png`)
/// 2. Multi-point Aurora Glow Orbs for ambient depth
/// 3. Subtle contrast & dark fade overlay
///
/// Designed to be placed as the first child of any [Stack] (with [StackFit.expand]).
class AppBackgroundLayer extends StatelessWidget {
  final String imagePath;
  final Duration duration;
  final Curve curve;
  final bool showAuroraOrbs;
  final bool showContrastOverlay;

  const AppBackgroundLayer({
    super.key,
    this.imagePath = 'assets/images/bg.png',
    this.duration = const Duration(milliseconds: 800),
    this.curve = Curves.easeOutCubic,
    this.showAuroraOrbs = true,
    this.showContrastOverlay = true,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Base background image with hardware-accelerated fade-in entrance
            Positioned.fill(
              child: FadeInBackgroundImage(
                imagePath: imagePath,
                duration: duration,
                curve: curve,
              ),
            ),

            // 2. Multi-point Aurora Glow Orbs for ambient depth
            if (showAuroraOrbs) ...[
              Positioned(
                top: -60,
                right: -50,
                child: Container(
                  width: 280,
                  height: 280,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFFC10067).withValues(alpha: 0.20),
                        const Color(0xFFF43F5E).withValues(alpha: 0.08),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.45, 1.0],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 100,
                left: -80,
                child: Container(
                  width: 290,
                  height: 290,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFF4F46E5).withValues(alpha: 0.18),
                        const Color(0xFF7C3AED).withValues(alpha: 0.08),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.45, 1.0],
                    ),
                  ),
                ),
              ),
            ],

            // 3. Subtle contrast & fade overlay
            if (showContrastOverlay)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0xFF0B0F19).withValues(alpha: 0.65),
                        const Color(0xFF0B0F19).withValues(alpha: 0.50),
                        const Color(0xFF0B0F19).withValues(alpha: 0.85),
                      ],
                      stops: const [0.0, 0.45, 1.0],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

