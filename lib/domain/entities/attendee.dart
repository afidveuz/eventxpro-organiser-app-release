import 'package:equatable/equatable.dart';

/// Session access tag matching EventXPro session_access array
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
      title: json['title'] as String? ?? '',
      startTm: json['start_tm'] as String?,
      hallName: json['hall_name'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      if (startTm != null) 'start_tm': startTm,
      if (hallName != null) 'hall_name': hallName,
    };
  }

  @override
  List<Object?> get props => [title, startTm, hallName];
}

/// Attendee information matching React Native eventxproorganiser AttendeeSheet
class Attendee extends Equatable {
  final String name;
  final String badgeType;
  final String? company;
  final String? category;
  final String? ticketId;
  final String? photoUrl;
  final String? punchTime;
  final String? lastCheckinSession;
  final String? lastCheckinTime;
  final String? checkinDt;
  final String? alertType;
  final bool? badgeIssue;
  final List<SessionAccessItem>? sessionAccess;

  const Attendee({
    required this.name,
    required this.badgeType,
    this.company,
    this.category,
    this.ticketId,
    this.photoUrl,
    this.punchTime,
    this.lastCheckinSession,
    this.lastCheckinTime,
    this.checkinDt,
    this.alertType,
    this.badgeIssue,
    this.sessionAccess,
  });

  String get fullName => name;

  /// Helper to get 1 or 2 letter initials matching React Native nameShoter
  String get initials {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'P';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length > 1 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return trimmed[0].toUpperCase();
  }

  factory Attendee.fromJson(Map<String, dynamic> json) {
    List<SessionAccessItem>? access;
    if (json['session_access'] is List) {
      access = (json['session_access'] as List)
          .whereType<Map<String, dynamic>>()
          .map((item) => SessionAccessItem.fromJson(item))
          .toList();
    }

    return Attendee(
      name: json['name'] as String? ?? 'Authorized Attendee',
      badgeType: json['badge_type'] as String? ?? 'General Admission',
      company: json['company'] as String?,
      category: json['category'] as String?,
      ticketId: json['ticket_id']?.toString() ?? json['unique_id']?.toString(),
      photoUrl: json['photo_url'] as String? ??
          json['register_user_photo'] as String? ??
          json['user_image'] as String?,
      punchTime: json['punch_time'] as String?,
      lastCheckinSession: json['last_checkin_session'] as String?,
      lastCheckinTime: json['last_checkin_time'] as String?,
      checkinDt: json['checkin_dt'] as String?,
      alertType: json['alert_type'] as String?,
      badgeIssue: json['badge_issue'] as bool?,
      sessionAccess: access,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'badge_type': badgeType,
      if (company != null) 'company': company,
      if (category != null) 'category': category,
      if (ticketId != null) 'ticket_id': ticketId,
      if (photoUrl != null) 'photo_url': photoUrl,
      if (punchTime != null) 'punch_time': punchTime,
      if (lastCheckinSession != null) 'last_checkin_session': lastCheckinSession,
      if (lastCheckinTime != null) 'last_checkin_time': lastCheckinTime,
      if (checkinDt != null) 'checkin_dt': checkinDt,
      if (alertType != null) 'alert_type': alertType,
      if (badgeIssue != null) 'badge_issue': badgeIssue,
      if (sessionAccess != null)
        'session_access': sessionAccess!.map((e) => e.toJson()).toList(),
    };
  }

  @override
  List<Object?> get props => [
        name,
        badgeType,
        company,
        category,
        ticketId,
        photoUrl,
        punchTime,
        lastCheckinSession,
        lastCheckinTime,
        checkinDt,
        alertType,
        badgeIssue,
        sessionAccess,
      ];
}
