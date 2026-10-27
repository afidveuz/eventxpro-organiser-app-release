import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../theme/app_theme.dart';
import '../../presentation/widgets/update_dialog.dart';

enum UpdateType {
  none,
  regular,
  force,
}

class AppUpdateInfo {
  final UpdateType type;
  final String currentVersion;
  final int currentBuildNumber;
  final String latestVersion;
  final int latestBuildNumber;
  final String minRequiredVersion;
  final int minRequiredBuildNumber;
  final String apkUrl;
  final String releaseNotes;

  const AppUpdateInfo({
    required this.type,
    required this.currentVersion,
    required this.currentBuildNumber,
    required this.latestVersion,
    required this.latestBuildNumber,
    required this.minRequiredVersion,
    required this.minRequiredBuildNumber,
    required this.apkUrl,
    required this.releaseNotes,
  });

  bool get isForceUpdate => type == UpdateType.force;
  bool get isRegularUpdate => type == UpdateType.regular;
  bool get hasUpdate => type != UpdateType.none;
}

class AppUpdateService {
  static final AppUpdateService _instance = AppUpdateService._internal();
  factory AppUpdateService() => _instance;
  AppUpdateService._internal();

  FirebaseRemoteConfig? _remoteConfig;

  /// Initializes Remote Config settings and default fallbacks
  Future<void> initialize() async {
    try {
      _remoteConfig = FirebaseRemoteConfig.instance;

      await _remoteConfig!.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 10),
          // Fetch immediately in debug mode; 30-minute cache in release
          minimumFetchInterval:
              kDebugMode ? Duration.zero : const Duration(minutes: 30),
        ),
      );

      await _remoteConfig!.setDefaults(const {
        'min_required_version': '1.0.0',
        'min_required_build': 1,
        'latest_version': '1.0.0',
        'latest_build': 1,
        'apk_download_url': '',
        'release_notes': 'Bug fixes and performance improvements.',
      });

      debugPrint('[AppUpdateService] Initialized successfully.');
    } catch (e) {
      debugPrint('[AppUpdateService] Initialization error: $e');
    }
  }

  /// Fetches latest Remote Config values and determines update status
  Future<AppUpdateInfo> checkForUpdate() async {
    try {
      _remoteConfig ??= FirebaseRemoteConfig.instance;

      // 1. Fetch & activate latest values from Firebase
      await _remoteConfig!.fetchAndActivate();

      // 2. Read current app version & build number from package_info_plus
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      final currentBuild = int.tryParse(packageInfo.buildNumber) ?? 0;

      // 3. Read Remote Config parameters
      final minRequiredVersion =
          _remoteConfig!.getString('min_required_version').trim();
      final minRequiredBuild = _remoteConfig!.getInt('min_required_build');

      final latestVersion = _remoteConfig!.getString('latest_version').trim();
      final latestBuild = _remoteConfig!.getInt('latest_build');

      final apkUrl = _remoteConfig!.getString('apk_download_url').trim();
      final releaseNotes = _remoteConfig!.getString('release_notes').trim();

      debugPrint(
        '[AppUpdateService] Installed: v$currentVersion+$currentBuild | '
        'Min Required: v$minRequiredVersion+$minRequiredBuild | '
        'Latest: v$latestVersion+$latestBuild | '
        'APK URL: $apkUrl',
      );

      // 4. Compare installed version against thresholds
      UpdateType updateType = UpdateType.none;

      // Only evaluate if a valid APK URL exists
      if (apkUrl.isNotEmpty) {
        if (_isOutdated(
          currentVersion: currentVersion,
          currentBuild: currentBuild,
          targetVersion: minRequiredVersion,
          targetBuild: minRequiredBuild,
        )) {
          updateType = UpdateType.force;
        } else if (_isOutdated(
          currentVersion: currentVersion,
          currentBuild: currentBuild,
          targetVersion: latestVersion,
          targetBuild: latestBuild,
        )) {
          updateType = UpdateType.regular;
        }
      }

      return AppUpdateInfo(
        type: updateType,
        currentVersion: currentVersion,
        currentBuildNumber: currentBuild,
        latestVersion: latestVersion.isNotEmpty ? latestVersion : currentVersion,
        latestBuildNumber: latestBuild > 0 ? latestBuild : currentBuild,
        minRequiredVersion: minRequiredVersion,
        minRequiredBuildNumber: minRequiredBuild,
        apkUrl: apkUrl,
        releaseNotes: releaseNotes.isNotEmpty
            ? releaseNotes
            : 'Bug fixes and performance improvements.',
      );
    } catch (e) {
      debugPrint('[AppUpdateService] Error checking for updates: $e');
      return const AppUpdateInfo(
        type: UpdateType.none,
        currentVersion: '',
        currentBuildNumber: 0,
        latestVersion: '',
        latestBuildNumber: 0,
        minRequiredVersion: '',
        minRequiredBuildNumber: 0,
        apkUrl: '',
        releaseNotes: '',
      );
    }
  }

  /// Checks for updates and displays the dialog if an update is available or required.
  /// If [showLatestToast] is true (e.g. on manual check), notifies if already on latest.
  Future<AppUpdateInfo> checkAndPromptUpdate(
    BuildContext context, {
    bool showLatestToast = false,
  }) async {
    final info = await checkForUpdate();
    if (!context.mounted) return info;

    if (info.hasUpdate) {
      await UpdateDialog.show(context, info);
    } else if (showLatestToast) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('EventXPro is up to date (v${info.currentVersion}).'),
          backgroundColor: AppTheme.statusSuccess,
          duration: const Duration(seconds: 2),
        ),
      );
    }
    return info;
  }

  /// Determines whether current version/build is strictly lower than target
  bool _isOutdated({
    required String currentVersion,
    required int currentBuild,
    required String targetVersion,
    required int targetBuild,
  }) {
    if (targetVersion.isEmpty && targetBuild <= 0) return false;

    // Check semantic version string first (e.g., 1.0.1 vs 1.1.0)
    final versionComparison = _compareSemanticVersions(currentVersion, targetVersion);
    if (versionComparison < 0) {
      return true; // current < target
    } else if (versionComparison > 0) {
      return false; // current > target
    }

    // If semantic versions match, compare build numbers
    if (targetBuild > 0 && currentBuild > 0) {
      return currentBuild < targetBuild;
    }

    return false;
  }

  /// Returns -1 if v1 < v2, 1 if v1 > v2, 0 if v1 == v2
  int _compareSemanticVersions(String v1, String v2) {
    if (v1.isEmpty && v2.isEmpty) return 0;
    if (v1.isEmpty) return -1;
    if (v2.isEmpty) return 1;

    try {
      final v1Parts = v1.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final v2Parts = v2.split('.').map((e) => int.tryParse(e) ?? 0).toList();

      final maxParts = v1Parts.length > v2Parts.length ? v1Parts.length : v2Parts.length;

      for (int i = 0; i < maxParts; i++) {
        final p1 = i < v1Parts.length ? v1Parts[i] : 0;
        final p2 = i < v2Parts.length ? v2Parts[i] : 0;

        if (p1 < p2) return -1;
        if (p1 > p2) return 1;
      }
      return 0;
    } catch (_) {
      return 0;
    }
  }
}
