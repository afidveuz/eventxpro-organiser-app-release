import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../../core/config/app_constants.dart';
import '../../core/services/audio_feedback_service.dart';
import '../../core/services/haptic_feedback_service.dart';
import '../../data/datasources/scanner_local_storage.dart';
import '../../domain/adapters/i_hardware_scanner_adapter.dart';
import '../../domain/entities/scan_audit_item.dart';
import '../../domain/entities/scan_request.dart';
import '../../domain/entities/scan_response.dart';
import '../../domain/repositories/i_scanner_repository.dart';
import 'scanner_event.dart';
import 'scanner_state.dart';

class ScannerBloc extends Bloc<ScannerEvent, ScannerState> {
  final IScannerRepository _repository;
  final ScannerLocalStorage _localStorage;
  final AudioFeedbackService _audioService;
  final HapticFeedbackService _hapticService;

  HardwareScannerAdapter _activeAdapter;
  StreamSubscription<String>? _adapterSubscription;
  Timer? _feedbackResetTimer;

  // Active screen scanning gate: only process hardware scans when scanner screen is foregrounded
  bool _isScanningActive;

  bool get isScanningActive => _isScanningActive;
  HardwareScannerAdapter get activeAdapter => _activeAdapter;
  AudioFeedbackService get audioService => _audioService;

  // Duplicate suppression tracking (Section 7: 300 ms identical value suppression)
  String? _lastScannedToken;
  DateTime? _lastScanTime;
  int _suppressionMs = AppConstants.defaultDuplicateSuppressionMs;

  // Last logical scan for safe retry with preserved idempotency key (Section 7 & 9)
  ScanRequest? _lastLogicalRequest;

  // Session scan history audit log
  final List<ScanAuditItem> _recentScans = [];

  // Bounded FIFO processing queue (Section 7)
  final List<String> _pendingQueue = [];
  bool _isProcessing = false;

  ScannerBloc({
    required IScannerRepository repository,
    required ScannerLocalStorage localStorage,
    required HardwareScannerAdapter activeAdapter,
    AudioFeedbackService? audioService,
    HapticFeedbackService? hapticService,
    bool isScanningActive = true,
  })  : _repository = repository,
        _localStorage = localStorage,
        _activeAdapter = activeAdapter,
        _audioService = audioService ?? AudioFeedbackService(),
        _hapticService = hapticService ?? HapticFeedbackService(),
        _isScanningActive = isScanningActive,
        super(ScannerInitialState(
          eventId: localStorage.getEventId(),
          gateId: localStorage.getGateId(),
          scanType: localStorage.getScanType(),
          deviceId: localStorage.getDeviceId(),
          adapterName: activeAdapter.name,
          isOfflineMode: localStorage.isOfflineModeEnabled,
          queueDepth: repository.telemetry.pendingQueueDepth,
          telemetry: repository.telemetry,
          recentScans: const [],
        )) {
    on<ScannerInitialized>(_onInitialized);
    on<ScannerScanningResumed>(_onScanningResumed);
    on<ScannerScanningPaused>(_onScanningPaused);
    on<ScannerSetScanningEnabled>(_onSetScanningEnabled);
    on<ScannerRawBarcodeReceived>(_onRawBarcodeReceived);
    on<ScannerFeedbackTimeout>(_onFeedbackTimeout);
    on<ScannerRetryLast>(_onRetryLast);
    on<ScannerAdapterSwitched>(_onAdapterSwitched);
    on<ScannerConfigChanged>(_onConfigChanged);
    on<ScannerSyncOfflineRequested>(_onSyncOfflineRequested);
    on<ScannerClearOfflineQueueRequested>(_onClearOfflineQueueRequested);
  }

  Future<void> _onInitialized(
      ScannerInitialized event, Emitter<ScannerState> emit) async {
    _suppressionMs = _localStorage.getSuppressionMs();
    await _bindAdapter(_activeAdapter);

    emit(ScannerReadyState(
      eventId: _localStorage.getEventId(),
      gateId: _localStorage.getGateId(),
      scanType: _localStorage.getScanType(),
      deviceId: _localStorage.getDeviceId(),
      adapterName: _activeAdapter.name,
      isOfflineMode: _localStorage.isOfflineModeEnabled,
      queueDepth: _repository.telemetry.pendingQueueDepth,
      telemetry: _repository.telemetry,
      recentScans: List.unmodifiable(_recentScans),
    ));
  }

  void _onScanningResumed(
      ScannerScanningResumed event, Emitter<ScannerState> emit) {
    if (!_isScanningActive) {
      _isScanningActive = true;
      debugPrint('[ScannerBloc] ▶️ Scanning ACTIVE: Hardware scanner inputs will be processed');
    }
  }

