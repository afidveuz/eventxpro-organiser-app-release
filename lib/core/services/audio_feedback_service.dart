import 'package:flutter/services.dart';

enum AudioTone {
  success,
  warning,
  error,
  scanBeep,
}

/// Service handling audio chimes and cues for different scan results.
class AudioFeedbackService {
  static final AudioFeedbackService _instance = AudioFeedbackService._internal();
  factory AudioFeedbackService() => _instance;
  AudioFeedbackService._internal();

  bool isAudioEnabled = true;

  Future<void> playTone(AudioTone tone) async {
    if (!isAudioEnabled) return;

    try {
      switch (tone) {
        case AudioTone.success:
          // System sound alert + double click for pleasant acceptance
          await SystemSound.play(SystemSoundType.alert);
          break;
        case AudioTone.warning:
          await SystemSound.play(SystemSoundType.click);
          await Future.delayed(const Duration(milliseconds: 120));
          await SystemSound.play(SystemSoundType.click);
          break;
        case AudioTone.error:
          await SystemSound.play(SystemSoundType.alert);
          break;
        case AudioTone.scanBeep:
          await SystemSound.play(SystemSoundType.click);
          break;
      }
    } catch (_) {
      // Audio playback fails gracefully on systems without audio device
    }
  }
}
