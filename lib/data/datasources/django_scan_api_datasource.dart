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

    final cleanType = request.scanType.toLowerCase().trim();
    final punchType = (cleanType == 'check_out' || cleanType == 'exit')
        ? 'check_out'
        : 'check_in';

    String endpoint = AppConstants.eventEntranceEndpoint;
    Map<String, dynamic> payload = {
      'event_id': request.eventId > 0 ? request.eventId : 1,
      'type': punchType,
      'user_latitude': 11.0,
      'user_longitude': 12.0,
      'user_city': '',
      'user_input': qrInput,
      'scan_type': scanType,
    };

    if (request.section == 'hall') {
      endpoint = 'organizer/event-hall-entrance';
      payload['hall_id'] = request.gateId;
    } else if (request.section == 'agenda') {
      endpoint = 'organizer/event-agenda-entrance';
      payload['agenda_id'] = request.gateId;
    } else if (request.section == 'session') {
      endpoint = 'organizer/event-sessiontype-entrance';
      payload['sessiontype_id'] = request.gateId;
    } else {
      endpoint = AppConstants.eventEntranceEndpoint;
      if (request.gateId > 0) payload['entrance_id'] = request.gateId;
      if (request.sectionLocation != null && request.sectionLocation!.isNotEmpty) {
        payload['location'] = request.sectionLocation;
      }
    }

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      'X-Request-ID': request.scanRequestId,
      'X-Device-ID': request.deviceId,
    };

    try {
      Response response = await _dio.post(
        endpoint,
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
      return ScanResponse.fromJson(
        {
          'status': false,
          'alert_type': 'warning',
          'message': 'Already Checked In',
          'punch_time': '14:20',
          'last_checkin_session': 'Main Gate',
          'last_checkin_time': '14:20:00',
          'user_data': {
            'firstname': 'Victoria',
            'lastname': 'Sterling',
            'ticket_type_cat': 'VIP Speaker',
            'company_name': 'Quantum Analytics',
            'unique_id': 'TICK-${token.hashCode.abs() % 100000}',
            'reg_cat': 'VIP',
          },
          'check_in_id': 'chk-${request.scanRequestId.length >= 8 ? request.scanRequestId.substring(0, 8) : request.scanRequestId}',
          'server_time': DateTime.now().toUtc().toIso8601String(),
        },
        latencyMs: latency,
        scanRequestId: request.scanRequestId,
      );
    }

    // 6. Valid Admission
    _admittedTokens.add(token);

    String attendeeName = 'Alex Mercer';
    String badgeType = 'VIP Attendee';
    String company = 'EventX Global Corp';
    String regCat = 'DELEGATE';

    if (token.contains('VIP')) {
      attendeeName = 'Victoria Sterling';
      badgeType = 'VIP Speaker';
      company = 'Quantum Analytics';
      regCat = 'VIP';
    } else if (token.contains('EXH')) {
      attendeeName = 'Marcus Vance';
      badgeType = 'Exhibitor';
      company = 'Partner Exhibitor';
      regCat = 'EXHIBITOR';
    }

    return ScanResponse.fromJson(
      {
        'status': true,
        'alert_type': 'success',
        'message': 'Checked In Successfully!',
        'punch_time': '15:30',
        'last_checkin_session': 'Main Entrance',
        'last_checkin_time': '12:00:00',
        'user_data': {
          'firstname': attendeeName.split(' ').first,
          'lastname': attendeeName.split(' ').length > 1 ? attendeeName.split(' ').last : '',
          'ticket_type_cat': badgeType,
          'company_name': company,
          'unique_id': 'TICK-${token.hashCode.abs() % 100000}',
          'reg_cat': regCat,
        },
        'session_access': [
          {
            'title': 'Keynote Conference',
            'start_tm': '10:00',
            'hall_name': 'Hall 1',
          },
        ],
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

  /// High-performance chunked batch synchronization matching Django endpoints.
  /// Sends up to 100 records in a single payload.
  Future<BatchSyncResult> syncOfflineBatch({
    required String section,
    required int eventId,
    required List<dynamic> chunk, // List<CheckinRecord>
  }) async {
    if (chunk.isEmpty) {
      return const BatchSyncResult();
    }

    final token = _authLocalStorage?.getToken();
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };

    // Determine endpoint & id key based on section
    String endpoint;
    String idKey;

    switch (section.toLowerCase()) {
      case 'hall':
        endpoint = 'organizer/offline-mode-hall-action';
        idKey = 'hall_id';
        break;
      case 'agenda':
        endpoint = 'organizer/offline-mode-agenda-action';
        idKey = 'agenda_id';
        break;
      case 'session':
        endpoint = 'organizer/offline-mode-sessiontype-action';
        idKey = 'sessiontype_id';
        break;
      case 'entrances':
      default:
        endpoint = 'organizer/offline-mode-entrance-action';
        idKey = 'entrance_id';
        break;
    }

    final formPayload = chunk.map((item) {
      final date = item.timestamp as DateTime;
      final dateStr =
          '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      final timeStr =
          '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
      final datetimeStr = '$dateStr $timeStr';

      return {
        'app_id': item.id,
        'user_input': item.code,
        'action_type': item.scanType,
        'event_id': eventId,
        'new_date': dateStr,
        'new_time': timeStr,
        'datetime_string': datetimeStr,
        idKey: item.entranceId,
        'location': item.entranceLocation,
      };
    }).toList();

    try {
      final response = await _dio.post(
        endpoint,
        data: formPayload,
        options: Options(
          headers: headers,
          validateStatus: (status) => true,
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data is String
            ? jsonDecode(response.data as String) as Map<String, dynamic>
            : (response.data as Map<String, dynamic>);

        int parseId(dynamic val) {
          if (val == null) return 0;
          if (val is num) return val.toInt();
          if (val is String) return int.tryParse(val) ?? 0;
          return 0;
        }

        final updatedList = (data['updated_records_app_id'] as List<dynamic>?)
                ?.map(parseId)
                .where((id) => id > 0)
                .toList() ??
            [];
        final notExistsList = (data['not_exists_users_app_id'] as List<dynamic>?)
                ?.map(parseId)
                .where((id) => id > 0)
                .toList() ??
            [];

        return BatchSyncResult(
          updatedRecordsAppId: updatedList,
          notExistsUsersAppId: notExistsList,
          isSuccess: true,
        );
      } else {
        return BatchSyncResult(
          isSuccess: false,
          errorMessage: 'Server responded with status: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('[DjangoScanApiDatasource] ❌ syncOfflineBatch error: $e');
      return BatchSyncResult(
        isSuccess: false,
        errorMessage: e.toString(),
      );
    }
  }
}

class BatchSyncResult {
  final List<int> updatedRecordsAppId;
  final List<int> notExistsUsersAppId;
  final bool isSuccess;
  final String? errorMessage;

  const BatchSyncResult({
    this.updatedRecordsAppId = const [],
    this.notExistsUsersAppId = const [],
    this.isSuccess = true,
    this.errorMessage,
  });
}