  void _onScanningPaused(
      ScannerScanningPaused event, Emitter<ScannerState> emit) {
    if (_isScanningActive) {
      _isScanningActive = false;
      _pendingQueue.clear();
      debugPrint('[ScannerBloc] ⏸️ Scanning PAUSED: Hardware scanner inputs will be ignored');
    }
  }

  void _onSetScanningEnabled(
      ScannerSetScanningEnabled event, Emitter<ScannerState> emit) {
    if (_isScanningActive != event.isEnabled) {
      _isScanningActive = event.isEnabled;
      if (!_isScanningActive) {
        _pendingQueue.clear();
      }
      debugPrint(
          '[ScannerBloc] 🔄 Scanning toggled to ${event.isEnabled ? "ACTIVE" : "PAUSED"}');
    }
  }

  Future<void> _bindAdapter(HardwareScannerAdapter adapter) async {
    await _adapterSubscription?.cancel();
    _activeAdapter = adapter;
    await _activeAdapter.initialize();

    _adapterSubscription = _activeAdapter.scanStream.listen((barcode) {
      add(ScannerRawBarcodeReceived(barcode));
    });
  }

  Future<void> _onRawBarcodeReceived(
      ScannerRawBarcodeReceived event, Emitter<ScannerState> emit) async {
    final rawToken = event.rawBarcode.trim();

    // 0. Active screen guard: Ignore hardware scans when not on the scanner screen
    if (!_isScanningActive) {
      debugPrint(
          '[ScannerBloc] ⏹️ Hardware scan IGNORED: Scanner is inactive/paused (scanned: "$rawToken")');
      return;
    }

    final now = event.receivedAt;

    // 1. Hardware duplicate suppression (Section 7: 300 ms benchmark for identical value)
    if (_lastScannedToken == rawToken && _lastScanTime != null) {
      final elapsedMs = now.difference(_lastScanTime!).inMilliseconds;
      if (elapsedMs < _suppressionMs) {
        _repository.recordSuppression();
        debugPrint(
            '[SCAN DEDUPLICATION] ⚡ Suppressed repeated callback for "$rawToken" (elapsed: ${elapsedMs}ms < ${_suppressionMs}ms threshold)');
        return; // Suppress duplicate hardware callback
      }
    }

    _lastScannedToken = rawToken;
    _lastScanTime = now;

    // Cancel any active reset timer: immediate continuous scanning of next code!
    _feedbackResetTimer?.cancel();

    // 2. Bounded FIFO Queue management (Section 7)
    if (_pendingQueue.length >= AppConstants.maxQueueCapacity) {
      _repository.recordDrop();
      debugPrint('[SCAN QUEUE OVERFLOW] ⚠️ Safe drop triggered: Queue exceeded ${AppConstants.maxQueueCapacity} capacity');
      return;
    }

    _pendingQueue.add(rawToken);
    await _processQueue(emit);
  }

  Future<void> _processQueue(Emitter<ScannerState> emit) async {
    if (_isProcessing || _pendingQueue.isEmpty) return;

    _isProcessing = true;
    final token = _pendingQueue.removeAt(0);

    // Beep immediately on physical hardware decode reception
    _audioService.playTone(AudioTone.scanBeep);

    // Generate unique RFC4122 UUID request ID for each physical scan attempt (Section 7)
    final scanRequestId = const Uuid().v4();

    final request = ScanRequest(
      qrToken: token,
      eventId: _localStorage.getEventId(),
      gateId: _localStorage.getGateId(),
      scanType: _localStorage.getScanType(),
      deviceId: _localStorage.getDeviceId(),
      scanRequestId: scanRequestId,
      scannedAt: DateTime.now(),
      section: _localStorage.getSection(),
      sectionLocation: _localStorage.getSectionLocation(),
    );

    _lastLogicalRequest = request;

    // Emit in-flight processing state
    emit(ScannerProcessingState(
      eventId: request.eventId,
      gateId: request.gateId,
      scanType: request.scanType,
      deviceId: request.deviceId,
      adapterName: _activeAdapter.name,
      isOfflineMode: _localStorage.isOfflineModeEnabled,
      queueDepth: _repository.telemetry.pendingQueueDepth,
      telemetry: _repository.telemetry,
      tokenSnippet: token.length > 8 ? '${token.substring(0, 8)}...' : token,
      scanRequestId: scanRequestId,
      recentScans: List.unmodifiable(_recentScans),
    ));

    // Call authoritative validation
    final response = await _repository.validateScan(request);

    // Save to audit history
    final auditItem = ScanAuditItem(
      timestamp: DateTime.now(),
      qrToken: token,
      code: response.code,
      status: response.status,
      message: response.message,
      attendeeName: response.attendee?.name,
      badgeType: response.attendee?.badgeType,
      company: response.attendee?.company,
      latencyMs: response.latencyMs,
      scanRequestId: request.scanRequestId,
      testApiResponse: response.testApiResponse,
    );
    _recentScans.insert(0, auditItem);
    if (_recentScans.length > 50) {
      _recentScans.removeLast();
    }

    // Print full scanned details clearly to terminal & log
    _printScanDetails(request, response);

    // Trigger audio & haptic feedback matching outcome
    if (response.code.isSuccess) {
      _audioService.playTone(AudioTone.success);
      _hapticService.trigger(HapticPattern.success);
    } else if (response.code.isWarning) {
      _audioService.playTone(AudioTone.warning);
      _hapticService.trigger(HapticPattern.warning);
    } else if (response.code.isRejected) {
      _audioService.playTone(AudioTone.error);
      _hapticService.trigger(HapticPattern.error);
    } else {
      _audioService.playTone(AudioTone.warning);
    }

    emit(ScannerDecisionState(
      eventId: request.eventId,
      gateId: request.gateId,
      scanType: request.scanType,
      deviceId: request.deviceId,
      adapterName: _activeAdapter.name,
      isOfflineMode: _localStorage.isOfflineModeEnabled,
      queueDepth: _repository.telemetry.pendingQueueDepth,
      telemetry: _repository.telemetry,
      request: request,
      response: response,
      recentScans: List.unmodifiable(_recentScans),
    ));

    _isProcessing = false;

    // Start auto-reset timer back to ready-to-scan state only if queue is empty
    _feedbackResetTimer?.cancel();
    if (_pendingQueue.isEmpty) {
      final isShortToast = _localStorage.isShortToastEnabled;
      final holdDuration = isShortToast
          ? const Duration(milliseconds: 1800)
          : AppConstants.feedbackDisplayDuration;
      _feedbackResetTimer = Timer(holdDuration, () {
        if (!isClosed) {
          add(const ScannerFeedbackTimeout());
        }
      });
    }

    // Check if more items queued in FIFO - process immediately for continuous high-speed flow
    if (_pendingQueue.isNotEmpty) {
      await _processQueue(emit);
    }
  }

