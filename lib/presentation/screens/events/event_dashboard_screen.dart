import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/adapters/simulated_hardware_adapter.dart';
import '../../../data/adapters/zebra_datawedge_adapter.dart';
import '../../../data/datasources/scanner_local_storage.dart';
import '../../../data/repositories/auth_repository.dart';
import '../attendees/event_attendees_screen.dart';
import '../attendees/spot_registration_screen.dart';
import '../lead/leads_list_screen.dart';
import '../onsite_qr_verification_screen.dart';
import '../qr_verification_screen.dart';
import 'event_sessions_screen.dart';
import '../../widgets/fade_in_background_image.dart';

/// Event Dashboard Screen matching `EventDashboard.jsx` in the reference React Native app.
/// Features:
/// - Event Banner with Event Photo, Logo, and Title
/// - Total Registration, Total Venue / Unique Visits, No Shows, Today Visits, Checkin Count, and Leads
/// - Prominent 'Check-In / Check-Out' navigation banner navigating to `EventSessionsScreen`
/// - Action tiles: Registration, QR Verification, On-Site QR Verification, Leads
class EventDashboardScreen extends StatefulWidget {
  final int eventId;
  final String eventName;
  final Map<String, dynamic>? eventData;
  final ZebraDataWedgeAdapter? zebraAdapter;
  final SimulatedHardwareAdapter? simulatorAdapter;

  const EventDashboardScreen({
    super.key,
    required this.eventId,
    required this.eventName,
    this.eventData,
    this.zebraAdapter,
    this.simulatorAdapter,
  });

  @override
  State<EventDashboardScreen> createState() => _EventDashboardScreenState();
}

class _EventDashboardScreenState extends State<EventDashboardScreen> {
  bool _isLoading = true;
  bool _isRefreshing = false;
  Map<String, dynamic> _eventDetails = {};
  Map<String, dynamic>? _cachedPermissions;

  @override
  void initState() {
    super.initState();
    try {
      final storage = context.read<ScannerLocalStorage>();
      final raw = storage.getOfflineData();
      if (raw != null && raw.isNotEmpty) {
        final parsed = jsonDecode(raw) as Map<String, dynamic>;
        final perm = (parsed['permission'] as Map<String, dynamic>?) ?? parsed;
        _cachedPermissions = perm;
      }
    } catch (_) {}
    _loadDashboardData();
  }

  /// Resolve full image URL from relative path
  String _resolveImageUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http://') || path.startsWith('https://')) return path;

