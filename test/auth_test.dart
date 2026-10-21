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

      await authLocalStorage.clearSession();
      expect(authLocalStorage.isLoggedIn, false);
      expect(authLocalStorage.getToken(), null);
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
}
