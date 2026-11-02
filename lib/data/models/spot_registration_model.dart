import 'dart:math' as math;
import 'package:dio/dio.dart';

class SpotRegistrationRequest {
  final int eventId;
  final int ticketId;
  final String firstName;
  final String lastName;
  final String email;
  final String countryCode; // e.g. "+971"
  final String mobile;
  final String companyName;
  final String jobTitle;
  final String country;
  final String nationality;
  final String? countryInitial; // ISO alpha-2 e.g. "AE", "IN"
  final String? title;
  final String? city;
  final String? notes;
  final String? companyType;
  final String? industry;
  final String? paymentMode;
  final double? receivedAmount;
  final String? currency;
  final String? promoCode;
  final String? referenceNumber;
  final String? collectedBy;

  const SpotRegistrationRequest({
    required this.eventId,
    required this.ticketId,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.countryCode,
    required this.mobile,
    required this.companyName,
    required this.jobTitle,
    required this.country,
    required this.nationality,
    this.countryInitial,
    this.title,
    this.city,
    this.notes,
    this.companyType,
    this.industry,
    this.paymentMode = 'onsite_qr',
    this.receivedAmount = 0.0,
    this.currency,
    this.promoCode,
    this.referenceNumber,
    this.collectedBy = 'Spot Registration',
  });

  static String _generateRandomRef() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = math.Random();
    final randomCode = List.generate(
      6,
      (index) => chars[random.nextInt(chars.length)],
    ).join();
    return 'SPOT-$randomCode';
  }

  Map<String, dynamic> toRequestBody() {
    final cleanDialCode = countryCode.trim().startsWith('+')
        ? countryCode.trim()
        : '+${countryCode.trim()}';

    final refCode = referenceNumber ?? _generateRandomRef();

    return {
      if (title != null && title!.trim().isNotEmpty) 'title': title!.trim(),
      'firstname': firstName.trim(),
      'lastname': lastName.trim(),
      if (email.trim().isNotEmpty) 'email': email.trim().toLowerCase(),
      'country_code': cleanDialCode,
      'mobile': mobile.trim(),
      'company_name': companyName.trim(),
      // In kiosk_v2, the backend expects 'designation'
      'designation': jobTitle.trim(),
      'job_title': jobTitle.trim(),
      // In kiosk_v2, the backend expects 'ticket' (ID)
      'ticket': ticketId,
      'ticket_id': ticketId,
      'event_id': eventId,
      'country': country.trim(),
      'country_of_residence': country.trim(),
      if (countryInitial != null && countryInitial!.trim().isNotEmpty) ...{
        'country_of_residence_code': countryInitial!.trim(),
        'country_initial': countryInitial!.trim(),
        'nationality_code': countryInitial!.trim(),
      },
      'nationality': nationality.trim(),
      if (city != null && city!.trim().isNotEmpty) 'city': city!.trim(),
      if (notes != null && notes!.trim().isNotEmpty) 'notes': notes!.trim(),
      if (companyType != null && companyType!.trim().isNotEmpty)
        'company_type': companyType!.trim(),
      if (industry != null && industry!.trim().isNotEmpty)
        'industry': industry!.trim(),
      // Payment fields required by kiosk_v2 backend API
      'payment_mode': paymentMode ?? 'onsite_qr',
      'received_amount': receivedAmount ?? 0.0,
      'reference_number': refCode,
      'collected_by': collectedBy ?? 'Spot Registration',
      'payment_datetime': DateTime.now().toIso8601String(),
      'payment_status': 1,
      if (currency != null && currency!.trim().isNotEmpty)
        'currency': currency!.trim(),
      if (promoCode != null && promoCode!.trim().isNotEmpty)
        'promo_code': promoCode!.trim(),
    };
  }

  FormData toFormData() => FormData.fromMap(toRequestBody());

  /// Strict organizer payload matching `CreateAttendee.jsx` in the reference React Native app.
  /// Omits unhandled kiosk payment fields that cause Django 500 errors on `organizer/create-attendee`.
  Map<String, dynamic> toOrganizerPayload() {
    final cleanDialCode = countryCode.trim().startsWith('+')
        ? countryCode.trim()
        : '+${countryCode.trim()}';

    return {
      'firstname': firstName.trim(),
      'lastname': lastName.trim(),
      if (email.trim().isNotEmpty) 'email': email.trim().toLowerCase(),
      'country': country.trim(),
      'country_code': cleanDialCode,
      if (countryInitial != null && countryInitial!.trim().isNotEmpty)
        'country_initial': countryInitial!.trim(),
      'mobile': mobile.trim(),
      'company_name': companyName.trim(),
      'job_title': jobTitle.trim(),
      if (nationality.trim().isNotEmpty)
        'nationality': nationality.trim(),
      'event_id': eventId,
      'ticket_id': ticketId,
    };
  }

  Map<String, dynamic> toJson() => toRequestBody();
}

class SpotRegistrationResult {
  final bool isSuccess;
  final String? message;
  final int? attendeeId;
  final String? uniqueId;
  final String? fullName;
  final String? email;
  final String? ticketName;
  final Map<String, dynamic>? rawData;

  const SpotRegistrationResult({
    required this.isSuccess,
    this.message,
    this.attendeeId,
    this.uniqueId,
    this.fullName,
    this.email,
    this.ticketName,
    this.rawData,
  });

  factory SpotRegistrationResult.success({
    required String message,
    int? attendeeId,
    String? uniqueId,
    String? fullName,
    String? email,
    String? ticketName,
    Map<String, dynamic>? rawData,
  }) {
    return SpotRegistrationResult(
      isSuccess: true,
      message: message,
      attendeeId: attendeeId,
      uniqueId: uniqueId,
      fullName: fullName,
      email: email,
      ticketName: ticketName,
      rawData: rawData,
    );
  }

  factory SpotRegistrationResult.failure({
    required String message,
    Map<String, dynamic>? rawData,
  }) {
    return SpotRegistrationResult(
      isSuccess: false,
      message: message,
      rawData: rawData,
    );
  }
}
