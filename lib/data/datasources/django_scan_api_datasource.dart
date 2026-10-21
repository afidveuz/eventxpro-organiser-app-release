import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../core/config/app_constants.dart';
import '../../domain/entities/scan_decision_code.dart';
import '../../domain/entities/scan_request.dart';
import '../../domain/entities/scan_response.dart';

class DjangoScanApiDatasource {
  final Dio _dio;
  bool useMockServer = false;

  // In-memory set of already checked-in QR tokens to simulate Django database constraints
  final Set<String> _admittedTokens = {};

  DjangoScanApiDatasource({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: AppConstants.defaultBaseUrl,
                connectTimeout: AppConstants.defaultNetworkTimeout,
                receiveTimeout: AppConstants.defaultNetworkTimeout,
                headers: {
                  'Content-Type': 'application/json',
                  'Accept': 'application/json',
                },
              ),
            );

  void updateBaseUrl(String url) {
    _dio.options.baseUrl = url;
  }

  String testUsername = 'user@example.com';

  /// Test Login API requested by user:
  /// POST https://riseexpobackend-staging.veuzco.com/kiosk/api/v1/login
  /// Pass scanned code as password
  Future<String> callTestLoginApi({
    required String scannedCode,
    String? username,
    int type = 2,
  }) async {
    final user = username ?? testUsername;
    const url = 'https://riseexpobackend-staging.veuzco.com/kiosk/api/v1/login';
    final payload = {
      'username': user,
      'password': scannedCode,
      'type': type,
    };

    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'User-Agent': 'GitexKiosk/1.0.0',
    };

