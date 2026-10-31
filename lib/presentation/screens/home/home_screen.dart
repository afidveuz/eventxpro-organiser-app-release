import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/network/api_client.dart';
import '../../../core/services/app_update_service.dart';
import '../../../core/services/gate_count_service.dart';
import '../../../data/adapters/simulated_hardware_adapter.dart';
import '../../../data/adapters/zebra_datawedge_adapter.dart';
import '../../../data/datasources/offline_database_helper.dart';
import '../../../data/datasources/scanner_local_storage.dart';
import '../../bloc/auth/auth_bloc.dart';
import '../../bloc/auth/auth_event.dart';
import '../../bloc/scanner_bloc.dart';
import '../../bloc/scanner_event.dart';
import '../auth/login_screen.dart';
import '../events/event_dashboard_screen.dart';
import '../kiosk_scanner_screen.dart';
import '../offline/offline_sessions_screen.dart';
import '../../widgets/session_punch_card.dart';

/// Cached parsed sections for high-performance zero-delay rendering
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

/// EventXPro Organiser HomeScreen matching the reference React Native design:
/// - Top Bar with EventXPro branding and quick reload
/// - Quick Actions: Dashboard and Hide/Show Gates toggle
/// - Structured sections: Entrances & Gates, Halls, Agendas, Sessions
/// - High-contrast Check-In and Check-Out punch cards with In/Out metrics
class HomeScreen extends StatefulWidget {
  final ZebraDataWedgeAdapter? zebraAdapter;
  final SimulatedHardwareAdapter? simulatorAdapter;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onOpenLeads;

