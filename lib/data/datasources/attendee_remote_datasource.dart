import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../core/config/app_constants.dart';
import '../../core/network/api_client.dart';
import '../models/attendee_details_model.dart';
import '../models/attendee_list_item_model.dart';
import '../models/country_model.dart';
import '../models/spot_registration_model.dart';
import '../models/ticket_type_model.dart';

class AttendeePunchResult {
  final bool isSuccess;
  final String? message;
  final String? alertType;
  final Map<String, dynamic>? rawData;

  const AttendeePunchResult({
    required this.isSuccess,
    this.message,
    this.alertType,
    this.rawData,
  });
}

class AttendeeRemoteDatasource {
  final ApiClient _apiClient;

  AttendeeRemoteDatasource({required ApiClient apiClient})
      : _apiClient = apiClient;

  /// Fetches attendee profile and Entrance, Hall, and Agenda checkin/checkout history
  /// via GET `organizer/event-register-user-details?id=$attendeeId`
  Future<AttendeeDetailsModel?> getAttendeeDetails({
    required int attendeeId,
  }) async {
    try {
      final response = await _apiClient.dio.get(
        'organizer/event-register-user-details',
        queryParameters: {'id': attendeeId},
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data is Map<String, dynamic>
            ? response.data as Map<String, dynamic>
            : jsonDecode(response.data.toString()) as Map<String, dynamic>;

        return AttendeeDetailsModel.fromJson(data);
      }
      return null;
    } catch (e) {
      debugPrint('[AttendeeRemoteDatasource] getAttendeeDetails error: $e');
      rethrow;
    }
  }

  /// Fetches attendee OTP for admin viewing
  /// GET `organizer/admin/view-register-user-otp?uid=$uid`
  Future<Map<String, dynamic>?> getAttendeeOtp({required String uid}) async {
    try {
      final response = await _apiClient.dio.get(
        'organizer/admin/view-register-user-otp',
        queryParameters: {'uid': uid},
      );
      if (response.data != null) {
        final data = response.data is Map<String, dynamic>
            ? response.data as Map<String, dynamic>
            : jsonDecode(response.data.toString()) as Map<String, dynamic>;
        return data;
      }
      return null;
    } catch (e) {
      debugPrint('[AttendeeRemoteDatasource] getAttendeeOtp error: $e');
      return null;
    }
  }

  /// Fetches paginated list of attendees for an event metric
  /// Endpoints: 'event-register-users', 'totalattendees-list', 'noshow-list', 'today-visits', 'checkin-list'
  Future<AttendeePaginatedResult> getEventAttendees({
    required int eventId,
    required String endPoint,
    int pageNo = 1,
    int count = 20,
    String keyword = '',
    Map<String, dynamic>? filterObj,
  }) async {
    try {
      final filtersJson = jsonEncode([filterObj ?? {}]);

      final response = await _apiClient.dio.get(
        'organizer/$endPoint',
        queryParameters: {
          'event_id': eventId,
          'count': count,
          'page_no': pageNo,
          'key_word': keyword,
          'filter_list': filtersJson,
        },
      );

      final data = response.data is Map<String, dynamic>
          ? response.data as Map<String, dynamic>
          : jsonDecode(response.data.toString()) as Map<String, dynamic>;

      final rawList = (data['user_data'] as List<dynamic>?) ??
          (data['attendees'] as List<dynamic>?) ??
          [];

      final attendees = rawList
          .whereType<Map<String, dynamic>>()
          .map((e) => AttendeeListItemModel.fromJson(e))
          .toList();

      final nextPage = data['next_page'] as int?;
      final totalCount = (data['count'] as num?)?.toInt() ?? attendees.length;

      return AttendeePaginatedResult(
        attendees: attendees,
        hasNextPage: nextPage != null,
        nextPage: nextPage,
        totalCount: totalCount,
      );
    } catch (e) {
      debugPrint('[AttendeeRemoteDatasource] getEventAttendees error: $e');
      rethrow;
    }
  }

  /// Fetches paginated list of attendees for a specific session/gate
  /// via GET `organizer/attend-user-checkin-checkout-list`
  Future<AttendeePaginatedResult> getSessionAttendees({
    required int eventId,
    required String pageType, // 'entrance' | 'hall' | 'agenda' | 'session_type'
    required String actionType, // 'check_in' | 'check_out'
    int pageNo = 1,
    int count = 20,
    String keyword = '',
    int? agendaId,
    int? hallId,
    int? entranceId,
  }) async {
    try {
      final Map<String, dynamic> queryParams = {
        'event_id': eventId,
        'page_type': pageType,
        'action_type': actionType,
        'count': count,
        'page_no': pageNo,
        'key_word': keyword,
        'agenda_id': agendaId ?? 0,
        'hall_id': hallId ?? 0,
      };

      if (entranceId != null && entranceId > 0) {
        queryParams['entrance_id'] = entranceId;
      }

      final response = await _apiClient.dio.get(
        'organizer/attend-user-checkin-checkout-list',
        queryParameters: queryParams,
      );

      final data = response.data is Map<String, dynamic>
          ? response.data as Map<String, dynamic>
          : jsonDecode(response.data.toString()) as Map<String, dynamic>;

      final rawList = (data['user_data'] as List<dynamic>?) ?? [];
      final attendees = rawList
          .whereType<Map<String, dynamic>>()
          .map((e) => AttendeeListItemModel.fromJson(e))
          .toList();

      final nextPage = data['next_page'] as int?;
      final totalCount = (data['count'] as num?)?.toInt() ?? attendees.length;

      return AttendeePaginatedResult(
        attendees: attendees,
        hasNextPage: nextPage != null,
        nextPage: nextPage,
        totalCount: totalCount,
      );
    } catch (e) {
      debugPrint('[AttendeeRemoteDatasource] getSessionAttendees error: $e');
      rethrow;
    }
  }

