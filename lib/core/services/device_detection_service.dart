import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../data/datasources/scanner_local_storage.dart';
import '../config/app_constants.dart';

enum DeviceManufacturerType {
  honeywell,
  zebra,
  generic,
}

class DeviceInfoResult {
  final String manufacturer;
  final String model;
  final String brand;
  final String device;
  final String osRelease;
  final int sdkInt;
  final DeviceManufacturerType type;
  final String scannerEngine;
  final bool isHardwareScannerCapable;

  const DeviceInfoResult({
    required this.manufacturer,
    required this.model,
    required this.brand,
    required this.device,
    required this.osRelease,
    required this.sdkInt,
    required this.type,
    required this.scannerEngine,
    required this.isHardwareScannerCapable,
  });

  String get displayName {
    if (manufacturer.isNotEmpty && model.isNotEmpty) {
      if (model.toLowerCase().contains(manufacturer.toLowerCase())) {
        return model;
      }
      return '$manufacturer $model';
    } else if (model.isNotEmpty) {
      return model;
    }
    return 'Android Device';
  }

  bool get isHoneywell => type == DeviceManufacturerType.honeywell;
  bool get isZebra => type == DeviceManufacturerType.zebra;
}

class DeviceDetectionService {
  static const MethodChannel _controlChannel =
      MethodChannel(AppConstants.scannerControlChannel);

  static final DeviceDetectionService _instance = DeviceDetectionService._internal();
  factory DeviceDetectionService() => _instance;
  DeviceDetectionService._internal();

  DeviceInfoResult? _cachedInfo;
  DeviceInfoResult? get cachedInfo => _cachedInfo;

  /// Queries the Android native layer to detect device OEM (Honeywell vs Zebra vs Generic)
  /// and caches the values in RAM and SharedPreferences.
  Future<DeviceInfoResult> detectDevice({ScannerLocalStorage? storage}) async {
    if (_cachedInfo != null && storage == null) {
      return _cachedInfo!;
    }

    if (!kIsWeb && Platform.isAndroid) {
      try {
        final dynamic raw = await _controlChannel.invokeMethod('getDeviceInfo');
        if (raw is Map) {
          final manufacturer = raw['manufacturer']?.toString() ?? 'Android';
          final model = raw['model']?.toString() ?? 'Device';
          final brand = raw['brand']?.toString() ?? '';
          final device = raw['device']?.toString() ?? '';
          final osRelease = raw['osRelease']?.toString() ?? '';
          final sdkInt = (raw['sdkInt'] as num?)?.toInt() ?? 0;
          final rawType = raw['deviceType']?.toString() ?? 'GENERIC_ANDROID';
          final scannerEngine = raw['scannerEngine']?.toString() ?? 'Auto-Detect';
          final isCapable = raw['isHardwareScannerCapable'] == true;

          final type = rawType == 'HONEYWELL'
              ? DeviceManufacturerType.honeywell
              : rawType == 'ZEBRA'
                  ? DeviceManufacturerType.zebra
                  : DeviceManufacturerType.generic;

          final result = DeviceInfoResult(
            manufacturer: manufacturer,
            model: model,
            brand: brand,
            device: device,
            osRelease: osRelease,
            sdkInt: sdkInt,
            type: type,
            scannerEngine: scannerEngine,
            isHardwareScannerCapable: isCapable,
          );

          _cachedInfo = result;

          if (storage != null) {
            await storage.setDeviceManufacturer(manufacturer);
            await storage.setDeviceModel(model);
            await storage.setDeviceBrand(brand);
            await storage.setDeviceType(rawType);
            await storage.setScannerEngine(scannerEngine);
          }

          debugPrint(
              '[DeviceDetectionService] 📱 Detected Device: ${result.displayName} | Type: $rawType | Engine: $scannerEngine');
          return result;
        }
      } catch (e) {
        debugPrint('[DeviceDetectionService] ⚠️ Native device query failed: $e');
      }
    }

    // Non-Android / Desktop / Web Fallback
    final fallback = DeviceInfoResult(
      manufacturer: defaultTargetPlatform.name,
      model: kIsWeb ? 'Web Browser' : 'Desktop Environment',
      brand: 'Generic',
      device: defaultTargetPlatform.name,
      osRelease: 'N/A',
      sdkInt: 0,
      type: DeviceManufacturerType.generic,
      scannerEngine: 'Simulated Hardware Adapter',
      isHardwareScannerCapable: false,
    );
    _cachedInfo = fallback;
    return fallback;
  }

  /// Request the native layer to re-provision the scanner profile (Honeywell / Zebra)
  Future<bool> reprovisionScanner() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final res = await _controlChannel.invokeMethod('provisionScanner');
        return res == true;
      } catch (e) {
        debugPrint('[DeviceDetectionService] ⚠️ Re-provisioning failed: $e');
        return false;
      }
    }
    return false;
  }
}
