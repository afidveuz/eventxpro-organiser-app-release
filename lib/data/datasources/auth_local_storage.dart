import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/remote_config_service.dart';
import '../models/user_model.dart';
import '../models/user_profile_model.dart';

class AuthLocalStorage {
  static const String _keyToken = 'auth_token';
  static const String _keyRefreshToken = 'auth_refresh_token';
  static const String _keyUser = 'auth_user';
  static const String _keyUserProfile = 'auth_user_profile';
  static const String _keyCountries = 'auth_countries';
  static const String _keyBaseUrl = 'auth_base_url';
  static const String _keyMediaUrl = 'auth_media_url';
  static const String _keyEventName = 'auth_event_name';

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secureStorage;

  // In-memory cache for ultra-fast, zero-latency synchronous access
  String? _cachedToken;
  String? _cachedRefreshToken;

  AuthLocalStorage(
    this._prefs, {
    FlutterSecureStorage? secureStorage,
    String? initialToken,
    String? initialRefreshToken,
  })  : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                resetOnError: true,
              ),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
            ),
        _cachedToken = initialToken,
        _cachedRefreshToken = initialRefreshToken;

  static Future<AuthLocalStorage> create({
    FlutterSecureStorage? secureStorage,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final storage = secureStorage ??
        const FlutterSecureStorage(
          aOptions: AndroidOptions(
            resetOnError: true,
          ),
          iOptions: IOSOptions(
            accessibility: KeychainAccessibility.first_unlock,
          ),
        );

    // 1. Read token & refresh token securely from Hardware KeyStore / Keychain
    String? token = await storage.read(key: _keyToken);
    String? refreshToken = await storage.read(key: _keyRefreshToken);

    // 2. Migration: If legacy tokens exist in unencrypted SharedPreferences, migrate them
    if (token == null || token.isEmpty) {
      final legacyToken = prefs.getString(_keyToken);
      if (legacyToken != null && legacyToken.isNotEmpty) {
        token = legacyToken;
        await storage.write(key: _keyToken, value: token);
      }
    }
    if (refreshToken == null || refreshToken.isEmpty) {
      final legacyRefresh = prefs.getString(_keyRefreshToken);
      if (legacyRefresh != null && legacyRefresh.isNotEmpty) {
        refreshToken = legacyRefresh;
        await storage.write(key: _keyRefreshToken, value: refreshToken);
      }
    }

    // 3. Remove plaintext tokens from SharedPreferences completely
    await prefs.remove(_keyToken);
    await prefs.remove(_keyRefreshToken);

    // 4. Sanitize legacy user model in SharedPreferences to ensure no tokens exist in auth_user JSON
    final rawUser = prefs.getString(_keyUser);
    if (rawUser != null && rawUser.isNotEmpty) {
      try {
        final map = jsonDecode(rawUser) as Map<String, dynamic>;
        if (map.containsKey('token') || map.containsKey('refreshToken')) {
          map.remove('token');
          map.remove('refreshToken');
          await prefs.setString(_keyUser, jsonEncode(map));
        }
      } catch (_) {}
    }

    return AuthLocalStorage(
      prefs,
      secureStorage: storage,
      initialToken: token,
      initialRefreshToken: refreshToken,
    );
  }

  // Token Management (Hardware Keystore / Keychain secured)
  String? getToken() => _cachedToken;

  Future<void> setToken(String token) async {
    _cachedToken = token;
    await _secureStorage.write(key: _keyToken, value: token);
    // Guarantee no plaintext copy is left behind in SharedPreferences
    await _prefs.remove(_keyToken);
  }

  String? getRefreshToken() => _cachedRefreshToken;

  Future<void> setRefreshToken(String refreshToken) async {
    _cachedRefreshToken = refreshToken;
    await _secureStorage.write(key: _keyRefreshToken, value: refreshToken);
    // Guarantee no plaintext copy is left behind in SharedPreferences
    await _prefs.remove(_keyRefreshToken);
  }

  bool get isLoggedIn {
    final token = getToken();
    return token != null && token.trim().isNotEmpty;
  }

  // User Profile (Tokens are never saved in cleartext SharedPreferences JSON)
  UserModel? getUser() {
    final raw = _prefs.getString(_keyUser);
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return UserModel.fromJson(
        map,
        token: getToken(),
        refreshToken: getRefreshToken(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> setUser(UserModel user) async {
    // Only persist non-sensitive profile info to SharedPreferences
    final safeUserMap = {
      'username': user.username,
      'name': user.name,
      'isAdmin': user.isAdmin,
    };
    await _prefs.setString(_keyUser, jsonEncode(safeUserMap));
  }

  // Full User Profile from organizer/user-profile
  UserProfileModel? getUserProfile() {
    final raw = _prefs.getString(_keyUserProfile);
    if (raw != null && raw.isNotEmpty) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        return UserProfileModel.fromJson(map);
      } catch (_) {}
    }
    // Fallback to basic cached user if full profile is not yet loaded
    final user = getUser();
    if (user != null) {
      return UserProfileModel(
        name: user.name,
        username: user.username,
        email: '',
        phone: '',
        isAdmin: user.isAdmin,
      );
    }
    return null;
  }

  Future<void> setUserProfile(UserProfileModel profile) async {
    await _prefs.setString(_keyUserProfile, jsonEncode(profile.toJson()));
    // Also keep basic user in sync
    await setUser(UserModel(
      username: profile.username,
      name: profile.name,
      isAdmin: profile.isAdmin,
    ));
  }

  // Countries Cache
  String? getCountriesJson() => _prefs.getString(_keyCountries);
  Future<void> setCountriesJson(String jsonString) =>
      _prefs.setString(_keyCountries, jsonString);

  /// Returns true if the user manually configured a custom base URL override.
  bool get hasCustomBaseUrl {
    final stored = _prefs.getString(_keyBaseUrl);
    return stored != null &&
        stored.trim().isNotEmpty &&
        !stored.contains('api-sfs-sfm.eventxpro.com');
  }

  // Dynamic Base URL
  String getBaseUrl() {
    final stored = _prefs.getString(_keyBaseUrl);
    if (stored != null &&
        stored.trim().isNotEmpty &&
        !stored.contains('api-sfs-sfm.eventxpro.com')) {
      return stored.endsWith('/') ? stored : '$stored/';
    }
    return RemoteConfigService().getDefaultBaseUrl();
  }

  Future<void> setBaseUrl(String url) async {
    final clean = url.trim().endsWith('/') ? url.trim() : '${url.trim()}/';
    await _prefs.setString(_keyBaseUrl, clean);
    await _prefs.setString(
      _keyMediaUrl,
      url.trim().endsWith('/')
          ? url.trim().substring(0, url.trim().length - 1)
          : url.trim(),
    );
  }

  Future<void> clearBaseUrl() async {
    await _prefs.remove(_keyBaseUrl);
    await _prefs.remove(_keyMediaUrl);
  }

  // Media Base URL for resolving profile pictures and media assets
  String getMediaUrl() {
    final stored = _prefs.getString(_keyMediaUrl);
    if (stored != null && stored.trim().isNotEmpty) {
      return stored.trim();
    }
    final base = getBaseUrl();
    return base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  }

  // Event Name
  String? getEventName() => _prefs.getString(_keyEventName);
  Future<void> setEventName(String name) =>
      _prefs.setString(_keyEventName, name);

  // Full Session Save
  Future<void> saveAuthSession({
    required String token,
    required String refreshToken,
    required UserModel user,
    String? countriesJson,
  }) async {
    await setToken(token);
    await setRefreshToken(refreshToken);
    await setUser(user);
    if (countriesJson != null) {
      await setCountriesJson(countriesJson);
    }
  }

  // Logout / Clear
  Future<void> clearSession() async {
    _cachedToken = null;
    _cachedRefreshToken = null;
    await _secureStorage.delete(key: _keyToken);
    await _secureStorage.delete(key: _keyRefreshToken);
    await _prefs.remove(_keyToken);
    await _prefs.remove(_keyRefreshToken);
    await _prefs.remove(_keyUser);
    await _prefs.remove(_keyUserProfile);
    // keep countries and base url cached for fast app reuse
  }
}
