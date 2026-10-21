import '../entities/scan_request.dart';
import '../entities/scan_response.dart';
import '../entities/telemetry_data.dart';

abstract class IScannerRepository {
  /// Validate a scanned token against the authoritative Django backend.
  Future<ScanResponse> validateScan(ScanRequest request);

  /// Queue a scan locally when offline mode is enabled or network is degraded.
  Future<void> queueOfflineScan(ScanRequest request);

  /// Get all pending scans stored in local offline FIFO queue.
  Future<List<ScanRequest>> getPendingOfflineScans();

  /// Attempt to synchronize pending offline scans with backend.
  Future<int> syncOfflineScans();

  /// Clear pending offline scans.
  Future<void> clearOfflineQueue();

  /// Current telemetry measurements
  TelemetryData get telemetry;

  /// Record a hardware duplicate suppression event (300ms filter)
  void recordSuppression();

  /// Record a FIFO queue overflow drop
  void recordDrop();
}
