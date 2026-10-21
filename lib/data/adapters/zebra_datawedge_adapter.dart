import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../core/config/app_constants.dart';
import '../../domain/adapters/i_hardware_scanner_adapter.dart';

/// Native Zebra DataWedge BroadcastReceiver adapter using Flutter EventChannel.
/// Listens to decoded scan broadcasts without simulated keystrokes or hidden TextFields.
class ZebraDataWedgeAdapter implements HardwareScannerAdapter {
  static const EventChannel _eventChannel =
      EventChannel(AppConstants.scannerEventChannel);
  static const MethodChannel _controlChannel =
      MethodChannel(AppConstants.scannerControlChannel);

  final StreamController<String> _scanStreamController =
      StreamController<String>.broadcast();
  StreamSubscription<dynamic>? _channelSubscription;

  bool _isListening = false;
  String _statusDescription = 'Initialized';

  @override
  String get name => 'Zebra DataWedge (Native)';

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
        _channelSubscription?.cancel();
        _channelSubscription = _eventChannel
            .receiveBroadcastStream()
            .listen(_onHardwareEvent, onError: _onHardwareError);

        _isListening = true;
        _statusDescription = 'Active • Intent: ${AppConstants.dataWedgeIntentAction}';
        debugPrint('[ZebraDataWedgeAdapter] Listening on ${AppConstants.scannerEventChannel}');
      } catch (e) {
        _statusDescription = 'Error initializing native EventChannel: $e';
        debugPrint('[ZebraDataWedgeAdapter] Initialization failed: $e');
      }
    } else {
      _statusDescription = 'Native DataWedge available on Android hardware only';
      debugPrint('[ZebraDataWedgeAdapter] Running on non-Android platform: $defaultTargetPlatform');
    }
  }

  void _onHardwareEvent(dynamic event) {
    if (event == null) return;
    final scannedString = event.toString().trim();
    if (scannedString.isNotEmpty) {
      _scanStreamController.add(scannedString);
    }
  }

  void _onHardwareError(dynamic error) {
    debugPrint('[ZebraDataWedgeAdapter] EventChannel error: $error');
    _statusDescription = 'Channel error: $error';
  }

  /// Send intent command to DataWedge (e.g. create profile or switch profile)
  Future<void> sendDataWedgeCommand(String command, String parameter) async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _controlChannel.invokeMethod('sendDataWedgeCommand', {
          'command': command,
          'parameter': parameter,
        });
      } catch (e) {
        debugPrint('[ZebraDataWedgeAdapter] Failed to send DW command: $e');
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
        debugPrint('[ZebraDataWedgeAdapter] Failed to simulate broadcast: $e');
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
