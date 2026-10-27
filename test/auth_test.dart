import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scanner/core/config/app_constants.dart';
import 'package:qr_scanner/core/network/api_client.dart';
import 'package:qr_scanner/data/datasources/auth_local_storage.dart';
import 'package:qr_scanner/data/datasources/auth_remote_datasource.dart';
import 'package:qr_scanner/data/models/user_model.dart';
import 'package:qr_scanner/data/repositories/auth_repository.dart';
import 'package:qr_scanner/presentation/bloc/auth/auth_bloc.dart';
import 'package:qr_scanner/presentation/bloc/auth/auth_event.dart';
import 'package:qr_scanner/presentation/bloc/auth/auth_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockAuthRemoteDatasource extends AuthRemoteDatasource {
  bool shouldSucceed = true;
  String mockErrorMessage = 'Invalid Credentials';

  MockAuthRemoteDatasource({required super.apiClient});

  @override
  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    if (shouldSucceed) {
      return {
        'status': true,
        'token': 'mock-access-token-xyz',
        'refresh_token': 'mock-refresh-token-abc',
        'username': username,
        'name': 'Test Organizer',
        'is_admin': true,
      };
    } else {
      return {
        'status': false,
        'message': mockErrorMessage,
      };
    }
  }

  @override
  Future<String?> fetchCountries() async {
    return '["United Arab Emirates", "Saudi Arabia", "India", "Kenya"]';
  }

  @override
  Future<Map<String, dynamic>> generateOtp({required String email}) async {
    return {'status': true, 'message': 'OTP sent'};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AuthLocalStorage authLocalStorage;
  late ApiClient apiClient;
  late MockAuthRemoteDatasource remoteDatasource;
  late AuthRepository authRepository;
  late AuthBloc authBloc;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    authLocalStorage = await AuthLocalStorage.create();
    apiClient = ApiClient(localStorage: authLocalStorage);
    remoteDatasource = MockAuthRemoteDatasource(apiClient: apiClient);
    authRepository = AuthRepository(
      remoteDatasource: remoteDatasource,
      localStorage: authLocalStorage,
    );
    authBloc = AuthBloc(authRepository: authRepository);
  });

  tearDown(() {
    authBloc.close();
  });

  group('UserModel Tests', () {
    test('Correctly parses organizer/login JSON response', () {
      final json = {
        'username': 'admin@eventxpro.com',
        'name': 'Super Admin',
        'is_admin': true,
        'token': 'sample-jwt',
        'refresh_token': 'sample-refresh',
      };

      final user = UserModel.fromJson(json);
      expect(user.username, 'admin@eventxpro.com');
      expect(user.name, 'Super Admin');
      expect(user.isAdmin, true);
      expect(user.token, 'sample-jwt');
      expect(user.refreshToken, 'sample-refresh');
    });

    test('Correctly falls back to is_company_admin if is_admin is absent', () {
      final json = {
        'username': 'company@eventxpro.com',
        'name': 'Company Admin',
        'is_company_admin': true,
      };

      final user = UserModel.fromJson(json);
      expect(user.isAdmin, true);
    });
  });

  group('AuthLocalStorage Tests', () {
    test('Stores and retrieves auth session cleanly', () async {
      expect(authLocalStorage.isLoggedIn, false);

      const user = UserModel(
        username: 'organizer@test.com',
        name: 'John Doe',
        isAdmin: true,
      );

      await authLocalStorage.saveAuthSession(
        token: 'token-123',
        refreshToken: 'refresh-456',
        user: user,
      );

      expect(authLocalStorage.isLoggedIn, true);
      expect(authLocalStorage.getToken(), 'token-123');
      expect(authLocalStorage.getRefreshToken(), 'refresh-456');
      expect(authLocalStorage.getUser()?.username, 'organizer@test.com');

      // Security Verification: Plain SharedPreferences MUST NOT contain raw tokens!
      final rawPrefs = await SharedPreferences.getInstance();
      expect(rawPrefs.containsKey('auth_token'), isFalse);
      expect(rawPrefs.containsKey('auth_refresh_token'), isFalse);

      // Verify auth_user in SharedPreferences does not leak tokens
      final rawUser = rawPrefs.getString('auth_user');
      expect(rawUser, isNotNull);
      expect(rawUser!.contains('token-123'), isFalse);
      expect(rawUser.contains('refresh-456'), isFalse);

      // Verify FlutterSecureStorage actually holds the encrypted tokens
      const secureStorage = FlutterSecureStorage();
      final secureToken = await secureStorage.read(key: 'auth_token');
      final secureRefresh = await secureStorage.read(key: 'auth_refresh_token');
      expect(secureToken, 'token-123');
      expect(secureRefresh, 'refresh-456');

      await authLocalStorage.clearSession();
      expect(authLocalStorage.isLoggedIn, false);
      expect(authLocalStorage.getToken(), null);
      expect(await secureStorage.read(key: 'auth_token'), null);
      expect(await secureStorage.read(key: 'auth_refresh_token'), null);
    });

    test('Migrates legacy plaintext tokens from SharedPreferences to FlutterSecureStorage and deletes them from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        'auth_token': 'legacy-plain-token',
        'auth_refresh_token': 'legacy-plain-refresh',
        'auth_user': '{"username":"old@test.com","name":"Old User","isAdmin":false,"token":"legacy-plain-token"}',
      });
      FlutterSecureStorage.setMockInitialValues({});

      // Initialize storage, triggering automatic migration
      final migratedStorage = await AuthLocalStorage.create();

      // Verified: In-memory & Secure Storage have the tokens
      expect(migratedStorage.getToken(), 'legacy-plain-token');
      expect(migratedStorage.getRefreshToken(), 'legacy-plain-refresh');

      const secureStorage = FlutterSecureStorage();
      expect(await secureStorage.read(key: 'auth_token'), 'legacy-plain-token');
      expect(await secureStorage.read(key: 'auth_refresh_token'), 'legacy-plain-refresh');

      // Verified: Plaintext SharedPreferences is completely wiped of tokens
      final rawPrefs = await SharedPreferences.getInstance();
      expect(rawPrefs.containsKey('auth_token'), isFalse);
      expect(rawPrefs.containsKey('auth_refresh_token'), isFalse);

      final userJson = rawPrefs.getString('auth_user');
      expect(userJson, isNotNull);
      expect(userJson!.contains('legacy-plain-token'), isFalse);
    });

    test('Handles dynamic base URL and resets to default', () async {
      expect(authLocalStorage.getBaseUrl(), AppConstants.defaultBaseUrl);

      await authLocalStorage.setBaseUrl('https://staging-api.eventxpro.com');
      expect(authLocalStorage.getBaseUrl(), 'https://staging-api.eventxpro.com/');

      await authLocalStorage.clearBaseUrl();
      expect(authLocalStorage.getBaseUrl(), AppConstants.defaultBaseUrl);
    });
  });

  group('AuthBloc & Validation Tests', () {
    test('Validation fails when username and password are empty', () async {
      authBloc.add(const LoginSubmitted(username: '', password: ''));

      await expectLater(
        authBloc.stream,
        emitsInOrder([
          const AuthUnauthenticated(
            errorMessage: 'Please enter username and password',
          ),
        ]),
      );
    });

    test('Validation fails when password is empty', () async {
      authBloc.add(const LoginSubmitted(username: 'admin', password: ''));

      await expectLater(
        authBloc.stream,
        emitsInOrder([
          const AuthUnauthenticated(
            errorMessage: 'Please enter password',
          ),
        ]),
      );
    });

    test('Successful login emits AuthLoading then AuthAuthenticated', () async {
      remoteDatasource.shouldSucceed = true;

      authBloc.add(const LoginSubmitted(
        username: 'admin@eventxpro.com',
        password: 'Password123',
      ));

      await expectLater(
        authBloc.stream,
        emitsInOrder([
          const AuthLoading(message: 'Logging in...'),
          predicate<AuthState>((state) {
            return state is AuthAuthenticated &&
                state.user.username == 'admin@eventxpro.com' &&
                state.user.isAdmin == true;
          }),
        ]),
      );

      // Verify stored credentials
      expect(authLocalStorage.isLoggedIn, true);
      expect(authLocalStorage.getToken(), 'mock-access-token-xyz');
    });

    test('Failed login emits AuthLoading then AuthUnauthenticated with backend message', () async {
      remoteDatasource.shouldSucceed = false;
      remoteDatasource.mockErrorMessage = 'Invalid Credentials';

      authBloc.add(const LoginSubmitted(
        username: 'wrong@eventxpro.com',
        password: 'WrongPassword',
      ));

      await expectLater(
        authBloc.stream,
        emitsInOrder([
          const AuthLoading(message: 'Logging in...'),
          const AuthUnauthenticated(errorMessage: 'Invalid Credentials'),
        ]),
      );

      expect(authLocalStorage.isLoggedIn, false);
    });

    test('Logout clears session and emits AuthUnauthenticated', () async {
      await authLocalStorage.setToken('existing-token');
      expect(authLocalStorage.isLoggedIn, true);

      authBloc.add(const LogoutRequested());

      await expectLater(
        authBloc.stream,
        emitsInOrder([
          const AuthLoading(message: 'Logging out...'),
          const AuthUnauthenticated(),
        ]),
      );

      expect(authLocalStorage.isLoggedIn, false);
    });
  });

  group('ApiClient 401 Session Interceptor Tests', () {
    test('401 on login endpoint does not trigger onUnauthorized callback', () async {
      bool onUnauthorizedCalled = false;
      apiClient.onUnauthorized = (msg) {
        onUnauthorizedCalled = true;
      };

      apiClient.dio.httpClientAdapter = Mock401Adapter({'detail': 'Invalid username or password'});

      final realRemoteDatasource = AuthRemoteDatasource(apiClient: apiClient);
      final result = await realRemoteDatasource.login(
        username: 'wronguser',
        password: 'wrongpassword',
      );

      expect(result['status'], false);
      expect(result['message'], 'Invalid username or password');
      expect(onUnauthorizedCalled, false);
      expect(authLocalStorage.isLoggedIn, false);
    });

    test('401 on authenticated endpoint with active session triggers onUnauthorized', () async {
      bool onUnauthorizedCalled = false;
      String? unauthorizedMsg;
      apiClient.onUnauthorized = (msg) {
        onUnauthorizedCalled = true;
        unauthorizedMsg = msg;
      };

      // Set logged in session
      await authLocalStorage.setToken('valid-token');
      expect(authLocalStorage.isLoggedIn, true);

      apiClient.dio.httpClientAdapter = Mock401Adapter({'detail': 'Another login detected'});

      try {
        await apiClient.dio.get('organizer/dashboard');
      } catch (_) {}

      expect(onUnauthorizedCalled, true);
      expect(unauthorizedMsg, 'Another login detected');
      expect(authLocalStorage.isLoggedIn, false);
    });
  });

  group('ApiClient.formatDioError Sanitization Tests', () {
    test('DNS failure / wrong domain does not leak internal domain or library debug text', () {
      final dioErr = DioException(
        requestOptions: RequestOptions(path: 'organizer/login'),
        type: DioExceptionType.connectionError,
        message: "The connection errored: Failed host lookup: 'api-ism-plme-gfmdddd-ghf-staging.eventxpro.com' This indicates an error which most likely cannot be solved by the library.",
      );

      final formatted = ApiClient.formatDioError(dioErr);

      expect(formatted, 'Unable to reach server. Please check your internet connection or server configuration.');
      expect(formatted.contains('api-ism-plme-gfmdddd-ghf-staging.eventxpro.com'), false);
      expect(formatted.contains('indicates an error'), false);
      expect(formatted.contains('library'), false);
    });

    test('Structured JSON message from backend is returned as-is', () {
      final dioErr = DioException(
        requestOptions: RequestOptions(path: 'organizer/login'),
        response: Response(
          requestOptions: RequestOptions(path: 'organizer/login'),
          statusCode: 401,
          data: {'detail': 'No active account found with the given credentials'},
        ),
      );

      final formatted = ApiClient.formatDioError(dioErr);
      expect(formatted, 'No active account found with the given credentials');
    });

    test('Connection timeout produces friendly message', () {
      final dioErr = DioException(
        requestOptions: RequestOptions(path: 'organizer/login'),
        type: DioExceptionType.connectionTimeout,
      );

      final formatted = ApiClient.formatDioError(dioErr);
      expect(formatted, 'Connection timed out. Please check your internet connection.');
    });

    test('HTTP 500 error produces clean message with status code', () {
      final dioErr = DioException(
        requestOptions: RequestOptions(path: 'organizer/login'),
        response: Response(
          requestOptions: RequestOptions(path: 'organizer/login'),
          statusCode: 500,
        ),
      );

      final formatted = ApiClient.formatDioError(dioErr);
      expect(formatted, 'Server error (500). Please try again later.');
    });
  });
}

class Mock401Adapter implements HttpClientAdapter {
  final Map<String, dynamic> responseData;
  Mock401Adapter(this.responseData);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      jsonEncode(responseData),
      401,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}


