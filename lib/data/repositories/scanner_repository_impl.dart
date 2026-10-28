import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/cache/scan_memory_cache.dart';
import '../../core/crypto/ticket_encryption_service.dart';
import '../../domain/entities/attendee.dart';
import '../../domain/entities/scan_decision_code.dart';
import '../../domain/entities/scan_request.dart';
import '../../domain/entities/scan_response.dart';
import '../../domain/entities/telemetry_data.dart';
import '../../domain/repositories/i_scanner_repository.dart';
import '../datasources/django_scan_api_datasource.dart';
import '../datasources/offline_database_helper.dart';
import '../datasources/scanner_local_storage.dart';
import '../models/checkin_record.dart';

/// Ultra-High-Performance Scanner Repository implementation.
///
/// Combines:
/// 1. ScanMemoryCache: Sub-millisecond O(1) in-memory duplicate check and queue depth
/// 2. OfflineDatabaseHelper: SQLite Write-Ahead-Logging (WAL) for 2ms persistent write
/// 3. TicketEncryptionService: DES ECB offline ticket validity check matching React Native EventXPro
/// 4. Chunked Batch Sync: Uploads in batches of 100 records per HTTP POST
class ScannerRepositoryImpl implements IScannerRepository {
  final DjangoScanApiDatasource _remoteDatasource;
  final ScannerLocalStorage _localStorage;
  final OfflineDatabaseHelper _dbHelper;
  final ScanMemoryCache _memoryCache;
  final TicketEncryptionService _cryptoService;
  final TelemetryData _telemetryData = TelemetryData();

  ScannerRepositoryImpl({
    required DjangoScanApiDatasource remoteDatasource,
    required ScannerLocalStorage localStorage,
    OfflineDatabaseHelper? dbHelper,
    ScanMemoryCache? memoryCache,
    TicketEncryptionService? cryptoService,
  })  : _remoteDatasource = remoteDatasource,
        _localStorage = localStorage,
        _dbHelper = dbHelper ?? OfflineDatabaseHelper(),
        _memoryCache = memoryCache ?? ScanMemoryCache(),
        _cryptoService = cryptoService ?? TicketEncryptionService() {
    _telemetryData.pendingQueueDepth = _memoryCache.pendingCount;
  }

  /// Factory helper that pre-warms the RAM cache from SQLite on startup
  static Future<ScannerRepositoryImpl> create({
    required DjangoScanApiDatasource remoteDatasource,
    required ScannerLocalStorage localStorage,
    OfflineDatabaseHelper? dbHelper,
    ScanMemoryCache? memoryCache,
    TicketEncryptionService? cryptoService,
  }) async {
    final db = dbHelper ?? OfflineDatabaseHelper();
    final cache = memoryCache ?? ScanMemoryCache();

    // Warm up RAM cache from SQLite
    try {
      final existingCodes = await db.getAllScannedCodes();
      cache.populate(existingCodes);
      final unsyncedCount = await db.getUnsyncedCount();
      cache.setPendingCount(unsyncedCount);
    } catch (e) {
      debugPrint('[ScannerRepositoryImpl] ⚠️ Warm-up warning: $e');
    }

    return ScannerRepositoryImpl(
      remoteDatasource: remoteDatasource,
      localStorage: localStorage,
      dbHelper: db,
      memoryCache: cache,
      cryptoService: cryptoService,
    );
  }

  @override
  TelemetryData get telemetry => _telemetryData;

