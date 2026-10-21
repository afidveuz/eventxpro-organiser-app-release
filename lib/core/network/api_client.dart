import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../data/datasources/auth_local_storage.dart';
import '../config/app_constants.dart';

class ApiClient {
  final AuthLocalStorage _localStorage;
  late final Dio _dio;

  ApiClient({required AuthLocalStorage localStorage})
      : _localStorage = localStorage {
    _dio = Dio(
      BaseOptions(
        baseUrl: _localStorage.getBaseUrl(),
        connectTimeout: AppConstants.defaultNetworkTimeout,
        receiveTimeout: AppConstants.defaultNetworkTimeout,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          // Always keep baseUrl aligned with stored setting
          options.baseUrl = _localStorage.getBaseUrl();

          final token = _localStorage.getToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          debugPrint('🌐 [API REQ] ${options.method} ${options.baseUrl}${options.path}');
          return handler.next(options);
        },
        onResponse: (response, handler) {
          debugPrint('✅ [API RESP ${response.statusCode}] ${response.requestOptions.path}');
          return handler.next(response);
        },
        onError: (DioException error, handler) async {
          debugPrint('❌ [API ERR ${error.response?.statusCode}] ${error.requestOptions.path} => ${error.response?.data}');
          
          // Check for 401 Unauthorized to trigger token refresh or clear session
          if (error.response?.statusCode == 401) {
            final refreshToken = _localStorage.getRefreshToken();
            if (refreshToken != null && refreshToken.isNotEmpty) {
              final newAccessToken = await _attemptRefreshToken(refreshToken);
              if (newAccessToken != null) {
                // Retry failed request with new access token
                final clonedOptions = error.requestOptions;
                clonedOptions.headers['Authorization'] = 'Bearer $newAccessToken';
                try {
                  final retryResp = await _dio.fetch(clonedOptions);
                  return handler.resolve(retryResp);
                } catch (retryErr) {
                  return handler.next(error);
                }
              }
            }
          }
          return handler.next(error);
        },
      ),
    );
  }

  Future<String?> _attemptRefreshToken(String refreshToken) async {
    try {
      final refreshDio = Dio(
        BaseOptions(
          baseUrl: _localStorage.getBaseUrl(),
          headers: {
            'Authorization': 'Bearer $refreshToken',
            'Content-Type': 'application/json',
          },
        ),
      );
      final response = await refreshDio.post(AppConstants.refreshTokenEndpoint);
      if (response.statusCode == 200 && response.data != null) {
        final newToken = response.data['token'] as String?;
        final newRefreshToken = response.data['refresh_token'] as String?;
        if (newToken != null) {
          await _localStorage.setToken(newToken);
          if (newRefreshToken != null) {
            await _localStorage.setRefreshToken(newRefreshToken);
          }
          return newToken;
        }
      }
    } catch (e) {
      debugPrint('Failed to refresh auth token: $e');
      await _localStorage.clearSession();
    }
    return null;
  }

  void updateBaseUrl(String newUrl) {
    _dio.options.baseUrl = newUrl;
  }

  Dio get dio => _dio;
}
