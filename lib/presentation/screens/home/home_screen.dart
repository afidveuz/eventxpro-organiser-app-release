import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/network/api_client.dart';
import '../../../core/services/app_update_service.dart';
import '../../../core/services/device_detection_service.dart';
import '../../../core/services/gate_count_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/adapters/simulated_hardware_adapter.dart';
import '../../../data/adapters/zebra_datawedge_adapter.dart';
import '../../../data/datasources/offline_database_helper.dart';
import '../../../data/datasources/scanner_local_storage.dart';
import '../../../data/models/user_profile_model.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../bloc/auth/auth_bloc.dart';
import '../../bloc/auth/auth_event.dart';
import '../../bloc/scanner_bloc.dart';
import '../../bloc/scanner_event.dart';
import '../auth/login_screen.dart';
import '../kiosk_scanner_screen.dart';
import '../offline/offline_sessions_screen.dart';
import '../settings_screen.dart';
import '../../widgets/session_punch_card.dart';

/// Cached parsed sections for high-performance zero-delay expansion
class _ParsedEventSections {
  final List<Map<String, dynamic>> entranceList;
  final List<Map<String, dynamic>> hallList;
  final List<Map<String, dynamic>> agendaList;
  final List<Map<String, dynamic>> sessionList;

  const _ParsedEventSections({
    required this.entranceList,
    required this.hallList,
    required this.agendaList,
    required this.sessionList,
  });
}

/// EventXPro Organiser HomeScreen matching the reference React Native design.
/// Features:
/// - EventXPro signature color theme (#171C26, #0C1A52, #C10067 accent)
/// - Blinking "Offline Mode" badge when offline is active
/// - "TOTAL EVENTS" and "SCANNED USER" metrics count cards
/// - Event list with dates, description and "KNOW MORE" action
/// - "KNOW MORE" box with Entrances / Sessions and side-by-side CHECK-IN & CHECK-OUT buttons
class HomeScreen extends StatefulWidget {
  final ZebraDataWedgeAdapter? zebraAdapter;
  final SimulatedHardwareAdapter? simulatorAdapter;

  const HomeScreen({
    super.key,
    this.zebraAdapter,
    this.simulatorAdapter,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  int _totalEvents = 0;
  int _totalScannedCount = 0;
  List<Map<String, dynamic>> _eventList = [];
  bool _isOffline = false;
  int? _expandedEventPk;
  final Map<int, Map<String, dynamic>> _eventPermissions = {};
  final Map<int, _ParsedEventSections> _parsedSectionsCache = {};
  final Set<int> _loadingPermissions = {};
  DeviceInfoResult? _deviceInfo;
  UserProfileModel? _userProfile;
  int _countRefreshTrigger = 0;
  int _serverRefreshTrigger = 0;

  /// Throttle & Cache management for dashboard API requests
  DateTime? _lastDashboardFetchTime;
  bool _isDashboardFetching = false;
  static const Duration _dashboardThrottleDuration = Duration(seconds: 30);

  late final AnimationController _blinkController;
  late final Animation<double> _blinkAnimation;

  @override
  void initState() {
    super.initState();
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);

    _blinkAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _blinkController, curve: Curves.easeInOut),
    );

    _loadDashboardData();
    _initDeviceInfo();
    _initUserProfile();

