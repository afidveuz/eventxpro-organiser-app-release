import 'package:equatable/equatable.dart';

/// Represents the response model for attendee details in QR Blacklist and QR Verification.
/// Corresponds to backend endpoint: `organizer/get-user-details?event_id={id}&ticket_id={code}`
class QrUserDetailsModel extends Equatable {
  final bool status;
  final String message;
  final String ticketId;
  final QrAttendeeDetails userDetails;
  final String? lastCheckinSession;
  final String? lastCheckinTime;
  final List<SessionAccessItem> sessionAccess;

  const QrUserDetailsModel({
    required this.status,
    required this.message,
    required this.ticketId,
    required this.userDetails,
    this.lastCheckinSession,
    this.lastCheckinTime,
    this.sessionAccess = const [],
  });

  factory QrUserDetailsModel.fromJson(Map<String, dynamic> json, {required String ticketId}) {
    final root = (json['data'] is Map<String, dynamic>)
        ? json['data'] as Map<String, dynamic>
        : json;

    final rawUser = (root['user_details'] is Map<String, dynamic>)
        ? root['user_details'] as Map<String, dynamic>
        : (root['user_data'] is Map<String, dynamic>)
            ? root['user_data'] as Map<String, dynamic>
            : (root['user'] is Map<String, dynamic>)
                ? root['user'] as Map<String, dynamic>
                : root;

    final rawSessions = (root['session_access'] is List)
        ? root['session_access'] as List<dynamic>
        : (rawUser['session_access'] is List)
            ? rawUser['session_access'] as List<dynamic>
            : <dynamic>[];

    final statusVal = root['status'];
    final isSuccess = statusVal == true ||
        statusVal == 1 ||
        statusVal?.toString().toLowerCase() == 'true' ||
        statusVal?.toString().toLowerCase() == 'success';

    return QrUserDetailsModel(
      status: isSuccess,
      message: (root['message'] ?? root['msg'] ?? '').toString(),
      ticketId: ticketId,
      userDetails: QrAttendeeDetails.fromJson(rawUser),
      lastCheckinSession: (root['last_checkin_session'] ?? rawUser['last_checkin_session'])?.toString(),
      lastCheckinTime: (root['last_checkin_time'] ?? rawUser['last_checkin_time'])?.toString(),
      sessionAccess: rawSessions
          .whereType<Map<String, dynamic>>()
          .map((s) => SessionAccessItem.fromJson(s))
          .toList(),
    );
  }

  QrUserDetailsModel copyWith({
    bool? status,
    String? message,
    String? ticketId,
    QrAttendeeDetails? userDetails,
    String? lastCheckinSession,
    String? lastCheckinTime,
    List<SessionAccessItem>? sessionAccess,
  }) {
    return QrUserDetailsModel(
      status: status ?? this.status,
      message: message ?? this.message,
      ticketId: ticketId ?? this.ticketId,
      userDetails: userDetails ?? this.userDetails,
      lastCheckinSession: lastCheckinSession ?? this.lastCheckinSession,
      lastCheckinTime: lastCheckinTime ?? this.lastCheckinTime,
      sessionAccess: sessionAccess ?? this.sessionAccess,
    );
  }

  @override
  List<Object?> get props => [
        status,
        message,
        ticketId,
        userDetails,
        lastCheckinSession,
        lastCheckinTime,
        sessionAccess,
      ];
}

/// Attendee specific fields extracted from `user_details` or `user_data`.
class QrAttendeeDetails extends Equatable {
  final String? userImage;
  final String firstname;
  final String lastname;
  final String? arabicName;
  final String? companyName;
  final String uniqueId;
  final String? seatNo;
  final String? displayTicketCode;
  final String? country;
  final String? email;
  final String? displayTicketName;
  final String? ticketTypeCat;
  final bool blacklistStatus;

  const QrAttendeeDetails({
    this.userImage,
    required this.firstname,
    required this.lastname,
    this.arabicName,
    this.companyName,
    required this.uniqueId,
    this.seatNo,
    this.displayTicketCode,
    this.country,
    this.email,
    this.displayTicketName,
    this.ticketTypeCat,
    this.blacklistStatus = false,
  });

  static String? _clean(dynamic val) {
    if (val == null) return null;
    final s = val.toString().trim();
    return s.isEmpty ? null : s;
  }

