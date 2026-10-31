import 'dart:convert';
import 'package:dio/dio.dart';
import '../../core/config/app_constants.dart';
import '../../core/network/api_client.dart';
import '../models/onsite_coupon_details_model.dart';
import '../models/qr_blacklist_user_model.dart';

class QrVerificationRemoteDatasource {
  final ApiClient _apiClient;

  QrVerificationRemoteDatasource({required ApiClient apiClient})
      : _apiClient = apiClient;

  Future<QrUserDetailsModel> getUserDetails({
    required int eventId,
    required String ticketId,
  }) async {
    int effectiveEventId = eventId;
    if (effectiveEventId <= 1) {
      try {
        final dashRes = await _apiClient.dio.get('organizer/dashboard');
        if (dashRes.statusCode == 200 && dashRes.data != null) {
          final data = dashRes.data is Map
              ? dashRes.data as Map<String, dynamic>
              : (dashRes.data is String ? jsonDecode(dashRes.data as String) : null);
          if (data != null) {
            final rawEvents = data['event_list'] as List<dynamic>? ?? [];
            if (rawEvents.isNotEmpty) {
              final firstEvt = rawEvents.first as Map<String, dynamic>;
              final pk = (firstEvt['pk'] as num?)?.toInt() ??
                  (firstEvt['id'] as num?)?.toInt() ??
                  int.tryParse(firstEvt['pk']?.toString() ?? '') ??
                  int.tryParse(firstEvt['id']?.toString() ?? '');
              if (pk != null && pk > 1) {
                effectiveEventId = pk;
              }
            }
          }
        }
      } catch (_) {}
    }

    try {
      final response = await _apiClient.dio.get(
        AppConstants.getUserDetailsEndpoint,
        queryParameters: {
          'event_id': effectiveEventId,
          'ticket_id': ticketId,
        },
      );

      if (response.statusCode == 200 && response.data != null) {
        final map = response.data is Map<String, dynamic>
            ? response.data as Map<String, dynamic>
            : Map<String, dynamic>.from(response.data as Map);

        final statusVal = map['status'] ?? (map['data'] is Map ? (map['data'] as Map)['status'] : null);
        final isSuccess = statusVal == true ||
            statusVal == 1 ||
            statusVal?.toString().toLowerCase() == 'true' ||
            statusVal?.toString().toLowerCase() == 'success';

        if (isSuccess || map.containsKey('user_details') || (map['data'] is Map && (map['data'] as Map).containsKey('user_details'))) {
          return QrUserDetailsModel.fromJson(map, ticketId: ticketId);
        }
        throw Exception(map['message']?.toString() ?? 'Attendee not found');
      }
      throw Exception('Failed to fetch attendee details (status: ${response.statusCode})');
    } on DioException catch (e) {
      throw Exception(ApiClient.formatDioError(e));
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception(e.toString());
    }
  }

  Future<String> updateBlacklistStatus({
    required String ticketId,
    required bool blacklistStatus,
    required String notes,
    int? eventId,
    String? uniqueId,
  }) async {
    Map<String, dynamic> buildPayload(String id) => {
          'ticket_id': id,
          'blacklist_status': blacklistStatus,
          'notes': notes,
          if (eventId != null && eventId > 0) 'event_id': eventId,
        };

    final queryParams = <String, dynamic>{
      if (eventId != null && eventId > 0) 'event_id': eventId,
    };

    try {
      final response = await _apiClient.dio.post(
        AppConstants.blacklistUpdateEndpoint,
        data: buildPayload(ticketId),
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
      );

      if (response.statusCode == 200 && response.data != null) {
        final map = response.data is Map<String, dynamic>
            ? response.data as Map<String, dynamic>
            : Map<String, dynamic>.from(response.data as Map);

        return map['message']?.toString() ?? 'Blacklist status updated successfully';
      }
      throw Exception('Failed to update blacklist status (status: ${response.statusCode})');
    } on DioException catch (e) {
      // If 404 Not Found and uniqueId is available and distinct, retry with uniqueId
      if (e.response?.statusCode == 404 &&
          uniqueId != null &&
          uniqueId.isNotEmpty &&
          uniqueId != ticketId) {
        try {
          final retryResponse = await _apiClient.dio.post(
            AppConstants.blacklistUpdateEndpoint,
            data: buildPayload(uniqueId),
            queryParameters: queryParams.isNotEmpty ? queryParams : null,
          );

          if (retryResponse.statusCode == 200 && retryResponse.data != null) {
            final map = retryResponse.data is Map<String, dynamic>
                ? retryResponse.data as Map<String, dynamic>
                : Map<String, dynamic>.from(retryResponse.data as Map);

            return map['message']?.toString() ?? 'Blacklist status updated successfully';
          }
        } catch (_) {
          // If fallback retry also fails, rethrow formatted original error
        }
      }
      throw Exception(ApiClient.formatDioError(e));
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception(e.toString());
    }
  }

  Future<OnsiteCouponModel> getCouponDetails({
    required String couponCode,
  }) async {
    try {
      final response = await _apiClient.dio.get(
        AppConstants.getCouponDetailsEndpoint,
        queryParameters: {
          'coupon_code': couponCode,
        },
      );

      if (response.statusCode == 200 && response.data != null) {
        final map = response.data is Map<String, dynamic>
            ? response.data as Map<String, dynamic>
            : Map<String, dynamic>.from(response.data as Map);

        final statusVal = map['status'];
        final isSuccess = statusVal == true ||
            statusVal == 1 ||
            statusVal?.toString().toLowerCase() == 'true' ||
            statusVal?.toString().toLowerCase() == 'success';

        if (isSuccess) {
          return OnsiteCouponModel.fromJson(map);
        }
        throw Exception(map['message']?.toString() ?? 'Coupon not found or invalid');
      }
      throw Exception('Failed to fetch coupon details (status: ${response.statusCode})');
    } on DioException catch (e) {
      throw Exception(ApiClient.formatDioError(e));
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception(e.toString());
    }
  }
}
