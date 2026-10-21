import 'package:flutter/material.dart';
import '../../core/config/app_constants.dart';

class AppBackground extends StatelessWidget {
  final Widget child;
  final bool disablePadding;
  final bool isOffline;

  const AppBackground({
    super.key,
    required this.child,
    this.disablePadding = false,
    this.isOffline = false,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.brandBg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background Image with dark gradient fallback
          Positioned.fill(
            child: Image.asset(
              'assets/images/bg.png',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  decoration: const BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(0, -0.2),
                      radius: 1.2,
                      colors: [
                        Color(0xFF262C40),
                        Color(0xFF131722),
                        Color(0xFF0C1019),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Offline indicator badge (blinking style matching React Native)
          if (isOffline)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF3B30),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x80FF3B30),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: const Text(
                  'Offline Mode',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ),

          // Child content with SafeArea
          SafeArea(
            top: !disablePadding,
            bottom: !disablePadding,
            left: !disablePadding,
            right: !disablePadding,
            child: child,
          ),
        ],
      ),
    );
  }
}