  void _printScanDetails(ScanRequest request, ScanResponse response) {
    debugPrint('''
╔════════════════════════════════════════════════════════════════
║ [HARDWARE SCAN DECODED & VALIDATED]
╠════════════════════════════════════════════════════════════════
║  QR Token:        ${request.qrToken}
║  Decision:        ${response.code.code} (Status: ${response.status})
║  Message:         ${response.message}
║  Attendee Name:   ${response.attendee?.name ?? 'None (Access Denied / Unassigned)'}
║  Badge Category:  ${response.attendee?.badgeType ?? 'N/A'}
║  Company:         ${response.attendee?.company ?? 'N/A'}
║  Check-In ID:     ${response.checkInId ?? 'N/A'}
║  Gate / Event:    Gate #${request.gateId} (${request.scanType}) • Event #${request.eventId}
║  Device UUID:     ${request.deviceId}
║  Scan Request ID: ${request.scanRequestId}
║  Scanned At:      ${request.scannedAt.toLocal()}
║  Roundtrip Time:  ${response.latencyMs} ms
║  Test API Result: ${response.testApiResponse ?? 'N/A'}
╚════════════════════════════════════════════════════════════════''');
  }

  void _onFeedbackTimeout(
      ScannerFeedbackTimeout event, Emitter<ScannerState> emit) {
    if (state is ScannerDecisionState) {
      emit(ScannerReadyState(
        eventId: _localStorage.getEventId(),
        gateId: _localStorage.getGateId(),
        scanType: _localStorage.getScanType(),
        deviceId: _localStorage.getDeviceId(),
        adapterName: _activeAdapter.name,
        isOfflineMode: _localStorage.isOfflineModeEnabled,
        queueDepth: _repository.telemetry.pendingQueueDepth,
        telemetry: _repository.telemetry,
        recentScans: List.unmodifiable(_recentScans),
      ));
    }
  }

  Future<void> _onRetryLast(
      ScannerRetryLast event, Emitter<ScannerState> emit) async {
    if (_lastLogicalRequest == null) return;

    // Reuse the exact same scan_request_id for idempotency retry (Section 7 & 9)
    final retryRequest = _lastLogicalRequest!;

    emit(ScannerProcessingState(
      eventId: retryRequest.eventId,
      gateId: retryRequest.gateId,
      scanType: retryRequest.scanType,
      deviceId: retryRequest.deviceId,
      adapterName: _activeAdapter.name,
      isOfflineMode: _localStorage.isOfflineModeEnabled,
      queueDepth: _repository.telemetry.pendingQueueDepth,
      telemetry: _repository.telemetry,
      tokenSnippet: 'Retrying ID: ${retryRequest.scanRequestId.substring(0, 6)}...',
      scanRequestId: retryRequest.scanRequestId,
      recentScans: List.unmodifiable(_recentScans),
    ));

    final response = await _repository.validateScan(retryRequest);
    _printScanDetails(retryRequest, response);

    emit(ScannerDecisionState(
      eventId: retryRequest.eventId,
      gateId: retryRequest.gateId,
      scanType: retryRequest.scanType,
      deviceId: retryRequest.deviceId,
      adapterName: _activeAdapter.name,
      isOfflineMode: _localStorage.isOfflineModeEnabled,
      queueDepth: _repository.telemetry.pendingQueueDepth,
      telemetry: _repository.telemetry,
      request: retryRequest,
      response: response,
      recentScans: List.unmodifiable(_recentScans),
    ));

    _feedbackResetTimer?.cancel();
    _feedbackResetTimer = Timer(AppConstants.feedbackDisplayDuration, () {
      if (!isClosed) {
        add(const ScannerFeedbackTimeout());
      }
    });
  }

