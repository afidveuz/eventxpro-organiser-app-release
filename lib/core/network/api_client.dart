import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../data/datasources/auth_local_storage.dart';
import '../config/app_constants.dart';
import '../services/crashlytics_service.dart';

class ApiClient {
  final AuthLocalStorage _localStorage;
  late final Dio _dio;
  void Function(String message)? onUnauthorized;

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
          CrashlyticsService().log('HTTP ${options.method} ${options.path}');
          return handler.next(options);
        },
        onResponse: (response, handler) {
          debugPrint('✅ [API RESP ${response.statusCode}] ${response.requestOptions.path}');
          return handler.next(response);
        },
        onError: (DioException error, handler) async {
          debugPrint('❌ [API ERR ${error.response?.statusCode}] ${error.requestOptions.path} => ${error.response?.data}');
          
          // Detect and report Server Down / 5xx / Connection failure to Firebase Crashlytics
          final statusCode = error.response?.statusCode;
          final isServerDown = (statusCode != null && statusCode >= 500) ||
              error.type == DioExceptionType.connectionTimeout ||
              error.type == DioExceptionType.receiveTimeout ||
              error.type == DioExceptionType.sendTimeout ||
              error.type == DioExceptionType.connectionError;

          if (isServerDown) {
            CrashlyticsService().recordServerDown(
              endpoint: error.requestOptions.path,
              baseUrl: error.requestOptions.baseUrl,
              statusCode: statusCode,
              errorMessage: ApiClient.formatDioError(error),
              stackTrace: error.stackTrace,
              extra: {
                'method': error.requestOptions.method,
                'dio_type': error.type.name,
              },
            );
          }

          // Check for 401 Unauthorized to trigger token refresh or clear session
          if (error.response?.statusCode == 401) {
            // Ignore 401 on login or auth endpoints, or when no user session is active.
            // A 401 on login is an invalid credential error, not an expired session.
            final path = error.requestOptions.path;
            final isAuthEndpoint = path.contains(AppConstants.loginEndpoint) ||
                path.contains(AppConstants.refreshTokenEndpoint) ||
                path.contains(AppConstants.generateOtpEndpoint);

            if (isAuthEndpoint || !_localStorage.isLoggedIn) {
              return handler.next(error);
            }

            String message = 'Unauthorized. Please login again.';
            if (error.response?.data is Map) {
              final rawMsg = error.response?.data['message'] ?? error.response?.data['detail'];
              if (rawMsg != null) message = rawMsg.toString();
            }

            final isAnotherLogin = message.toLowerCase().contains('another login detected') ||
                message.toLowerCase().contains('logged out');

            // If explicitly logged out due to another login, clear session immediately and notify logout
            if (isAnotherLogin) {
              debugPrint('🚨 [API 401] Another login detected! Clearing session and logging out.');
              await _localStorage.clearSession();
              onUnauthorized?.call(message);
              return handler.next(error);
            }

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
                  await _localStorage.clearSession();
                  onUnauthorized?.call(message);
                  return handler.next(error);
                }
              }
            }

            await _localStorage.clearSession();
            onUnauthorized?.call(message);
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

  /// Formats a DioException into a standard, clean, user-friendly error message.
  /// Never exposes private internal URLs, domains, stack traces, or library debugging text.
  static String formatDioError(DioException dioErr) {
    // 1. If backend returned a structured JSON response
    if (dioErr.response?.data != null) {
      final data = dioErr.response!.data;
      if (data is Map<String, dynamic>) {
        final msg = data['message'] ?? data['detail'] ?? data['error'];
        if (msg != null && msg.toString().trim().isNotEmpty) {
          return msg.toString().trim();
        }
      } else if (data is String && data.trim().isNotEmpty) {
        try {
          final parsed = jsonDecode(data);
          if (parsed is Map<String, dynamic>) {
            final msg = parsed['message'] ?? parsed['detail'] ?? parsed['error'];
            if (msg != null && msg.toString().trim().isNotEmpty) {
              return msg.toString().trim();
            }
          }
        } catch (_) {
          // If response is raw HTML or plaintext, do not expose raw HTML
        }
      }
    }

    // 2. HTTP Status Code based fallbacks
    final statusCode = dioErr.response?.statusCode;
    if (statusCode != null) {
      switch (statusCode) {
        case 400:
          return 'Invalid request. Please verify credentials.';
        case 401:
          return 'Invalid username or password.';
        case 403:
          return 'Access denied. You do not have permission.';
        case 404:
          return 'Server endpoint not found. Please verify domain configuration.';
        case 500:
        case 502:
        case 503:
        case 504:
          return 'Server error ($statusCode). Please try again later.';
        default:
          return 'Request failed ($statusCode). Please try again.';
      }
    }

    // 3. Network and Socket error handling (DNS failures, offline, timeouts)
    switch (dioErr.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Connection timed out. Please check your internet connection.';
      case DioExceptionType.badCertificate:
        return 'Security certificate error. Please verify server domain.';
      case DioExceptionType.cancel:
        return 'Request was cancelled.';
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
      default:
        final errText = '${dioErr.error ?? ''} ${dioErr.message ?? ''}'.toLowerCase();
        if (errText.contains('failed host lookup') ||
            errText.contains('nodename nor servname') ||
            errText.contains('socketexception') ||
            errText.contains('network is unreachable')) {
          return 'Unable to reach server. Please check your internet connection or server configuration.';
        }
        if (errText.contains('connection refused')) {
          return 'Connection refused by server. Please verify your domain configuration.';
        }
        return 'Network connection issue. Please check your internet connection.';
    }
  }
}
