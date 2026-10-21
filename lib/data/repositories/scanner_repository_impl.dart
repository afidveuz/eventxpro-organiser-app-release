import '../../domain/entities/scan_request.dart';
import '../../domain/entities/scan_response.dart';
import '../../domain/entities/telemetry_data.dart';
import '../../domain/repositories/i_scanner_repository.dart';
import '../datasources/django_scan_api_datasource.dart';
import '../datasources/scanner_local_storage.dart';

class ScannerRepositoryImpl implements IScannerRepository {
  final DjangoScanApiDatasource _remoteDatasource;
  final ScannerLocalStorage _localStorage;
  final TelemetryData _telemetryData = TelemetryData();

  ScannerRepositoryImpl({
    required DjangoScanApiDatasource remoteDatasource,
    required ScannerLocalStorage localStorage,
  })  : _remoteDatasource = remoteDatasource,
        _localStorage = localStorage {
    _telemetryData.pendingQueueDepth = _localStorage.getOfflineQueue().length;
  }

  @override
  TelemetryData get telemetry => _telemetryData;

  @override
  Future<ScanResponse> validateScan(ScanRequest request) async {
    _telemetryData.totalScans++;

    // If offline admission mode is active (Section 10)
    if (_localStorage.isOfflineModeEnabled) {
      await _localStorage.addToOfflineQueue(request);
      _telemetryData.pendingQueueDepth = _localStorage.getOfflineQueue().length;
      return ScanResponse.offlineQueued(scanRequestId: request.scanRequestId);
    }

    final response = await _remoteDatasource.validateScan(request);

    // Record telemetry metrics (Section 11)
    _telemetryData.recordLatency(response.latencyMs);

    if (response.code.isSuccess) {
      _telemetryData.acceptedCount++;
    } else if (response.code.isWarning) {
      _telemetryData.warningCount++;
    } else if (response.code.isRejected) {
      _telemetryData.rejectedCount++;
    } else if (response.code.isNetworkError) {
      _telemetryData.networkTimeoutCount++;
      // If network fails, queue to offline cache for later sync
      await _localStorage.addToOfflineQueue(request);
      _telemetryData.pendingQueueDepth = _localStorage.getOfflineQueue().length;
    }

    return response;
  }

  @override
  Future<void> queueOfflineScan(ScanRequest request) async {
    await _localStorage.addToOfflineQueue(request);
    _telemetryData.pendingQueueDepth = _localStorage.getOfflineQueue().length;
  }

  @override
  Future<List<ScanRequest>> getPendingOfflineScans() async {
    return _localStorage.getOfflineQueue();
  }

  @override
  Future<int> syncOfflineScans() async {
    final pending = _localStorage.getOfflineQueue();
    if (pending.isEmpty) return 0;

    int syncedCount = 0;
    for (final scan in List<ScanRequest>.from(pending)) {
      final res = await _remoteDatasource.validateScan(scan);
      if (!res.code.isNetworkError) {
        syncedCount++;
      }
    }

    // Clear queue after sync attempt
    await _localStorage.clearOfflineQueue();
    _telemetryData.pendingQueueDepth = 0;
    return syncedCount;
  }

  @override
  Future<void> clearOfflineQueue() async {
    await _localStorage.clearOfflineQueue();
    _telemetryData.pendingQueueDepth = 0;
  }

  @override
  void recordSuppression() {
    _telemetryData.duplicateSuppressedCount++;
  }

  @override
  void recordDrop() {
    _telemetryData.queueDropCount++;
  }
}
