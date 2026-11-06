class UpdateAttendeeRequest {
  final int attendeeId;
  final int? eventId;
  final int? ticketId;
  final String firstName;
  final String lastName;
  final String email;
  final String countryCode; // e.g. "+971"
  final String mobile;
  final String companyName;
  final String jobTitle;
  final String country;
  final String? countryInitial; // ISO alpha-2 e.g. "AE", "IN"
  final String? nationality;
  final String? notes;

  const UpdateAttendeeRequest({
    required this.attendeeId,
    this.eventId,
    this.ticketId,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.countryCode,
    required this.mobile,
    required this.companyName,
    required this.jobTitle,
    required this.country,
    this.countryInitial,
    this.nationality,
    this.notes,
  });

  /// Payload matching `EditAttendeesDetails.jsx`:
  /// POST `edit-attendee/{pk}`
  Map<String, dynamic> toOrganizerPayload() {
    final dial = countryCode.startsWith('+') ? countryCode : '+$countryCode';
    return {
      'firstname': firstName.trim(),
      'lastname': lastName.trim(),
      'email': email.trim(),
      'country_code': dial,
      'country_initial': (countryInitial ?? 'AE').toUpperCase(),
      'country': country.trim(),
      'mobile': mobile.trim(),
      'company_name': companyName.trim(),
      'job_title': jobTitle.trim(),
      if (eventId != null) 'event_id': eventId,
      if (ticketId != null) 'ticket_id': ticketId,
      if (nationality != null && nationality!.isNotEmpty)
        'nationality': nationality!.trim(),
    };
  }

  /// Payload matching `useRegistrationEdit.jsx`:
  /// PATCH `organizer/api/v1/update-user/{id}`
  Map<String, dynamic> toV1Payload() {
    final dial = countryCode.startsWith('+') ? countryCode : '+$countryCode';
    return {
      'firstname': firstName.trim(),
      'lastname': lastName.trim(),
      'email': email.trim(),
      'mobile': mobile.trim(),
      'country_code': dial,
      'country_of_residence': country.trim(),
      'nationality': (nationality != null && nationality!.isNotEmpty)
          ? nationality!.trim()
          : country.trim(),
      'company_name': companyName.trim(),
      'designation': jobTitle.trim(),
      if (notes != null && notes!.trim().isNotEmpty) 'notes': notes!.trim(),
    };
  }
}

class UpdateAttendeeResult {
  final bool isSuccess;
  final String message;
  final String? field;
  final Map<String, dynamic>? rawData;

  const UpdateAttendeeResult({
    required this.isSuccess,
    required this.message,
    this.field,
    this.rawData,
  });

  factory UpdateAttendeeResult.success({
    required String message,
    Map<String, dynamic>? rawData,
  }) {
    return UpdateAttendeeResult(
      isSuccess: true,
      message: message,
      rawData: rawData,
    );
  }

  factory UpdateAttendeeResult.failure({
    required String message,
    String? field,
    Map<String, dynamic>? rawData,
  }) {
    return UpdateAttendeeResult(
      isSuccess: false,
      message: message,
      field: field,
      rawData: rawData,
    );
  }
}

