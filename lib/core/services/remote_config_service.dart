import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import '../config/app_constants.dart';

/// Central service for Firebase Remote Config management.
/// Handles dynamic runtime configuration including:
/// - Default backend API Base URL / Domain
/// - Admin Master Password for unlocking server settings
/// - App version and OTA update thresholds
class RemoteConfigService {
  static final RemoteConfigService _instance = RemoteConfigService._internal();
  factory RemoteConfigService() => _instance;
  RemoteConfigService._internal();

  FirebaseRemoteConfig? _remoteConfig;

  // Remote Config parameter keys
  static const String keyDefaultBaseUrl = 'default_base_url';
  static const String keyDefaultDomain = 'default_domain';
  static const String keyMasterPassword = 'master_password';

  // App Update keys (shared with AppUpdateService)
  static const String keyMinRequiredVersion = 'min_required_version';
  static const String keyMinRequiredBuild = 'min_required_build';
  static const String keyLatestVersion = 'latest_version';
  static const String keyLatestBuild = 'latest_build';
  static const String keyApkDownloadUrl = 'apk_download_url';
  static const String keyReleaseNotes = 'release_notes';

  FirebaseRemoteConfig get remoteConfig =>
      _remoteConfig ?? FirebaseRemoteConfig.instance;

  /// Initializes Remote Config settings and default fallbacks.
  Future<void> initialize() async {
    try {
      _remoteConfig = FirebaseRemoteConfig.instance;

      await _remoteConfig!.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 10),
          // Immediate fetch in debug mode; 15-minute cache in release mode
          minimumFetchInterval:
              kDebugMode ? Duration.zero : const Duration(minutes: 15),
        ),
      );

      await _remoteConfig!.setDefaults({
        // Domain and security defaults
        keyDefaultBaseUrl: AppConstants.defaultBaseUrl,
        keyDefaultDomain: AppConstants.defaultBaseUrl,
        keyMasterPassword: AppConstants.masterPassword,

        // App update defaults
        keyMinRequiredVersion: '1.0.0',
        keyMinRequiredBuild: 1,
        keyLatestVersion: '1.0.0',
        keyLatestBuild: 1,
        keyApkDownloadUrl: '',
        keyReleaseNotes: 'Bug fixes and performance improvements.',
      });

      debugPrint('[RemoteConfigService] Initialized with default settings.');
    } catch (e) {
      debugPrint('[RemoteConfigService] Initialization error: $e');
    }
  }

  /// Fetches and activates latest Remote Config parameters from Firebase.
  Future<bool> fetchAndActivate() async {
    try {
      _remoteConfig ??= FirebaseRemoteConfig.instance;
      final updated = await _remoteConfig!.fetchAndActivate();
      debugPrint('[RemoteConfigService] fetchAndActivate completed (updated: $updated)');
      return updated;
    } catch (e) {
      debugPrint('[RemoteConfigService] fetchAndActivate error: $e');
      return false;
    }
  }

  /// Returns the configured default base URL / domain.
  /// Checks 'default_base_url' first, then 'default_domain', then falls back
  /// to [AppConstants.defaultBaseUrl].
  /// Guarantees a valid http(s) scheme and trailing slash.
  String getDefaultBaseUrl() {
    if (Firebase.apps.isEmpty) {
      return AppConstants.defaultBaseUrl;
    }
    try {
      _remoteConfig ??= FirebaseRemoteConfig.instance;
      String url = _remoteConfig!.getString(keyDefaultBaseUrl).trim();
      if (url.isEmpty) {
        url = _remoteConfig!.getString(keyDefaultDomain).trim();
      }
      if (url.isEmpty) {
        url = AppConstants.defaultBaseUrl;
      }

      // Ensure proper protocol prefix
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        url = 'https://$url';
      }

      // Ensure trailing slash for endpoint concatenation
      if (!url.endsWith('/')) {
        url = '$url/';
      }

      return url;
    } catch (e) {
      debugPrint('[RemoteConfigService] Error reading default base URL: $e');
      return AppConstants.defaultBaseUrl;
    }
  }

  /// Returns the active master password for unlocking Admin Base URL settings.
  /// Falls back to [AppConstants.masterPassword] if unset or offline.
  String getMasterPassword() {
    if (Firebase.apps.isEmpty) {
      return AppConstants.masterPassword;
    }
    try {
      _remoteConfig ??= FirebaseRemoteConfig.instance;
      final pass = _remoteConfig!.getString(keyMasterPassword).trim();
      if (pass.isNotEmpty) {
        return pass;
      }
    } catch (e) {
      debugPrint('[RemoteConfigService] Error reading master password: $e');
    }
    return AppConstants.masterPassword;
  }

  /// Validates an input string against the remote config or fallback default master password.
  bool verifyMasterPassword(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return false;

    final remotePass = getMasterPassword();
    return trimmed == remotePass || trimmed == AppConstants.masterPassword;
  }
}
