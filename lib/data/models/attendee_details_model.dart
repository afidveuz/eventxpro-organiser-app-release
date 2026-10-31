
/// Individual Check-in / Check-out time log
class HistoryLogItem {
  final String? checkInTime;
  final String? checkOutTime;

  const HistoryLogItem({
    this.checkInTime,
    this.checkOutTime,
  });

  factory HistoryLogItem.fromJson(Map<String, dynamic> json) {
    return HistoryLogItem(
      checkInTime: (json['main_check_in_tm'] ??
              json['hall_check_in_tm'] ??
              json['agenda_check_in_tm'])
          ?.toString(),
      checkOutTime: (json['main_check_out_tm'] ??
              json['hall_check_out_tm'] ??
              json['agenda_check_out_tm'])
          ?.toString(),
    );
  }
}

/// Entrance History Group (grouped by date)
class EntranceHistoryGroup {
  final String? checkInDate;
  final List<HistoryLogItem> logs;

  const EntranceHistoryGroup({
    this.checkInDate,
    required this.logs,
  });

  factory EntranceHistoryGroup.fromJson(Map<String, dynamic> json) {
    final rawLogs = json['event_user_history_logs'] as List<dynamic>? ?? [];
    return EntranceHistoryGroup(
      checkInDate: json['main_check_in_dt']?.toString(),
      logs: rawLogs
          .whereType<Map<String, dynamic>>()
          .map((e) => HistoryLogItem.fromJson(e))
          .toList(),
    );
  }
}

/// Hall History Group (hall name, date, and logs)
class HallHistoryGroup {
  final String? hallName;
  final String? checkInDate;
  final List<HistoryLogItem> logs;

  const HallHistoryGroup({
    this.hallName,
    this.checkInDate,
    required this.logs,
  });

  factory HallHistoryGroup.fromJson(Map<String, dynamic> json) {
    final rawLogs = json['event_user_history_logs'] as List<dynamic>? ?? [];
    return HallHistoryGroup(
      hallName: json['hall_name']?.toString() ?? 'Hall',
      checkInDate: json['hall_check_in_dt']?.toString(),
      logs: rawLogs
          .whereType<Map<String, dynamic>>()
          .map((e) => HistoryLogItem.fromJson(e))
          .toList(),
    );
  }
}

/// Agenda History Group (agenda title, date, and logs)
class AgendaHistoryGroup {
  final String? agendaTitle;
  final String? checkInDate;
  final List<HistoryLogItem> logs;

  const AgendaHistoryGroup({
    this.agendaTitle,
    this.checkInDate,
    required this.logs,
  });

  factory AgendaHistoryGroup.fromJson(Map<String, dynamic> json) {
    final rawLogs = json['event_user_history_logs'] as List<dynamic>? ?? [];
    return AgendaHistoryGroup(
      agendaTitle: json['agenda_title']?.toString() ?? 'Agenda',
      checkInDate: json['agenda_check_in_dt']?.toString(),
      logs: rawLogs
          .whereType<Map<String, dynamic>>()
          .map((e) => HistoryLogItem.fromJson(e))
          .toList(),
    );
  }
}

/// Social link item for Twitter, Facebook, Instagram, LinkedIn
class SocialLinkItem {
  final String type;
  final String url;

  const SocialLinkItem({required this.type, required this.url});
}

/// Comprehensive Attendee Details Model matching `AttendeesDetails.jsx` in `eventxproorganiser`.
class AttendeeDetailsModel {
  final int id;
  final String? uid;
  final String firstname;
  final String? lastname;
  final String? designation;
  final String? companyName;
  final String? country;
  final String? uniqueId;
  final String? ticketName;
  final String? paidStatus;
  final bool? digitalBadgeIssue;
  final bool? badgeIssue;
  final String? bookingStatus;
  final String? email;
  final String? mobile;
  final String? photoUrl;
  final String? eventName;
  final bool isDetailsAllowed;
  final List<SocialLinkItem> socialLinks;
  final List<EntranceHistoryGroup> entranceHistory;
  final List<HallHistoryGroup> hallHistory;
  final List<AgendaHistoryGroup> agendaHistory;

  const AttendeeDetailsModel({
    required this.id,
    this.uid,
    required this.firstname,
    this.lastname,
    this.designation,
    this.companyName,
    this.country,
    this.uniqueId,
    this.ticketName,
    this.paidStatus,
    this.digitalBadgeIssue,
    this.badgeIssue,
    this.bookingStatus,
    this.email,
    this.mobile,
    this.photoUrl,
    this.eventName,
    this.isDetailsAllowed = true,
    this.socialLinks = const [],
    this.entranceHistory = const [],
    this.hallHistory = const [],
    this.agendaHistory = const [],
  });

