import 'package:flutter/material.dart';

/// Represents a single attendee row in an Attendee list matching `AllAttendeeListCard.jsx` & `AttendeesCard.jsx`.
class AttendeeListItemModel {
  final int pk;
  final String? uid;
  final String firstname;
  final String? lastname;
  final String? designation;
  final String? companyName;
  final String? country;
  final String? uniqueId;
  final String? ticketName;
  final String? photoUrl;
  final String? email;
  final String? mobile;
  final String? address;
  final String? punchType;
  final bool? isCheckedIn;

  const AttendeeListItemModel({
    required this.pk,
    this.uid,
    required this.firstname,
    this.lastname,
    this.designation,
    this.companyName,
    this.country,
    this.uniqueId,
    this.ticketName,
    this.photoUrl,
    this.email,
    this.mobile,
    this.address,
    this.punchType,
    this.isCheckedIn,
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

  Color get avatarColor {
    final colors = [
      const Color(0xFF6366F1), // Indigo
      const Color(0xFF8B5CF6), // Purple
      const Color(0xFFEC4899), // Pink
      const Color(0xFF14B8A6), // Teal
      const Color(0xFFF59E0B), // Amber
      const Color(0xFF10B981), // Emerald
      const Color(0xFF3B82F6), // Blue
      const Color(0xFFEF4444), // Coral Red
      const Color(0xFF06B6D4), // Cyan
    ];
    final hash = (pk + fullName.hashCode).abs();
    return colors[hash % colors.length];
  }

  factory AttendeeListItemModel.fromJson(Map<String, dynamic> json) {
    return AttendeeListItemModel(
      pk: (json['pk'] as num?)?.toInt() ??
          (json['id'] as num?)?.toInt() ??
          (json['user_id'] as num?)?.toInt() ??
          0,
      uid: json['uid']?.toString(),
      firstname: json['firstname']?.toString() ?? '',
      lastname: json['lastname']?.toString(),
      designation: json['designation']?.toString(),
      companyName: json['company_name']?.toString() ?? json['company']?.toString(),
      country: json['country']?.toString(),
      uniqueId: json['unique_id']?.toString() ??
          json['ticket_id']?.toString() ??
          json['urn']?.toString(),
      ticketName: json['display_ticket_name']?.toString() ??
          json['ticket_type_cat']?.toString() ??
          json['ticket_type']?.toString(),
      photoUrl: json['register_user_photo']?.toString() ??
          json['photo_url']?.toString() ??
          json['user_image']?.toString(),
      email: json['email']?.toString(),
      mobile: json['mobile']?.toString(),
      address: json['address']?.toString(),
      punchType: json['punch_type']?.toString(),
      isCheckedIn: json['is_checked_in'] == true || json['checked_in'] == true,
    );
  }
}

/// Paginated result of Attendee list items
class AttendeePaginatedResult {
  final List<AttendeeListItemModel> attendees;
  final bool hasNextPage;
  final int? nextPage;
  final int totalCount;

  const AttendeePaginatedResult({
    required this.attendees,
    required this.hasNextPage,
    this.nextPage,
    required this.totalCount,
  });
}
