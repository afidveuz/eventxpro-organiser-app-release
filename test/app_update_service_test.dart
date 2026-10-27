import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scanner/core/services/app_update_service.dart';

void main() {
  group('AppUpdateInfo & Type logic', () {
    test('Force update properties are correctly identified', () {
      const info = AppUpdateInfo(
        type: UpdateType.force,
        currentVersion: '1.0.0',
        currentBuildNumber: 1,
        latestVersion: '1.2.0',
        latestBuildNumber: 3,
        minRequiredVersion: '1.1.0',
        minRequiredBuildNumber: 2,
        apkUrl: 'https://example.com/app.apk',
        releaseNotes: 'Security patch required',
      );

      expect(info.isForceUpdate, isTrue);
      expect(info.isRegularUpdate, isFalse);
      expect(info.hasUpdate, isTrue);
    });

    test('Regular update properties are correctly identified', () {
      const info = AppUpdateInfo(
        type: UpdateType.regular,
        currentVersion: '1.1.0',
        currentBuildNumber: 2,
        latestVersion: '1.2.0',
        latestBuildNumber: 3,
        minRequiredVersion: '1.0.0',
        minRequiredBuildNumber: 1,
        apkUrl: 'https://example.com/app.apk',
        releaseNotes: 'New feature',
      );

      expect(info.isForceUpdate, isFalse);
      expect(info.isRegularUpdate, isTrue);
      expect(info.hasUpdate, isTrue);
    });

    test('No update when version is current', () {
      const info = AppUpdateInfo(
        type: UpdateType.none,
        currentVersion: '1.2.0',
        currentBuildNumber: 3,
        latestVersion: '1.2.0',
        latestBuildNumber: 3,
        minRequiredVersion: '1.0.0',
        minRequiredBuildNumber: 1,
        apkUrl: 'https://example.com/app.apk',
        releaseNotes: '',
      );

      expect(info.isForceUpdate, isFalse);
      expect(info.isRegularUpdate, isFalse);
      expect(info.hasUpdate, isFalse);
    });
  });
}
