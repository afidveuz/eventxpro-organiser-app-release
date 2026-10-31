import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/network/api_client.dart';
import '../../../core/services/app_update_service.dart';
import '../../../core/services/gate_count_service.dart';
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
import '../events/event_dashboard_screen.dart';
import '../kiosk_scanner_screen.dart';
import '../offline/offline_sessions_screen.dart';
import '../../widgets/session_punch_card.dart';

/// Custom painter that renders a modern tech dot-grid pattern
/// with subtle micro-cross accents that interact with atmospheric background glow orbs.
class _HomeScreenPatternPainter extends CustomPainter {
  const _HomeScreenPatternPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final dotPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..style = PaintingStyle.fill;

    final crossPaint = Paint()
      ..color = AppTheme.brandGradientStart.withValues(alpha: 0.08)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    const double spacing = 26.0;
    const double dotRadius = 1.0;

    int rowIndex = 0;
    for (double y = spacing / 2; y < size.height; y += spacing, rowIndex++) {
      int colIndex = 0;
      for (double x = spacing / 2; x < size.width; x += spacing, colIndex++) {
        // Decorative micro-cross at regular intervals (every 6th cell)
        if (rowIndex % 6 == 0 && colIndex % 6 == 0) {
          canvas.drawLine(Offset(x - 3, y), Offset(x + 3, y), crossPaint);
          canvas.drawLine(Offset(x, y - 3), Offset(x, y + 3), crossPaint);
        } else {
          canvas.drawCircle(Offset(x, y), dotRadius, dotPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

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
  int? _expandedEventPk;
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
          if (pk != null && _expandedEventPk == null) {
            _expandedEventPk = pk;
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

        final totalEvt = (data['total_event'] as num?)?.toInt() ?? 0;
        final totalScanned =
            (data['total_scanned_count'] as num?)?.toInt() ?? 0;
        final rawEvents = data['event_list'] as List<dynamic>? ?? [];
        final events = rawEvents.whereType<Map<String, dynamic>>().toList();

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
          _totalEvents = totalEvt;
          _totalScannedCount = totalScanned;
          _eventList = events;
          _isLoading = false;
          if (events.length == 1 && _expandedEventPk == null) {
            final first = events.first;
            final pk =
                (first['pk'] as num?)?.toInt() ??
                (first['id'] as num?)?.toInt() ??
                int.tryParse(first['pk']?.toString() ?? '') ??
                int.tryParse(first['id']?.toString() ?? '');
            if (pk != null) {
              _expandedEventPk = pk;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.eventxproBg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Base background image
          Positioned.fill(
            child: Image.asset('assets/images/bg.png', fit: BoxFit.cover),
          ),

          // 2. Multi-point Aurora Glow Orbs (Unique Color Pattern Atmosphere)
          // Top-right signature Magenta/Pink orb
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
                      const Color(0xFFC10067).withValues(alpha: 0.28),
                      const Color(0xFFF43F5E).withValues(alpha: 0.12),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.45, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // Top-left Electric Indigo / Violet orb
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
                      const Color(0xFF4F46E5).withValues(alpha: 0.24),
                      const Color(0xFF7C3AED).withValues(alpha: 0.10),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.45, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // Mid-right Cyber Cyan shimmer orb
          Positioned(
            top: 380,
            right: -70,
            child: IgnorePointer(
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF0EA5E9).withValues(alpha: 0.18),
                      const Color(0xFF06B6D4).withValues(alpha: 0.06),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // Bottom-left Deep Navy & Purple pool
          Positioned(
            bottom: -50,
            left: -50,
            child: IgnorePointer(
              child: Container(
                width: 320,
                height: 320,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF0C1A52).withValues(alpha: 0.45),
                      const Color(0xFF312E81).withValues(alpha: 0.20),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // 3. Geometric Tech Dot-Grid Pattern overlay
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: const _HomeScreenPatternPainter(),
              ),
            ),
          ),

          // 4. Subtle contrast & vignette overlay
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(0xFF131722).withValues(alpha: 0.35),
                      Colors.transparent,
                      const Color(0xFF0D111A).withValues(alpha: 0.50),
                    ],
                    stops: const [0.0, 0.45, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // 3. Foreground content
          SafeArea(
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // ── 1. Top Metrics Count Cards ────────────
                          _buildCountCardsRow(),
                          const SizedBox(height: 14),

                          if (_isOffline) ...[
                            _buildOfflineNoticeBar(),
                            const SizedBox(height: 14),
                          ],

                          // ── 2. Events Section Header ──────────────
                          _buildEventsSectionHeader(),
                          const SizedBox(height: 10),

                          // ── 3. Events List / Know More ────────────
                          _buildEventsSection(),
                          const SizedBox(height: 28),
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

  // ── Top Header / App Bar ─────────────────────────────────────────
  Widget _buildTopBar() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF131722).withValues(alpha: 0.70),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            child: Row(
              children: [
                // EventXPro Logo
                Image.asset(
                  'assets/images/logo.png',
                  height: 28,
                  fit: BoxFit.contain,
                ),
                const SizedBox(width: 10),

                // Offline status chip
                if (_isOffline)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF3B30).withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.wifi_off_rounded,
                          size: 11,
                          color: Color(0xFFFF5252),
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Offline',
                          style: TextStyle(
                            color: Color(0xFFFF5252),
                            fontWeight: FontWeight.w700,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),

                const Spacer(),

                // Refresh Button
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _isLoading
                        ? null
                        : () => _handleManualRefresh(silent: false),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: _isLoading
                            ? const SizedBox(
                                width: 15,
                                height: 15,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    AppTheme.eventxproAccent,
                                  ),
                                ),
                              )
                            : const Icon(
                                Icons.refresh_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Subtle brand accent hairline at the bottom of top bar
          Container(
            height: 1.5,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.brandGradientStart.withValues(alpha: 0.50),
                  AppTheme.brandGradientEnd.withValues(alpha: 0.40),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Metrics Count Cards (Unique colorful themes per metric) ──
  Widget _buildCountCardsRow() {
    return Row(
      children: [
        // Total Events Card (Indigo/Violet Accent)
        Expanded(
          child: _buildMetricCard(
            title: 'ACTIVE EVENTS',
            count: _totalEvents,
            icon: Icons.event_available_rounded,
            iconColor: const Color(0xFF818CF8),
            iconBgColor: const Color(0xFF6366F1).withValues(alpha: 0.18),
            gradientColors: [
              const Color(0xFF1B1E38).withValues(alpha: 0.90),
              const Color(0xFF131526).withValues(alpha: 0.90),
            ],
            shadowColor: const Color(0xFF4F46E5).withValues(alpha: 0.15),
          ),
        ),
        const SizedBox(width: 10),

        // Scanned Users Card (Magenta/Rose Accent)
        Expanded(
          child: _buildMetricCard(
            title: 'TOTAL SCANS',
            count: _totalScannedCount,
            icon: Icons.qr_code_scanner_rounded,
            iconColor: const Color(0xFFFB7185),
            iconBgColor: const Color(0xFFF43F5E).withValues(alpha: 0.18),
            gradientColors: [
              const Color(0xFF2C1525).withValues(alpha: 0.90),
              const Color(0xFF1A0F19).withValues(alpha: 0.90),
            ],
            shadowColor: const Color(0xFFE11D48).withValues(alpha: 0.15),
            isClickable: true,
            onTap: () async {
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
    required List<Color> gradientColors,
    required Color shadowColor,
    bool isClickable = false,
    VoidCallback? onTap,
  }) {
    final card = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: iconBgColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(child: Icon(icon, size: 16, color: iconColor)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  count.toString(),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -0.3,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.65),
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          if (isClickable)
            Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: iconColor.withValues(alpha: 0.70),
            ),
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
          borderRadius: BorderRadius.circular(12),
          child: card,
        ),
      );
    }

    return card;
  }

  // ── Compact Offline Notice Strip ─────────────────────────────────
  Widget _buildOfflineNoticeBar() {
    return InkWell(
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const OfflineSessionsScreen()),
        );
        _loadDashboardData(forceRefresh: false, silent: true);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xFFFF9800).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          children: [
            Icon(Icons.wifi_off_rounded, color: Color(0xFFFFB74D), size: 16),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Offline Mode Active — scans saved locally',
                style: TextStyle(
                  color: Color(0xFFFFE0B2),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              color: Color(0xFFFFB74D),
              size: 11,
            ),
          ],
        ),
      ),
    );
  }

  // ── Events Section Header ────────────────────────────────────────
  Widget _buildEventsSectionHeader() {
    return Row(
      children: [
        Container(
          width: 3.5,
          height: 14,
          decoration: BoxDecoration(
            gradient: AppTheme.brandGradient,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        const Text(
          'EVENT GATES & SESSIONS',
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.7,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppTheme.brandGradientStart.withValues(alpha: 0.18),
                AppTheme.brandGradientEnd.withValues(alpha: 0.18),
              ],
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.brandGradientStart,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                '$_totalEvents ACTIVE',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
            ],
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
          gradient: LinearGradient(
            colors: [
              const Color(0xFF20283A).withValues(alpha: 0.70),
              const Color(0xFF161C28).withValues(alpha: 0.65),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 30,
                height: 30,
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(
                    AppTheme.eventxproAccent,
                  ),
                  strokeWidth: 2.8,
                ),
              ),
              SizedBox(height: 14),
              Text(
                'Loading Events & Sessions...',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
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
          gradient: LinearGradient(
            colors: [
              const Color(0xFF20283A).withValues(alpha: 0.70),
              const Color(0xFF161C28).withValues(alpha: 0.65),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                shape: BoxShape.circle,
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
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 12.5,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide.none,
                backgroundColor: Colors.white.withValues(alpha: 0.08),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 9,
                ),
              ),
              onPressed: () => _handleManualRefresh(silent: false),
              icon: const Icon(Icons.refresh_rounded, size: 15),
              label: const Text(
                'Refresh Events',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _eventList
          .map((eventData) => _buildEventCard(eventData))
          .toList(),
    );
  }

  Widget _buildEventCard(Map<String, dynamic> data) {
    final int eventPk =
        (data['pk'] as num?)?.toInt() ??
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
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1B2232).withValues(alpha: 0.85),
            const Color(0xFF131824).withValues(alpha: 0.90),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isExpanded
                ? AppTheme.brandGradientStart.withValues(alpha: 0.15)
                : Colors.black.withValues(alpha: 0.25),
            blurRadius: isExpanded ? 16 : 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Entire Event Card Header is Tappable ──────────────
          Material(
            color: Colors.transparent,
            child: InkWell(
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
              borderRadius: isExpanded
                  ? const BorderRadius.vertical(top: Radius.circular(16))
                  : BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Meta Row: Event Tag & Date
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3.5,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.brandGradientStart.withValues(
                              alpha: 0.15,
                            ),
                            borderRadius: BorderRadius.circular(6),
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
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3.5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.calendar_today_rounded,
                                  size: 10.5,
                                  color: Colors.white70,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  startDate.isNotEmpty && endDate.isNotEmpty
                                      ? (startDate == endDate
                                            ? startDate
                                            : '$startDate - $endDate')
                                      : (startDate.isNotEmpty
                                            ? startDate
                                            : endDate),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Event Name
                    Text(
                      eventName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.2,
                        height: 1.25,
                      ),
                    ),

                    // Short Description
                    if (cleanDesc.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        cleanDesc,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.60),
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),

                    // Side-by-Side Action Buttons (Dashboard & Open Gates)
                    Row(
                      children: [
                        // Dedicated Dashboard Button
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
                                      eventData: data,
                                      zebraAdapter: widget.zebraAdapter,
                                      simulatorAdapter: widget.simulatorAdapter,
                                    ),
                                  ),
                                );
                              },
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                height: 38,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.brandGradientStart.withValues(
                                    alpha: 0.15,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.analytics_rounded,
                                      size: 15,
                                      color: AppTheme.brandGradientStart,
                                    ),
                                    SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        'Dashboard',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 12,
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                                    ),
                                    SizedBox(width: 4),
                                    Icon(
                                      Icons.arrow_forward_ios_rounded,
                                      size: 10,
                                      color: Colors.white60,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),

                        // Expand / Collapse Gates Button
                        Expanded(
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () {
                                HapticFeedback.lightImpact();
                                setState(() {
                                  if (isExpanded) {
                                    _expandedEventPk = null;
                                  } else {
                                    _expandedEventPk = eventPk;
                                    if (!_eventPermissions.containsKey(
                                      eventPk,
                                    )) {
                                      _fetchPermissionsForEvent(eventPk);
                                    }
                                  }
                                });
                              },
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                height: 38,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                decoration: BoxDecoration(
                                  gradient: isExpanded
                                      ? null
                                      : AppTheme.brandGradient,
                                  color: isExpanded
                                      ? Colors.white.withValues(alpha: 0.08)
                                      : null,
                                  borderRadius: BorderRadius.circular(10),
                                  boxShadow: isExpanded
                                      ? null
                                      : [
                                          BoxShadow(
                                            color: AppTheme.brandGradientStart
                                                .withValues(alpha: 0.35),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      isExpanded
                                          ? Icons.visibility_off_rounded
                                          : Icons.door_sliding_outlined,
                                      size: 15,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        isExpanded
                                            ? 'Hide Gates'
                                            : 'Open Gates',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 12,
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    AnimatedRotation(
                                      turns: isExpanded ? 0.5 : 0.0,
                                      duration: const Duration(
                                        milliseconds: 200,
                                      ),
                                      child: const Icon(
                                        Icons.keyboard_arrow_down_rounded,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Expanded Know More Box (Entrances, Halls, Agendas, Sessions) ──
          if (isExpanded) ...[
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFF11151E).withValues(alpha: 0.72),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(15),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
          final cachedPk =
              (event?['pk'] as num?)?.toInt() ??
              (event?['id'] as num?)?.toInt() ??
              int.tryParse(event?['pk']?.toString() ?? '');
          if ((cachedPk == eventId || _eventList.length == 1) &&
              parsed['permission'] is Map) {
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
                valueColor: AlwaysStoppedAnimation<Color>(
                  AppTheme.eventxproAccent,
                ),
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
            final String title =
                item['entrance_name']?.toString() ?? 'Entrance';
            final String? loc = item['location']?.toString();
            final String displayTitle = loc != null && loc.isNotEmpty
                ? '$title - $loc'
                : title;
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
          if (hallList.isNotEmpty ||
              agendaList.isNotEmpty ||
              sessionList.isNotEmpty)
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
          if (sessionList.isNotEmpty) const SizedBox(height: 16),
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

  /// Section Header matching React Native EveSectionWrapper
  Widget _buildCategoryHeader({
    required String title,
    required IconData icon,
    required int? count,
    Color accentColor = AppTheme.eventxproAccent,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 10),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(child: Icon(icon, size: 13, color: accentColor)),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 11.5,
              letterSpacing: 0.6,
            ),
          ),
          if (count != null) ...[
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count Available',
                style: TextStyle(
                  color: accentColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
