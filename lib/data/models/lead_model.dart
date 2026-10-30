import 'package:equatable/equatable.dart';

/// Lead Model representing an attendee captured as an exhibitor / organizer lead.
class LeadModel extends Equatable {
  final int id;
  final String uniqueId;
  final String firstname;
  final String? lastname;
  final String? email;
  final String? mobile;
  final String? countryCode;
  final String? companyName;
  final String? designation;
  final String? department;
  final String? city;
  final String? country;
  final String? ticketType;
  final String leadType; // 'HOT' | 'WARM' | 'COLD'
  final String? notes;
  final String? photo;
  final String? eventName;
  final String? checkInDt;
  final String? checkInTm;
  final List<dynamic>? checkinHistory;

  const LeadModel({
    required this.id,
    required this.uniqueId,
    required this.firstname,
    this.lastname,
    this.email,
    this.mobile,
    this.countryCode,
    this.companyName,
    this.designation,
    this.department,
    this.city,
    this.country,
    this.ticketType,
    this.leadType = 'COLD',
    this.notes,
    this.photo,
    this.eventName,
    this.checkInDt,
    this.checkInTm,
    this.checkinHistory,
  });

  String get fullName {
    final last = lastname?.trim() ?? '';
    final first = firstname.trim();
    return last.isNotEmpty ? '$first $last' : first;
  }

  String get initials {
    final first = firstname.trim();
    final last = lastname?.trim() ?? '';
    if (first.isEmpty && last.isEmpty) return 'L';
    if (last.isNotEmpty && first.isNotEmpty) {
      return '${first[0]}${last[0]}'.toUpperCase();
    }
    return first.isNotEmpty ? first[0].toUpperCase() : 'L';
  }

  factory LeadModel.fromJson(Map<String, dynamic> json) {
    // In Django: 'lead-capture-attendee' returns 'lead_id' for the lead table record,
    // whereas 'id' is the attendee's user/registration ID.
    // 'lead-list' returns 'id' as the lead record PK.
    final rawLeadId = json['lead_id'] ?? json['leadId'] ?? json['id'];
    final parsedId = (rawLeadId as num?)?.toInt() ??
        int.tryParse(rawLeadId?.toString() ?? '') ??
        0;

    return LeadModel(
      id: parsedId,
      uniqueId: json['unique_id']?.toString() ?? '',
      firstname: json['firstname']?.toString() ?? '',
      lastname: json['lastname']?.toString(),
      email: json['email']?.toString(),
      mobile: json['mobile']?.toString(),
      countryCode: json['country_code']?.toString(),
      companyName: json['company_name']?.toString() ?? json['company']?.toString(),
      designation: json['designation']?.toString() ?? json['job_title']?.toString(),
      department: json['department']?.toString(),
      city: json['city']?.toString(),
      country: json['country']?.toString(),
      ticketType: json['ticket_type']?.toString() ?? json['registerusercategory']?.toString(),
      leadType: (json['lead_type']?.toString().toUpperCase() ?? 'COLD'),
      notes: json['notes']?.toString(),
      photo: json['register_user_photo']?.toString() ?? json['photo']?.toString(),
      eventName: json['event_name']?.toString(),
      checkInDt: json['Booth_check_in_dt']?.toString() ?? json['front_desk_check_in_dt']?.toString(),
      checkInTm: json['lead_check_in_tm']?.toString() ?? json['front_desk_check_in_tm']?.toString(),
      checkinHistory: json['visitor_checkin_history'] as List<dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'unique_id': uniqueId,
      'firstname': firstname,
      'lastname': lastname,
      'email': email,
      'mobile': mobile,
      'country_code': countryCode,
      'company_name': companyName,
      'designation': designation,
      'department': department,
      'city': city,
      'country': country,
      'ticket_type': ticketType,
      'lead_type': leadType,
      'notes': notes,
      'register_user_photo': photo,
      'event_name': eventName,
      'Booth_check_in_dt': checkInDt,
      'lead_check_in_tm': checkInTm,
      'visitor_checkin_history': checkinHistory,
    };
  }

  LeadModel copyWith({
    int? id,
    String? uniqueId,
    String? firstname,
    String? lastname,
    String? email,
    String? mobile,
    String? countryCode,
    String? companyName,
    String? designation,
    String? department,
    String? city,
    String? country,
    String? ticketType,
    String? leadType,
    String? notes,
    String? photo,
    String? eventName,
    String? checkInDt,
    String? checkInTm,
    List<dynamic>? checkinHistory,
  }) {
    return LeadModel(
      id: id ?? this.id,
      uniqueId: uniqueId ?? this.uniqueId,
      firstname: firstname ?? this.firstname,
      lastname: lastname ?? this.lastname,
      email: email ?? this.email,
      mobile: mobile ?? this.mobile,
      countryCode: countryCode ?? this.countryCode,
      companyName: companyName ?? this.companyName,
      designation: designation ?? this.designation,
      department: department ?? this.department,
      city: city ?? this.city,
      country: country ?? this.country,
      ticketType: ticketType ?? this.ticketType,
      leadType: leadType ?? this.leadType,
      notes: notes ?? this.notes,
      photo: photo ?? this.photo,
      eventName: eventName ?? this.eventName,
      checkInDt: checkInDt ?? this.checkInDt,
      checkInTm: checkInTm ?? this.checkInTm,
      checkinHistory: checkinHistory ?? this.checkinHistory,
    );
  }

  @override
  List<Object?> get props => [
        id,
        uniqueId,
        firstname,
        lastname,
        email,
        mobile,
        companyName,
        designation,
        leadType,
        notes,
        photo,
        checkInDt,
        checkInTm,
      ];
}