  @override
  Future<ScanResponse> validateScan(ScanRequest request) async {
    _telemetryData.totalScans++;

    // -------------------------------------------------------------
    // ⚡ HIGH-PERFORMANCE OFFLINE PATH (< 5ms response time)
    // -------------------------------------------------------------
    if (_localStorage.isOfflineModeEnabled) {
      final qr = request.qrToken.trim();

      // 1. Validate Code Authenticity (DES ECB Decryption matching React Native OfflineScanner.jsx)
      final keyString = _localStorage.getTicketEncryptionKey();
      final validationResult = _cryptoService.validateTicket(
        rawQrToken: qr,
        keyString: keyString,
      );

      if (!validationResult.isValid) {
        _telemetryData.rejectedCount++;
        _telemetryData.recordLatency(2);
        return ScanResponse(
          status: 'REJECTED',
          code: ScanDecisionCode.invalidBadge,
          message: validationResult.errorMessage ?? 'Invalid QR Code',
          serverTime: DateTime.now(),
          latencyMs: 2,
          scanRequestId: request.scanRequestId,
        );
      }

      // 2. Resolve Punch Type ('check_in' or 'check_out')
      final cleanType = request.scanType.toLowerCase().trim();
      final punchType = (cleanType == 'check_out' || cleanType == 'exit')
          ? 'check_out'
          : 'check_in';

      // 3. Fast Non-Blocking WAL SQLite write (< 2ms)
      // Every valid scan is recorded into SQLite (matching eventxproorganiser addCheckin)
      final record = CheckinRecord(
        scanRequestId: request.scanRequestId,
        encryptedCode: validationResult.decryptedPayload.isNotEmpty
            ? validationResult.decryptedPayload
            : qr,
        code: validationResult.normalizedCode,
        entranceId: request.gateId,
        entranceLocation: request.sectionLocation ?? 'Gate ${request.gateId}',
        scanType: punchType,
        section: request.section.isNotEmpty ? request.section : 'entrances',
        timestamp: request.scannedAt,
        eventId: request.eventId > 0 ? request.eventId : 1,
      );

      final insertStart = DateTime.now();
      await _dbHelper.insertCheckin(record);
      final insertLatency = DateTime.now().difference(insertStart).inMilliseconds;

      // 4. Update RAM telemetry state instantly
      _memoryCache.incrementPending();
      _telemetryData.pendingQueueDepth = _memoryCache.pendingCount;
      _telemetryData.acceptedCount++;
      _telemetryData.recordLatency(insertLatency.clamp(1, 100));

      final actionText = punchType == 'check_in' ? 'Check-In' : 'Check-Out';
      return ScanResponse(
        status: 'ACCEPTED',
        code: ScanDecisionCode.entryAllowed,
        message: '$actionText Successful',
        checkInId: 'offline-${request.scanRequestId.length >= 8 ? request.scanRequestId.substring(0, 8) : request.scanRequestId}',
        serverTime: DateTime.now(),
        latencyMs: insertLatency.clamp(1, 100),
        scanRequestId: request.scanRequestId,
        attendee: const Attendee(
          name: 'Offline Attendee',
          badgeType: 'OFFLINE VERIFIED',
          company: 'Offline Validated',
        ),
      );
    }

    // -------------------------------------------------------------
    // 🌐 ONLINE AUTHORITATIVE PATH
    // -------------------------------------------------------------
    final response = await _remoteDatasource.validateScan(request);
    _telemetryData.recordLatency(response.latencyMs);

    if (response.code.isSuccess) {
      _telemetryData.acceptedCount++;
      _memoryCache.recordScan(request.qrToken);
    } else if (response.code.isWarning) {
      _telemetryData.warningCount++;
    } else if (response.code.isRejected) {
      _telemetryData.rejectedCount++;
    } else if (response.code.isNetworkError) {
      _telemetryData.networkTimeoutCount++;
      // Auto-fallback: save degraded scan to offline queue
      final cleanType = request.scanType.toLowerCase().trim();
      final punchType = (cleanType == 'check_out' || cleanType == 'exit')
          ? 'check_out'
          : 'check_in';
      final record = CheckinRecord(
        scanRequestId: request.scanRequestId,
        encryptedCode: request.qrToken,
        code: request.qrToken,
        entranceId: request.gateId,
        entranceLocation: request.sectionLocation != null && request.sectionLocation!.isNotEmpty
            ? request.sectionLocation!
            : 'Gate ${request.gateId}',
        scanType: punchType,
        section: request.section.isNotEmpty ? request.section : 'entrances',
        timestamp: request.scannedAt,
        eventId: request.eventId > 0 ? request.eventId : 1,
      );
      await _dbHelper.insertCheckin(record);
      _memoryCache.incrementPending();
      _telemetryData.pendingQueueDepth = _memoryCache.pendingCount;

      return response.copyWith(
        status: 'QUEUED',
        alertType: 'warning',
        message: 'Scan Saved Offline (No Internet)',
      );
    }

    return response;
  }

  @override
  Future<void> queueOfflineScan(ScanRequest request) async {
    final record = CheckinRecord(
      scanRequestId: request.scanRequestId,
      encryptedCode: request.qrToken,
      code: request.qrToken,
      entranceId: request.gateId,
      entranceLocation: 'Gate ${request.gateId}',
      scanType: (request.scanType.toLowerCase().trim() == 'check_out' ||
              request.scanType.toLowerCase().trim() == 'exit')
          ? 'check_out'
          : 'check_in',
      section: 'entrances',
      timestamp: request.scannedAt,
      eventId: request.eventId,
    );
    await _dbHelper.insertCheckin(record);
    _memoryCache.recordScan(request.qrToken);
    _memoryCache.incrementPending();
    _telemetryData.pendingQueueDepth = _memoryCache.pendingCount;
  }

  @override
  Future<List<ScanRequest>> getPendingOfflineScans() async {
    final records = await _dbHelper.getUnsyncedChunk(limit: 500);
    return records
        .map((r) => ScanRequest(
              qrToken: r.code,
              eventId: r.eventId,
              gateId: r.entranceId,
              scanType: r.scanType,
              deviceId: _localStorage.getDeviceId(),
              scanRequestId: r.scanRequestId,
              scannedAt: r.timestamp,
            ))
        .toList();
  }

  @override
  Future<int> syncOfflineScans() async {
    int totalSynced = 0;
    bool hasMore = true;

    // ⚡ CHUNKED BATCH SYNC: Uploads 100 items per HTTP request
    while (hasMore) {
      final chunk = await _dbHelper.getUnsyncedChunk(limit: 100);
      if (chunk.isEmpty) {
        hasMore = false;
        break;
      }

      final batchResult = await _remoteDatasource.syncOfflineBatch(
        section: 'entrances',
        eventId: _localStorage.getEventId(),
        chunk: chunk,
      );

      if (batchResult.isSuccess) {
        // Atomic batch update in SQLite
        await _dbHelper.markBatchSynced(
          updatedIds: batchResult.updatedRecordsAppId,
          notExistIds: batchResult.notExistsUsersAppId,
        );

        final processedCount = batchResult.updatedRecordsAppId.length +
            batchResult.notExistsUsersAppId.length;

        // If backend returned zero updated IDs, mark whole chunk to prevent infinite loop
        final countToDeduct = processedCount > 0 ? processedCount : chunk.length;
        if (processedCount == 0) {
          final allChunkIds = chunk.map((e) => e.id!).whereType<int>().toList();
          await _dbHelper.markBatchSynced(updatedIds: allChunkIds);
        }

        totalSynced += countToDeduct;
        _memoryCache.decrementPending(countToDeduct);
      } else {
        // Stop on network failure to preserve records
        debugPrint('[ScannerRepositoryImpl] ⚠️ Batch sync paused: ${batchResult.errorMessage}');
        break;
      }
    }

    _telemetryData.pendingQueueDepth = _memoryCache.pendingCount;
    return totalSynced;
  }

  @override
  Future<void> clearOfflineQueue() async {
    await _dbHelper.clearAll();
    _memoryCache.clear();
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