  String get fullName {
    final first = firstname.trim();
    final last = lastname?.trim() ?? '';
    if (first.isEmpty && last.isEmpty) return 'No Name';
    if (last.isEmpty) return first;
    return '$first $last';
  }

  String get initials {
    final clean = fullName.trim();
    if (clean.isEmpty || clean == 'No Name') return 'P';
    final parts = clean.split(RegExp(r'\s+'));
    if (parts.length > 1 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return clean[0].toUpperCase();
  }

  factory AttendeeDetailsModel.fromJson(Map<String, dynamic> json) {
    final userData = json['user_data'] is Map<String, dynamic>
        ? json['user_data'] as Map<String, dynamic>
        : (json['attendee_details'] is List && (json['attendee_details'] as List).isNotEmpty
            ? (json['attendee_details'] as List).first as Map<String, dynamic>
            : json);

    final eventName = json['event_name']?.toString() ??
        json['publish_event_name']?.toString();

    final isDetails = json['organiser_app_attendee_personal_details'] != false;

    // Parse Social Links
    final List<SocialLinkItem> sLinks = [];
    final twitter = userData['twitter']?.toString();
    if (twitter != null && twitter.isNotEmpty) {
      sLinks.add(SocialLinkItem(type: 'Twitter', url: twitter));
    }
    final facebook = userData['facebook']?.toString();
    if (facebook != null && facebook.isNotEmpty) {
      sLinks.add(SocialLinkItem(type: 'Facebook', url: facebook));
    }
    final instagram = userData['instagram']?.toString();
    if (instagram != null && instagram.isNotEmpty) {
      sLinks.add(SocialLinkItem(type: 'Instagram', url: instagram));
    }
    final linkedin = userData['linkedin']?.toString();
    if (linkedin != null && linkedin.isNotEmpty) {
      sLinks.add(SocialLinkItem(type: 'LinkedIn', url: linkedin));
    }

    // Parse Entrance History
    final rawEntrance = userData['entrance_checkin_checkout_history'] as List<dynamic>? ?? [];
    final entranceHistory = rawEntrance
        .whereType<Map<String, dynamic>>()
        .map((e) => EntranceHistoryGroup.fromJson(e))
        .toList();

    // Parse Hall History
    final rawHall = userData['hall_checkin_checkout_history'] as List<dynamic>? ?? [];
    final hallHistory = rawHall
        .whereType<Map<String, dynamic>>()
        .map((e) => HallHistoryGroup.fromJson(e))
        .toList();

    // Parse Agenda History
    final rawAgenda = userData['agenda_checkin_checkout_history'] as List<dynamic>? ?? [];
    final agendaHistory = rawAgenda
        .whereType<Map<String, dynamic>>()
        .map((e) => AgendaHistoryGroup.fromJson(e))
        .toList();

    return AttendeeDetailsModel(
      id: (userData['pk'] as num?)?.toInt() ??
          (userData['id'] as num?)?.toInt() ??
          0,
      uid: userData['uid']?.toString(),
      firstname: userData['firstname']?.toString() ?? '',
      lastname: userData['lastname']?.toString(),
      designation: userData['designation']?.toString(),
      companyName: userData['company_name']?.toString(),
      country: userData['country']?.toString(),
      uniqueId: userData['unique_id']?.toString() ??
          userData['ticket_id']?.toString(),
      ticketName: userData['display_ticket_name']?.toString() ??
          userData['ticket_type_cat']?.toString() ??
          userData['ticket_type']?.toString(),
      paidStatus: userData['paid_status']?.toString(),
      digitalBadgeIssue: userData['digital_badge_issue'] == true,
      badgeIssue: userData['badge_issue'] == true,
      bookingStatus: userData['booking_status']?.toString(),
      email: userData['email']?.toString(),
      mobile: userData['mobile']?.toString(),
      photoUrl: userData['register_user_photo']?.toString() ??
          userData['photo_url']?.toString(),
      eventName: eventName,
      isDetailsAllowed: isDetails,
      socialLinks: sLinks,
      entranceHistory: entranceHistory,
      hallHistory: hallHistory,
      agendaHistory: agendaHistory,
    );
  }
}
