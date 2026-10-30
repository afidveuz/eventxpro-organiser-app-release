import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../data/datasources/offline_database_helper.dart';
import '../../data/datasources/scanner_local_storage.dart';
import '../config/app_constants.dart';
import '../network/api_client.dart';

/// Data class holding separate check-in and check-out counts for a gate/session
class GateCheckInOutCount {
  final int checkIn;
  final int checkOut;

  const GateCheckInOutCount({
    this.checkIn = 0,
    this.checkOut = 0,
  });

  GateCheckInOutCount copyWith({
    int? checkIn,
    int? checkOut,
  }) {
    return GateCheckInOutCount(
      checkIn: checkIn ?? this.checkIn,
      checkOut: checkOut ?? this.checkOut,
    );
  }

  @override
  String toString() => 'GateCheckInOutCount(in: $checkIn, out: $checkOut)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GateCheckInOutCount &&
          runtimeType == other.runtimeType &&
          checkIn == other.checkIn &&
          checkOut == other.checkOut;

  @override
  int get hashCode => checkIn.hashCode ^ checkOut.hashCode;
}

class _CacheEntry {
  final GateCheckInOutCount count;
  final DateTime timestamp;

  _CacheEntry(this.count, this.timestamp);
}

/// Service to fetch and manage separate check-in and check-out counts for every gate/session
/// Matching React Native EventXPro hook: `src/screens/Events/hooks/useCount.js`
class GateCountService {
  final ApiClient _apiClient;
  final OfflineDatabaseHelper _dbHelper;
  final ScannerLocalStorage _localStorage;

  // In-memory cache with timestamp for ultra-fast instant UI rendering
  final Map<String, _CacheEntry> _cache = {};

  // In-flight deduplication: map of cache key to active Future
  final Map<String, Future<GateCheckInOutCount>> _inFlight = {};

  // Concurrency limiter: max 3 concurrent network requests to prevent server socket drops
  static const int _maxConcurrent = 3;
  int _activeRequests = 0;
  final List<Completer<void>> _waitQueue = [];

  // Default cache TTL for background checks (30s)
  static const Duration _cacheTtl = Duration(seconds: 30);

  GateCountService({
    required ApiClient apiClient,
    required OfflineDatabaseHelper dbHelper,
    required ScannerLocalStorage localStorage,
  })  : _apiClient = apiClient,
        _dbHelper = dbHelper,
        _localStorage = localStorage;

  String _cacheKey(int eventId, String section, int actionId, String? location) {
    return '$eventId-$section-$actionId-${location ?? ''}';
  }

  GateCheckInOutCount? getCached(int eventId, String section, int actionId, [String? location]) {
    return _cache[_cacheKey(eventId, section, actionId, location)]?.count;
  }

  /// Concurrency queue to throttle simultaneous network calls
  Future<T> _enqueue<T>(Future<T> Function() task) async {
    while (_activeRequests >= _maxConcurrent) {
      final completer = Completer<void>();
      _waitQueue.add(completer);
      await completer.future;
    }
    _activeRequests++;
    try {
      return await task();
    } finally {
      _activeRequests--;
      if (_waitQueue.isNotEmpty) {
        _waitQueue.removeAt(0).complete();
      }
    }
  }