  const HomeScreen({
    super.key,
    this.zebraAdapter,
    this.simulatorAdapter,
    this.onOpenSettings,
    this.onOpenLeads,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isLoading = true;
  int _totalEvents = 0;
  int _totalScannedCount = 0;
  List<Map<String, dynamic>> _eventList = [];
  bool _isOffline = false;
  int? _selectedEventPk;
  bool _showGates = true;
  final Map<int, Map<String, dynamic>> _eventPermissions = {};
  final Map<int, _ParsedEventSections> _parsedSectionsCache = {};
  final Set<int> _loadingPermissions = {};
  int _countRefreshTrigger = 0;
  int _serverRefreshTrigger = 0;

  /// Throttle & Cache management for dashboard API requests
  DateTime? _lastDashboardFetchTime;
  bool _isDashboardFetching = false;
  static const Duration _dashboardThrottleDuration = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    _loadDashboardData();

    // Check for app updates on home screen load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        AppUpdateService().checkAndPromptUpdate(context);
      }
    });
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
    final isThrottled =
        !forceRefresh &&
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
        int? pk;
        if (event != null) {
          pk =
              (event['pk'] as num?)?.toInt() ??
              (event['id'] as num?)?.toInt() ??
              int.tryParse(event['pk']?.toString() ?? '') ??
              int.tryParse(event['id']?.toString() ?? '');
          if (pk != null && parsed['permission'] is Map) {
            final permMap = Map<String, dynamic>.from(
              parsed['permission'] as Map,
            );
            _eventPermissions[pk] = permMap;
            _parsedSectionsCache[pk] = _parseSections(permMap);
          }
        }

        setState(() {
          _totalEvents = event != null ? 1 : 0;
          _totalScannedCount = totalScanned;
          _eventList = event != null ? [event] : [];
          _isLoading = false;
          if (pk != null) {
            _selectedEventPk = pk;
          }
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

        final rawEvents = data['event_list'] as List<dynamic>? ?? [];
        final events = rawEvents.whereType<Map<String, dynamic>>().toList();
        final totalEvt =
            (data['total_event'] as num?)?.toInt() ?? events.length;
        final totalScanned =
            (data['total_scanned_count'] as num?)?.toInt() ?? 0;

        // If there's an event, fetch permissions and cache offline
        if (events.isNotEmpty) {
          final firstEvt = events.first;
          final int? evtPk =
              (firstEvt['pk'] as num?)?.toInt() ??
              (firstEvt['id'] as num?)?.toInt() ??
              int.tryParse(firstEvt['pk']?.toString() ?? '') ??
              int.tryParse(firstEvt['id']?.toString() ?? '');
          if (evtPk != null) {
            try {
              final permRes = await apiClient.dio.get(
                'organizer/event-permission/$evtPk',
              );
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
          _totalEvents = totalEvt > 0 ? totalEvt : events.length;
          _totalScannedCount = totalScanned;
          _eventList = events;
          _isLoading = false;
          if (events.isNotEmpty) {
            final first = events.first;
            final pk =
                (first['pk'] as num?)?.toInt() ??
                (first['id'] as num?)?.toInt() ??
                int.tryParse(first['pk']?.toString() ?? '') ??
                int.tryParse(first['id']?.toString() ?? '');
            if (pk != null &&
                (_selectedEventPk == null ||
                    !events.any((e) =>
                        ((e['pk'] ?? e['id']) == _selectedEventPk)))) {
              _selectedEventPk = pk;
            }
          }
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
          final rawMsg =
              e.response?.data['message'] ?? e.response?.data['detail'];
          if (rawMsg != null) msg = rawMsg.toString();
        }
        _handleSessionExpired(msg);
        return;
      }
      debugPrint(
        '[HomeScreen] ⚠️ Online fetch failed, falling back to offline: $e',
      );
      await _loadOfflineData(scannerLocalStorage, dbHelper);
    } catch (e) {
      debugPrint(
        '[HomeScreen] ⚠️ Online fetch failed, falling back to offline: $e',
      );
      await _loadOfflineData(scannerLocalStorage, dbHelper);
    }
  }

  Future<void> _fetchPermissionsForEvent(int eventPk) async {
    if (_eventPermissions.containsKey(eventPk) ||
        _loadingPermissions.contains(eventPk)) {
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
        final cachedPk =
            (event?['pk'] as num?)?.toInt() ??
            (event?['id'] as num?)?.toInt() ??
            int.tryParse(event?['pk']?.toString() ?? '');
        if ((cachedPk == eventPk || _eventList.length == 1) &&
            parsed['permission'] is Map) {
          final cachedPerm = Map<String, dynamic>.from(
            parsed['permission'] as Map,
          );
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
        final res = await apiClient.dio.get(
          'organizer/event-permission/$eventPk',
        );
        if (res.statusCode == 200 && res.data != null) {
          final Map<String, dynamic> perm = res.data is Map
              ? Map<String, dynamic>.from(res.data as Map)
              : Map<String, dynamic>.from(
                  jsonDecode(res.data.toString()) as Map,
                );
          if (mounted) {
            setState(() {
              _eventPermissions[eventPk] = perm;
              _parsedSectionsCache[eventPk] = _parseSections(perm);
            });
          }
        }
      } catch (e) {
        debugPrint(
          '[HomeScreen] ⚠️ Error loading permissions for event $eventPk: $e',
        );
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
              if (mounted &&
                  totalScanned > 0 &&
                  totalScanned > _totalScannedCount) {
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

  Map<String, dynamic>? _getActiveEvent() {
    if (_eventList.isEmpty) return null;
    if (_selectedEventPk != null) {
      try {
        return _eventList.firstWhere((e) {
          final pk = (e['pk'] as num?)?.toInt() ??
              (e['id'] as num?)?.toInt() ??
              int.tryParse(e['pk']?.toString() ?? '') ??
              int.tryParse(e['id']?.toString() ?? '');
          return pk == _selectedEventPk;
        });
      } catch (_) {}
    }
    return _eventList.first;
  }

  int _getActiveEventPk(Map<String, dynamic>? event) {
    if (event == null) {
      try {
        return context.read<ScannerLocalStorage>().getEventId();
      } catch (_) {
        return 1;
      }
    }
    return (event['pk'] as num?)?.toInt() ??
        (event['id'] as num?)?.toInt() ??
        int.tryParse(event['pk']?.toString() ?? '') ??
        int.tryParse(event['id']?.toString() ?? '') ??
        1;
  }

  String _getActiveEventName(Map<String, dynamic>? event) {
    return event?['publish_event_name']?.toString() ??
        event?['event_name']?.toString() ??
        'Event';
  }

  String _formatDate(dynamic dateVal) {
    if (dateVal == null) return '';
    final str = dateVal.toString().trim();
    if (str.isEmpty) return '';
    try {
      final dt = DateTime.parse(str);
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      final month = months[dt.month - 1];
      return '$month ${dt.day.toString().padLeft(2, '0')}, ${dt.year}';
    } catch (_) {
      return str.split('T').first;
    }
  }

  String _getEventDateRange(Map<String, dynamic>? event) {
    if (event == null) return '';
    final rawStart = event['publish_start_dt'] ??
        event['start_dt'] ??
        event['start_date'] ??
        event['event_start_date'];
    final rawEnd = event['publish_end_dt'] ??
        event['end_dt'] ??
        event['end_date'] ??
        event['event_end_date'];

    final startStr = _formatDate(rawStart);
    final endStr = _formatDate(rawEnd);

    if (startStr.isNotEmpty && endStr.isNotEmpty) {
      if (startStr == endStr) return startStr;
      return '$startStr - $endStr';
    }
    return startStr.isNotEmpty ? startStr : endStr;
  }

  @override
  Widget build(BuildContext context) {
    final activeEvent = _getActiveEvent();
    final int activeEventPk = _getActiveEventPk(activeEvent);
    final String activeEventName = _getActiveEventName(activeEvent);

    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Base background image
          Positioned.fill(
            child: Image.asset(
              'assets/images/bg.png',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox.shrink(),
            ),
          ),

          // 2. Multi-point Aurora Glow Orbs for ambient depth
          Positioned(
            top: -60,
            right: -50,
            child: IgnorePointer(
              child: Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFFC10067).withValues(alpha: 0.20),
                      const Color(0xFFF43F5E).withValues(alpha: 0.08),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.45, 1.0],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 100,
            left: -80,
            child: IgnorePointer(
              child: Container(
                width: 290,
                height: 290,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF4F46E5).withValues(alpha: 0.18),
                      const Color(0xFF7C3AED).withValues(alpha: 0.08),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.45, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // 3. Subtle contrast & fade overlay
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(0xFF0B0F19).withValues(alpha: 0.65),
                      const Color(0xFF0B0F19).withValues(alpha: 0.50),
                      const Color(0xFF0B0F19).withValues(alpha: 0.85),
                    ],
                    stops: const [0.0, 0.45, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // 4. Foreground content
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(
                  child: RefreshIndicator(
                    color: const Color(0xFF6366F1),
                    backgroundColor: const Color(0xFF131926),
                    onRefresh: () => _handleManualRefresh(silent: true),
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 1. Metric Cards: TOTAL EVENTS & SCANNED USERS
                          _buildMetricsRow(),
                          const SizedBox(height: 12),

                          // 2. Active Event Name & Date Card
                          if (_eventList.isNotEmpty || !_isLoading) ...[
                            _buildEventInfoCard(
                              activeEventPk,
                              activeEventName,
                              activeEvent,
                            ),
                            const SizedBox(height: 12),
                          ],

                          // 3. Quick Action Row: [Dashboard >] & [Hide Gates ^ / Show Gates v]
                          _buildQuickActionsRow(
                            activeEventPk,
                            activeEventName,
                            activeEvent,
                          ),
                          const SizedBox(height: 14),

                          // Gates & Sessions Content (or loading / empty state)
                          if (_isLoading && _eventList.isEmpty)
                            _buildLoadingState()
                          else if (_eventList.isEmpty)
                            _buildEmptyEventsState()
                          else if (_showGates)
                            _buildGatesSections(activeEventPk, activeEventName)
                          else
                            const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Top Header / App Bar (Matching Screenshot) ───────────────────
  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // EventXPro Logo Image
          Image.asset(
            'assets/images/logo.png',
            height: 28,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => RichText(
              text: const TextSpan(
                children: [
                  TextSpan(
                    text: 'EventX',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  TextSpan(
                    text: 'Pro',
                    style: TextStyle(
                      color: Color(0xFF8E9BAE),
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Offline Status Chip
          if (_isOffline) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 7,
                vertical: 2.5,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFFF3B30).withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.wifi_off_rounded,
                    size: 10,
                    color: Color(0xFFFF5252),
                  ),
                  SizedBox(width: 3),
                  Text(
                    'Offline',
                    style: TextStyle(
                      color: Color(0xFFFF5252),
                      fontWeight: FontWeight.w700,
                      fontSize: 9.5,
                    ),
                  ),
                ],
              ),
            ),
          ],

          const Spacer(),

          // Refresh Button
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _isLoading
                  ? null
                  : () => _handleManualRefresh(silent: false),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF131926),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFF1F293D),
                    width: 1.0,
                  ),
                ),
                child: Center(
                  child: _isLoading
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Color(0xFF8E9BAE),
                            ),
                          ),
                        )
                      : const Icon(
                          Icons.sync_rounded,
                          color: Color(0xFF8E9BAE),
                          size: 19,
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Quick Actions Row: [Dashboard >] & [Hide Gates ^] ─────────────
  Widget _buildQuickActionsRow(
    int eventPk,
    String eventName,
    Map<String, dynamic>? eventData,
  ) {
    return Row(
      children: [
        // Dashboard Button
        Expanded(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => EventDashboardScreen(
                      eventId: eventPk,
                      eventName: eventName,
                      eventData: eventData,
                      zebraAdapter: widget.zebraAdapter,
                      simulatorAdapter: widget.simulatorAdapter,
                    ),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                height: 46,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF131926),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF1F293D),
                    width: 1.0,
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.bar_chart_rounded,
                      size: 18,
                      color: Color(0xFF64748B),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Dashboard',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Spacer(),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: Color(0xFF64748B),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),

        // Hide / Show Gates Button
        Expanded(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() {
                  _showGates = !_showGates;
                });
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                height: 46,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF131926),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF1F293D),
                    width: 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _showGates
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 18,
                      color: const Color(0xFF64748B),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _showGates ? 'Hide Gates' : 'Show Gates',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      _showGates
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: const Color(0xFF64748B),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Metrics Row: [TOTAL EVENTS] & [SCANNED USERS] ─────────────────
  Widget _buildMetricsRow() {
    return Row(
      children: [
        // Total Events Card
        Expanded(
          child: _buildMetricCard(
            title: 'TOTAL EVENTS',
            count: _totalEvents,
            icon: Icons.event_available_rounded,
            iconColor: const Color(0xFF818CF8),
            iconBgColor: const Color(0xFF6366F1).withValues(alpha: 0.16),
            borderColor: const Color(0xFF283048),
          ),
        ),
        const SizedBox(width: 10),

        // Scanned Users Card
        Expanded(
          child: _buildMetricCard(
            title: 'SCANNED USERS',
            count: _totalScannedCount,
            icon: Icons.qr_code_scanner_rounded,
            iconColor: const Color(0xFFFB7185),
            iconBgColor: const Color(0xFFF43F5E).withValues(alpha: 0.16),
            borderColor: const Color(0xFF382230),
            isClickable: true,
            onTap: () async {
              HapticFeedback.lightImpact();
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const OfflineSessionsScreen(),
                ),
              );
              _loadDashboardData(forceRefresh: false, silent: true);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required String title,
    required int count,
    required IconData icon,
    required Color iconColor,
    required Color iconBgColor,
    required Color borderColor,
    bool isClickable = false,
    VoidCallback? onTap,
  }) {
    final cardContent = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFF131926),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: borderColor,
          width: 1.0,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconBgColor,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Center(
              child: Icon(
                icon,
                size: 19,
                color: iconColor,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  count.toString(),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.3,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF8E9BAE),
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
          if (isClickable)
            Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: iconColor.withValues(alpha: 0.7),
            ),
        ],
      ),
    );

    if (isClickable && onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: cardContent,
        ),
      );
    }

    return cardContent;
  }

  // ── Active Event Name & Date Card ─────────────────────────────────
  Widget _buildEventInfoCard(
    int activePk,
    String activeName,
    Map<String, dynamic>? activeEvent,
  ) {
    final dateRange = _getEventDateRange(activeEvent);
    final location = activeEvent?['location']?.toString() ??
        activeEvent?['venue']?.toString() ??
        '';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF131926),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF1F293D),
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: Event ID tag + Date badge + Switch button (if multiple)
          Row(
            children: [
              // Event ID pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF1B2436),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: const Color(0xFF28364F),
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
                        color: Color(0xFF00E676),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'EVENT #$activePk',
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // Date range badge
              if (dateRange.isNotEmpty)
                Expanded(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.calendar_today_rounded,
                        size: 11,
                        color: Color(0xFF64748B),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          dateRange,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                const Spacer(),

              // If multiple events, provide a subtle switcher trigger
              if (_eventList.length > 1)
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _showEventPickerBottomSheet,
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E273A),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: const Color(0xFF2D3B55),
                          width: 0.8,
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Switch',
                            style: TextStyle(
                              color: Color(0xFF818CF8),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(width: 2),
                          Icon(
                            Icons.unfold_more_rounded,
                            size: 12,
                            color: Color(0xFF818CF8),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 10),

          // Event Name
          Text(
            activeName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16.5,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
              height: 1.25,
            ),
          ),

          // Optional location subtitle
          if (location.isNotEmpty) ...[
            const SizedBox(height: 5),
            Row(
              children: [
                const Icon(
                  Icons.location_on_outlined,
                  size: 12,
                  color: Color(0xFF64748B),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    location,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
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

  void _showEventPickerBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF131926),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Select Event',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _eventList.length,
                    separatorBuilder: (_, _) => const Divider(
                      color: Color(0xFF1F293D),
                      height: 1,
                    ),
                    itemBuilder: (_, index) {
                      final evt = _eventList[index];
                      final pk = (evt['pk'] as num?)?.toInt() ??
                          (evt['id'] as num?)?.toInt() ??
                          int.tryParse(evt['pk']?.toString() ?? '') ??
                          index;
                      final name = evt['publish_event_name']?.toString() ??
                          evt['event_name']?.toString() ??
                          'Event #$pk';
                      final isSelected = pk == _selectedEventPk;

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          isSelected
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_off_rounded,
                          color: isSelected
                              ? const Color(0xFF6366F1)
                              : const Color(0xFF8E9BAE),
                          size: 20,
                        ),
                        title: Text(
                          name,
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.white70,
                            fontWeight: isSelected
                                ? FontWeight.w800
                                : FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          if (_selectedEventPk != pk) {
                            setState(() {
                              _selectedEventPk = pk;
                            });
                            if (!_eventPermissions.containsKey(pk)) {
                              _fetchPermissionsForEvent(pk);
                            }
                          }
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Gates & Sessions Section (Entrances, Halls, Agendas, Sessions) ─
  Widget _buildGatesSections(int eventId, String eventName) {
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
          if ((cachedPk == eventId || _eventList.length <= 1) &&
              parsed['permission'] is Map) {
            final perm = Map<String, dynamic>.from(parsed['permission'] as Map);
            _eventPermissions[eventId] = perm;
            sections = _parseSections(perm);
            _parsedSectionsCache[eventId] = sections;
          }
        } catch (_) {}
      }
    }

    // Trigger permission fetch if missing
    if (sections == null &&
        !_eventPermissions.containsKey(eventId) &&
        !_loadingPermissions.contains(eventId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fetchPermissionsForEvent(eventId);
      });
    }

    if (sections == null && _loadingPermissions.contains(eventId)) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 36),
        alignment: Alignment.center,
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  Color(0xFF6366F1),
                ),
              ),
            ),
            SizedBox(height: 12),
            Text(
              'Loading gates & sessions...',
              style: TextStyle(color: Color(0xFF8E9BAE), fontSize: 12.5),
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

    if (entranceList.isEmpty &&
        hallList.isEmpty &&
        agendaList.isEmpty &&
        sessionList.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
        decoration: BoxDecoration(
          color: const Color(0xFF131926),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF1E273A)),
        ),
        child: const Center(
          child: Text(
            'No gates or sessions configured for this event.',
            style: TextStyle(color: Color(0xFF8E9BAE), fontSize: 13),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── 1. ENTRANCES & GATES ──────────────────────────────
        if (entranceList.isNotEmpty) ...[
          _buildCategoryHeader(
            title: 'ENTRANCES & GATES',
            icon: Icons.door_sliding_outlined,
            count: entranceList.length,
          ),
          ...entranceList.map((item) {
            final int entranceId = (item['entrance_id'] as num?)?.toInt() ?? 1;
            final String title =
                item['entrance_name']?.toString() ?? 'Entrance';
            final String? loc = item['location']?.toString();
            final String displayTitle =
                loc != null && loc.isNotEmpty ? '$title - $loc' : title;
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
        ],

        // ── 2. HALLS ──────────────────────────────────────────
        if (hallList.isNotEmpty) ...[
          _buildCategoryHeader(
            title: 'HALLS',
            icon: Icons.domain_outlined,
            count: hallList.length,
          ),
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
        ],

        // ── 3. AGENDAS ────────────────────────────────────────
        if (agendaList.isNotEmpty) ...[
          _buildCategoryHeader(
            title: 'AGENDAS',
            icon: Icons.event_note_outlined,
            count: agendaList.length,
          ),
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
        ],

        // ── 4. SESSIONS ───────────────────────────────────────
        if (sessionList.isNotEmpty) ...[
          _buildCategoryHeader(
            title: 'SESSIONS',
            icon: Icons.co_present_outlined,
            count: sessionList.length,
          ),
          ...sessionList.map((item) {
            final int sessId =
                ((item['session_type_id'] ?? item['sessiontype_id']) as num?)
                    ?.toInt() ??
                0;
            final String title =
                (item['sessiontype_name'] ?? item['session_type_name'])
                    ?.toString() ??
                'Session';
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

  // ── Category Header (Matching Screenshot) ────────────────────────
  Widget _buildCategoryHeader({
    required String title,
    required IconData icon,
    required int count,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 10),
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: const Color(0xFF8E9BAE),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF8E9BAE),
              fontWeight: FontWeight.w800,
              fontSize: 12,
              letterSpacing: 0.8,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF131926),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: const Color(0xFF1F293D),
                width: 1.0,
              ),
            ),
            child: Text(
              '$count Available',
              style: const TextStyle(
                color: Color(0xFF8E9BAE),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      alignment: Alignment.center,
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
              strokeWidth: 2.5,
            ),
          ),
          SizedBox(height: 14),
          Text(
            'Loading gates & sessions...',
            style: TextStyle(
              color: Color(0xFF8E9BAE),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyEventsState() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      decoration: BoxDecoration(
        color: const Color(0xFF131926),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E273A)),
      ),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
              color: Color(0xFF1B2436),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.event_busy_rounded,
              size: 26,
              color: Color(0xFF8E9BAE),
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
            style: const TextStyle(
              color: Color(0xFF8E9BAE),
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Color(0xFF2B374E)),
              backgroundColor: const Color(0xFF1B2436),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onPressed: () => _handleManualRefresh(silent: false),
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text(
              'Refresh Events',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }

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
          },
        ],
        hallList: const [],
        agendaList: const [],
        sessionList: const [],
      );
    }

    // 1. Entrances
    List<Map<String, dynamic>> entranceList = [];
    final entrancePerm =
        permission['entrance_permission'] as Map<String, dynamic>?;
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
          },
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
    final sessionPerm =
        permission['sessiontype_permission'] as Map<String, dynamic>?;
    if (sessionPerm != null && sessionPerm['access'] == true) {
      final rawList = sessionPerm['sessiontype_list'] as List<dynamic>? ?? [];
      sessionList = rawList.whereType<Map<String, dynamic>>().toList();
    }

    if (entranceList.isEmpty &&
        hallList.isEmpty &&
        agendaList.isEmpty &&
        sessionList.isEmpty) {
      final gateId = context.read<ScannerLocalStorage>().getGateId();
      entranceList = [
        {
          'entrance_id': gateId,
          'entrance_name': 'Main Entrance',
          'location': 'Gate #$gateId',
          'entrance_in_access': true,
          'entrance_out_access': true,
        },
      ];
    }

    return _ParsedEventSections(
      entranceList: entranceList,
      hallList: hallList,
      agendaList: agendaList,
      sessionList: sessionList,
    );
  }
}
