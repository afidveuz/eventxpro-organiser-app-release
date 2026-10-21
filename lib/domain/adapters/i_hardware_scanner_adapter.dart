import 'dart:async';

/// Abstract adapter interface for OEM barcode/QR scanners.
/// Decouples hardware-specific intent receivers from shared Flutter logic.
abstract class HardwareScannerAdapter {
  /// Unique identifier of the adapter (e.g. 'Zebra DataWedge', 'Honeywell Intent', 'Hardware Simulator')
  String get name;

  /// Human-friendly description of current connection or availability
  String get description;

  /// Stream emitting normalized, raw decoded barcode/QR strings
  Stream<String> get scanStream;

  /// Whether the hardware engine is active and listening
  bool get isListening;

  /// Initialize and bind the hardware listener (EventChannel / Receiver)
  Future<void> initialize();

  /// Pause or stop listening (e.g. on screen exit or logout)
  Future<void> stop();

  /// Dispose resources and subscriptions
  Future<void> dispose();
}
