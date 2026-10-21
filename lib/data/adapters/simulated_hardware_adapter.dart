import 'dart:async';
import '../../domain/adapters/i_hardware_scanner_adapter.dart';

/// Simulated Hardware Scanner Engine.
/// Generates decoded QR events without requiring physical hardware in hand.
/// Ideal for testing on Windows desktop, macOS, Web, and Android Emulators.
class SimulatedHardwareAdapter implements HardwareScannerAdapter {
  final StreamController<String> _scanStreamController =
      StreamController<String>.broadcast();
  bool _isListening = false;

  @override
  String get name => 'Hardware Scanner Simulator';

  @override
  String get description => 'Virtual Barcode Engine (Active)';

  @override
  Stream<String> get scanStream => _scanStreamController.stream;

  @override
  bool get isListening => _isListening;

  @override
  Future<void> initialize() async {
    _isListening = true;
  }

  /// Simulate physical laser trigger scan of a single barcode
  void triggerScan(String rawPayload) {
    if (!_isListening) return;
    _scanStreamController.add(rawPayload);
  }

  /// Simulate rapid multi-scan burst to stress-test 300ms deduplication and FIFO queue
  Future<void> triggerBurst({
    required String barcode,
    required int count,
    required Duration interval,
  }) async {
    for (int i = 0; i < count; i++) {
      if (!_isListening) break;
      _scanStreamController.add(barcode);
      await Future.delayed(interval);
    }
  }

  @override
  Future<void> stop() async {
    _isListening = false;
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _scanStreamController.close();
  }
}