  /// Fetches check-in and check-out count for a specific gate/entrance/session
  /// Matching `organizer/show-counts?event_id=${evId}&action_type=${checkInOutType}&action_id=${checkInOutId}&location=${location}`
  Future<GateCheckInOutCount> getCounts({
    required int eventId,
    required String section,
    required int actionId,
    String? location,
    bool forceRefresh = false,
  }) async {
    final key = _cacheKey(eventId, section, actionId, location);

    // Fast-path: Return cached count if still fresh and not force-refreshing
    final cachedEntry = _cache[key];
    if (!forceRefresh && cachedEntry != null) {
      final isFresh = DateTime.now().difference(cachedEntry.timestamp) < _cacheTtl;
      if (isFresh) {
        return cachedEntry.count;
      }
    }

    // In-flight deduplication: If a request for this exact target is currently pending, share it
    if (_inFlight.containsKey(key)) {
      return _inFlight[key]!;
    }

    final future = _executeGetCounts(
      key: key,
      eventId: eventId,
      section: section,
      actionId: actionId,
      location: location,
    );

    _inFlight[key] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove(key);
    }
  }

  Future<GateCheckInOutCount> _executeGetCounts({
    required String key,
    required int eventId,
    required String section,
    required int actionId,
    String? location,
  }) async {
    // Map internal section identifier to backend action_type
    final String actionType;
    switch (section.toLowerCase()) {
      case 'entrances':
      case 'entrance':
        actionType = 'entrance';
        break;
      case 'hall':
      case 'halls':
        actionType = 'hall';
        break;
      case 'agenda':
      case 'agendas':
        actionType = 'agenda';
        break;
      case 'session':
      case 'sessions':
      case 'session_type':
        actionType = 'session_type';
        break;
      default:
        actionType = section;
    }

    // 1. Offline Mode: Fetch directly from SQLite WAL database
    if (_localStorage.isOfflineModeEnabled) {
      final local = await _dbHelper.getGateCheckInOutCount(
        eventId: eventId,
        section: section,
        entranceId: actionId,
      );
      final count = GateCheckInOutCount(
        checkIn: local['in'] ?? 0,
        checkOut: local['out'] ?? 0,
      );
      _cache[key] = _CacheEntry(count, DateTime.now());
      return count;
    }

    // 2. Online Mode: Query backend API throttled via concurrency queue
    try {
      final queryParams = <String, dynamic>{
        'event_id': eventId,
        'action_type': actionType,
        'action_id': actionId,
      };
      if (location != null && location.isNotEmpty && location != 'null') {
        queryParams['location'] = location;
      }

      final res = await _enqueue(() => _fetchWithRetry(queryParams));

      if (res != null && res.statusCode == 200 && res.data != null) {
        final data = res.data is Map
            ? Map<String, dynamic>.from(res.data as Map)
            : Map<String, dynamic>.from(jsonDecode(res.data.toString()) as Map);

        if (data['status'] == true) {
          final serverIn = (data['checkin_count'] as num?)?.toInt() ??
              int.tryParse(data['checkin_count']?.toString() ?? '') ??
              0;
          final serverOut = (data['checkout_count'] as num?)?.toInt() ??
              int.tryParse(data['checkout_count']?.toString() ?? '') ??
              0;

          // Merge any unsynced scans saved locally on this device
          final unsynced = await _dbHelper.getUnsyncedGateCheckInOutCount(
            eventId: eventId,
            section: section,
            entranceId: actionId,
          );
          final pendingIn = unsynced['in'] ?? 0;
          final pendingOut = unsynced['out'] ?? 0;

          final count = GateCheckInOutCount(
            checkIn: serverIn + pendingIn,
            checkOut: serverOut + pendingOut,
          );
          _cache[key] = _CacheEntry(count, DateTime.now());
          return count;
        }
      }
    } catch (e) {
      debugPrint('[GateCountService] ⚠️ Error fetching counts for $actionType #$actionId: $e');
    }

    // 3. Fallback: Query SQLite database if API call fails
    final local = await _dbHelper.getGateCheckInOutCount(
      eventId: eventId,
      section: section,
      entranceId: actionId,
    );
    final count = GateCheckInOutCount(
      checkIn: local['in'] ?? 0,
      checkOut: local['out'] ?? 0,
    );
    _cache[key] = _CacheEntry(count, DateTime.now());
    return count;
  }

  /// Performs network GET with 1 transient retry on connection error
  Future<Response?> _fetchWithRetry(Map<String, dynamic> queryParams) async {
    try {
      return await _apiClient.dio.get(
        AppConstants.showCountsEndpoint,
        queryParameters: queryParams,
        options: Options(
          extra: {'skipCrashlyticsReport': true},
        ),
      );
    } on DioException catch (e) {
      // If transient connection drop (e.g. connection closed before header), retry once
      final isConnectionIssue = e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout;
      if (isConnectionIssue) {
        await Future.delayed(const Duration(milliseconds: 300));
        return await _apiClient.dio.get(
          AppConstants.showCountsEndpoint,
          queryParameters: queryParams,
          options: Options(
            extra: {'skipCrashlyticsReport': true},
          ),
        );
      }
      rethrow;
    }
  }

  /// Increments local count in memory immediately upon a successful scan
  void incrementCount({
    required int eventId,
    required String section,
    required int actionId,
    required String punchType,
    String? location,
  }) {
    final key = _cacheKey(eventId, section, actionId, location);
    final current = _cache[key]?.count ?? const GateCheckInOutCount();
    final isCheckIn = punchType.toLowerCase().contains('in') ||
        punchType.toLowerCase().contains('entry');

    final updated = current.copyWith(
      checkIn: isCheckIn ? current.checkIn + 1 : current.checkIn,
      checkOut: !isCheckIn ? current.checkOut + 1 : current.checkOut,
    );
    _cache[key] = _CacheEntry(updated, DateTime.now());
  }

  void clearCache() {
    _cache.clear();
  }
}