    // Check for app updates on home screen load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        AppUpdateService().checkAndPromptUpdate(context);
      }
    });
  }

  Future<void> _initUserProfile() async {
    try {
      final authRepo = context.read<AuthRepository>();
      final cached = authRepo.cachedUserProfile;
      if (cached != null && mounted) {
        setState(() => _userProfile = cached);
      } else {
        final profile = await authRepo.getUserProfile();
        if (mounted) {
          setState(() => _userProfile = profile);
        }
      }
    } catch (_) {}
  }

  Future<void> _initDeviceInfo() async {
    try {
      final storage = context.read<ScannerLocalStorage>();
      final info = await DeviceDetectionService().detectDevice(storage: storage);
      if (mounted) {
        setState(() {
          _deviceInfo = info;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _blinkController.dispose();
    super.dispose();
  }

  /// Strip HTML tags from event description (matching React Native helper)
  String _stripHtmlTags(String? htmlString) {
    if (htmlString == null || htmlString.isEmpty) return '';
    return htmlString.replaceAll(RegExp(r'<[^>]*>'), '').trim();
  }

  /// Format date to MMM DD YYYY (e.g. Oct 23 2026)
  String _formatDate(dynamic dateVal) {
    if (dateVal == null) return '';
    try {
      final dt = DateTime.parse(dateVal.toString());
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      final month = months[dt.month - 1];
      return '$month ${dt.day.toString().padLeft(2, '0')} ${dt.year}';
    } catch (_) {
      return dateVal.toString();
    }
  }

  Future<void> _loadDashboardData({
    bool forceRefresh = false,
    bool silent = false,
  }) async {
    if (!mounted) return;
    // 1. Prevent concurrent overlapping executions
    if (_isDashboardFetching) return;

    final scannerLocalStorage = context.read<ScannerLocalStorage>();
    final dbHelper = context.read<OfflineDatabaseHelper>();
    final isOfflineEnabled = scannerLocalStorage.isOfflineModeEnabled;

    if (mounted) {
      setState(() {
        _isOffline = isOfflineEnabled;
      });
    }

    // 2. Offline Mode Handling
    if (isOfflineEnabled) {
      if (!silent) {
        setState(() => _isLoading = true);
      }
      await _loadOfflineData(scannerLocalStorage, dbHelper);
      return;
    }

    // 3. Online Mode: Throttling / TTL Check
    final now = DateTime.now();
    final isThrottled = !forceRefresh &&
        _lastDashboardFetchTime != null &&
        now.difference(_lastDashboardFetchTime!) < _dashboardThrottleDuration;

    if (isThrottled) {
      final elapsed = now.difference(_lastDashboardFetchTime!).inSeconds;
      debugPrint(
        '[HomeScreen] ⏳ Dashboard API throttled (${elapsed}s elapsed, min ${_dashboardThrottleDuration.inSeconds}s). '
        'Pull down to refresh or tap refresh icon to force update.',
      );

      // Even when throttled, refresh local offline scanned metrics immediately
      try {
        final totalScanned = await dbHelper.getTotalScannedCount();
        if (mounted && totalScanned > 0 && _totalScannedCount != totalScanned) {
          setState(() {
            _totalScannedCount = totalScanned;
          });
        }
      } catch (_) {}
      return;
    }

    // 4. Show loading state like previous when not silent
    if (!silent) {
      setState(() => _isLoading = true);
    }

    _isDashboardFetching = true;
    try {
      await _loadOnlineData(scannerLocalStorage, dbHelper);
      _lastDashboardFetchTime = DateTime.now();
    } finally {
      _isDashboardFetching = false;
      if (mounted && _isLoading) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadOfflineData(
    ScannerLocalStorage scannerLocalStorage,
    OfflineDatabaseHelper dbHelper,
  ) async {
    try {
      final rawOffline = scannerLocalStorage.getOfflineData();
      final totalScanned = await dbHelper.getTotalScannedCount();

      if (rawOffline != null && rawOffline.isNotEmpty) {
        final parsed = jsonDecode(rawOffline) as Map<String, dynamic>;
        final event = parsed['event'] as Map<String, dynamic>?;
        if (event != null && parsed['permission'] != null) {
          final pk = (event['pk'] as num?)?.toInt() ??
                     (event['id'] as num?)?.toInt() ??
                     int.tryParse(event['pk']?.toString() ?? '') ??
                     int.tryParse(event['id']?.toString() ?? '');
          if (pk != null && parsed['permission'] is Map) {
            final permMap = Map<String, dynamic>.from(parsed['permission'] as Map);
            _eventPermissions[pk] = permMap;
            _parsedSectionsCache[pk] = _parseSections(permMap);
          }
        }

        setState(() {
          _totalEvents = event != null ? 1 : 0;
          _totalScannedCount = totalScanned;
          _eventList = event != null ? [event] : [];
          _isLoading = false;
        });
      } else {
        setState(() {
          _totalEvents = 0;
          _totalScannedCount = totalScanned;
          _eventList = [];
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[HomeScreen] ❌ Error loading offline dashboard: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadOnlineData(
    ScannerLocalStorage scannerLocalStorage,
    OfflineDatabaseHelper dbHelper,
  ) async {
    try {
      final apiClient = context.read<ApiClient>();
      final res = await apiClient.dio.get('organizer/dashboard');

      if (res.statusCode == 200 && res.data != null) {
        final data = res.data is Map<String, dynamic>
            ? res.data as Map<String, dynamic>
            : jsonDecode(res.data.toString()) as Map<String, dynamic>;

        final totalEvt = (data['total_event'] as num?)?.toInt() ?? 0;
        final totalScanned = (data['total_scanned_count'] as num?)?.toInt() ?? 0;
        final rawEvents = data['event_list'] as List<dynamic>? ?? [];
        final events = rawEvents.whereType<Map<String, dynamic>>().toList();

        // If there's an event, fetch permissions and cache offline
        if (events.isNotEmpty) {
          final firstEvt = events.first;
          final int? evtPk = (firstEvt['pk'] as num?)?.toInt() ??
                             (firstEvt['id'] as num?)?.toInt() ??
                             int.tryParse(firstEvt['pk']?.toString() ?? '') ??
                             int.tryParse(firstEvt['id']?.toString() ?? '');
          if (evtPk != null) {
            try {
              final permRes = await apiClient.dio.get('organizer/event-permission/$evtPk');
              if (permRes.statusCode == 200 && permRes.data != null) {
                final permData = {
                  'event': firstEvt,
                  'permission': permRes.data,
                };
                await scannerLocalStorage.setOfflineData(jsonEncode(permData));
                Map<String, dynamic>? permMap;
                if (permRes.data is Map) {
                  permMap = Map<String, dynamic>.from(permRes.data as Map);
                } else {
                  final parsed = jsonDecode(permRes.data.toString());
                  if (parsed is Map) {
                    permMap = Map<String, dynamic>.from(parsed);
                  }
                }
                if (permMap != null) {
                  _eventPermissions[evtPk] = permMap;
                  _parsedSectionsCache[evtPk] = _parseSections(permMap);
                }
              }
            } catch (permErr) {
              debugPrint('[HomeScreen] ⚠️ Permission fetch error: $permErr');
            }
          }
        }

        setState(() {
          _totalEvents = totalEvt;
          _totalScannedCount = totalScanned;
          _eventList = events;
          _isLoading = false;
        });
      } else if (res.statusCode == 401) {
        String msg = 'You have been logged out (another login detected)';
        if (res.data is Map) {
          final rawMsg = res.data['message'] ?? res.data['detail'];
          if (rawMsg != null) msg = rawMsg.toString();
        }
        _handleSessionExpired(msg);
      } else {
        await _loadOfflineData(scannerLocalStorage, dbHelper);
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        String msg = 'You have been logged out (another login detected)';
        if (e.response?.data is Map) {
          final rawMsg = e.response?.data['message'] ?? e.response?.data['detail'];
          if (rawMsg != null) msg = rawMsg.toString();
        }
        _handleSessionExpired(msg);
        return;
      }
      debugPrint('[HomeScreen] ⚠️ Online fetch failed, falling back to offline: $e');
      await _loadOfflineData(scannerLocalStorage, dbHelper);
    } catch (e) {
      debugPrint('[HomeScreen] ⚠️ Online fetch failed, falling back to offline: $e');
      await _loadOfflineData(scannerLocalStorage, dbHelper);
    }
  }

  Future<void> _fetchPermissionsForEvent(int eventPk) async {
    if (_eventPermissions.containsKey(eventPk) || _loadingPermissions.contains(eventPk)) {
      return;
    }

    if (mounted) {
      setState(() {
        _loadingPermissions.add(eventPk);
      });
    } else {
      _loadingPermissions.add(eventPk);
    }

    // 1. Check local offline cache first for instant fallback
    final scannerLocalStorage = context.read<ScannerLocalStorage>();
    final rawOffline = scannerLocalStorage.getOfflineData();
    if (rawOffline != null && rawOffline.isNotEmpty) {
      try {
        final parsed = jsonDecode(rawOffline) as Map<String, dynamic>;
        final event = parsed['event'] as Map<String, dynamic>?;
        final cachedPk = (event?['pk'] as num?)?.toInt() ??
                         (event?['id'] as num?)?.toInt() ??
                         int.tryParse(event?['pk']?.toString() ?? '');
        if ((cachedPk == eventPk || _eventList.length == 1) && parsed['permission'] is Map) {
          final cachedPerm = Map<String, dynamic>.from(parsed['permission'] as Map);
          if (mounted) {
            setState(() {
              _eventPermissions[eventPk] = cachedPerm;
              _parsedSectionsCache[eventPk] = _parseSections(cachedPerm);
            });
          }
        }
      } catch (_) {}
    }

    // 2. If online, fetch latest permission from server
    if (!_isOffline) {
      try {
        final apiClient = context.read<ApiClient>();
        final res = await apiClient.dio.get('organizer/event-permission/$eventPk');
        if (res.statusCode == 200 && res.data != null) {
          final Map<String, dynamic> perm = res.data is Map
              ? Map<String, dynamic>.from(res.data as Map)
              : Map<String, dynamic>.from(jsonDecode(res.data.toString()) as Map);
          if (mounted) {
            setState(() {
              _eventPermissions[eventPk] = perm;
              _parsedSectionsCache[eventPk] = _parseSections(perm);
            });
          }
        }
      } catch (e) {
        debugPrint('[HomeScreen] ⚠️ Error loading permissions for event $eventPk: $e');
      }
    }

    if (mounted) {
      setState(() {
        _loadingPermissions.remove(eventPk);
      });
    } else {
      _loadingPermissions.remove(eventPk);
    }
  }

  void _handleSessionExpired(String reason) {
    debugPrint('[HomeScreen] 🚨 Session expired: $reason');
    if (!mounted) return;
    context.read<AuthBloc>().add(LogoutRequested(reason: reason));
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void _handleLogout() {
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppTheme.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Log Out',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Are you sure you want to log out of EventXPro?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              context.read<AuthBloc>().add(const LogoutRequested());
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
            child: const Text(
              'Log Out',
              style: TextStyle(
                color: AppTheme.eventxproDanger,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleManualRefresh({bool silent = true}) async {
    try {
      context.read<GateCountService>().clearCache();
    } catch (_) {}
    setState(() {
      _serverRefreshTrigger++;
    });
    await _loadDashboardData(forceRefresh: true, silent: silent);
  }

  void _launchScanner({
    required String punchType,
    required int gateId,
    required int eventId,
    String? gateName,
    String? eventName,
    String section = 'entrances',
    String? sectionLocation,
  }) {
    // Reset session counter so we know how many scans happen during this scanner session
    try {
      context.read<GateCountService>().resetSessionScans();
    } catch (_) {}

    context.read<ScannerBloc>().add(
          ScannerConfigChanged(
            scanType: punchType,
            gateId: gateId,
            eventId: eventId,
            section: section,
            sectionLocation: sectionLocation,
          ),
        );

    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (_) => KioskScannerScreen(
          zebraAdapter: widget.zebraAdapter,
          simulatorAdapter: widget.simulatorAdapter,
          initialPunchType: punchType,
          initialGateId: gateId,
          initialEventId: eventId,
          gateName: gateName,
          eventName: eventName,
          section: section,
          sectionLocation: sectionLocation,
        ),
      ),
    )
        .then((_) async {
      if (!mounted) return;

      // Option A: ZERO network calls upon return from scanner!
      // 1. Update Scanned User metric locally from in-memory session or SQLite WAL
      try {
        final service = context.read<GateCountService>();
        final newScans = service.sessionAcceptedScans;
        if (newScans > 0) {
          setState(() {
            _totalScannedCount += newScans;
          });
        } else {
          final dbHelper = context.read<OfflineDatabaseHelper>();
          final totalScanned = await dbHelper.getTotalScannedCount();
          if (mounted && totalScanned > 0 && totalScanned > _totalScannedCount) {
            setState(() {
              _totalScannedCount = totalScanned;
            });
          }
        }
      } catch (_) {}

      // 2. Trigger local-only cache sync for punch cards (0 network requests)
      setState(() {
        _countRefreshTrigger++;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.eventxproBg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1B2335),
              AppTheme.eventxproBg,
              Color(0xFF10141D),
            ],
            stops: [0.0, 0.45, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildTopBar(),
              Expanded(
                child: RefreshIndicator(
                  color: AppTheme.eventxproAccent,
                  backgroundColor: AppTheme.surfaceElevated,
                  onRefresh: () => _handleManualRefresh(silent: true),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Welcome & Organiser Greeting Header
                        _buildWelcomeHeader(),
                        const SizedBox(height: 16),

                        // ── 1. Top Metrics Count Cards ────────────
                        _buildCountCardsRow(),
                        const SizedBox(height: 16),

                        if (_isOffline) ...[
                          _buildOfflineSessionBanner(),
                          const SizedBox(height: 16),
                        ],

                        // ── 2. Events Section Header ──────────────
                        _buildEventsSectionHeader(),
                        const SizedBox(height: 12),

                        // ── 3. Events List / Know More ────────────
                        _buildEventsSection(),
                        const SizedBox(height: 36),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Welcome & Organiser Header ───────────────────────────────────
  Widget _buildWelcomeHeader() {
    final name = _userProfile?.name;
    final displayName = (name != null && name.trim().isNotEmpty)
        ? name.trim()
        : 'Organiser Portal';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: AppTheme.brandGradientStart,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'EVENTXPRO ORGANISER',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
                width: 1,
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.shield_rounded,
                  size: 13,
                  color: AppTheme.brandGradientStart,
                ),
                SizedBox(width: 5),
                Text(
                  'Gate Pass',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Top Header / App Bar ─────────────────────────────────────────
  Widget _buildTopBar() {
    final dev = _deviceInfo;
    final hasStatusBadges = _isOffline || (dev != null && dev.isHardwareScannerCapable);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF131722).withValues(alpha: 0.95),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // Logo
              Image.asset(
                'assets/images/logo.png',
                height: 32,
                fit: BoxFit.contain,
              ),
              const Spacer(),

              // Refresh Action
              _buildTopBarActionButton(
                tooltip: 'Refresh Dashboard',
                onTap: _isLoading ? null : () => _handleManualRefresh(silent: false),
                icon: _isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(AppTheme.eventxproAccent),
                        ),
                      )
                    : const Icon(Icons.refresh_rounded, color: Colors.white, size: 19),
              ),
              const SizedBox(width: 8),

              // Settings Action
              _buildTopBarActionButton(
                tooltip: 'Settings',
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                  _loadDashboardData(forceRefresh: false, silent: true);
                },
                icon: const Icon(Icons.settings_outlined, color: Colors.white, size: 19),
              ),
              const SizedBox(width: 8),

              // Logout Action
              _buildTopBarActionButton(
                tooltip: 'Log Out',
                onTap: _handleLogout,
                bgTint: AppTheme.eventxproDanger.withValues(alpha: 0.12),
                borderTint: AppTheme.eventxproDanger.withValues(alpha: 0.3),
                icon: const Icon(Icons.logout_rounded, color: AppTheme.eventxproDanger, size: 18),
              ),
            ],
          ),

          // Sub-row for Status Badges (Hardware Device & Offline Mode)
          if (hasStatusBadges) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (dev != null && dev.isHardwareScannerCapable)
                  InkWell(
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SettingsScreen()),
                      );
                      _loadDashboardData(forceRefresh: false, silent: true);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: dev.isHoneywell
                            ? const Color(0xFFD32F2F).withValues(alpha: 0.16)
                            : const Color(0xFF0288D1).withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: dev.isHoneywell
                              ? const Color(0xFFEF5350).withValues(alpha: 0.5)
                              : const Color(0xFF29B6F6).withValues(alpha: 0.5),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: dev.isHoneywell ? const Color(0xFFFF8A80) : const Color(0xFF81D4FA),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.qr_code_scanner_rounded,
                            size: 13,
                            color: dev.isHoneywell
                                ? const Color(0xFFFF8A80)
                                : const Color(0xFF81D4FA),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            dev.displayName,
                            style: TextStyle(
                              color: dev.isHoneywell
                                  ? const Color(0xFFFF8A80)
                                  : const Color(0xFF81D4FA),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                const Spacer(),

                // Pulsing Offline Mode Badge (Matching RN Background.jsx)
                if (_isOffline)
                  GestureDetector(
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const OfflineSessionsScreen()),
                      );
                      _loadDashboardData(forceRefresh: false, silent: true);
                    },
                    child: FadeTransition(
                      opacity: _blinkAnimation,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF3B30),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFFF3B30).withValues(alpha: 0.5),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.wifi_off_rounded, size: 12, color: Colors.white),
                            SizedBox(width: 5),
                            Text(
                              'Offline Mode',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else if (dev != null && dev.isHardwareScannerCapable)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E676).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF00E676).withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: Color(0xFF00E676),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        const Text(
                          'Online Sync',
                          style: TextStyle(
                            color: Color(0xFF00E676),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTopBarActionButton({
    required Widget icon,
    required String tooltip,
    required VoidCallback? onTap,
    Color? bgTint,
    Color? borderTint,
  }) {
    return Material(
      color: Colors.transparent,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Ink(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: bgTint ?? Colors.white.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: borderTint ?? Colors.white.withValues(alpha: 0.12),
                width: 1,
              ),
            ),
            child: Center(child: icon),
          ),
        ),
      ),
    );
  }

  // ── Metrics Count Cards ──────────────────────────────────────────
  Widget _buildCountCardsRow() {
    return Row(
      children: [
        // Total Events Card
        Expanded(
          child: _buildMetricCard(
            title: 'TOTAL EVENTS',
            count: _totalEvents,
            icon: Icons.calendar_month_rounded,
            iconColor: const Color(0xFFFDBE10),
            accentColor: const Color(0xFFFDBE10),
            subtitle: 'Assigned to you',
            tagLabel: 'ACTIVE',
          ),
        ),
        const SizedBox(width: 14),

        // Scanned Users Card (tappable to view offline encrypted codes)
        Expanded(
          child: _buildMetricCard(
            title: 'SCANNED USERS',
            count: _totalScannedCount,
            icon: Icons.qr_code_scanner_rounded,
            iconColor: AppTheme.brandGradientStart,
            accentColor: AppTheme.brandGradientStart,
            subtitle: 'Tap to view records',
            tagLabel: 'LOGS',
            isClickable: true,
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const OfflineSessionsScreen()),
              );
              _loadDashboardData(forceRefresh: false, silent: true);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildOfflineSessionBanner() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const OfflineSessionsScreen()),
          );
          _loadDashboardData(forceRefresh: false, silent: true);
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF2C1622), Color(0xFF1C2234)],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppTheme.brandGradientStart.withValues(alpha: 0.4),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.brandGradientStart.withValues(alpha: 0.12),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.brandGradientStart.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.brandGradientStart.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: const Icon(Icons.cloud_off_rounded, color: AppTheme.brandGradientStart, size: 22),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Offline Session Active',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Tap to view offline logs & sync records',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Manage',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(width: 3),
                    Icon(Icons.arrow_forward_ios_rounded, color: Colors.white70, size: 10),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required int count,
    required IconData icon,
    required Color iconColor,
    required Color accentColor,
    String? subtitle,
    String? tagLabel,
    bool isClickable = false,
    VoidCallback? onTap,
  }) {
    final card = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF222B3D),
            Color(0xFF161C27),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top row: Icon badge + tag
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: iconColor.withValues(alpha: 0.35),
                    width: 1,
                  ),
                ),
                child: Center(
                  child: Icon(icon, size: 20, color: iconColor),
                ),
              ),
              if (tagLabel != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: isClickable
                        ? accentColor.withValues(alpha: 0.15)
                        : Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isClickable
                          ? accentColor.withValues(alpha: 0.35)
                          : Colors.white.withValues(alpha: 0.1),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        tagLabel,
                        style: TextStyle(
                          color: isClickable ? accentColor : Colors.white70,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                      if (isClickable) ...[
                        const SizedBox(width: 3),
                        Icon(Icons.arrow_forward_ios_rounded, size: 8, color: accentColor),
                      ],
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),

          // Count Number
          Text(
            count.toString(),
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w900,
              color: accentColor,
              height: 1.1,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),

          // Title
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
          ],
        ],
      ),
    );

    if (isClickable && onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          borderRadius: BorderRadius.circular(16),
          child: card,
        ),
      );
    }

    return card;
  }

  // ── Events Section Header ────────────────────────────────────────
  Widget _buildEventsSectionHeader() {
    return Row(
      children: [
        Container(
          width: 3.5,
          height: 15,
          decoration: BoxDecoration(
            gradient: AppTheme.brandGradient,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        const Text(
          'ASSIGNED EVENTS',
          style: TextStyle(
            color: Colors.white,
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
        const Spacer(),
        if (_eventList.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Text(
              '${_eventList.length} Active',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  // ── Events Section & Know More Box ───────────────────────────────
  Widget _buildEventsSection() {
    if (_isLoading) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF20283A), Color(0xFF161C28)],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 30,
                height: 30,
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(AppTheme.eventxproAccent),
                  strokeWidth: 2.8,
                ),
              ),
              SizedBox(height: 14),
              Text(
                'Loading Events & Sessions...',
                style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      );
    }

    if (_eventList.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF20283A), Color(0xFF161C28)],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: const Icon(
                Icons.event_busy_rounded,
                size: 28,
                color: Colors.white38,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'No Events Available',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _isOffline
                  ? 'Connect to internet to download offline event sessions.'
                  : 'No active events assigned to your organiser profile.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, fontSize: 12.5, height: 1.3),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: AppTheme.brandGradientStart.withValues(alpha: 0.6)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              ),
              onPressed: () => _handleManualRefresh(silent: false),
              icon: const Icon(Icons.refresh_rounded, size: 15),
              label: const Text('Refresh Events', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _eventList.map((eventData) => _buildEventCard(eventData)).toList(),
    );
  }

  Widget _buildEventCard(Map<String, dynamic> data) {
    final int eventPk = (data['pk'] as num?)?.toInt() ??
                        (data['id'] as num?)?.toInt() ??
                        int.tryParse(data['pk']?.toString() ?? '') ??
                        1;
    final String eventName = data['publish_event_name']?.toString() ?? 'Event';
    final String rawDesc = data['description']?.toString() ?? '';
    final String cleanDesc = _stripHtmlTags(rawDesc);
    final String startDate = _formatDate(data['publish_start_dt']);
    final String endDate = _formatDate(data['publish_end_dt']);
    final bool isExpanded = _expandedEventPk == eventPk;

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF20283A),
            Color(0xFF161C28),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isExpanded
              ? AppTheme.brandGradientStart.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.12),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.32),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Event Info Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Meta: Event ID Badge & Date Tag
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.brandGradientStart.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: AppTheme.brandGradientStart.withValues(alpha: 0.35),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 5,
                            height: 5,
                            decoration: const BoxDecoration(
                              color: AppTheme.brandGradientStart,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'EVENT #$eventPk',
                            style: const TextStyle(
                              color: AppTheme.brandGradientStart,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    if (startDate.isNotEmpty || endDate.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.calendar_today_rounded, size: 10, color: Colors.white60),
                            const SizedBox(width: 4),
                            Text(
                              startDate.isNotEmpty && endDate.isNotEmpty
                                  ? '$startDate to $endDate'
                                  : (startDate.isNotEmpty ? startDate : endDate),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),

                // Event Title
                Text(
                  eventName.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                    height: 1.25,
                  ),
                ),

                if (cleanDesc.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    cleanDesc,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                  ),
                ],
                const SizedBox(height: 16),

                // "KNOW MORE / HIDE SESSIONS" Button Row
                Row(
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        setState(() {
                          if (isExpanded) {
                            _expandedEventPk = null;
                          } else {
                            _expandedEventPk = eventPk;
                            if (!_eventPermissions.containsKey(eventPk)) {
                              _fetchPermissionsForEvent(eventPk);
                            }
                          }
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                        decoration: BoxDecoration(
                          gradient: AppTheme.brandGradient,
                          borderRadius: BorderRadius.circular(25),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.brandGradientStart.withValues(alpha: isExpanded ? 0.5 : 0.3),
                              blurRadius: isExpanded ? 10 : 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              isExpanded ? 'HIDE SESSIONS' : 'KNOW MORE',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(width: 6),
                            AnimatedRotation(
                              turns: isExpanded ? 0.5 : 0.0,
                              duration: const Duration(milliseconds: 200),
                              child: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: Colors.white,
                                size: 17,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (!isExpanded)
                      Text(
                        'Tap to access gates',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // ── KNOW MORE BOX (Sessions & Entrances with Check-in / Check-out) ──
          if (isExpanded) ...[
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFF121622),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(15)),
                border: Border(
                  top: BorderSide(
                    color: Colors.white.withValues(alpha: 0.1),
                    width: 1,
                  ),
                ),
              ),
              padding: const EdgeInsets.all(16),
              child: _buildKnowMoreBox(eventPk, eventName),
            ),
          ],
        ],
      ),
    );
  }

  /// Know More Box for Check-In and Check-Out matching React Native EventXPro:
  /// - OfflineEventDetails.jsx / EventDetails.jsx
  /// - Supports 4 session categories: Entrances, Halls, Agendas, and Sessions
  /// Parse permissions into structured sections once, caching results for instant lookups
  _ParsedEventSections _parseSections(Map<String, dynamic>? permission) {
    if (permission == null) {
      final defaultGate = context.read<ScannerLocalStorage>().getGateId();
      return _ParsedEventSections(
        entranceList: [
          {
            'entrance_id': defaultGate,
            'entrance_name': 'Main Entrance',
            'location': 'Gate #$defaultGate',
            'entrance_in_access': true,
            'entrance_out_access': true,
          }
        ],
        hallList: const [],
        agendaList: const [],
        sessionList: const [],
      );
    }

    // 1. Entrances
    List<Map<String, dynamic>> entranceList = [];
    final entrancePerm = permission['entrance_permission'] as Map<String, dynamic>?;
    if (entrancePerm != null && entrancePerm['access'] != false) {
      final rawList = entrancePerm['entrance_list'] as List<dynamic>? ?? [];
      entranceList = rawList.whereType<Map<String, dynamic>>().toList();
    }
    if (entranceList.isEmpty && permission['entrance'] is Map) {
      final ent = permission['entrance'] as Map<String, dynamic>;
      if (ent['access'] == true) {
        final gateId = context.read<ScannerLocalStorage>().getGateId();
        entranceList = [
          {
            'entrance_id': gateId,
            'entrance_name': 'Main Entrance',
            'location': 'Gate #$gateId',
            'entrance_in_access': ent['checkin'] != false,
            'entrance_out_access': ent['checkout'] != false,
          }
        ];
      }
    }

    // 2. Halls
    List<Map<String, dynamic>> hallList = [];
    final hallPerm = permission['hall_permission'] as Map<String, dynamic>?;
    if (hallPerm != null && hallPerm['access'] == true) {
      final rawList = hallPerm['hall_list'] as List<dynamic>? ?? [];
      hallList = rawList.whereType<Map<String, dynamic>>().toList();
    }

    // 3. Agendas
    List<Map<String, dynamic>> agendaList = [];
    final agendaPerm = permission['agenda_permission'] as Map<String, dynamic>?;
    if (agendaPerm != null && agendaPerm['access'] == true) {
      final rawList = agendaPerm['agenda_list'] as List<dynamic>? ?? [];
      agendaList = rawList.whereType<Map<String, dynamic>>().toList();
    }

    // 4. Sessions
    List<Map<String, dynamic>> sessionList = [];
    final sessionPerm = permission['sessiontype_permission'] as Map<String, dynamic>?;
    if (sessionPerm != null && sessionPerm['access'] == true) {
      final rawList = sessionPerm['sessiontype_list'] as List<dynamic>? ?? [];
      sessionList = rawList.whereType<Map<String, dynamic>>().toList();
    }

    if (entranceList.isEmpty && hallList.isEmpty && agendaList.isEmpty && sessionList.isEmpty) {
      final gateId = context.read<ScannerLocalStorage>().getGateId();
      entranceList = [
        {
          'entrance_id': gateId,
          'entrance_name': 'Main Entrance',
          'location': 'Gate #$gateId',
          'entrance_in_access': true,
          'entrance_out_access': true,
        }
      ];
    }

    return _ParsedEventSections(
      entranceList: entranceList,
      hallList: hallList,
      agendaList: agendaList,
      sessionList: sessionList,
    );
  }

  /// Know More Box for Check-In and Check-Out matching React Native EventXPro:
  /// - OfflineEventDetails.jsx / EventDetails.jsx
  /// - Supports 4 session categories: Entrances, Halls, Agendas, and Sessions
  Widget _buildKnowMoreBox(int eventId, String eventName) {
    // 1. Resolve sections directly from in-memory parsed cache (O(1) instant)
    _ParsedEventSections? sections = _parsedSectionsCache[eventId];
    if (sections == null && _eventPermissions.containsKey(eventId)) {
      sections = _parseSections(_eventPermissions[eventId]);
      _parsedSectionsCache[eventId] = sections;
    }

    // Fallback: check offline storage if not cached yet
    if (sections == null) {
      final scannerLocalStorage = context.read<ScannerLocalStorage>();
      final rawOffline = scannerLocalStorage.getOfflineData();
      if (rawOffline != null && rawOffline.isNotEmpty) {
        try {
          final parsed = jsonDecode(rawOffline) as Map<String, dynamic>;
          final event = parsed['event'] as Map<String, dynamic>?;
          final cachedPk = (event?['pk'] as num?)?.toInt() ??
                           (event?['id'] as num?)?.toInt() ??
                           int.tryParse(event?['pk']?.toString() ?? '');
          if ((cachedPk == eventId || _eventList.length == 1) && parsed['permission'] is Map) {
            final perm = Map<String, dynamic>.from(parsed['permission'] as Map);
            _eventPermissions[eventId] = perm;
            sections = _parseSections(perm);
            _parsedSectionsCache[eventId] = sections;
          }
        } catch (_) {}
      }
    }

    // If still fetching permissions over network and not yet in cache, show clean inline spinner
    if (sections == null && _loadingPermissions.contains(eventId)) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        alignment: Alignment.center,
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.eventxproAccent),
              ),
            ),
            SizedBox(height: 10),
            Text(
              'Loading sessions & gates...',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      );
    }

    sections ??= _parseSections(null);

    final entranceList = sections.entranceList;
    final hallList = sections.hallList;
    final agendaList = sections.agendaList;
    final sessionList = sections.sessionList;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── 1. ENTRANCES & GATES ──────────────────────────────
        if (entranceList.isNotEmpty) ...[
          _buildCategoryHeader(
            title: 'ENTRANCES & GATES',
            icon: Icons.meeting_room_rounded,
            count: entranceList.length,
            accentColor: const Color(0xFF00E5FF),
          ),
          const SizedBox(height: 10),
          ...entranceList.map((item) {
            final int entranceId = (item['entrance_id'] as num?)?.toInt() ?? 1;
            final String title = item['entrance_name']?.toString() ?? 'Entrance';
            final String? loc = item['location']?.toString();
            final String displayTitle = loc != null && loc.isNotEmpty ? '$title - $loc' : title;
            final bool inAccess = item['entrance_in_access'] != false;
            final bool outAccess = item['entrance_out_access'] != false;

            return SessionPunchCard(
              eventId: eventId,
              eventName: eventName,
              sessionId: entranceId,
              title: displayTitle,
              section: 'entrances',
              sectionLocation: loc ?? title,
              hasInAccess: inAccess,
              hasOutAccess: outAccess,
              refreshTrigger: _countRefreshTrigger,
              serverRefreshTrigger: _serverRefreshTrigger,
              onCheckIn: () => _launchScanner(
                punchType: 'check_in',
                gateId: entranceId,
                eventId: eventId,
                gateName: displayTitle,
                eventName: eventName,
                section: 'entrances',
                sectionLocation: loc ?? title,
              ),
              onCheckOut: () => _launchScanner(
                punchType: 'check_out',
                gateId: entranceId,
                eventId: eventId,
                gateName: displayTitle,
                eventName: eventName,
                section: 'entrances',
                sectionLocation: loc ?? title,
              ),
            );
          }),
          if (hallList.isNotEmpty || agendaList.isNotEmpty || sessionList.isNotEmpty)
            const SizedBox(height: 16),
        ],

        // ── 2. HALLS (Matching OfflineEventDetails.jsx & EventDetails.jsx) ──
        if (hallList.isNotEmpty) ...[
          _buildCategoryHeader(
            title: 'HALLS',
            icon: Icons.domain_rounded,
            count: hallList.length,
            accentColor: const Color(0xFF6366F1),
          ),
          const SizedBox(height: 10),
          ...hallList.map((item) {
            final int hallId = (item['hall_id'] as num?)?.toInt() ?? 0;
            final String title = item['hall_name']?.toString() ?? 'Hall';
            final bool inAccess = item['hall_in_access'] == true;
            final bool outAccess = item['hall_out_access'] == true;

            return SessionPunchCard(
              eventId: eventId,
              eventName: eventName,
              sessionId: hallId,
              title: title,
              section: 'hall',
              sectionLocation: title,
              hasInAccess: inAccess,
              hasOutAccess: outAccess,
              refreshTrigger: _countRefreshTrigger,
              serverRefreshTrigger: _serverRefreshTrigger,
              onCheckIn: () => _launchScanner(
                punchType: 'check_in',
                gateId: hallId,
                eventId: eventId,
                gateName: title,
                eventName: eventName,
                section: 'hall',
                sectionLocation: title,
              ),
              onCheckOut: () => _launchScanner(
                punchType: 'check_out',
                gateId: hallId,
                eventId: eventId,
                gateName: title,
                eventName: eventName,
                section: 'hall',
                sectionLocation: title,
              ),
            );
          }),
          if (agendaList.isNotEmpty || sessionList.isNotEmpty)
            const SizedBox(height: 16),
        ],

        // ── 3. AGENDAS (Matching OfflineAgendaInOutCard.jsx & AgendaInOutCard.jsx) ──
        if (agendaList.isNotEmpty) ...[
          _buildCategoryHeader(
            title: 'AGENDAS',
            icon: Icons.event_note_rounded,
            count: agendaList.length,
            accentColor: const Color(0xFFA855F7),
          ),
          const SizedBox(height: 10),
          ...agendaList.map((item) {
            final int agendaId = (item['agenda_id'] as num?)?.toInt() ?? 0;
            final String rawName = item['agendaname']?.toString() ?? 'Agenda';
            final dynamic day = item['day'];
            final String title = day != null ? 'Day-$day $rawName' : rawName;
            final String? date = item['agenda_dt']?.toString();
            final String? start = item['start_tm']?.toString();
            final String? end = item['end_tm']?.toString();
            final String? agendaType = item['agendatype']?.toString();
            final bool inAccess = item['agenda_in_access'] == true;
            final bool outAccess = item['agenda_out_access'] == true;

            return AgendaPunchCard(
              eventId: eventId,
              eventName: eventName,
              agendaId: agendaId,
              title: title,
              date: date,
              start: start,
              end: end,
              agendaType: agendaType,
              hasInAccess: inAccess,
              hasOutAccess: outAccess,
              refreshTrigger: _countRefreshTrigger,
              serverRefreshTrigger: _serverRefreshTrigger,
              onCheckIn: () => _launchScanner(
                punchType: 'check_in',
                gateId: agendaId,
                eventId: eventId,
                gateName: title,
                eventName: eventName,
                section: 'agenda',
                sectionLocation: title,
              ),
              onCheckOut: () => _launchScanner(
                punchType: 'check_out',
                gateId: agendaId,
                eventId: eventId,
                gateName: title,
                eventName: eventName,
                section: 'agenda',
                sectionLocation: title,
              ),
            );
          }),
          if (sessionList.isNotEmpty)
            const SizedBox(height: 16),
        ],

        // ── 4. SESSIONS (Matching OfflineSessionInOutCard.jsx & SessionInOutCard.jsx) ──
        if (sessionList.isNotEmpty) ...[
          _buildCategoryHeader(
            title: 'SESSIONS',
            icon: Icons.co_present_rounded,
            count: sessionList.length,
            accentColor: const Color(0xFFFF9800),
          ),
          const SizedBox(height: 10),
          ...sessionList.map((item) {
            final int sessId = ((item['session_type_id'] ?? item['sessiontype_id']) as num?)?.toInt() ?? 0;
            final String title = (item['sessiontype_name'] ?? item['session_type_name'])?.toString() ?? 'Session';
            final bool inAccess = item['sessiontype_in_access'] == true;
            final bool outAccess = item['sessiontype_out_access'] == true;

            return SessionPunchCard(
              eventId: eventId,
              eventName: eventName,
              sessionId: sessId,
              title: title,
              section: 'session',
              sectionLocation: title,
              hasInAccess: inAccess,
              hasOutAccess: outAccess,
              refreshTrigger: _countRefreshTrigger,
              serverRefreshTrigger: _serverRefreshTrigger,
              onCheckIn: () => _launchScanner(
                punchType: 'check_in',
                gateId: sessId,
                eventId: eventId,
                gateName: title,
                eventName: eventName,
                section: 'session',
                sectionLocation: title,
              ),
              onCheckOut: () => _launchScanner(
                punchType: 'check_out',
                gateId: sessId,
                eventId: eventId,
                gateName: title,
                eventName: eventName,
                section: 'session',
                sectionLocation: title,
              ),
            );
          }),
        ],
      ],
    );
  }

  /// Section Header matching React Native EveSectionWrapper
  Widget _buildCategoryHeader({
    required String title,
    required IconData icon,
    required int count,
    Color accentColor = AppTheme.eventxproAccent,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.12),
            width: 1.2,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(
                color: accentColor.withValues(alpha: 0.35),
                width: 1,
              ),
            ),
            child: Center(
              child: Icon(icon, size: 14, color: accentColor),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
              letterSpacing: 0.6,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: accentColor.withValues(alpha: 0.25)),
            ),
            child: Text(
              '$count Available',
              style: TextStyle(
                color: accentColor,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