    try {
      final authRepo = context.read<AuthRepository>();
      final baseUrl = authRepo.mediaUrl;
      final cleanBase = baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl;
      final cleanPath = path.startsWith('/') ? path : '/$path';
      return '$cleanBase$cleanPath';
    } catch (_) {
      return path;
    }
  }

  /// Format date to MMM DD YYYY
  String _formatDate(dynamic dateVal) {
    if (dateVal == null) return '';
    try {
      final dt = DateTime.parse(dateVal.toString());
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      final month = months[dt.month - 1];
      return '$month ${dt.day.toString().padLeft(2, '0')} ${dt.year}';
    } catch (_) {
      return dateVal.toString();
    }
  }

  Future<void> _loadDashboardData({bool silent = false}) async {
    if (!silent) {
      setState(() => _isLoading = true);
    } else {
      setState(() => _isRefreshing = true);
    }

    final apiClient = context.read<ApiClient>();
    final storage = context.read<ScannerLocalStorage>();

    try {
      // 1. Fetch Event-based Details (Metrics, Photo, Logo, Counts)
      final res = await apiClient.dio.get(
        'organizer/event-based-details',
        queryParameters: {'event_id': widget.eventId},
      );

      if (res.statusCode == 200 && res.data != null) {
        Map<String, dynamic> dataMap = {};
        if (res.data is Map) {
          dataMap = Map<String, dynamic>.from(res.data as Map);
        } else {
          final parsed = jsonDecode(res.data.toString());
          if (parsed is Map) {
            dataMap = Map<String, dynamic>.from(parsed);
          }
        }

        // Cache response locally for offline fallback
        try {
          await storage.setCustomString(
            'event_dashboard_cache_${widget.eventId}',
            jsonEncode(dataMap),
          );
        } catch (_) {}

        if (mounted) {
          setState(() {
            _eventDetails = dataMap;
            _isLoading = false;
            _isRefreshing = false;
          });
        }
      }

      // 2. Pre-fetch permissions for fast navigation to Check-In / Check-Out
      try {
        final permRes = await apiClient.dio.get(
          'organizer/event-permission/${widget.eventId}',
        );
        if (permRes.statusCode == 200 && permRes.data != null) {
          if (permRes.data is Map) {
            _cachedPermissions = Map<String, dynamic>.from(permRes.data as Map);
          } else {
            final parsed = jsonDecode(permRes.data.toString());
            if (parsed is Map) {
              _cachedPermissions = Map<String, dynamic>.from(parsed);
            }
          }
          if (_cachedPermissions != null) {
            try {
              final eventObj = (_eventDetails['eventlist'] as Map<String, dynamic>?) ??
                  {'pk': widget.eventId, 'id': widget.eventId};
              await storage.setOfflineData(jsonEncode({
                'event': eventObj,
                'permission': _cachedPermissions,
                'cached_at': DateTime.now().toIso8601String(),
              }));
            } catch (_) {}
          }
          if (mounted) setState(() {});
        }
      } catch (_) {}
    } catch (e) {
      debugPrint('[EventDashboardScreen] Error loading dashboard data: $e');

      // Offline Fallback: load from local cache
      if (mounted) {
        try {
          final cachedRaw = storage.getCustomString('event_dashboard_cache_${widget.eventId}');
          if (cachedRaw != null && cachedRaw.isNotEmpty) {
            final cachedMap = jsonDecode(cachedRaw);
            if (cachedMap is Map) {
              setState(() {
                _eventDetails = Map<String, dynamic>.from(cachedMap);
                _isLoading = false;
                _isRefreshing = false;
              });
              return;
            }
          }
        } catch (_) {}

        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  void _openCheckInOutSessions() {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EventSessionsScreen(
          eventId: widget.eventId,
          eventName: _getEventName(),
          initialPermissions: _cachedPermissions,
          zebraAdapter: widget.zebraAdapter,
          simulatorAdapter: widget.simulatorAdapter,
        ),
      ),
    );
  }

  bool get _canUpdateUsers {
    try {
      final authRepo = context.read<AuthRepository>();
      if (authRepo.currentUser?.isAdmin == true) return true;
    } catch (_) {}
    return _eventDetails['user_update'] == true ||
        _cachedPermissions?['user_update'] == true;
  }

  void _openAttendees(String title, String endPoint) {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EventAttendeesScreen(
          eventId: widget.eventId,
          eventName: _getEventName(),
          title: title,
          endPoint: endPoint,
          canEditAttendee: _canUpdateUsers,
        ),
      ),
    );
  }

  void _openSpotRegistration() {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SpotRegistrationScreen(
          eventId: widget.eventId,
          eventName: _getEventName(),
        ),
      ),
    ).then((_) {
      _loadDashboardData(silent: true);
    });
  }

  String _getEventName() {
    final eventlist = _eventDetails['eventlist'] as Map<String, dynamic>?;
    return eventlist?['publish_event_name']?.toString() ??
        widget.eventData?['publish_event_name']?.toString() ??
        widget.eventName;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.eventxproBg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const AppBackgroundLayer(),

          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(
                  child: RefreshIndicator(
                    color: AppTheme.accentIndigo,
                    backgroundColor: AppTheme.surfaceElevated,
                    onRefresh: () => _loadDashboardData(silent: true),
                    child: _isLoading
                        ? _buildLoadingState()
                        : SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // ── 1. Hero Event Banner Card ────────────
                                _buildEventHeroCard(),
                                const SizedBox(height: 16),

                                // ── 2. Prominent Check-In / Check-Out ──
                                _buildCheckInOutBanner(),
                                const SizedBox(height: 16),

                                // ── 3. Metrics Grid (Registrations, Visits, etc.)
                                _buildMetricsSection(),
                                const SizedBox(height: 16),

                                // ── 4. Quick Action Tiles ────────────────
                                _buildQuickActionTiles(),
                                const SizedBox(height: 32),
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

  // ── Reusable Glassmorphic Card Container ─────────────────────────
  Widget _buildGlassCard({
    required Widget child,
    BorderRadius? borderRadius,
    EdgeInsetsGeometry? padding,
    Border? border,
    Color? color,
  }) {
    final radius = borderRadius ?? BorderRadius.circular(16);
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: color ?? Colors.white.withValues(alpha: 0.04),
            borderRadius: radius,
            border: border ??
                Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                  width: 1,
                ),
          ),
          child: child,
        ),
      ),
    );
  }

  // ── Top Header / App Bar ─────────────────────────────────────────
  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // Sleek Glass Back Button
          _buildGlassCard(
            borderRadius: BorderRadius.circular(12),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.of(context).pop();
                },
                borderRadius: BorderRadius.circular(12),
                splashColor: AppTheme.accentIndigo.withValues(alpha: 0.12),
                highlightColor: AppTheme.accentIndigo.withValues(alpha: 0.06),
                child: const SizedBox(
                  width: 38,
                  height: 38,
                  child: Center(
                    child: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Title & Event Name
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Text(
                      'Event Home',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 5,
                            height: 5,
                            decoration: const BoxDecoration(
                              color: Color(0xFF10B981),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            'LIVE',
                            style: TextStyle(
                              color: Color(0xFF34D399),
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(
                      Icons.event_note_rounded,
                      size: 12,
                      color: AppTheme.accentIndigo,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        _getEventName(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.65),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Glass Refresh Button
          _buildGlassCard(
            borderRadius: BorderRadius.circular(12),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  HapticFeedback.lightImpact();
                  _loadDashboardData(silent: false);
                },
                borderRadius: BorderRadius.circular(12),
                splashColor: AppTheme.accentIndigo.withValues(alpha: 0.12),
                highlightColor: AppTheme.accentIndigo.withValues(alpha: 0.06),
                child: SizedBox(
                  width: 38,
                  height: 38,
                  child: Center(
                    child: _isRefreshing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                AppTheme.accentIndigo,
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
          ),
        ],
      ),
    );
  }

  // ── 1. Hero Event Banner Card ────────────────────────────────────
  Widget _buildEventHeroCard() {
    final eventlist = _eventDetails['eventlist'] as Map<String, dynamic>?;
    final photoPath = eventlist?['event_photo']?.toString() ??
        widget.eventData?['event_photo']?.toString();
    final logoPath = eventlist?['logo']?.toString() ??
        widget.eventData?['logo']?.toString();
    final fullPhotoUrl = _resolveImageUrl(photoPath);
    final fullLogoUrl = _resolveImageUrl(logoPath);

    final eventName = _getEventName();
    final startDate = _formatDate(eventlist?['publish_start_dt'] ?? widget.eventData?['publish_start_dt']);
    final endDate = _formatDate(eventlist?['publish_end_dt'] ?? widget.eventData?['publish_end_dt']);
    final myBadges = _eventDetails['mybadge'] as List<dynamic>? ?? [];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Banner Background Image
          if (fullPhotoUrl.isNotEmpty)
            Positioned.fill(
              child: Image.network(
                fullPhotoUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Image.asset(
                  'assets/images/bg.png',
                  fit: BoxFit.cover,
                ),
              ),
            )
          else
            Positioned.fill(
              child: Image.asset('assets/images/bg.png', fit: BoxFit.cover),
            ),

          // Gradient Overlay
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF0C101A).withValues(alpha: 0.70),
                    const Color(0xFF0C101A).withValues(alpha: 0.92),
                  ],
                ),
              ),
            ),
          ),

          // Content
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Event Logo
                if (fullLogoUrl.isNotEmpty)
                  Container(
                    height: 52,
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Image.network(
                      fullLogoUrl,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) =>
                          const SizedBox.shrink(),
                    ),
                  ),

                // Event Title
                Text(
                  eventName.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 8),

                // Date Chip
                if (startDate.isNotEmpty || endDate.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppTheme.accentIndigo.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppTheme.accentIndigo.withValues(alpha: 0.25),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.calendar_today_rounded,
                          size: 11,
                          color: AppTheme.accentIndigo,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          startDate == endDate ? startDate : '$startDate - $endDate',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),

                // MY BADGE Button (if user has digital badge)
                if (myBadges.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.accentIndigo.withValues(alpha: 0.35),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.confirmation_number_rounded, size: 16, color: Colors.white),
                        SizedBox(width: 6),
                        Text(
                          'MY BADGE',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 2. Prominent Highlighted Check-In / Check-Out Hero Tile ──────
  Widget _buildCheckInOutBanner() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF3730A3), // Subdued rich indigo (Tailwind indigo-800)
            Color(0xFF1E1B4B), // Deep midnight indigo (Tailwind indigo-950)
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF6366F1).withValues(alpha: 0.28),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: const Color(0xFF3730A3).withValues(alpha: 0.18),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            _openCheckInOutSessions();
          },
          borderRadius: BorderRadius.circular(16),
          splashColor: Colors.white.withValues(alpha: 0.12),
          highlightColor: Colors.white.withValues(alpha: 0.05),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                // Frosted Glass Icon Badge
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18),
                      width: 1,
                    ),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.qr_code_scanner_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Check-In / Check-Out',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Scan attendees at entrances, halls & sessions',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.80),
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // Crisp Action Pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6.5),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.14),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'SCAN',
                        style: TextStyle(
                          color: Color(0xFF312E81),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward_rounded,
                        color: Color(0xFF312E81),
                        size: 12,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Section Header Helper ────────────────────────────────────────
  Widget _buildSectionHeader(String title) {
    return Row(
      children: [
        Container(
          width: 3.5,
          height: 14,
          decoration: BoxDecoration(
            color: AppTheme.accentIndigo,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }

  // ── 3. Metrics Section: Turnout Hero + 2x2 Secondary Grid ────────
  Widget _buildMetricsSection() {
    final int totalReg = (_eventDetails['totalconfirmation'] as num?)?.toInt() ?? 0;
    final int totalVisits = (_eventDetails['totalattendees'] as num?)?.toInt() ?? 0;
    final int noShows = (_eventDetails['noshow'] as num?)?.toInt() ?? 0;
    final int todayVisits = (_eventDetails['todayvisits'] as num?)?.toInt() ?? 0;
    final int checkinCount = (_eventDetails['checkincount'] as num?)?.toInt() ?? 0;
    final int leads = (_eventDetails['leadcaptured'] as num?)?.toInt() ?? 0;
    final leadPerm = _cachedPermissions?['lead_capture_permission'];
    final bool hasLeadPermission = _eventDetails['lead_permission'] != false &&
        (leadPerm == true || leadPerm == 1 || leadPerm == 'true');
    final int badgeIssued = (_eventDetails['badge_issue_count'] as num?)?.toInt() ?? 0;

    final double turnoutRatio = totalReg > 0 ? (totalVisits / totalReg).clamp(0.0, 1.0) : 0.0;
    final String turnoutPercent = totalReg > 0 ? (turnoutRatio * 100).toStringAsFixed(1) : '0.0';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Section Title
        _buildSectionHeader('ATTENDEE METRICS'),
        const SizedBox(height: 10),

        // 1. Hero Event Turnout Overview Card
        _buildHeroTurnoutCard(
          totalReg: totalReg,
          totalVisits: totalVisits,
          turnoutRatio: turnoutRatio,
          turnoutPercent: turnoutPercent,
        ),
        const SizedBox(height: 10),

        // 2. Secondary Metrics 2x2 Grid: Row 1
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _buildSecondaryMetricCard(
                  title: 'Today Visits',
                  count: todayVisits,
                  icon: Icons.today_rounded,
                  onTap: () => _openAttendees('Today Visitors', 'today-visits'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildSecondaryMetricCard(
                  title: 'Checkin Count',
                  count: checkinCount,
                  icon: Icons.how_to_reg_rounded,
                  onTap: () => _openAttendees('Check-in', 'checkin-list'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Secondary Metrics 2x2 Grid: Row 2
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _buildSecondaryMetricCard(
                  title: 'No Shows',
                  count: noShows,
                  icon: Icons.person_off_rounded,
                  onTap: () => _openAttendees('No Shows', 'noshow-list'),
                ),
              ),
              const SizedBox(width: 10),
              if (hasLeadPermission)
                Expanded(
                  child: _buildSecondaryMetricCard(
                    title: 'Leads Captured',
                    count: leads,
                    icon: Icons.contact_mail_rounded,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const LeadsListScreen(isRootTab: false),
                        ),
                      );
                    },
                  ),
                )
              else if (badgeIssued > 0)
                Expanded(
                  child: _buildSecondaryMetricCard(
                    title: 'Badge Issued',
                    count: badgeIssued,
                    icon: Icons.badge_rounded,
                  ),
                )
              else
                const Spacer(),
            ],
          ),
        ),

        // Optional Row 3: Badge Issued (if available and leads permission occupied 4th slot)
        if (badgeIssued > 0 && hasLeadPermission) ...[
          const SizedBox(height: 10),
          _buildGlassCard(
            borderRadius: BorderRadius.circular(14),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppTheme.accentIndigo.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppTheme.accentIndigo.withValues(alpha: 0.22),
                          width: 1,
                        ),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.badge_rounded,
                          color: AppTheme.accentIndigo,
                          size: 17,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Badge Issued',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                Text(
                  badgeIssued.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 19,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ── Hero Turnout Card with Progress Bar ──────────────────────────
  Widget _buildHeroTurnoutCard({
    required int totalReg,
    required int totalVisits,
    required double turnoutRatio,
    required String turnoutPercent,
  }) {
    return _buildGlassCard(
      borderRadius: BorderRadius.circular(16),
      color: AppTheme.accentIndigo.withValues(alpha: 0.08),
      border: Border.all(
        color: AppTheme.accentIndigo.withValues(alpha: 0.24),
        width: 1.2,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Row: Title + Turnout Pill Badge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppTheme.accentIndigo.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.pie_chart_outline_rounded,
                          color: AppTheme.accentIndigo,
                          size: 16,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'ATTENDANCE TURNOUT',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                  decoration: BoxDecoration(
                    color: AppTheme.accentIndigo.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppTheme.accentIndigo.withValues(alpha: 0.32),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 5,
                        height: 5,
                        decoration: const BoxDecoration(
                          color: AppTheme.accentIndigo,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '$turnoutPercent% Turnout',
                        style: const TextStyle(
                          color: Color(0xFFC7D2FE),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Two Hero KPI Pillars: Registrations & Venue Visits
            Row(
              children: [
                // 1. Total Registration
                Expanded(
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      _openAttendees('Total Registration', 'event-register-users');
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                totalReg.toString(),
                                style: const TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: -0.5,
                                  height: 1.1,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 10,
                                color: Colors.white.withValues(alpha: 0.3),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Total Registration',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Vertical Divider
                Container(
                  width: 1,
                  height: 38,
                  color: Colors.white.withValues(alpha: 0.08),
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                ),

                // 2. Total Venue Visits
                Expanded(
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      _openAttendees('Total Unique Visitors', 'totalattendees-list');
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                totalVisits.toString(),
                                style: const TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFFC7D2FE),
                                  letterSpacing: -0.5,
                                  height: 1.1,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 10,
                                color: Colors.white.withValues(alpha: 0.3),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Total Venue Visits',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Turnout Progress Bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Stack(
                children: [
                  Container(
                    height: 6,
                    width: double.infinity,
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                  FractionallySizedBox(
                    widthFactor: turnoutRatio,
                    child: Container(
                      height: 6,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [AppTheme.accentIndigo, Color(0xFF818CF8)],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Live progress ratio
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$totalVisits arrived of $totalReg registered',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.5),
                    fontWeight: FontWeight.w400,
                  ),
                ),
                Text(
                  totalReg >= totalVisits ? '${totalReg - totalVisits} remaining' : '',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.5),
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Secondary 2x2 Metric Card With Contextual Icon Badge ─────────
  Widget _buildSecondaryMetricCard({
    required String title,
    required int count,
    required IconData icon,
    VoidCallback? onTap,
  }) {
    return _buildGlassCard(
      borderRadius: BorderRadius.circular(14),
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap != null
              ? () {
                  HapticFeedback.lightImpact();
                  onTap();
                }
              : null,
          borderRadius: BorderRadius.circular(14),
          splashColor: AppTheme.accentIndigo.withValues(alpha: 0.12),
          highlightColor: AppTheme.accentIndigo.withValues(alpha: 0.06),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: AppTheme.accentIndigo.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppTheme.accentIndigo.withValues(alpha: 0.22),
                          width: 1,
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          icon,
                          size: 16,
                          color: AppTheme.accentIndigo,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 10,
                      color: Colors.white.withValues(alpha: 0.20),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  count.toString(),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.5,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── 4. Quick Action Tiles (Unified with accentIndigo, Clean Minimal) ─
  Widget _buildQuickActionTiles() {
    final hasSpotRegPermission =
        _eventDetails['spot_registration_permission'] != false &&
        _cachedPermissions?['spot_registration_permission'] != false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeader('QUICK ACTIONS'),
        const SizedBox(height: 10),

        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            // Registration Action Tile
            _buildActionTile(
              title: 'Registration',
              icon: Icons.group_rounded,
              onTap: () => _openAttendees('Total Registration', 'event-register-users'),
            ),

            if (hasSpotRegPermission)
              _buildActionTile(
                title: 'Spot Registration',
                icon: Icons.person_add_alt_1_rounded,
                onTap: _openSpotRegistration,
              ),

            // QR Verification
            _buildActionTile(
              title: 'QR Verification',
              icon: Icons.qr_code_scanner_rounded,
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => QrVerificationScreen(
                      eventId: widget.eventId,
                      eventName: _getEventName(),
                      zebraAdapter: widget.zebraAdapter,
                      simulatorAdapter: widget.simulatorAdapter,
                    ),
                  ),
                );
              },
            ),

            // Onsite QR Verification
            _buildActionTile(
              title: 'Onsite QR Verification',
              icon: Icons.confirmation_number_rounded,
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => OnsiteQrVerificationScreen(
                      eventId: widget.eventId,
                      eventName: _getEventName(),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionTile({
    required String title,
    required IconData icon,
    Color color = AppTheme.accentIndigo,
    required VoidCallback onTap,
  }) {
    final width = (MediaQuery.of(context).size.width - 42) / 2;

    final tile = _buildGlassCard(
      borderRadius: BorderRadius.circular(14),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: color.withValues(alpha: 0.22),
                width: 1,
              ),
            ),
            child: Center(
              child: Icon(icon, size: 18, color: color),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              softWrap: true,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
                height: 1.25,
              ),
            ),
          ),
          Icon(
            Icons.arrow_forward_ios_rounded,
            size: 11,
            color: Colors.white.withValues(alpha: 0.22),
          ),
        ],
      ),
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        borderRadius: BorderRadius.circular(14),
        splashColor: color.withValues(alpha: 0.12),
        highlightColor: color.withValues(alpha: 0.06),
        child: SizedBox(
          width: width,
          child: tile,
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 2.8,
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.accentIndigo),
            ),
          ),
          SizedBox(height: 14),
          Text(
            'Loading Event Dashboard...',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
