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
    ScanDecisionCode decisionCode;

    if (rawCode != null) {
      decisionCode = ScanDecisionCode.fromCode(rawCode);
    } else {
      final isStatusTrue = json['status'] == true;
      final msg = (json['message'] as String? ?? json['detail'] as String? ?? '').toLowerCase();

      if (isStatusTrue) {
        decisionCode = ScanDecisionCode.entryAllowed;
      } else if (msg.contains('limited') || msg.contains('already')) {
        decisionCode = ScanDecisionCode.alreadyCheckedIn;
      } else if (msg.contains('not found') || msg.contains('valid code') || msg.contains('invalid')) {
        decisionCode = ScanDecisionCode.invalidBadge;
      } else if (msg.contains('expired')) {
        decisionCode = ScanDecisionCode.expired;
      } else {
        decisionCode = ScanDecisionCode.accessDenied;
      }
    }

    Attendee? parsedAttendee;
    if (json['attendee'] != null && json['attendee'] is Map<String, dynamic>) {
      parsedAttendee = Attendee.fromJson(json['attendee'] as Map<String, dynamic>);
    } else if (json['user_data'] != null && json['user_data'] is Map<String, dynamic>) {
      final u = json['user_data'] as Map<String, dynamic>;
      final fn = (u['firstname'] as String? ?? '').trim();
      final ln = (u['lastname'] as String? ?? '').trim();
      final fullName = '$fn $ln'.trim();
      parsedAttendee = Attendee(
        name: fullName.isNotEmpty ? fullName : 'Attendee',
        badgeType: u['ticket_type_cat'] as String? ?? u['display_ticket_name'] as String? ?? 'Authorized Badge',
        company: u['company_name'] as String?,
        category: u['reg_cat'] as String?,
      );
    }

    DateTime? parsedServerTime;
    if (json['server_time'] != null) {
      parsedServerTime = DateTime.tryParse(json['server_time'] as String);
    }

    final String statusStr = json['status'] is bool
        ? (json['status'] == true
            ? 'ACCEPTED'
            : (decisionCode == ScanDecisionCode.alreadyCheckedIn ? 'WARNING' : 'REJECTED'))
        : (json['status'] as String? ?? decisionCode.status);

    final String messageStr =
        json['message'] as String? ?? json['detail'] as String? ?? 'Processed';

    final String? resolvedCheckInId = json['check_in_id'] as String? ??
        (json['user_data'] is Map && json['user_data']['unique_id'] != null
            ? 'chk-${json['user_data']['unique_id']}'
            : null);

    return ScanResponse(
      status: statusStr,
      code: decisionCode,
      message: messageStr,
      attendee: parsedAttendee,
      checkInId: resolvedCheckInId,
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
