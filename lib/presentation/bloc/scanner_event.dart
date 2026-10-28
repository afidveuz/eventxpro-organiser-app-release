import 'package:equatable/equatable.dart';
import '../../domain/adapters/i_hardware_scanner_adapter.dart';

abstract class ScannerEvent extends Equatable {
  const ScannerEvent();

  @override
  List<Object?> get props => [];
}

/// Initialize the Central Scan Controller and subscribe to hardware adapter
class ScannerInitialized extends ScannerEvent {
  const ScannerInitialized();
}

/// Raw barcode/QR string emitted from the native EventChannel
class ScannerRawBarcodeReceived extends ScannerEvent {
  final String rawBarcode;
  final DateTime receivedAt;

  ScannerRawBarcodeReceived(this.rawBarcode, [DateTime? receivedAt])
      : receivedAt = receivedAt ?? DateTime.now();

  @override
  List<Object?> get props => [rawBarcode, receivedAt];
}

/// Operator enters scanner screen or foregrounds app - enable hardware scan processing
class ScannerScanningResumed extends ScannerEvent {
  const ScannerScanningResumed();
}

/// Operator leaves scanner screen, opens settings/home, or backgrounds app - pause scan processing
class ScannerScanningPaused extends ScannerEvent {
  const ScannerScanningPaused();
}

/// Programmatically set whether scan processing is enabled
class ScannerSetScanningEnabled extends ScannerEvent {
  final bool isEnabled;
  const ScannerSetScanningEnabled(this.isEnabled);

  @override
  List<Object?> get props => [isEnabled];
}

/// Dispatched by timer after feedback hold duration to return to ready state
class ScannerFeedbackTimeout extends ScannerEvent {
  const ScannerFeedbackTimeout();
}

/// Operator taps retry button for a failed or timed-out scan
/// (Reuses original scan_request_id for idempotency!)
class ScannerRetryLast extends ScannerEvent {
  const ScannerRetryLast();
}

/// Switch active hardware scanner adapter (Zebra native vs simulator)
class ScannerAdapterSwitched extends ScannerEvent {
  final HardwareScannerAdapter newAdapter;

  const ScannerAdapterSwitched(this.newAdapter);

  @override
  List<Object?> get props => [newAdapter.name];
}

/// Update gate, event, scan type, or duplicate threshold settings
class ScannerConfigChanged extends ScannerEvent {
  final int? eventId;
  final int? gateId;
  final String? scanType;
  final int? suppressionMs;
  final bool? offlineModeEnabled;
  final String? testUsername;
  final String? section;
  final String? sectionLocation;

  const ScannerConfigChanged({
    this.eventId,
    this.gateId,
    this.scanType,
    this.suppressionMs,
    this.offlineModeEnabled,
    this.testUsername,
    this.section,
    this.sectionLocation,
  });

  @override
  List<Object?> get props => [
        eventId,
        gateId,
        scanType,
        suppressionMs,
        offlineModeEnabled,
        testUsername,
        section,
        sectionLocation,
      ];
}

/// Synchronize locally queued offline scans
class ScannerSyncOfflineRequested extends ScannerEvent {
  const ScannerSyncOfflineRequested();
}

/// Clear offline queue
class ScannerClearOfflineQueueRequested extends ScannerEvent {
  const ScannerClearOfflineQueueRequested();
}
