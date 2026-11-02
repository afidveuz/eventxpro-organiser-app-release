import 'package:flutter/material.dart';
import '../../core/config/app_constants.dart';
import 'blinking_offline_button.dart';
import 'fade_in_background_image.dart';

class AppBackground extends StatelessWidget {
  final Widget child;
  final bool disablePadding;
  final bool isOffline;
  final bool animateBackground;
  final Duration animationDuration;

  const AppBackground({
    super.key,
    required this.child,
    this.disablePadding = false,
    this.isOffline = false,
    this.animateBackground = true,
    this.animationDuration = const Duration(milliseconds: 800),
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.brandBg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          AppBackgroundLayer(
            duration: animationDuration,
          ),

          // Offline indicator badge (blinking style matching React Native)
          if (isOffline)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 16,
              child: const BlinkingOfflineButton(),
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
