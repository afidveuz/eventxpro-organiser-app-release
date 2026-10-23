import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../core/config/app_constants.dart';
import '../../domain/entities/scan_request.dart';

/// Local persistent storage for offline scan queues, gate settings, and device identity.
class ScannerLocalStorage {
  static const String _keyDeviceId = 'scanner_device_id';
  static const String _keyEventId = 'scanner_event_id';
  static const String _keyGateId = 'scanner_gate_id';
  static const String _keyScanType = 'scanner_scan_type';
  static const String _keyOfflineQueue = 'scanner_offline_queue';
  static const String _keyOfflineMode = 'scanner_offline_mode_enabled';
  static const String _keyServerUrl = 'scanner_server_url';
  static const String _keySuppressionMs = 'scanner_suppression_ms';
  static const String _keyTestUsername = 'scanner_test_username';
  static const String _keySimpleUiMode = 'scanner_simple_ui_mode';
  static const String _keyCameraEnabled = 'scanner_camera_enabled';
  static const String _keyTopLevelTickets = 'scanner_top_level_tickets';
  static const String _keyShortToast = 'scanner_short_toast';
  static const String _keyOfflineData = 'scanner_offline_data';

  final SharedPreferences _prefs;

  ScannerLocalStorage(this._prefs);

  static Future<ScannerLocalStorage> create() async {
    final prefs = await SharedPreferences.getInstance();
    return ScannerLocalStorage(prefs);
  }

  /// Get or create a persistent registered-device-uuid
  String getDeviceId() {
    String? id = _prefs.getString(_keyDeviceId);
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      _prefs.setString(_keyDeviceId, id);
    }
    return id;
  }

  int getEventId() {
    final val = _prefs.getInt(_keyEventId);
    if (val == null || val == 1024) {
      return AppConstants.defaultEventId; // 1
    }
    return val;
  }
  Future<void> setEventId(int value) => _prefs.setInt(_keyEventId, value);

  int getGateId() => _prefs.getInt(_keyGateId) ?? AppConstants.defaultGateId;
  Future<void> setGateId(int value) => _prefs.setInt(_keyGateId, value);

  String getScanType() =>
      _prefs.getString(_keyScanType) ?? AppConstants.defaultScanType;
  Future<void> setScanType(String value) =>
      _prefs.setString(_keyScanType, value);

  bool get isOfflineModeEnabled => _prefs.getBool(_keyOfflineMode) ?? false;
  Future<void> setOfflineMode(bool enabled) =>
      _prefs.setBool(_keyOfflineMode, enabled);

  bool get isSimpleUiMode => _prefs.getBool(_keySimpleUiMode) ?? true;
  Future<void> setSimpleUiMode(bool enabled) =>
      _prefs.setBool(_keySimpleUiMode, enabled);

  bool get isCameraEnabled => _prefs.getBool(_keyCameraEnabled) ?? false;
  Future<void> setCameraEnabled(bool enabled) =>
      _prefs.setBool(_keyCameraEnabled, enabled);

  bool get isTopLevelTicketsEnabled =>
      _prefs.getBool(_keyTopLevelTickets) ?? false;
  Future<void> setTopLevelTickets(bool enabled) =>
      _prefs.setBool(_keyTopLevelTickets, enabled);

  bool get isShortToastEnabled => _prefs.getBool(_keyShortToast) ?? false;
  Future<void> setShortToast(bool enabled) =>
      _prefs.setBool(_keyShortToast, enabled);

  String? getOfflineData() => _prefs.getString(_keyOfflineData);
  Future<void> setOfflineData(String data) =>
      _prefs.setString(_keyOfflineData, data);

  /// Retrieves the event ticket encryption key from offline cached permissions, or fallback default
  String getTicketEncryptionKey() {
    final rawData = getOfflineData();
    if (rawData != null && rawData.isNotEmpty) {
      try {
        final map = jsonDecode(rawData) as Map<String, dynamic>;
        final permission = map['permission'] as Map<String, dynamic>?;
        final key = permission?['ticket_encryption_key'] as String?;
        if (key != null && key.trim().isNotEmpty) {
          return key.trim();
        }
      } catch (_) {}
    }
    return AppConstants.defaultTicketEncryptionKey;
  }

  String getServerUrl() =>
      _prefs.getString(_keyServerUrl) ?? AppConstants.defaultBaseUrl;
  Future<void> setServerUrl(String url) => _prefs.setString(_keyServerUrl, url);

  int getSuppressionMs() =>
      _prefs.getInt(_keySuppressionMs) ??
      AppConstants.defaultDuplicateSuppressionMs;
  Future<void> setSuppressionMs(int ms) =>
      _prefs.setInt(_keySuppressionMs, ms);

  String getTestUsername() =>
      _prefs.getString(_keyTestUsername) ?? 'user@example.com';
  Future<void> setTestUsername(String username) =>
      _prefs.setString(_keyTestUsername, username);

  /// Offline Queue Operations (FIFO)
  List<ScanRequest> getOfflineQueue() {
    final rawList = _prefs.getStringList(_keyOfflineQueue) ?? [];
    return rawList.map((itemStr) {
      final map = jsonDecode(itemStr) as Map<String, dynamic>;
      return ScanRequest(
        qrToken: map['qr_token'] as String,
        eventId: map['event_id'] as int,
        gateId: map['gate_id'] as int,
        scanType: map['scan_type'] as String? ?? 'ENTRY',
        deviceId: map['device_id'] as String,
        scanRequestId: map['scan_request_id'] as String,
        scannedAt: DateTime.tryParse(map['scanned_at'] as String? ?? '') ??
            DateTime.now(),
      );
    }).toList();
  }

  Future<void> addToOfflineQueue(ScanRequest request) async {
    final rawList = _prefs.getStringList(_keyOfflineQueue) ?? [];
    if (rawList.length >= AppConstants.maxQueueCapacity) {
      // Safe FIFO overflow drop: drop oldest
      rawList.removeAt(0);
    }
    rawList.add(jsonEncode(request.toJson()));
    await _prefs.setStringList(_keyOfflineQueue, rawList);
  }

  Future<void> clearOfflineQueue() async {
    await _prefs.remove(_keyOfflineQueue);
  }
}