  /// Effective ticket type/category name for display, mirroring eventxpro-manager:
  /// `data?.user_details?.display_ticket_name || data?.user_details?.ticket_type_cat || ''`
  String? get ticketCategory {
    if (displayTicketName != null && displayTicketName!.trim().isNotEmpty) {
      return displayTicketName!.trim();
    }
    if (ticketTypeCat != null && ticketTypeCat!.trim().isNotEmpty) {
      return ticketTypeCat!.trim();
    }
    return null;
  }

  factory QrAttendeeDetails.fromJson(Map<String, dynamic> json) {
    final image = _clean(json['user_image'] ??
        json['register_user_photo'] ??
        json['photo'] ??
        json['image']);

    final fName = (json['firstname'] ?? json['first_name'] ?? json['name'] ?? '').toString().trim();
    final lName = (json['lastname'] ?? json['last_name'] ?? '').toString().trim();
    final uId = (json['unique_id'] ?? json['uid'] ?? json['ticket_id'] ?? json['urn'] ?? '').toString().trim();

    final isBlacklisted = json['blacklist_status'] == true ||
        json['blacklist_status'] == 1 ||
        json['blacklist_status']?.toString().toLowerCase() == 'true' ||
        json['is_blacklisted'] == true ||
        json['is_blocked'] == true;

    return QrAttendeeDetails(
      userImage: image,
      firstname: fName,
      lastname: lName,
      arabicName: _clean(json['arabic_name']),
      companyName: _clean(json['company_name'] ?? json['company']),
      uniqueId: uId,
      seatNo: _clean(json['seat_no'] ?? json['seat']),
      displayTicketCode: _clean(json['display_ticket_code'] ?? json['ticket_code']),
      country: _clean(json['country'] ?? json['country_name']),
      email: _clean(json['email']),
      displayTicketName: _clean(json['display_ticket_name'] ?? json['ticket_name']),
      ticketTypeCat: _clean(json['ticket_type_cat'] ?? json['reg_cat'] ?? json['category']),
      blacklistStatus: isBlacklisted,
    );
  }

  QrAttendeeDetails copyWith({
    String? userImage,
    String? firstname,
    String? lastname,
    String? arabicName,
    String? companyName,
    String? uniqueId,
    String? seatNo,
    String? displayTicketCode,
    String? country,
    String? email,
    String? displayTicketName,
    String? ticketTypeCat,
    bool? blacklistStatus,
  }) {
    return QrAttendeeDetails(
      userImage: userImage ?? this.userImage,
      firstname: firstname ?? this.firstname,
      lastname: lastname ?? this.lastname,
      arabicName: arabicName ?? this.arabicName,
      companyName: companyName ?? this.companyName,
      uniqueId: uniqueId ?? this.uniqueId,
      seatNo: seatNo ?? this.seatNo,
      displayTicketCode: displayTicketCode ?? this.displayTicketCode,
      country: country ?? this.country,
      email: email ?? this.email,
      displayTicketName: displayTicketName ?? this.displayTicketName,
      ticketTypeCat: ticketTypeCat ?? this.ticketTypeCat,
      blacklistStatus: blacklistStatus ?? this.blacklistStatus,
    );
  }

  String get fullName {
    final trimmedFirst = firstname.trim();
    final trimmedLast = lastname.trim();
    if (trimmedFirst.isEmpty && arabicName != null && arabicName!.trim().isNotEmpty) {
      return arabicName!.trim();
    }
    return [trimmedFirst, trimmedLast].where((s) => s.isNotEmpty).join(' ');
  }

  String get initials {
    final name = fullName;
    if (name.isEmpty) return 'P';
    final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length > 1) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return parts[0][0].toUpperCase();
  }

  @override
  List<Object?> get props => [
        userImage,
        firstname,
        lastname,
        arabicName,
        companyName,
        uniqueId,
        seatNo,
        displayTicketCode,
        country,
        email,
        displayTicketName,
        ticketTypeCat,
        blacklistStatus,
      ];
}

/// Represents an authorized session entry for the attendee.
class SessionAccessItem extends Equatable {
  final String title;
  final String? startTm;
  final String? hallName;

  const SessionAccessItem({
    required this.title,
    this.startTm,
    this.hallName,
  });

  factory SessionAccessItem.fromJson(Map<String, dynamic> json) {
    return SessionAccessItem(
      title: (json['title'] ?? json['session_name'] ?? json['name'] ?? '').toString(),
      startTm: (json['start_tm'] ?? json['start_time'] ?? json['time'])?.toString(),
      hallName: (json['hall_name'] ?? json['hall'] ?? json['location'])?.toString(),
    );
  }

  @override
  List<Object?> get props => [title, startTm, hallName];
}
