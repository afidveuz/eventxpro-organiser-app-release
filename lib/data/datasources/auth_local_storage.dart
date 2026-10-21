import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/config/app_constants.dart';
import '../models/user_model.dart';

class AuthLocalStorage {
  static const String _keyToken = 'auth_token';
  static const String _keyRefreshToken = 'auth_refresh_token';
  static const String _keyUser = 'auth_user';
  static const String _keyCountries = 'auth_countries';
  static const String _keyBaseUrl = 'auth_base_url';
  static const String _keyMediaUrl = 'auth_media_url';
  static const String _keyEventName = 'auth_event_name';

  final SharedPreferences _prefs;

  AuthLocalStorage(this._prefs);

  static Future<AuthLocalStorage> create() async {
    final prefs = await SharedPreferences.getInstance();
    return AuthLocalStorage(prefs);
  }

  // Token Management
  String? getToken() => _prefs.getString(_keyToken);
  Future<void> setToken(String token) => _prefs.setString(_keyToken, token);

  String? getRefreshToken() => _prefs.getString(_keyRefreshToken);
  Future<void> setRefreshToken(String refreshToken) =>
      _prefs.setString(_keyRefreshToken, refreshToken);

  bool get isLoggedIn {
    final token = getToken();
    return token != null && token.trim().isNotEmpty;
  }

  // User Profile
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
    await _prefs.setString(_keyUser, jsonEncode(user.toJson()));
  }

  // Countries Cache
  String? getCountriesJson() => _prefs.getString(_keyCountries);
  Future<void> setCountriesJson(String jsonString) =>
      _prefs.setString(_keyCountries, jsonString);

  // Dynamic Base URL
  String getBaseUrl() {
    final stored = _prefs.getString(_keyBaseUrl);
    if (stored != null &&
        stored.trim().isNotEmpty &&
        !stored.contains('api-sfs-sfm.eventxpro.com')) {
      return stored.endsWith('/') ? stored : '$stored/';
    }
    return AppConstants.defaultBaseUrl;
  }

  Future<void> setBaseUrl(String url) async {
    final clean = url.trim().endsWith('/') ? url.trim() : '${url.trim()}/';
    await _prefs.setString(_keyBaseUrl, clean);
    await _prefs.setString(_keyMediaUrl, url.trim().endsWith('/') ? url.trim().substring(0, url.trim().length - 1) : url.trim());
  }

  Future<void> clearBaseUrl() async {
    await _prefs.remove(_keyBaseUrl);
    await _prefs.remove(_keyMediaUrl);
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
    await _prefs.remove(_keyToken);
    await _prefs.remove(_keyRefreshToken);
    await _prefs.remove(_keyUser);
    // keep countries and base url cached for fast app reuse
  }
}
