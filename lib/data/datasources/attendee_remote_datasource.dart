import 'dart:convert';
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
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data is Map<String, dynamic>
            ? response.data as Map<String, dynamic>
            : jsonDecode(response.data.toString()) as Map<String, dynamic>;

        final rawList = data['Ticket_list'] ??
            data['ticket_list'] ??
            data['tickets'] ??
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

  /// Creates a walk-in attendee on-site (Spot Registration)
  /// Endpoint: `organizer/api/v1/create-user/{eventId}?lang=eng`
  /// Fallback: `organizer/create-attendee`
  Future<SpotRegistrationResult> createSpotAttendee({
    required SpotRegistrationRequest request,
  }) async {
    try {
      final payload = request.toJson();
      dynamic response;
      try {
        response = await _apiClient.dio.post(
          'organizer/api/v1/create-user/${request.eventId}?lang=eng',
          data: payload,
        );
      } catch (postErr) {
        // Fallback to legacy endpoint if v1 route is not mapped
        debugPrint('[AttendeeRemoteDatasource] v1 create-user failed: $postErr, attempting fallback');
        response = await _apiClient.dio.post(
          'organizer/create-attendee',
          data: payload,
        );
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
          final attendeeData = data['data'] is Map ? data['data'] as Map : data;
          final int? id = (attendeeData['id'] ??
                  attendeeData['pk'] ??
                  attendeeData['user_id'] as num?)
              ?.toInt();
          final String? uid = attendeeData['unique_id']?.toString() ??
              attendeeData['urn']?.toString() ??
              attendeeData['ticket_id']?.toString();
          final String name = attendeeData['name']?.toString() ??
              '${request.firstName} ${request.lastName}'.trim();

          return SpotRegistrationResult.success(
            message: data['message']?.toString() ?? 'Registration completed successfully',
            attendeeId: id,
            uniqueId: uid,
            fullName: name,
            email: request.email,
            rawData: data,
          );
        } else {
          final errorMsg = data['message']?.toString() ??
              data['detail']?.toString() ??
              'Registration failed. Please check inputs and try again.';
          return SpotRegistrationResult.failure(
            message: errorMsg,
            rawData: data,
          );
        }
      }
      return SpotRegistrationResult.failure(
        message: 'No response received from registration server.',
      );
    } catch (e) {
      debugPrint('[AttendeeRemoteDatasource] createSpotAttendee error: $e');
      return SpotRegistrationResult.failure(
        message: e.toString(),
      );
    }
  }

  /// Fetches global countries with dial codes, falling back to bundled list
  Future<List<CountryModel>> getCountries() async {
    try {
      final response = await _apiClient.dio.get(AppConstants.countriesEndpoint);
      if (response.statusCode == 200 && response.data != null) {
        dynamic parsed = response.data;
        if (parsed is String) {
          parsed = jsonDecode(parsed);
        }
        if (parsed is List) {
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
