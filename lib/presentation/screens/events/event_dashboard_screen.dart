import 'dart:convert';
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
                    color: AppTheme.eventxproAccent,
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

  // ── Top Header / App Bar ─────────────────────────────────────────
  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // Circular Back Button matching EventTopBar.jsx
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.of(context).pop();
              },
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    size: 14,
                    color: Color(0xFF131722),
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
                const Text(
                  'Event Home',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(
                      Icons.event_note_rounded,
                      size: 11,
                      color: AppTheme.brandGradientStart,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        _getEventName(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.65),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Refresh Icon
          IconButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              _loadDashboardData(silent: false);
            },
            icon: _isRefreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(
                    Icons.refresh_rounded,
                    color: Colors.white70,
                    size: 20,
                  ),
            tooltip: 'Refresh Dashboard',
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
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 14,
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
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 8),

                // Date Chip
                if (startDate.isNotEmpty || endDate.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.calendar_today_rounded,
                          size: 11,
                          color: AppTheme.brandGradientStart,
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
                      gradient: AppTheme.brandGradient,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.brandGradientStart.withValues(alpha: 0.4),
                          blurRadius: 8,
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

  // ── 2. Prominent Check-In / Check-Out Banner Card ────────────────
  Widget _buildCheckInOutBanner() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _openCheckInOutSessions,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF10B981).withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF10B981).withValues(alpha: 0.15),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.25),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Icon(
                    Icons.qr_code_2_rounded,
                    color: Color(0xFF34D399),
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Check-In / Check-Out',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.3,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Scan attendees at entrances, halls & sessions',
                      style: TextStyle(
                        color: Color(0xFFD1FAE5),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: Color(0xFF34D399),
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 3. Metrics Section Grid ──────────────────────────────────────
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Section Title
        Row(
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
              'ATTENDEE METRICS',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.7,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Row 1: Total Registration, Total Venue Visits, No Shows
        Row(
          children: [
            Expanded(
              child: _buildMetricTile(
                title: 'Total Registration',
                count: totalReg,
                countColor: const Color(0xFFFACC15), // Gold #D2C442
                onTap: () => _openAttendees('Total Registration', 'event-register-users'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildMetricTile(
                title: 'Total Venue Visits',
                count: totalVisits,
                countColor: const Color(0xFF6EE7B7), // Mint Green #8DFFBB
                onTap: () => _openAttendees('Total Unique Visitors', 'totalattendees-list'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildMetricTile(
                title: 'No Shows',
                count: noShows,
                countColor: const Color(0xFFF87171), // Coral Red #FF9292
                onTap: () => _openAttendees('No Shows', 'noshow-list'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Row 2: Today Visits, Checkin Count, and Leads (if active)
        Row(
          children: [
            Expanded(
              child: _buildMetricTile(
                title: 'Today Visits',
                count: todayVisits,
                countColor: const Color(0xFF6EE7B7),
                onTap: () => _openAttendees('Today Visitors', 'today-visits'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildMetricTile(
                title: 'Checkin Count',
                count: checkinCount,
                countColor: const Color(0xFF6EE7B7),
                onTap: () => _openAttendees('Check-in', 'checkin-list'),
              ),
            ),
            if (hasLeadPermission) ...[
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricTile(
                  title: 'Leads Captured',
                  count: leads,
                  countColor: const Color(0xFF6EE7B7),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const LeadsListScreen(isRootTab: false),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),

        // Row 3: Badge Issued (if available)
        if (badgeIssued > 0) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.badge_rounded, color: Colors.white, size: 20),
                    SizedBox(width: 10),
                    Text(
                      'Badge Issued :',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
                Text(
                  badgeIssued.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMetricTile({
    required String title,
    required int count,
    required Color countColor,
    VoidCallback? onTap,
  }) {
    final tile = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            count.toString(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: countColor,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1.2,
            ),
          ),
        ],
      ),
    );

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          borderRadius: BorderRadius.circular(10),
          child: tile,
        ),
      );
    }
    return tile;
  }

  // ── 4. Quick Action Tiles (matching Tiles.jsx) ───────────────────
  Widget _buildQuickActionTiles() {
    final leadPerm = _cachedPermissions?['lead_capture_permission'];
    final hasLeadPermission = _eventDetails['lead_permission'] != false &&
        (leadPerm == true || leadPerm == 1 || leadPerm == 'true');
    final hasSpotRegPermission =
        _eventDetails['spot_registration_permission'] != false &&
        _cachedPermissions?['spot_registration_permission'] != false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
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
              'QUICK ACTIONS',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.7,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            // Registration Action Tile
            _buildActionTile(
              title: 'Registration',
              icon: Icons.group_rounded,
              color: AppTheme.brandGradientStart,
              onTap: () => _openAttendees('Total Registration', 'event-register-users'),
            ),

            if (hasSpotRegPermission)
              _buildActionTile(
                title: 'Spot Registration',
                icon: Icons.person_add_alt_1_rounded,
                color: const Color(0xFFF59E0B),
                onTap: _openSpotRegistration,
              ),

            // Leads Tile (if lead permission is active)
            if (hasLeadPermission)
              _buildActionTile(
                title: 'Event Leads',
                icon: Icons.badge_rounded,
                color: const Color(0xFF10B981),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const LeadsListScreen(isRootTab: false),
                    ),
                  );
                },
              ),

            // QR Verification
            _buildActionTile(
              title: 'QR Verification',
              icon: Icons.qr_code_scanner_rounded,
              color: const Color(0xFFA855F7),
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
              color: const Color(0xFF06B6D4),
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
    required Color color,
    required VoidCallback onTap,
  }) {
    final width = (MediaQuery.of(context).size.width - 42) / 2;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: width,
          constraints: const BoxConstraints(minHeight: 58),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.06),
              width: 1.0,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  softWrap: true,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
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
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.eventxproAccent),
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
