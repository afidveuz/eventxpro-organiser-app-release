import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Custom structured exception representing a backend outage, 5xx server failure,
/// or network transport breakdown (timeouts, DNS failures, connection refused).
class ServerDownException implements Exception {
  final int? statusCode;
  final String endpoint;
  final String baseUrl;
  final String message;
  final DateTime timestamp;

  ServerDownException({
    this.statusCode,
    required this.endpoint,
    required this.baseUrl,
    required this.message,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() {
    final statusStr = statusCode != null ? 'HTTP $statusCode' : 'Network/Transport Failure';
    return 'ServerDownException [$statusStr] at $baseUrl$endpoint: $message';
  }
}

class CrashlyticsService {
  static final CrashlyticsService _instance = CrashlyticsService._internal();
  factory CrashlyticsService() => _instance;
  CrashlyticsService._internal();

  bool _isAvailable = false;
  final Map<String, DateTime> _lastReportedTime = {};
  static const Duration _throttleDuration = Duration(seconds: 60);

  bool get isAvailable => _isAvailable;

  /// Initializes Crashlytics handlers for Flutter framework errors & asynchronous Dart errors.
  Future<void> initialize() async {
    try {
      if (Firebase.apps.isEmpty) {
        debugPrint('[CrashlyticsService] ⚠️ Firebase not initialized. Crashlytics disabled.');
        return;
      }

      final crashlytics = FirebaseCrashlytics.instance;

      // Enable collection (always enabled in release/profile, enabled for testing in debug)
      await crashlytics.setCrashlyticsCollectionEnabled(true);

      // Catch uncaught Flutter framework errors (UI rendering, widget lifecycle)
      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.presentError(details);
        crashlytics.recordFlutterFatalError(details);
      };

      // Catch uncaught asynchronous Dart platform errors
      PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
        crashlytics.recordError(error, stack, fatal: true);
        return true;
      };

      _isAvailable = true;
      debugPrint('🔥 [CrashlyticsService] Initialized successfully with global crash hooks.');
    } catch (e, stack) {
      debugPrint('[CrashlyticsService] ❌ Failed to initialize Crashlytics: $e\n$stack');
      _isAvailable = false;
    }
  }

  /// Sets user and device metadata for richer crash and outage debugging.
  Future<void> setDeviceContext({
    String? deviceId,
    int? eventId,
    int? gateId,
    String? username,
    String? baseUrl,
  }) async {
    if (!_isAvailable) return;
    try {
      final crashlytics = FirebaseCrashlytics.instance;
      if (deviceId != null && deviceId.isNotEmpty) {
        await crashlytics.setUserIdentifier(deviceId);
        await crashlytics.setCustomKey('device_id', deviceId);
      }
      if (eventId != null) await crashlytics.setCustomKey('event_id', eventId);
      if (gateId != null) await crashlytics.setCustomKey('gate_id', gateId);
      if (username != null && username.isNotEmpty) {
        await crashlytics.setCustomKey('username', username);
      }
      if (baseUrl != null && baseUrl.isNotEmpty) {
        await crashlytics.setCustomKey('base_url', baseUrl);
      }
    } catch (e) {
      debugPrint('[CrashlyticsService] ⚠️ Failed to set context: $e');
    }
  }

  /// Records a server down or network failure to Firebase Crashlytics as a non-fatal event.
  /// Throttles repeated alerts within 60 seconds to prevent alert flooding during an outage.
  Future<void> recordServerDown({
    required String endpoint,
    required String baseUrl,
    int? statusCode,
    String? errorMessage,
    StackTrace? stackTrace,
    Map<String, dynamic>? extra,
  }) async {
    final now = DateTime.now();
    final throttleKey = '$baseUrl$endpoint-$statusCode';
    final lastTime = _lastReportedTime[throttleKey];

    // Throttle duplicate server-down reports within window to avoid spamming quota
    if (lastTime != null && now.difference(lastTime) < _throttleDuration) {
      log('Repeated Server Down [$statusCode] on $endpoint (throttled)');
      return;
    }
    _lastReportedTime[throttleKey] = now;

    final formattedMessage = errorMessage ?? 'Backend service unreachable or returned server error';
    log('🚨 Server Down detected: [$statusCode] $baseUrl$endpoint - $formattedMessage');

    if (!_isAvailable) return;

    try {
      final crashlytics = FirebaseCrashlytics.instance;
      await crashlytics.setCustomKey('failure_category', 'SERVER_DOWN');
      await crashlytics.setCustomKey('server_endpoint', endpoint);
      await crashlytics.setCustomKey('server_base_url', baseUrl);
      await crashlytics.setCustomKey('http_status', statusCode ?? 0);

      if (extra != null) {
        for (final entry in extra.entries) {
          final val = entry.value;
          if (val is int) {
            await crashlytics.setCustomKey(entry.key, val);
          } else if (val is double) {
            await crashlytics.setCustomKey(entry.key, val);
          } else if (val is bool) {
            await crashlytics.setCustomKey(entry.key, val);
          } else {
            await crashlytics.setCustomKey(entry.key, val.toString());
          }
        }
      }

      final exception = ServerDownException(
        statusCode: statusCode,
        endpoint: endpoint,
        baseUrl: baseUrl,
        message: formattedMessage,
        timestamp: now,
      );

      await crashlytics.recordError(
        exception,
        stackTrace ?? StackTrace.current,
        reason: 'Server Down / Gateway Failure: [HTTP ${statusCode ?? 'ERR'}] $endpoint',
        fatal: false, // Recorded as non-fatal so it doesn't inflate crash-free user stats
      );
    } catch (e) {
      debugPrint('[CrashlyticsService] ⚠️ Error reporting server down to Crashlytics: $e');
    }
  }

  /// Records an unexpected caught exception to Crashlytics.
  Future<void> recordError(
    dynamic exception,
    StackTrace? stackTrace, {
    String? reason,
    bool fatal = false,
  }) async {
    if (!_isAvailable) return;
    try {
      await FirebaseCrashlytics.instance.recordError(
        exception,
        stackTrace ?? StackTrace.current,
        reason: reason,
        fatal: fatal,
      );
    } catch (e) {
      debugPrint('[CrashlyticsService] ⚠️ Failed to record error: $e');
    }
  }

  /// Adds a breadcrumb log to Crashlytics for diagnostics leading up to a crash.
  void log(String message) {
    debugPrint('📝 [Crashlytics Log] $message');
    if (_isAvailable) {
      try {
        FirebaseCrashlytics.instance.log(message);
      } catch (_) {}
    }
  }
}
