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
      return {
        'status': false,
        'message': ApiClient.formatDioError(dioErr),
      };
    } catch (e) {
      return {
        'status': false,
        'message': 'Unexpected error occurred. Please try again.',
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
      return {
        'status': false,
        'message': ApiClient.formatDioError(dioErr),
      };
    } catch (e) {
      return {
        'status': false,
        'message': 'Unexpected error occurred. Please try again.',
      };
    }
  }
}
