import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../core/config/app_constants.dart';
import '../../domain/entities/scan_decision_code.dart';
import '../../domain/entities/scan_request.dart';
import '../../domain/entities/scan_response.dart';
import 'auth_local_storage.dart';

class DjangoScanApiDatasource {
  final Dio _dio;
  final AuthLocalStorage? _authLocalStorage;
  bool useMockServer = false;

  // In-memory set of already checked-in QR tokens for unit testing simulation
  final Set<String> _admittedTokens = {};

  DjangoScanApiDatasource({
    Dio? dio,
    AuthLocalStorage? authLocalStorage,
  })  : _authLocalStorage = authLocalStorage,
        _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: authLocalStorage?.getBaseUrl() ?? AppConstants.defaultBaseUrl,
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

  /// Authoritative QR Code Validation connecting directly to EventXPro:
  /// POST organizer/event-entrance
  Future<ScanResponse> validateScan(ScanRequest request) async {
    final stopwatch = Stopwatch()..start();

    // If unit test explicitly requests mock simulation
    if (useMockServer) {
      return _simulateDjangoAdmission(request, stopwatch);
    }

    // Keep BaseUrl synchronized with user configuration
    if (_authLocalStorage != null) {
      _dio.options.baseUrl = _authLocalStorage.getBaseUrl();
    }

    final token = _authLocalStorage?.getToken();
    final qrInput = request.qrToken.trim();
    final isDigitsOnly = RegExp(r'^\d+$').hasMatch(qrInput);
    int scanType = isDigitsOnly ? 1 : 0;

    final String punchType =
        request.scanType.toUpperCase() == 'EXIT' ? 'check_out' : 'check_in';

    Map<String, dynamic> payload = {
      'event_id': 1,
      'type': punchType,
      'user_latitude': 11.0,
      'user_longitude': 12.0,
      'user_city': '',
      'user_input': qrInput,
      'scan_type': scanType,
    };

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      'X-Request-ID': request.scanRequestId,
      'X-Device-ID': request.deviceId,
    };

