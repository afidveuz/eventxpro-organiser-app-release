import '../datasources/auth_local_storage.dart';
import '../datasources/auth_remote_datasource.dart';
import '../models/user_model.dart';
import '../models/user_profile_model.dart';

class AuthResult {
  final bool isSuccess;
  final UserModel? user;
  final String? errorMessage;

  AuthResult._({required this.isSuccess, this.user, this.errorMessage});

  factory AuthResult.success(UserModel user) =>
      AuthResult._(isSuccess: true, user: user);

  factory AuthResult.failure(String error) =>
      AuthResult._(isSuccess: false, errorMessage: error);
}

class AuthRepository {
  final AuthRemoteDatasource _remoteDatasource;
  final AuthLocalStorage _localStorage;

  AuthRepository({
    required AuthRemoteDatasource remoteDatasource,
    required AuthLocalStorage localStorage,
  })  : _remoteDatasource = remoteDatasource,
        _localStorage = localStorage;

  Future<AuthResult> login({
    required String username,
    required String password,
  }) async {
    final response = await _remoteDatasource.login(
      username: username,
      password: password,
    );

    final status = response['status'] as bool? ?? false;
    if (status) {
      final token = response['token'] as String? ?? '';
      final refreshToken = response['refresh_token'] as String? ?? '';
      final user = UserModel.fromJson(
        response,
        token: token,
        refreshToken: refreshToken,
      );

      // Concurrently fetch countries just like React Native app does
      final countriesJson = await _remoteDatasource.fetchCountries();

      // Persist full session
      await _localStorage.saveAuthSession(
        token: token,
        refreshToken: refreshToken,
        user: user,
        countriesJson: countriesJson,
      );

      return AuthResult.success(user);
    } else {
      final msg = response['message'] as String? ?? 'Invalid credentials. Please try again.';
      return AuthResult.failure(msg);
    }
  }

  bool get isLoggedIn => _localStorage.isLoggedIn;

  UserModel? get currentUser => _localStorage.getUser();

  UserProfileModel? get cachedUserProfile => _localStorage.getUserProfile();

  String get baseUrl => _localStorage.getBaseUrl();

  String get mediaUrl => _localStorage.getMediaUrl();

  bool get hasCustomBaseUrl => _localStorage.hasCustomBaseUrl;

  Future<void> updateBaseUrl(String url) => _localStorage.setBaseUrl(url);

  Future<void> clearBaseUrl() => _localStorage.clearBaseUrl();

  Future<void> logout() => _localStorage.clearSession();

  Future<Map<String, dynamic>> generateOtp(String email) =>
      _remoteDatasource.generateOtp(email: email);

  Future<Map<String, dynamic>> validateOtp({
    required String email,
    required int otp,
  }) =>
      _remoteDatasource.validateOtp(email: email, otp: otp);

  Future<Map<String, dynamic>> resetPassword({
    required String password,
    required String confirmPassword,
    required String resetToken,
  }) =>
      _remoteDatasource.resetPassword(
        password: password,
        confirmPassword: confirmPassword,
        resetToken: resetToken,
      );

  /// Fetches full user profile from 'organizer/user-profile' matching React Native useProfile.
  /// Falls back to cached profile when offline.
  Future<UserProfileModel?> getUserProfile({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = _localStorage.getUserProfile();
      if (cached != null && cached.email.isNotEmpty) {
        return cached;
      }
    }

    try {
      final response = await _remoteDatasource.getUserProfile();
      final status = response['status'] as bool? ?? false;
      if (status) {
        final dataMap = response['data'] is Map<String, dynamic>
            ? response['data'] as Map<String, dynamic>
            : response;

        // Retain isAdmin from current logged-in user if backend doesn't return it
        final current = _localStorage.getUser();
        if (!dataMap.containsKey('is_admin') &&
            !dataMap.containsKey('isAdmin') &&
            current != null) {
          dataMap['isAdmin'] = current.isAdmin;
        }

        final profile = UserProfileModel.fromJson(dataMap);
        await _localStorage.setUserProfile(profile);
        return profile;
      }
    } catch (_) {}

    return _localStorage.getUserProfile();
  }
}
