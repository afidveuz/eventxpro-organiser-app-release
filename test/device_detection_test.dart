import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scanner/core/services/device_detection_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DeviceInfoResult Tests', () {
    test('Correctly identifies Honeywell device type and displayName', () {
      const info = DeviceInfoResult(
        manufacturer: 'Honeywell',
        model: 'EDA51',
        brand: 'Honeywell',
        device: 'EDA51',
        osRelease: '10',
        sdkInt: 29,
        type: DeviceManufacturerType.honeywell,
        scannerEngine: 'Honeywell Data Collection Service',
        isHardwareScannerCapable: true,
      );

      expect(info.isHoneywell, isTrue);
      expect(info.isZebra, isFalse);
      expect(info.displayName, equals('Honeywell EDA51'));
    });

    test('Correctly identifies Zebra device type and displayName', () {
      const info = DeviceInfoResult(
        manufacturer: 'Zebra Technologies',
        model: 'TC15',
        brand: 'Zebra',
        device: 'TC15',
        osRelease: '11',
        sdkInt: 30,
        type: DeviceManufacturerType.zebra,
        scannerEngine: 'Zebra DataWedge API',
        isHardwareScannerCapable: true,
      );

      expect(info.isZebra, isTrue);
      expect(info.isHoneywell, isFalse);
      expect(info.displayName, equals('Zebra Technologies TC15'));
    });

    test('Non-hardware environment defaults to generic fallback', () {
      const info = DeviceInfoResult(
        manufacturer: 'Google',
        model: 'Pixel 7',
        brand: 'Google',
        device: 'panther',
        osRelease: '14',
        sdkInt: 34,
        type: DeviceManufacturerType.generic,
        scannerEngine: 'Simulated Hardware Adapter',
        isHardwareScannerCapable: false,
      );

      expect(info.isHoneywell, isFalse);
      expect(info.isZebra, isFalse);
      expect(info.isHardwareScannerCapable, isFalse);
    });
  });
}
