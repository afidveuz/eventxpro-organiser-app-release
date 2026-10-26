import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../core/config/app_constants.dart';
import '../../core/services/device_detection_service.dart';
import '../../domain/adapters/i_hardware_scanner_adapter.dart';

/// Universal Enterprise Hardware Scanner Adapter supporting both:
/// 1. Honeywell ScanPal EDA51 / CT40 / CT60 / CK65 (Honeywell Data Collection Service)
/// 2. Zebra TC15 / TC21 / TC26 / TC52 / TC57 (Zebra DataWedge API)
///
/// Listens to decoded hardware scan broadcast intents via native EventChannel.
class EnterpriseHardwareAdapter implements HardwareScannerAdapter {
  static const EventChannel _eventChannel =
      EventChannel(AppConstants.scannerEventChannel);
  static const MethodChannel _controlChannel =
      MethodChannel(AppConstants.scannerControlChannel);

  final StreamController<String> _scanStreamController =
      StreamController<String>.broadcast();
  StreamSubscription<dynamic>? _channelSubscription;

  bool _isListening = false;
  String _statusDescription = 'Initialized';
  String _adapterName = 'Enterprise Hardware Scanner';

  @override
  String get name => _adapterName;

  @override
  String get description => _statusDescription;

  @override
  Stream<String> get scanStream => _scanStreamController.stream;

  @override
  bool get isListening => _isListening;

  @override
  Future<void> initialize() async {
    if (_isListening) return;

    if (!kIsWeb && Platform.isAndroid) {
      try {
        // Query device profile to display OEM-accurate adapter title
        final deviceInfo = await DeviceDetectionService().detectDevice();
        if (deviceInfo.isHoneywell) {
          _adapterName = '${deviceInfo.displayName} (Honeywell Native)';
        } else if (deviceInfo.isZebra) {
          _adapterName = '${deviceInfo.displayName} (Zebra DataWedge)';
        } else {
          _adapterName = 'Enterprise Scanner (Native Broadcast)';
        }

        _channelSubscription?.cancel();
        _channelSubscription = _eventChannel
            .receiveBroadcastStream()
            .listen(_onHardwareEvent, onError: _onHardwareError);

        _isListening = true;
        _statusDescription = 'Active • Intent: ${AppConstants.dataWedgeIntentAction}';
        debugPrint('[$_adapterName] 🎯 Hardware listener active on ${AppConstants.scannerEventChannel}');
      } catch (e) {
        _statusDescription = 'Error initializing native EventChannel: $e';
        debugPrint('[EnterpriseHardwareAdapter] ❌ Initialization failed: $e');
      }
    } else {
      _statusDescription = 'Enterprise Hardware Scanner is active on Android physical devices only';
      debugPrint('[EnterpriseHardwareAdapter] Non-Android target: $defaultTargetPlatform');
    }
  }

  void _onHardwareEvent(dynamic event) {
    if (event == null) return;
    final scannedString = event.toString().trim();
    if (scannedString.isNotEmpty) {
      debugPrint('[EnterpriseHardwareAdapter] ⚡ Raw hardware decode event received: "$scannedString"');
      _scanStreamController.add(scannedString);
    }
  }

  void _onHardwareError(dynamic error) {
    debugPrint('[EnterpriseHardwareAdapter] ⚠️ EventChannel error: $error');
    _statusDescription = 'Channel error: $error';
  }

  /// Request the native platform to re-provision the scanner profile
  Future<void> reprovision() async {
    await DeviceDetectionService().reprovisionScanner();
  }

  /// Send intent command to Zebra DataWedge if running on a Zebra device
  Future<void> sendDataWedgeCommand(String command, String parameter) async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _controlChannel.invokeMethod('sendDataWedgeCommand', {
          'command': command,
          'parameter': parameter,
        });
      } catch (e) {
        debugPrint('[EnterpriseHardwareAdapter] Failed to send DW command: $e');
      }
    }
  }

  /// Simulate a hardware broadcast intent directly into Android receiver (for testing)
  Future<void> simulateNativeBroadcast(String barcode) async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _controlChannel.invokeMethod('simulateScanIntent', {
          'code': barcode,
        });
      } catch (e) {
        debugPrint('[EnterpriseHardwareAdapter] Failed to simulate broadcast: $e');
      }
    } else {
      // Direct stream injection fallback on desktop/web
      _onHardwareEvent(barcode);
    }
  }

  @override
  Future<void> stop() async {
    await _channelSubscription?.cancel();
    _channelSubscription = null;
    _isListening = false;
    _statusDescription = 'Stopped';
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _scanStreamController.close();
  }
}
