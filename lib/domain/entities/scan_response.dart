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
  final String? alertType;
  final String? punchTime;

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
    this.alertType,
    this.punchTime,
  });

  bool get isAlertSuccess => alertType == 'success' || code.isSuccess;
  bool get isAlertWarning => alertType == 'warning' || code.isWarning;
  bool get isAlertDanger => alertType == 'danger' || code.isRejected;
  bool get isAlertInfo => alertType == 'info';

  factory ScanResponse.fromJson(
    Map<String, dynamic> json, {
    int latencyMs = 0,
    int? decodeToEventMs,
    String? scanRequestId,
  }) {
    final rawCode = json['code'] as String?;
    final alertType = json['alert_type'] as String?;
    final punchTime = json['punch_time'] as String?;
    final lastCheckinSession = json['last_checkin_session'] as String?;
    final lastCheckinTime = json['last_checkin_time'] as String?;
    final checkinDt = json['checkin_dt'] as String?;

    ScanDecisionCode decisionCode;

    if (rawCode != null) {
      decisionCode = ScanDecisionCode.fromCode(rawCode);
    } else {
      final isStatusTrue = json['status'] == true;
      final msg = (json['message'] as String? ?? json['detail'] as String? ?? '').toLowerCase();

      if (isStatusTrue || alertType == 'success') {
        decisionCode = ScanDecisionCode.entryAllowed;
      } else if (msg.contains('limited') || msg.contains('already') || alertType == 'warning') {
        decisionCode = ScanDecisionCode.alreadyCheckedIn;
      } else if (msg.contains('not found') || msg.contains('valid code') || msg.contains('invalid')) {
        decisionCode = ScanDecisionCode.invalidBadge;
      } else if (msg.contains('expired')) {
        decisionCode = ScanDecisionCode.expired;
      } else {
        decisionCode = ScanDecisionCode.accessDenied;
      }
    }

    // Parse Session Access agenda list
    List<SessionAccessItem>? accessList;
    final rawAccess = json['session_access'] ??
        (json['data'] is Map ? json['data']['session_access'] : null);
    if (rawAccess is List) {
      accessList = rawAccess
          .whereType<Map<String, dynamic>>()
          .map((item) => SessionAccessItem.fromJson(item))
          .toList();
    }

    // Locate attendee / user dictionary
    Attendee? parsedAttendee;
    Map<String, dynamic>? userMap;
    if (json['user_data'] is Map<String, dynamic>) {
      userMap = json['user_data'] as Map<String, dynamic>;
    } else if (json['user_details'] is Map<String, dynamic>) {
      userMap = json['user_details'] as Map<String, dynamic>;
    } else if (json['data'] is Map && json['data']['user_data'] is Map<String, dynamic>) {
      userMap = json['data']['user_data'] as Map<String, dynamic>;
    } else if (json['data'] is Map && json['data']['user_details'] is Map<String, dynamic>) {
      userMap = json['data']['user_details'] as Map<String, dynamic>;
    }

    if (userMap != null) {
      final fn = (userMap['firstname'] as String? ?? userMap['first_name'] as String? ?? '').trim();
      final ln = (userMap['lastname'] as String? ?? userMap['last_name'] as String? ?? '').trim();
      final fullName = '$fn $ln'.trim();

      parsedAttendee = Attendee(
        name: fullName.isNotEmpty
            ? fullName
            : (userMap['name'] as String? ?? 'Authorized Attendee'),
        badgeType: userMap['ticket_type_cat'] as String? ??
            userMap['display_ticket_name'] as String? ??
            userMap['badge_type'] as String? ??
            userMap['reg_cat'] as String? ??
            'General Admission',
        company: userMap['company_name'] as String? ?? userMap['company'] as String?,
        category: userMap['reg_cat'] as String? ?? userMap['category'] as String?,
        ticketId: userMap['unique_id']?.toString() ?? userMap['ticket_id']?.toString(),
        photoUrl: userMap['register_user_photo'] as String? ??
            userMap['user_image'] as String? ??
            userMap['photo_url'] as String?,
        punchTime: punchTime ?? userMap['punch_time'] as String?,
        lastCheckinSession: lastCheckinSession ?? userMap['last_checkin_session'] as String?,
        lastCheckinTime: lastCheckinTime ?? userMap['last_checkin_time'] as String?,
        checkinDt: checkinDt ?? userMap['checkin_dt'] as String?,
        alertType: alertType,
        badgeIssue: userMap['badge_issue'] == true,
        sessionAccess: accessList,
      );
    } else if (json['attendee'] is Map<String, dynamic>) {
      parsedAttendee = Attendee.fromJson(json['attendee'] as Map<String, dynamic>);
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
        (userMap != null && userMap['unique_id'] != null
            ? 'chk-${userMap['unique_id']}'
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
      alertType: alertType,
      punchTime: punchTime,
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
      alertType: 'danger',
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
      alertType: 'warning',
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
    String? alertType,
    String? punchTime,
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
      alertType: alertType ?? this.alertType,
      punchTime: punchTime ?? this.punchTime,
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
        alertType,
        punchTime,
      ];
}