    try {
      Response response = await _dio.post(
        AppConstants.eventEntranceEndpoint,
        data: payload,
        options: Options(
          headers: headers,
          validateStatus: (status) => true,
        ),
      );

      var data = response.data is String
          ? jsonDecode(response.data as String) as Map<String, dynamic>
          : (response.data is Map<String, dynamic>
              ? response.data as Map<String, dynamic>
              : <String, dynamic>{'raw': response.data.toString()});

      // If user not found with scan_type 1 (numeric), retry once with scan_type 0 (or vice versa)
      final String msg = (data['message'] as String? ??
              data['detail'] as String? ??
              '')
          .toLowerCase();

      if (msg.contains('not found') && isDigitsOnly) {
        payload['scan_type'] = 0;
        final retryResponse = await _dio.post(
          AppConstants.eventEntranceEndpoint,
          data: payload,
          options: Options(
            headers: headers,
            validateStatus: (status) => true,
          ),
        );
        if (retryResponse.statusCode == 200 && retryResponse.data is Map) {
          response = retryResponse;
          data = retryResponse.data is String
              ? jsonDecode(retryResponse.data as String) as Map<String, dynamic>
              : retryResponse.data as Map<String, dynamic>;
        }
      }

      stopwatch.stop();
      final latencyMs = stopwatch.elapsedMilliseconds;
      final summary =
          '[HTTP ${response.statusCode}]: ${data['message'] ?? data['detail'] ?? (data['status'] == true ? 'OK' : 'FAILED')}';

      _printScanApiResponse(
        url: '${_dio.options.baseUrl}${AppConstants.eventEntranceEndpoint}',
        headers: headers,
        payload: payload,
        statusCode: response.statusCode ?? 200,
        responseBody: jsonEncode(data),
        latencyMs: latencyMs,
        isSuccess: data['status'] == true,
      );

      return ScanResponse.fromJson(
        data,
        latencyMs: latencyMs,
        scanRequestId: request.scanRequestId,
      ).copyWith(testApiResponse: summary);
    } on DioException catch (dioErr) {
      stopwatch.stop();
      final statusCode = dioErr.response?.statusCode ?? 0;
      final rawData = dioErr.response?.data;

      if (rawData is Map<String, dynamic>) {
        final summary = '[HTTP $statusCode]: ${rawData['message'] ?? rawData['detail'] ?? 'Error'}';
        return ScanResponse.fromJson(
          rawData,
          latencyMs: stopwatch.elapsedMilliseconds,
          scanRequestId: request.scanRequestId,
        ).copyWith(testApiResponse: summary);
      }

      return ScanResponse.networkError(
        message: 'Network Unreachable: ${dioErr.message ?? dioErr.type.name}',
        latencyMs: stopwatch.elapsedMilliseconds,
        scanRequestId: request.scanRequestId,
        testApiResponse: '[NET ERROR]: ${dioErr.type.name}',
      );
    } catch (e) {
      stopwatch.stop();
      return ScanResponse.networkError(
        message: 'Client Transport Failure: $e',
        latencyMs: stopwatch.elapsedMilliseconds,
        scanRequestId: request.scanRequestId,
        testApiResponse: '[ERROR]: $e',
      );
    }
  }

  void _printScanApiResponse({
    required String url,
    required Map<String, String> headers,
    required Map<String, dynamic> payload,
    required int statusCode,
    required String responseBody,
    required int latencyMs,
    bool isSuccess = false,
  }) {
    final statusBadge = isSuccess
        ? '✅ HTTP $statusCode (CHECK-IN SUCCESS)'
        : 'ℹ️ HTTP $statusCode (RESPONSE RECEIVED)';
    final banner = '''
╔════════════════════════════════════════════════════════════════
║ [EVENTXPRO REAL ENTRANCE SCAN API]
╠════════════════════════════════════════════════════════════════
║  Endpoint:     $url
║  Payload:      ${jsonEncode(payload)}
╠════════════════════════════════════════════════════════════════
║  Status:       $statusBadge
║  Latency:      $latencyMs ms
║  Response:     $responseBody
╚════════════════════════════════════════════════════════════════''';
    debugPrint(banner);
  }

  /// Authoritative admission simulator retained for deterministic unit tests
  Future<ScanResponse> _simulateDjangoAdmission(
      ScanRequest request, Stopwatch stopwatch) async {
    await Future.delayed(const Duration(milliseconds: 30));
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
    if (token.contains('WRONG') || token.contains('9999')) {
      return ScanResponse(
        status: 'REJECTED',
        code: ScanDecisionCode.wrongEvent,
        message: 'Badge registered for a different event',
        latencyMs: latency,
        scanRequestId: request.scanRequestId,
      );
    }

    // 3. Expired badge check
    if (token.contains('EXP') || token.contains('EXPIRED')) {
      return ScanResponse(
        status: 'REJECTED',
        code: ScanDecisionCode.expired,
        message: 'Badge validity expired',
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

    // 5. Already Checked In check
    if (_admittedTokens.contains(token) || token.contains('USED')) {
      return ScanResponse(
        status: 'WARNING',
        code: ScanDecisionCode.alreadyCheckedIn,
        message: 'Warning: Badge already admitted (Entry Limited)',
        checkInId: 'chk-${request.scanRequestId.length >= 8 ? request.scanRequestId.substring(0, 8) : request.scanRequestId}',
        serverTime: DateTime.now(),
        latencyMs: latency,
        scanRequestId: request.scanRequestId,
      );
    }

    // 6. Valid Admission
    _admittedTokens.add(token);

    String attendeeName = 'Alex Mercer';
    String badgeType = 'VIP Attendee';
    String company = 'EventX Global Corp';

    if (token.contains('VIP')) {
      attendeeName = 'Victoria Sterling';
      badgeType = 'VIP Speaker';
      company = 'Quantum Analytics';
    } else if (token.contains('EXH')) {
      attendeeName = 'Marcus Vance';
      badgeType = 'Exhibitor';
      company = 'Partner Exhibitor';
    }

    return ScanResponse.fromJson(
      {
        'status': true,
        'message': 'Checked In Successfully!',
        'user_data': {
          'firstname': attendeeName.split(' ').first,
          'lastname': attendeeName.split(' ').length > 1 ? attendeeName.split(' ').last : '',
          'ticket_type_cat': badgeType,
          'company_name': company,
          'unique_id': token,
        },
        'check_in_id': 'chk-${request.scanRequestId.length >= 8 ? request.scanRequestId.substring(0, 8) : request.scanRequestId}',
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