  /// Manual punch for an attendee from the Attendee list
  Future<AttendeePunchResult> punchAttendee({
    required String endpoint,
    required Map<String, dynamic> payload,
  }) async {
    try {
      final response = await _apiClient.dio.post(
        endpoint,
        data: payload,
      );

      final data = response.data is Map<String, dynamic>
          ? response.data as Map<String, dynamic>
          : jsonDecode(response.data.toString()) as Map<String, dynamic>;

      final isSuccess = data['status'] == true;
      final message = data['message']?.toString() ??
          (isSuccess ? 'Punch recorded successfully' : 'Punch failed');
      final alertType = data['alert_type']?.toString();

      return AttendeePunchResult(
        isSuccess: isSuccess,
        message: message,
        alertType: alertType,
        rawData: data,
      );
    } catch (e) {
      debugPrint('[AttendeeRemoteDatasource] punchAttendee error: $e');
      return AttendeePunchResult(
        isSuccess: false,
        message: e.toString(),
      );
    }
  }

  /// Fetches available ticket tiers for an event from `organizer/ticket-list/{eventId}`
  Future<List<TicketTypeModel>> getTicketList({required int eventId}) async {
    try {
      final response = await _apiClient.dio.get('organizer/ticket-list/$eventId');

      if ((response.statusCode == 200 || response.statusCode == 201) &&
          response.data != null) {
        final data = response.data is Map<String, dynamic>
            ? response.data as Map<String, dynamic>
            : jsonDecode(response.data.toString()) as Map<String, dynamic>;

        final rawList = data['tickets'] ??
            data['result'] ??
            data['results'] ??
            data['Ticket_list'] ??
            data['ticket_list'] ??
            data['data'];

        if (rawList is List) {
          return rawList
              .whereType<Map>()
              .map((item) =>
                  TicketTypeModel.fromJson(Map<String, dynamic>.from(item)))
              .toList();
        }
      }
      return [];
    } catch (e) {
      debugPrint('[AttendeeRemoteDatasource] getTicketList error: $e');
      rethrow;
    }
  }

  /// Creates a walk-in attendee on-site (Spot Registration).
  /// Uses the kiosk_v2 method: FormData payload with full field mapping (ticket, designation, payment info)
  /// Target endpoints: `organizer/api/v1/create-user/{eventId}?lang=eng` with fallback to `organizer/create-attendee`
  Future<SpotRegistrationResult> createSpotAttendee({
    required SpotRegistrationRequest request,
  }) async {
    try {
      dynamic response;
      dynamic lastError;

      // 1. First try organizer/create-attendee with strict organizer payload
      // (Matching CreateAttendee.jsx & CreateAttendeeOCR.jsx in eventxproorganiser)
      final organizerPayload = request.toOrganizerPayload();
      try {
        response = await _apiClient.dio.post(
          'organizer/create-attendee',
          data: organizerPayload,
        );
      } catch (createErr) {
        debugPrint('[AttendeeRemoteDatasource] organizer/create-attendee failed: $createErr, trying v1 create-user');
        lastError = createErr;

        // 2. Try organizer v1 create-user endpoint with JSON payload (matching AttendeesCreation.jsx)
        try {
          response = await _apiClient.dio.post(
            'organizer/api/v1/create-user/${request.eventId}?lang=eng',
            data: organizerPayload,
          );
        } catch (v1Err) {
          debugPrint('[AttendeeRemoteDatasource] organizer v1 create-user failed: $v1Err, trying FormData fallback');
          lastError = v1Err;

          // 3. Last fallback: FormData format if supported by kiosk backend
          try {
            response = await _apiClient.dio.post(
              'organizer/api/v1/create-user/${request.eventId}?lang=eng',
              data: request.toFormData(),
            );
          } catch (formErr) {
            lastError = formErr;
          }
        }
      }

      if (response != null && response.data != null) {
        final data = response.data is Map<String, dynamic>
            ? response.data as Map<String, dynamic>
            : jsonDecode(response.data.toString()) as Map<String, dynamic>;

        final bool isSuccess = data['status'] == true ||
            data['success'] == true ||
            response.statusCode == 200 ||
            response.statusCode == 201;

        if (isSuccess) {
          final attendeeData =
              data['data'] is Map ? data['data'] as Map : (data['result'] is Map ? data['result'] as Map : data);
          final int? id = (attendeeData['id'] ??
                  attendeeData['pk'] ??
                  attendeeData['user_id'] as num?)
              ?.toInt();
          final String? uid = attendeeData['unique_id']?.toString() ??
              attendeeData['urn']?.toString() ??
              attendeeData['ticket_id']?.toString();
          final String name = attendeeData['name']?.toString() ??
              '${request.firstName} ${request.lastName}'.trim();
          final String? ticketName = attendeeData['ticket'] is Map
              ? (attendeeData['ticket']['title'] ?? attendeeData['ticket']['name'])?.toString()
              : null;

          return SpotRegistrationResult.success(
            message: data['message']?.toString() ?? 'Registration completed successfully',
            attendeeId: id,
            uniqueId: uid,
            fullName: name,
            email: attendeeData['email']?.toString() ?? request.email,
            ticketName: ticketName,
            rawData: data,
          );
        } else {
          final errorMsg = _extractErrorMessage(data);
          return SpotRegistrationResult.failure(
            message: errorMsg,
            rawData: data,
          );
        }
      }

      // If no response and last error was DioException, format detailed field errors like kiosk_v2
      if (lastError != null) {
        if (lastError is DioException) {
          return SpotRegistrationResult.failure(
            message: _extractDioErrorMessage(lastError),
            rawData: lastError.response?.data is Map<String, dynamic>
                ? lastError.response!.data as Map<String, dynamic>
                : null,
          );
        }
        return SpotRegistrationResult.failure(
          message: lastError.toString(),
        );
      }

      return SpotRegistrationResult.failure(
        message: 'No response received from registration server.',
      );
    } catch (e) {
      debugPrint('[AttendeeRemoteDatasource] createSpotAttendee error: $e');
      if (e is DioException) {
        return SpotRegistrationResult.failure(
          message: _extractDioErrorMessage(e),
          rawData: e.response?.data is Map<String, dynamic>
              ? e.response!.data as Map<String, dynamic>
              : null,
        );
      }
      return SpotRegistrationResult.failure(
        message: e.toString(),
      );
    }
  }

