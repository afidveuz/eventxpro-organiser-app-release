import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
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
  AudioPlayer? _player;

  AudioPlayer _getOrCreatePlayer() {
    if (_player != null) return _player!;
    final player = AudioPlayer();
    try {
      player.setReleaseMode(ReleaseMode.stop);
      player.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            isSpeakerphoneOn: false,
            stayAwake: false,
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.assistanceSonification,
            audioFocus: AndroidAudioFocus.none,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.ambient,
            options: const {
              AVAudioSessionOptions.mixWithOthers,
            },
          ),
        ),
      );
    } catch (e) {
      debugPrint('[AUDIO] setAudioContext notice: $e');
    }
    _player = player;
    return player;
  }

  Future<void> playTone(AudioTone tone) async {
    if (!isAudioEnabled) return;

    switch (tone) {
      case AudioTone.success:
        await _playAsset('sounds/successSound.mp3');
        break;
      case AudioTone.warning:
      case AudioTone.error:
        await _playAsset('sounds/errorSound.mp3');
        break;
      case AudioTone.scanBeep:
        // Raw barcode captured: only play feedback after server/offline verification completes
        break;
    }
  }

  Future<void> _playAsset(String path) async {
    debugPrint('[AUDIO] Requesting playback: $path');
    try {
      final player = _getOrCreatePlayer();
      await player.play(AssetSource(path));
      debugPrint('[AUDIO] Successfully dispatched sound: $path');
    } catch (e) {
      debugPrint('[AUDIO ERROR] Failed to play "$path": $e');
      if (e.toString().contains('MissingPluginException')) {
        debugPrint(
            '[AUDIO CAUTION] ⚠️ "audioplayers" native binary not linked in currently running APK. Stop and re-run "flutter run" to compile native audio support into APK.');
      }
      try {
        await SystemSound.play(SystemSoundType.click);
        await HapticFeedback.mediumImpact();
      } catch (_) {}
    }
  }

  void dispose() {
    _player?.dispose();
    _player = null;
  }
}
