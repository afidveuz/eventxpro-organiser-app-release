import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/network/api_client.dart';
import '../../../core/services/app_update_service.dart';
import '../../../core/services/device_detection_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/adapters/simulated_hardware_adapter.dart';
import '../../../data/adapters/zebra_datawedge_adapter.dart';
import '../../../data/datasources/offline_database_helper.dart';
import '../../../data/datasources/scanner_local_storage.dart';
import '../../bloc/auth/auth_bloc.dart';
import '../../bloc/auth/auth_event.dart';
import '../../bloc/scanner_bloc.dart';
import '../../bloc/scanner_event.dart';
import '../auth/login_screen.dart';
import '../kiosk_scanner_screen.dart';
import '../offline/offline_sessions_screen.dart';
import '../settings_screen.dart';

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
  final Set<int> _loadingPermissions = {};
  DeviceInfoResult? _deviceInfo;

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

    // Check for app updates on home screen load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        AppUpdateService().checkAndPromptUpdate(context);
      }
    });
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
        if (event != null && parsed['permission'] is Map<String, dynamic>) {
          final pk = (event['pk'] ?? event['id']) as int?;
          if (pk != null) {
            _eventPermissions[pk] = parsed['permission'] as Map<String, dynamic>;
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
          final evtPk = firstEvt['pk'] ?? firstEvt['id'];
          if (evtPk != null) {
            try {
              final permRes = await apiClient.dio.get('organizer/event-permission/$evtPk');
              if (permRes.statusCode == 200 && permRes.data != null) {
                final permData = {
                  'event': firstEvt,
                  'permission': permRes.data,
                };
                await scannerLocalStorage.setOfflineData(jsonEncode(permData));
                if (permRes.data is Map<String, dynamic>) {
                  _eventPermissions[evtPk as int] = permRes.data as Map<String, dynamic>;
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

    _loadingPermissions.add(eventPk);

    // 1. Check local offline cache
    final scannerLocalStorage = context.read<ScannerLocalStorage>();
    final rawOffline = scannerLocalStorage.getOfflineData();
    if (rawOffline != null && rawOffline.isNotEmpty) {
      try {
        final parsed = jsonDecode(rawOffline) as Map<String, dynamic>;
        final event = parsed['event'] as Map<String, dynamic>?;
        final cachedPk = event?['pk'] ?? event?['id'];
        if (cachedPk == eventPk && parsed['permission'] is Map<String, dynamic>) {
          if (mounted) {
            setState(() {
              _eventPermissions[eventPk] = parsed['permission'] as Map<String, dynamic>;
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
          final perm = res.data is Map<String, dynamic>
              ? res.data as Map<String, dynamic>
              : jsonDecode(res.data.toString()) as Map<String, dynamic>;
          if (mounted) {
            setState(() {
              _eventPermissions[eventPk] = perm;
            });
          }
        }
      } catch (e) {
        debugPrint('[HomeScreen] ⚠️ Error loading permissions for event $eventPk: $e');
      }
    }

    _loadingPermissions.remove(eventPk);
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

  void _launchScanner({
    required String punchType,
    required int gateId,
    required int eventId,
    String? gateName,
    String? eventName,
    String section = 'entrances',
    String? sectionLocation,
  }) {
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
        .then((_) {
      // Re-fetch dashboard count upon returning from scanning session
      // Throttled (30s) and silent to prevent screen flicker and duplicate network requests
      _loadDashboardData(forceRefresh: false, silent: true);
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
              AppTheme.eventxproNavy,
              AppTheme.eventxproBg,
            ],
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
                  onRefresh: () => _loadDashboardData(forceRefresh: true, silent: true),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ── 1. Top Metrics Count Cards ────────────
                        _buildCountCardsRow(),
                        const SizedBox(height: 14),

                        if (_isOffline) ...[
                          _buildOfflineSessionBanner(),
                          const SizedBox(height: 14),
                        ],

                        // ── 2. Events List / Know More ────────────
                        _buildEventsSection(),
                        const SizedBox(height: 32),
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

  // ── Top Header / App Bar ─────────────────────────────────────────
  Widget _buildTopBar() {
    final dev = _deviceInfo;
    final hasStatusBadges = _isOffline || (dev != null && dev.isHardwareScannerCapable);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.eventxproBg.withValues(alpha: 0.8),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // Logo & Branding
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppTheme.eventxproAccent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.qr_code_2_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'EVENTXPRO',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                      Text(
                        'ORGANISER',
                        style: TextStyle(
                          color: AppTheme.eventxproAccent.withValues(alpha: 0.9),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const Spacer(),

              // Refresh Action
              IconButton(
                tooltip: 'Refresh',
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                padding: const EdgeInsets.all(6),
                icon: _isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(AppTheme.eventxproAccent),
                        ),
                      )
                    : const Icon(Icons.refresh_rounded, color: Colors.white70, size: 20),
                onPressed: _isLoading
                    ? null
                    : () => _loadDashboardData(forceRefresh: true, silent: false),
              ),

              // Settings Action
              IconButton(
                tooltip: 'Settings',
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                padding: const EdgeInsets.all(6),
                icon: const Icon(Icons.settings_outlined, color: Colors.white70, size: 20),
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                  _loadDashboardData(forceRefresh: false, silent: true);
                },
              ),

              // Logout Action
              IconButton(
                tooltip: 'Log Out',
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                padding: const EdgeInsets.all(6),
                icon: const Icon(Icons.logout_rounded, color: AppTheme.eventxproDanger, size: 20),
                onPressed: _handleLogout,
              ),
            ],
          ),

          // Sub-row for Status Badges (Hardware Device & Offline Mode)
          if (hasStatusBadges) ...[
            const SizedBox(height: 8),
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
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: dev.isHoneywell
                            ? const Color(0xFFD32F2F).withValues(alpha: 0.15)
                            : const Color(0xFF0288D1).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: dev.isHoneywell
                              ? const Color(0xFFEF5350).withValues(alpha: 0.6)
                              : const Color(0xFF29B6F6).withValues(alpha: 0.6),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.qr_code_scanner_rounded,
                            size: 12,
                            color: dev.isHoneywell
                                ? const Color(0xFFFF8A80)
                                : const Color(0xFF81D4FA),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            dev.displayName,
                            style: TextStyle(
                              color: dev.isHoneywell
                                  ? const Color(0xFFFF8A80)
                                  : const Color(0xFF81D4FA),
                              fontSize: 10.5,
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
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF3B30),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFFF3B30).withValues(alpha: 0.5),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.wifi_off_rounded, size: 12, color: Colors.white),
                            SizedBox(width: 4),
                            Text(
                              'Offline Mode',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 10.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── Metrics Count Cards (Matching RN CountCard.jsx) ─────────────
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
          ),
        ),
        const SizedBox(width: 14),

        // Scanned Users Card (tappable to view offline encrypted codes)
        Expanded(
          child: GestureDetector(
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const OfflineSessionsScreen()),
              );
              _loadDashboardData(forceRefresh: false, silent: true);
            },
            child: _buildMetricCard(
              title: 'SCANNED USER',
              count: _totalScannedCount,
              icon: Icons.qr_code_scanner_rounded,
              iconColor: AppTheme.eventxproAccent,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOfflineSessionBanner() {
    return GestureDetector(
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const OfflineSessionsScreen()),
        );
        _loadDashboardData(forceRefresh: false, silent: true);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1B2332),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.eventxproAccent.withValues(alpha: 0.5)),
          boxShadow: [
            BoxShadow(
              color: AppTheme.eventxproAccent.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.eventxproAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.cloud_off_rounded, color: AppTheme.eventxproAccent, size: 20),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Offline Session Active',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Tap to view scanned codes & sync records',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white60, size: 14),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required int count,
    required IconData icon,
    required Color iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      decoration: BoxDecoration(
        color: AppTheme.eventxproCardBg, // Pure white background matching RN CountCard
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 28, color: iconColor),
          ),
          const SizedBox(height: 8),
          Text(
            count.toString(),
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              color: AppTheme.eventxproAccent, // Signature magenta count
              height: 1.1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppTheme.eventxproDarkText,
              letterSpacing: 0.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ── Events Section & Know More Box ───────────────────────────────
  Widget _buildEventsSection() {
    if (_isLoading) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
        child: const Center(
          child: Column(
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.eventxproAccent),
                strokeWidth: 2.5,
              ),
              SizedBox(height: 12),
              Text(
                'Loading Events...',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    if (_eventList.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: AppTheme.eventxproBorder,
            width: 1,
          ),
        ),
        child: Column(
          children: [
            const Icon(
              Icons.event_busy_rounded,
              size: 44,
              color: Colors.white38,
            ),
            const SizedBox(height: 10),
            const Text(
              'No Events Available',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _isOffline
                  ? 'Connect to internet to download offline event sessions.'
                  : 'No active events assigned to your organiser profile.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, fontSize: 12),
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
    final int eventPk = (data['pk'] ?? data['id'] ?? 1) as int;
    final String eventName = data['publish_event_name']?.toString() ?? 'Event';
    final String rawDesc = data['description']?.toString() ?? '';
    final String cleanDesc = _stripHtmlTags(rawDesc);
    final String startDate = _formatDate(data['publish_start_dt']);
    final String endDate = _formatDate(data['publish_end_dt']);
    final bool isExpanded = _expandedEventPk == eventPk;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppTheme.eventxproBorder,
          width: 1.2,
        ),
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
                Text(
                  eventName.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                  ),
                ),
                if (cleanDesc.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    cleanDesc,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 13,
                      height: 1.3,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.calendar_today_rounded,
                      size: 13,
                      color: Colors.white70,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      startDate.isNotEmpty && endDate.isNotEmpty
                          ? '$startDate to $endDate'
                          : 'Dates scheduled',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // "KNOW MORE" Button
                Align(
                  alignment: Alignment.centerLeft,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () {
                        setState(() {
                          if (isExpanded) {
                            _expandedEventPk = null;
                          } else {
                            _expandedEventPk = eventPk;
                            _fetchPermissionsForEvent(eventPk);
                          }
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.eventxproAccent,
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.eventxproAccent.withValues(alpha: 0.4),
                              blurRadius: 6,
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
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                letterSpacing: 0.4,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              isExpanded
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── KNOW MORE BOX (Sessions & Entrances with Check-in / Check-out) ──
          if (isExpanded) ...[
            Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.25),
                border: Border(
                  top: BorderSide(
                    color: Colors.white.withValues(alpha: 0.15),
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
  Widget _buildKnowMoreBox(int eventId, String eventName) {
    final scannerLocalStorage = context.read<ScannerLocalStorage>();

    // 1. Resolve permissions: preferentially from per-event cache, or offline cached data
    Map<String, dynamic>? permission = _eventPermissions[eventId];
    if (permission == null) {
      final rawOffline = scannerLocalStorage.getOfflineData();
      if (rawOffline != null && rawOffline.isNotEmpty) {
        try {
          final parsed = jsonDecode(rawOffline) as Map<String, dynamic>;
          final event = parsed['event'] as Map<String, dynamic>?;
          final cachedPk = event?['pk'] ?? event?['id'];
          if (cachedPk == eventId || _eventList.length == 1) {
            permission = parsed['permission'] as Map<String, dynamic>?;
          }
        } catch (_) {}
      }
    }

    // 2. Parse ENTRANCES (matching React Native entrance_permission / entrance)
    List<Map<String, dynamic>> entranceList = [];
    final entrancePerm = permission?['entrance_permission'] as Map<String, dynamic>?;
    if (entrancePerm != null && entrancePerm['access'] != false) {
      final rawList = entrancePerm['entrance_list'] as List<dynamic>? ?? [];
      entranceList = rawList.whereType<Map<String, dynamic>>().toList();
    }
    // Fallback single entrance permission object (parsedData?.permission?.entrance?.access)
    if (entranceList.isEmpty && permission != null && permission['entrance'] is Map) {
      final ent = permission['entrance'] as Map<String, dynamic>;
      if (ent['access'] == true) {
        entranceList = [
          {
            'entrance_id': scannerLocalStorage.getGateId(),
            'entrance_name': 'Main Entrance',
            'location': 'Gate #${scannerLocalStorage.getGateId()}',
            'entrance_in_access': ent['checkin'] != false,
            'entrance_out_access': ent['checkout'] != false,
          }
        ];
      }
    }

    // 3. Parse HALLS (matching React Native hall_permission.hall_list)
    List<Map<String, dynamic>> hallList = [];
    final hallPerm = permission?['hall_permission'] as Map<String, dynamic>?;
    if (hallPerm != null && hallPerm['access'] == true) {
      final rawList = hallPerm['hall_list'] as List<dynamic>? ?? [];
      hallList = rawList.whereType<Map<String, dynamic>>().toList();
    }

    // 4. Parse AGENDAS (matching React Native agenda_permission.agenda_list)
    List<Map<String, dynamic>> agendaList = [];
    final agendaPerm = permission?['agenda_permission'] as Map<String, dynamic>?;
    if (agendaPerm != null && agendaPerm['access'] == true) {
      final rawList = agendaPerm['agenda_list'] as List<dynamic>? ?? [];
      agendaList = rawList.whereType<Map<String, dynamic>>().toList();
    }

    // 5. Parse SESSIONS (matching React Native sessiontype_permission.sessiontype_list)
    List<Map<String, dynamic>> sessionList = [];
    final sessionPerm = permission?['sessiontype_permission'] as Map<String, dynamic>?;
    if (sessionPerm != null && sessionPerm['access'] == true) {
      final rawList = sessionPerm['sessiontype_list'] as List<dynamic>? ?? [];
      sessionList = rawList.whereType<Map<String, dynamic>>().toList();
    }

    // If completely empty (e.g. offline with zero permissions configured), default to 1 entrance
    final bool allEmpty = entranceList.isEmpty && hallList.isEmpty && agendaList.isEmpty && sessionList.isEmpty;
    if (allEmpty) {
      entranceList = [
        {
          'entrance_id': scannerLocalStorage.getGateId(),
          'entrance_name': 'Main Entrance',
          'location': 'Gate #${scannerLocalStorage.getGateId()}',
          'entrance_in_access': true,
          'entrance_out_access': true,
        }
      ];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── 1. ENTRANCES & GATES ──────────────────────────────
        if (entranceList.isNotEmpty) ...[
          _buildCategoryHeader(
            title: 'ENTRANCES & GATES',
            icon: Icons.meeting_room_rounded,
            count: entranceList.length,
          ),
          const SizedBox(height: 10),
          ...entranceList.map((item) {
            final int entranceId = (item['entrance_id'] as num?)?.toInt() ?? 1;
            final String title = item['entrance_name']?.toString() ?? 'Entrance';
            final String? loc = item['location']?.toString();
            final String displayTitle = loc != null && loc.isNotEmpty ? '$title - $loc' : title;
            final bool inAccess = item['entrance_in_access'] != false;
            final bool outAccess = item['entrance_out_access'] != false;

            return _buildSessionPunchCard(
              eventId: eventId,
              eventName: eventName,
              sessionId: entranceId,
              title: displayTitle,
              section: 'entrances',
              sectionLocation: loc ?? title,
              hasInAccess: inAccess,
              hasOutAccess: outAccess,
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
          ),
          const SizedBox(height: 10),
          ...hallList.map((item) {
            final int hallId = (item['hall_id'] as num?)?.toInt() ?? 0;
            final String title = item['hall_name']?.toString() ?? 'Hall';
            final bool inAccess = item['hall_in_access'] == true;
            final bool outAccess = item['hall_out_access'] == true;

            return _buildSessionPunchCard(
              eventId: eventId,
              eventName: eventName,
              sessionId: hallId,
              title: title,
              section: 'hall',
              sectionLocation: title,
              hasInAccess: inAccess,
              hasOutAccess: outAccess,
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

            return _buildAgendaPunchCard(
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
          ),
          const SizedBox(height: 10),
          ...sessionList.map((item) {
            final int sessId = ((item['session_type_id'] ?? item['sessiontype_id']) as num?)?.toInt() ?? 0;
            final String title = (item['sessiontype_name'] ?? item['session_type_name'])?.toString() ?? 'Session';
            final bool inAccess = item['sessiontype_in_access'] == true;
            final bool outAccess = item['sessiontype_out_access'] == true;

            return _buildSessionPunchCard(
              eventId: eventId,
              eventName: eventName,
              sessionId: sessId,
              title: title,
              section: 'session',
              sectionLocation: title,
              hasInAccess: inAccess,
              hasOutAccess: outAccess,
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
  }) {
    return Container(
      padding: const EdgeInsets.only(bottom: 6),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppTheme.eventxproBorder,
            width: 1.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.eventxproAccent),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 13,
              letterSpacing: 0.8,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count Available',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Exact replica of OfflineEventSection.jsx / OfflineSessionInOutCard.jsx in React Native
  Widget _buildSessionPunchCard({
    required int eventId,
    required String eventName,
    required int sessionId,
    required String title,
    required String section,
    required String sectionLocation,
    required bool hasInAccess,
    required bool hasOutAccess,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: AppTheme.eventxproBorder,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 12),

          // Check-in & Check-out Buttons Row (Matching OfflineEventSection.jsx)
          Row(
            children: [
              // CHECK-IN BUTTON
              if (hasInAccess)
                Expanded(
                  child: _buildPunchButton(
                    label: 'CHECK-IN',
                    badgeColor: AppTheme.eventxproSuccess, // #8DFFBB
                    arrowColor: Colors.black,
                    onTap: () => _launchScanner(
                      punchType: 'check_in',
                      gateId: sessionId,
                      eventId: eventId,
                      gateName: title,
                      eventName: eventName,
                      section: section,
                      sectionLocation: sectionLocation,
                    ),
                  ),
                ),

              if (hasInAccess && hasOutAccess) const SizedBox(width: 10),

              // CHECK-OUT BUTTON
              if (hasOutAccess)
                Expanded(
                  child: _buildPunchButton(
                    label: 'CHECK-OUT',
                    badgeColor: AppTheme.eventxproDanger, // #FF6767
                    arrowColor: Colors.white,
                    onTap: () => _launchScanner(
                      punchType: 'check_out',
                      gateId: sessionId,
                      eventId: eventId,
                      gateName: title,
                      eventName: eventName,
                      section: section,
                      sectionLocation: sectionLocation,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Exact replica of OfflineAgendaInOutCard.jsx in React Native
  Widget _buildAgendaPunchCard({
    required int eventId,
    required String eventName,
    required int agendaId,
    required String title,
    String? date,
    String? start,
    String? end,
    String? agendaType,
    required bool hasInAccess,
    required bool hasOutAccess,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: AppTheme.eventxproBorder,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              if (agendaType != null && agendaType.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.eventxproAccent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppTheme.eventxproAccent, width: 0.8),
                  ),
                  child: Text(
                    agendaType.toUpperCase(),
                    style: const TextStyle(
                      color: AppTheme.eventxproAccent,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),

          // Date & Time metadata row
          if (date != null || start != null || end != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                if (date != null && date.isNotEmpty) ...[
                  const Icon(Icons.calendar_today_rounded, size: 12, color: Colors.white60),
                  const SizedBox(width: 4),
                  Text(
                    date,
                    style: const TextStyle(color: Colors.white60, fontSize: 11),
                  ),
                  const SizedBox(width: 12),
                ],
                if (start != null || end != null) ...[
                  const Icon(Icons.access_time_rounded, size: 12, color: Colors.white60),
                  const SizedBox(width: 4),
                  Text(
                    '${start ?? ''}${start != null && end != null ? ' - ' : ''}${end ?? ''}',
                    style: const TextStyle(color: Colors.white60, fontSize: 11),
                  ),
                ],
              ],
            ),
          ],

          const SizedBox(height: 12),

          // Check-in & Check-out Buttons Row
          Row(
            children: [
              if (hasInAccess)
                Expanded(
                  child: _buildPunchButton(
                    label: 'CHECK-IN',
                    badgeColor: AppTheme.eventxproSuccess,
                    arrowColor: Colors.black,
                    onTap: () => _launchScanner(
                      punchType: 'check_in',
                      gateId: agendaId,
                      eventId: eventId,
                      gateName: title,
                      eventName: eventName,
                      section: 'agenda',
                      sectionLocation: title,
                    ),
                  ),
                ),

              if (hasInAccess && hasOutAccess) const SizedBox(width: 10),

              if (hasOutAccess)
                Expanded(
                  child: _buildPunchButton(
                    label: 'CHECK-OUT',
                    badgeColor: AppTheme.eventxproDanger,
                    arrowColor: Colors.white,
                    onTap: () => _launchScanner(
                      punchType: 'check_out',
                      gateId: agendaId,
                      eventId: eventId,
                      gateName: title,
                      eventName: eventName,
                      section: 'agenda',
                      sectionLocation: title,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Pill button with right circular badge (Matching RN OfflineEventSection styles.btn & styles.arrowBtn)
  Widget _buildPunchButton({
    required String label,
    required Color badgeColor,
    required Color arrowColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(50),
        child: Container(
          padding: const EdgeInsets.only(left: 10, right: 4, top: 4, bottom: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12), // defaultTrans
            borderRadius: BorderRadius.circular(50),
            border: Border.all(
              color: AppTheme.eventxproBorder, // defaultBorder
              width: 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 11.5,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: badgeColor,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    size: 14,
                    color: arrowColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