    final stopwatch = Stopwatch()..start();
    try {
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          validateStatus: (status) => true,
        ),
      );

      final response = await dio.post(
        url,
        data: payload,
        options: Options(headers: headers),
      );

      stopwatch.stop();
      final responseBody = response.data is String
          ? response.data
          : jsonEncode(response.data);

      _printTestApiResponse(
        url: url,
        headers: headers,
        payload: payload,
        statusCode: response.statusCode ?? 200,
        responseBody: responseBody.toString(),
        latencyMs: stopwatch.elapsedMilliseconds,
      );

      return '[HTTP ${response.statusCode}]: $responseBody';
    } on DioException catch (dioErr) {
      stopwatch.stop();
      final statusCode = dioErr.response?.statusCode ?? 0;
      final rawData = dioErr.response?.data;
      String responseBody;
      if (rawData == null || (rawData is String && rawData.isEmpty)) {
        responseBody = dioErr.message ?? 'HTTP $statusCode Error';
      } else if (rawData is String) {
        responseBody = rawData;
      } else {
        try {
          responseBody = jsonEncode(rawData);
        } catch (_) {
          responseBody = rawData.toString();
        }
      }

      _printTestApiResponse(
        url: url,
        headers: headers,
        payload: payload,
        statusCode: statusCode,
        responseBody: responseBody.toString(),
        latencyMs: stopwatch.elapsedMilliseconds,
        isError: true,
      );

      return '[HTTP $statusCode]: $responseBody';
    } catch (e) {
      stopwatch.stop();
      _printTestApiResponse(
        url: url,
        headers: headers,
        payload: payload,
        statusCode: 0,
        responseBody: e.toString(),
        latencyMs: stopwatch.elapsedMilliseconds,
        isError: true,
      );

      return '[ERROR]: $e';
    }
  }

  void _printTestApiResponse({
    required String url,
    required Map<String, String> headers,
    required Map<String, dynamic> payload,
    required int statusCode,
    required String responseBody,
    required int latencyMs,
    bool isError = false,
  }) {
    final statusBadge = statusCode == 200
        ? '✅ 200 OK (AUTHORIZED)'
        : (isError ? '⚠️ HTTP $statusCode (FAILED)' : 'ℹ️ HTTP $statusCode');
    final banner = '''
╔════════════════════════════════════════════════════════════════
║ [TEST LOGIN API CALL - AFTER SCAN]
╠════════════════════════════════════════════════════════════════
║  Endpoint:     $url
║  Headers:      Content-Type: ${headers['Content-Type']}
║                Accept: ${headers['Accept']}
║                User-Agent: ${headers['User-Agent']}
║  Payload:      ${jsonEncode(payload)}
╠════════════════════════════════════════════════════════════════
║  Status:       $statusBadge
║  Latency:      $latencyMs ms
║  Response:     $responseBody
╚════════════════════════════════════════════════════════════════''';
    // Print directly to terminal stdout
    debugPrint(banner);
  }

  Future<ScanResponse> validateScan(ScanRequest request) async {
    final stopwatch = Stopwatch()..start();

    // Trigger test login API with scanned code as password
    String? testApiSummary;
    if (!useMockServer) {
      testApiSummary = await callTestLoginApi(
        scannedCode: request.qrToken,
        username: testUsername,
      );
    }

    // If Mock server is forced or URL is mock
    if (useMockServer || _dio.options.baseUrl.contains('mock') || _dio.options.baseUrl.contains('eventxpro.com')) {
      final simResponse = await _simulateDjangoAdmission(request, stopwatch);
      return simResponse.copyWith(testApiResponse: testApiSummary);
    }

    try {
      final response = await _dio.post(
        AppConstants.scanValidateEndpoint,
        data: request.toJson(),
        options: Options(
          headers: {
            'X-Request-ID': request.scanRequestId,
            'X-Device-ID': request.deviceId,
          },
        ),
      );

      stopwatch.stop();
      final data = response.data is String
          ? jsonDecode(response.data as String) as Map<String, dynamic>
          : response.data as Map<String, dynamic>;

      return ScanResponse.fromJson(
        data,
        latencyMs: stopwatch.elapsedMilliseconds,
        scanRequestId: request.scanRequestId,
      ).copyWith(testApiResponse: testApiSummary);
    } on DioException catch (dioErr) {
      stopwatch.stop();
      // If server returned structured JSON error with decision code (e.g. 403, 409, 422)
      if (dioErr.response?.data != null && dioErr.response?.data is Map) {
        final data = dioErr.response!.data as Map<String, dynamic>;
        return ScanResponse.fromJson(
          data,
          latencyMs: stopwatch.elapsedMilliseconds,
          scanRequestId: request.scanRequestId,
        ).copyWith(testApiResponse: testApiSummary);
      }

      // If network unreachable, fallback to simulation or network error
      return ScanResponse.networkError(
        message: 'Network Timeout / Unreachable (${dioErr.type.name})',
        latencyMs: stopwatch.elapsedMilliseconds,
        scanRequestId: request.scanRequestId,
        testApiResponse: testApiSummary,
      );
    } catch (e) {
      stopwatch.stop();
      return ScanResponse.networkError(
        message: 'Client Transport Failure: $e',
        latencyMs: stopwatch.elapsedMilliseconds,
        scanRequestId: request.scanRequestId,
        testApiResponse: testApiSummary,
      );
    }
  }

  /// Authoritative Django DRF Admission Simulator.
  /// Follows Section 8 & 9 rules:
  /// - Deterministic outcomes
  /// - Single-entry verification
  /// - Checks event_id and token shape
  /// - No PII revealed on rejection
  Future<ScanResponse> _simulateDjangoAdmission(
      ScanRequest request, Stopwatch stopwatch) async {
    // Add realistic 45ms server transaction latency
    await Future.delayed(const Duration(milliseconds: 45));
    stopwatch.stop();
    final latency = stopwatch.elapsedMilliseconds;
    final token = request.qrToken.trim();

    // 1. Shape / malformed validation
    if (token.isEmpty || token.startsWith('MALFORMED') || token.length < 4) {
      return ScanResponse(
        status: 'REJECTED',
        code: ScanDecisionCode.invalidBadge,
        message: 'Invalid badge format or unreadable token',
        latencyMs: latency,
        scanRequestId: request.scanRequestId,
      );
    }

    // 2. Wrong Event check
    if (token.contains('WRONG') || token.contains('1025') || request.eventId != AppConstants.defaultEventId) {
      return ScanResponse(
        status: 'REJECTED',
        code: ScanDecisionCode.wrongEvent,
        message: 'Badge registered for a different event (Event #${request.eventId})',
        latencyMs: latency,
        scanRequestId: request.scanRequestId,
      );
    }

    // 3. Expired badge check
    if (token.contains('EXP') || token.contains('EXPIRED')) {
      return ScanResponse(
        status: 'REJECTED',
        code: ScanDecisionCode.expired,
        message: 'Badge validity expired on 2026-10-18',
        latencyMs: latency,
        scanRequestId: request.scanRequestId,
      );
    }

    // 4. Access Denied / Revoked badge check
    if (token.contains('DENIED') || token.contains('BLOCKED')) {
      return ScanResponse(
        status: 'REJECTED',
        code: ScanDecisionCode.accessDenied,
        message: 'Security Alert: Access revoked by event administrator',
        latencyMs: latency,
        scanRequestId: request.scanRequestId,
      );
    }

    // 5. Single-Entry / Already Checked In check
    if (_admittedTokens.contains(token) || token.contains('USED')) {
      return ScanResponse(
        status: 'WARNING',
        code: ScanDecisionCode.alreadyCheckedIn,
        message: 'Warning: Badge already admitted at Gate #02 at 10:42 AM',
        checkInId: 'chk-${request.scanRequestId.length >= 8 ? request.scanRequestId.substring(0, 8) : request.scanRequestId}',
        serverTime: DateTime.now(),
        latencyMs: latency,
        scanRequestId: request.scanRequestId,
      );
    }

    // 6. Valid Admission (ENTRY_ALLOWED)
    _admittedTokens.add(token);

    // Dynamic attendee parsing based on token flavor
    String attendeeName = 'Alex Mercer';
    String badgeType = 'VIP Attendee';
    String company = 'EventX Global Corp';

    if (token.contains('VIP')) {
      attendeeName = 'Victoria Sterling';
      badgeType = 'VIP Speaker';
      company = 'Quantum Analytics';
    } else if (token.contains('EXH') || token.contains('EXHIBITOR')) {
      attendeeName = 'Marcus Vance';
      badgeType = 'Exhibitor';
      company = 'Zebra Technologies Partner';
    } else if (token.contains('PRESS')) {
      attendeeName = 'Elena Rostova';
      badgeType = 'Press & Media';
      company = 'Tech Tribune';
    } else if (token.length > 8) {
      attendeeName = 'Attendee #${token.substring(token.length - 4)}';
      badgeType = 'Delegate';
      company = 'Registered Partner';
    }

    final fakeAttendee = {
      'name': attendeeName,
      'badge_type': badgeType,
      'company': company,
    };

    final safeId = request.scanRequestId.length >= 8
        ? request.scanRequestId.substring(0, 8)
        : request.scanRequestId;

    return ScanResponse.fromJson(
      {
        'status': 'ACCEPTED',
        'code': 'ENTRY_ALLOWED',
        'message': 'Access granted - Welcome to EventXPro',
        'attendee': fakeAttendee,
        'check_in_id': 'chk-$safeId',
        'server_time': DateTime.now().toUtc().toIso8601String(),
      },
      latencyMs: latency,
      scanRequestId: request.scanRequestId,
    );
  }

  void resetSimulatedDatabase() {
    _admittedTokens.clear();
  }
}
