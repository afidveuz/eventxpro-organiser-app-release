import 'package:flutter/services.dart';

enum HapticPattern {
  success,
  warning,
  error,
}

/// Service handling haptic vibration feedback for Zebra/Android handheld terminals.
class HapticFeedbackService {
  static final HapticFeedbackService _instance = HapticFeedbackService._internal();
  factory HapticFeedbackService() => _instance;
  HapticFeedbackService._internal();

  bool isHapticsEnabled = true;

  Future<void> trigger(HapticPattern pattern) async {
    if (!isHapticsEnabled) return;

    try {
      switch (pattern) {
        case HapticPattern.success:
          await HapticFeedback.mediumImpact();
          break;
        case HapticPattern.warning:
          await HapticFeedback.heavyImpact();
          await Future.delayed(const Duration(milliseconds: 100));
          await HapticFeedback.heavyImpact();
          break;
        case HapticPattern.error:
          await HapticFeedback.vibrate();
          break;
      }
    } catch (_) {
      // Graceful fallback on non-vibrating devices
    }
  }
}
