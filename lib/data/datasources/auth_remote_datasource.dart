import 'dart:convert';
import 'package:dio/dio.dart';
import '../../core/config/app_constants.dart';
import '../../core/network/api_client.dart';

class AuthRemoteDatasource {
  final ApiClient _apiClient;

  AuthRemoteDatasource({required ApiClient apiClient})
      : _apiClient = apiClient;

  /// Call organizer/login endpoint
  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    try {
      final response = await _apiClient.dio.post(
        AppConstants.loginEndpoint,
        data: {
          'username': username.trim(),
          'password': password,
        },
      );

      final data = response.data is String
          ? jsonDecode(response.data as String) as Map<String, dynamic>
          : response.data as Map<String, dynamic>;

      return data;
    } on DioException catch (dioErr) {
      if (dioErr.response?.data != null) {
        final data = dioErr.response!.data;
        if (data is Map<String, dynamic>) {
          return {
            'status': false,
            'message': data['message'] ?? data['detail'] ?? 'Login failed. Please verify credentials.',
          };
        } else if (data is String) {
          try {
            final parsed = jsonDecode(data);
            if (parsed is Map<String, dynamic>) {
              return {
                'status': false,
                'message': parsed['message'] ?? parsed['detail'] ?? 'Login failed.',
              };
            }
          } catch (_) {}
        }
      }
      return {
        'status': false,
        'message': 'Network connection issue: ${dioErr.message ?? 'Please check internet'}',
      };
    } catch (e) {
      return {
        'status': false,
        'message': 'Unexpected error: $e',
      };
    }
  }

  /// Fetch countries for registration / country codes
  Future<String?> fetchCountries() async {
    try {
      final response = await _apiClient.dio.get(AppConstants.countriesEndpoint);
      if (response.statusCode == 200 && response.data != null) {
        if (response.data is String) {
          return response.data as String;
        } else {
          return jsonEncode(response.data);
        }
      }
    } catch (_) {
      // Non-critical, continue without countries
    }
    return null;
  }

  /// Request OTP for forgot password
  Future<Map<String, dynamic>> generateOtp({required String email}) async {
    try {
      final response = await _apiClient.dio.post(
        AppConstants.generateOtpEndpoint,
        data: {'email': email.trim()},
      );

      final data = response.data is String
          ? jsonDecode(response.data as String) as Map<String, dynamic>
          : response.data as Map<String, dynamic>;
      return data;
    } on DioException catch (dioErr) {
      final data = dioErr.response?.data;
      String msg = 'Failed to generate OTP';
      if (data is Map && data['message'] != null) {
        msg = data['message'].toString();
      }
      return {'status': false, 'message': msg};
    } catch (e) {
      return {'status': false, 'message': e.toString()};
    }
  }
}
