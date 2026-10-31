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
  final String? countryInitial; // ISO alpha-2 e.g. "AE", "IN" (from CreateAttendee.jsx)

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
  });

  Map<String, dynamic> toJson() {
    final cleanDialCode = countryCode.trim().startsWith('+')
        ? countryCode.trim()
        : '+${countryCode.trim()}';

    return {
      'firstname': firstName.trim(),
      'lastname': lastName.trim(),
      'email': email.trim().toLowerCase(),
      'country_code': cleanDialCode,
      'mobile': mobile.trim(),
      'company_name': companyName.trim(),
      'job_title': jobTitle.trim(),
      'country': country.trim(),
      'nationality': nationality.trim(),
      'ticket_id': ticketId,
      'event_id': eventId,
      if (countryInitial != null && countryInitial!.trim().isNotEmpty)
        'country_initial': countryInitial!.trim(),
    };
  }
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
