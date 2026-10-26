import 'dart:io';
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
  AudioFeedbackService._internal() {
    // Disable native audio player creation in headless test environments where platform channels are not mocked
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      isAudioEnabled = false;
    } else {
      _applyGlobalAudioContext();
    }
  }

  bool isAudioEnabled = true;
  AudioPlayer? _player;

  static void _applyGlobalAudioContext() {
    try {
      AudioPlayer.global.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            isSpeakerphoneOn: true,
            stayAwake: false,
            contentType: AndroidContentType.music,
            usageType: AndroidUsageType.media,
            audioFocus: AndroidAudioFocus.none,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: const {
              AVAudioSessionOptions.mixWithOthers,
            },
          ),
        ),
      );
    } catch (e) {
      debugPrint('[AUDIO] global setAudioContext notice: $e');
    }
  }

  AudioPlayer? _getOrCreatePlayer() {
    if (_player != null) return _player!;
    try {
      final player = AudioPlayer();
      player.setReleaseMode(ReleaseMode.stop);
      player.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            isSpeakerphoneOn: true,
            stayAwake: false,
            contentType: AndroidContentType.music,
            usageType: AndroidUsageType.media,
            audioFocus: AndroidAudioFocus.none,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: const {
              AVAudioSessionOptions.mixWithOthers,
            },
          ),
        ),
      );
      _player = player;
      return player;
    } catch (e) {
      debugPrint('[AUDIO] Error initializing AudioPlayer: $e');
      return null;
    }
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
        // Instant low-latency hardware decode acknowledgment (< 5ms)
        try {
          await SystemSound.play(SystemSoundType.click);
          await HapticFeedback.lightImpact();
        } catch (_) {}
        break;
    }
  }

  Future<void> _playAsset(String path) async {
    if (!isAudioEnabled) return;
    debugPrint('[AUDIO] Requesting playback: $path');
    try {
      final player = _getOrCreatePlayer();
      if (player == null) {
        throw Exception('AudioPlayer not available');
      }
      await player.stop();
      await player.setVolume(1.0);
      await player.play(AssetSource(path));
      debugPrint('[AUDIO] Successfully dispatched sound: $path');
    } catch (e) {
      debugPrint('[AUDIO ERROR] Failed to play "$path": $e');
      _player?.dispose();
      _player = null;
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

