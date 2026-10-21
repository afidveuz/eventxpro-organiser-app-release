import 'package:equatable/equatable.dart';
import 'attendee.dart';
import 'scan_decision_code.dart';

/// Response entity representing the authoritative admission decision.
class ScanResponse extends Equatable {
  final String status;
  final ScanDecisionCode code;
  final String message;
  final Attendee? attendee;
  final String? checkInId;
  final DateTime? serverTime;
  final int latencyMs;
  final int? decodeToEventMs;
  final String? scanRequestId;
  final String? testApiResponse;

  const ScanResponse({
    required this.status,
    required this.code,
    required this.message,
    this.attendee,
    this.checkInId,
    this.serverTime,
    this.latencyMs = 0,
    this.decodeToEventMs,
    this.scanRequestId,
    this.testApiResponse,
  });

  factory ScanResponse.fromJson(
    Map<String, dynamic> json, {
    int latencyMs = 0,
    int? decodeToEventMs,
    String? scanRequestId,
  }) {
    final rawCode = json['code'] as String?;
    final decisionCode = ScanDecisionCode.fromCode(rawCode);

    // Only allow attendee parsing if the response is actually accepted (least-privilege security)
    Attendee? parsedAttendee;
    if (decisionCode.isSuccess && json['attendee'] != null) {
      parsedAttendee = Attendee.fromJson(json['attendee'] as Map<String, dynamic>);
    }

    DateTime? parsedServerTime;
    if (json['server_time'] != null) {
      parsedServerTime = DateTime.tryParse(json['server_time'] as String);
    }

    return ScanResponse(
      status: json['status'] as String? ?? decisionCode.status,
      code: decisionCode,
      message: json['message'] as String? ?? 'Processed',
      attendee: parsedAttendee,
      checkInId: json['check_in_id'] as String?,
      serverTime: parsedServerTime,
      latencyMs: latencyMs,
      decodeToEventMs: decodeToEventMs,
      scanRequestId: scanRequestId,
      testApiResponse: json['test_api_response'] as String?,
    );
  }

  factory ScanResponse.networkError({
    required String message,
    required int latencyMs,
    String? scanRequestId,
    String? testApiResponse,
  }) {
    return ScanResponse(
      status: 'PENDING',
      code: ScanDecisionCode.networkError,
      message: message,
      attendee: null,
      latencyMs: latencyMs,
      scanRequestId: scanRequestId,
      testApiResponse: testApiResponse,
    );
  }

  factory ScanResponse.offlineQueued({
    required String scanRequestId,
    int latencyMs = 0,
    String? testApiResponse,
  }) {
    return ScanResponse(
      status: 'QUEUED',
      code: ScanDecisionCode.networkError,
      message: 'Stored in offline queue for background sync',
      attendee: null,
      latencyMs: latencyMs,
      scanRequestId: scanRequestId,
      testApiResponse: testApiResponse,
    );
  }

  ScanResponse copyWith({
    String? status,
    ScanDecisionCode? code,
    String? message,
    Attendee? attendee,
    String? checkInId,
    DateTime? serverTime,
    int? latencyMs,
    int? decodeToEventMs,
    String? scanRequestId,
    String? testApiResponse,
  }) {
    return ScanResponse(
      status: status ?? this.status,
      code: code ?? this.code,
      message: message ?? this.message,
      attendee: attendee ?? this.attendee,
      checkInId: checkInId ?? this.checkInId,
      serverTime: serverTime ?? this.serverTime,
      latencyMs: latencyMs ?? this.latencyMs,
      decodeToEventMs: decodeToEventMs ?? this.decodeToEventMs,
      scanRequestId: scanRequestId ?? this.scanRequestId,
      testApiResponse: testApiResponse ?? this.testApiResponse,
    );
  }

  @override
  List<Object?> get props => [
        status,
        code,
        message,
        attendee,
        checkInId,
        serverTime,
        latencyMs,
        decodeToEventMs,
        scanRequestId,
        testApiResponse,
      ];
}
