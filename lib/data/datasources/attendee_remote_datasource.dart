import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../core/network/api_client.dart';
import '../models/attendee_details_model.dart';
import '../models/attendee_list_item_model.dart';

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
}