  Future<void> _onAdapterSwitched(
      ScannerAdapterSwitched event, Emitter<ScannerState> emit) async {
    await _bindAdapter(event.newAdapter);
    _repository.telemetry.currentAdapter = event.newAdapter.name;

    emit(ScannerReadyState(
      eventId: _localStorage.getEventId(),
      gateId: _localStorage.getGateId(),
      scanType: _localStorage.getScanType(),
      deviceId: _localStorage.getDeviceId(),
      adapterName: _activeAdapter.name,
      isOfflineMode: _localStorage.isOfflineModeEnabled,
      queueDepth: _repository.telemetry.pendingQueueDepth,
      telemetry: _repository.telemetry,
      statusMessage: 'Switched to ${_activeAdapter.name}',
      recentScans: List.unmodifiable(_recentScans),
    ));
  }

  Future<void> _onConfigChanged(
      ScannerConfigChanged event, Emitter<ScannerState> emit) async {
    if (event.eventId != null) await _localStorage.setEventId(event.eventId!);
    if (event.gateId != null) await _localStorage.setGateId(event.gateId!);
    if (event.scanType != null) {
      await _localStorage.setScanType(event.scanType!);
    }
    if (event.suppressionMs != null) {
      _suppressionMs = event.suppressionMs!;
      await _localStorage.setSuppressionMs(event.suppressionMs!);
    }
    if (event.offlineModeEnabled != null) {
      await _localStorage.setOfflineMode(event.offlineModeEnabled!);
    }
    if (event.testUsername != null) {
      await _localStorage.setTestUsername(event.testUsername!);
    }
    if (event.section != null) {
      await _localStorage.setSection(event.section!);
    }
    if (event.sectionLocation != null) {
      await _localStorage.setSectionLocation(event.sectionLocation);
    }

    emit(ScannerReadyState(
      eventId: _localStorage.getEventId(),
      gateId: _localStorage.getGateId(),
      scanType: _localStorage.getScanType(),
      deviceId: _localStorage.getDeviceId(),
      adapterName: _activeAdapter.name,
      isOfflineMode: _localStorage.isOfflineModeEnabled,
      queueDepth: _repository.telemetry.pendingQueueDepth,
      telemetry: _repository.telemetry,
      recentScans: List.unmodifiable(_recentScans),
    ));
  }

  Future<void> _onSyncOfflineRequested(
      ScannerSyncOfflineRequested event, Emitter<ScannerState> emit) async {
    final synced = await _repository.syncOfflineScans();
    emit(ScannerReadyState(
      eventId: _localStorage.getEventId(),
      gateId: _localStorage.getGateId(),
      scanType: _localStorage.getScanType(),
      deviceId: _localStorage.getDeviceId(),
      adapterName: _activeAdapter.name,
      isOfflineMode: _localStorage.isOfflineModeEnabled,
      queueDepth: _repository.telemetry.pendingQueueDepth,
      telemetry: _repository.telemetry,
      statusMessage: 'Synced $synced offline records',
      recentScans: List.unmodifiable(_recentScans),
    ));
  }

  Future<void> _onClearOfflineQueueRequested(
      ScannerClearOfflineQueueRequested event,
      Emitter<ScannerState> emit) async {
    await _repository.clearOfflineQueue();
    emit(ScannerReadyState(
      eventId: _localStorage.getEventId(),
      gateId: _localStorage.getGateId(),
      scanType: _localStorage.getScanType(),
      deviceId: _localStorage.getDeviceId(),
      adapterName: _activeAdapter.name,
      isOfflineMode: _localStorage.isOfflineModeEnabled,
      queueDepth: 0,
      telemetry: _repository.telemetry,
      statusMessage: 'Offline queue cleared',
      recentScans: List.unmodifiable(_recentScans),
    ));
  }

  @override
  Future<void> close() {
    _adapterSubscription?.cancel();
    _feedbackResetTimer?.cancel();
    _activeAdapter.dispose();
    return super.close();
  }
}