  /// Extracts readable error message from response data matching kiosk_v2
  String _extractErrorMessage(Map<String, dynamic> data) {
    if (data.containsKey('detail')) {
      final detail = data['detail'];
      if (detail is Map) {
        final fieldErrors = <String>[];
        detail.forEach((key, val) {
          if (val is List) {
            fieldErrors.add('${key.toString().toUpperCase()}: ${val.join(", ")}');
          } else {
            fieldErrors.add('${key.toString().toUpperCase()}: $val');
          }
        });
        if (fieldErrors.isNotEmpty) {
          return fieldErrors.join('\n');
        }
      } else if (detail is String && detail.trim().isNotEmpty) {
        return detail.trim();
      }
    }
    return data['message']?.toString() ??
        data['error']?.toString() ??
        'Registration failed. Please check inputs and try again.';
  }

  /// Extracts detailed field validation errors from DioException matching kiosk_v2
  String _extractDioErrorMessage(DioException e) {
    if (e.response?.data != null) {
      dynamic resData = e.response!.data;
      if (resData is String) {
        try {
          resData = jsonDecode(resData);
        } catch (_) {}
      }
      if (resData is Map<String, dynamic>) {
        return _extractErrorMessage(resData);
      }
    }
    return e.message ?? 'Network error during registration. Please try again.';
  }

  /// Fetches global countries with dial codes from `microsite/v2/countries/`
  Future<List<CountryModel>> getCountries() async {
    try {
      final response = await _apiClient.dio.get(AppConstants.countriesEndpoint);

      if ((response.statusCode == 200 || response.statusCode == 201) &&
          response.data != null) {
        dynamic parsed = response.data;
        if (parsed is String) {
          parsed = jsonDecode(parsed);
        }
        if (parsed is Map && parsed['country_list'] is List) {
          final list = (parsed['country_list'] as List)
              .whereType<Map>()
              .map((c) => CountryModel.fromJson(Map<String, dynamic>.from(c)))
              .where((c) => c.label.isNotEmpty && c.code.isNotEmpty)
              .toList();
          if (list.isNotEmpty) return list;
        } else if (parsed is List) {
          final list = parsed
              .whereType<Map>()
              .map((c) => CountryModel.fromJson(Map<String, dynamic>.from(c)))
              .where((c) => c.label.isNotEmpty && c.code.isNotEmpty)
              .toList();
          if (list.isNotEmpty) return list;
        } else if (parsed is Map && parsed['data'] is List) {
          final list = (parsed['data'] as List)
              .whereType<Map>()
              .map((c) => CountryModel.fromJson(Map<String, dynamic>.from(c)))
              .where((c) => c.label.isNotEmpty && c.code.isNotEmpty)
              .toList();
          if (list.isNotEmpty) return list;
        }
      }
    } catch (e) {
      debugPrint('[AttendeeRemoteDatasource] getCountries error: $e. Using default list.');
    }
    return CountryModel.defaultCountries;
  }
}
