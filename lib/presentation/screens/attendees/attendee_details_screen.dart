import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/attendee_details_model.dart';
import '../../../data/repositories/attendee_repository.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../widgets/attendee_history_widgets.dart';
import '../../widgets/fade_in_background_image.dart';

/// Screen displaying complete Attendee Profile, Ticket/Booking details,
/// and Entrance, Hall, and Agenda Attendance History logs matching `AttendeesDetails.jsx`.
class AttendeeDetailsScreen extends StatefulWidget {
  final int attendeeId;
  final String? eventName;
  final AttendeeDetailsModel? initialDetails;

  const AttendeeDetailsScreen({
    super.key,
    required this.attendeeId,
    this.eventName,
    this.initialDetails,
  });

  @override
  State<AttendeeDetailsScreen> createState() => _AttendeeDetailsScreenState();
}

class _AttendeeDetailsScreenState extends State<AttendeeDetailsScreen> {
  AttendeeDetailsModel? _details;
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _details = widget.initialDetails;
    if (_details != null) {
      _isLoading = false;
    }
    _loadAttendeeDetails();
  }

  /// Resolve full image URL from relative path using AuthRepository mediaUrl
  String? _resolveImageUrl(String? path) {
    if (path == null || path.trim().isEmpty) return null;
    final clean = path.trim();
    if (clean.startsWith('http://') || clean.startsWith('https://')) return clean;

    try {
      final authRepo = context.read<AuthRepository>();
      final baseUrl = authRepo.mediaUrl;
      final cleanBase = baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl;
      final cleanPath = clean.startsWith('/') ? clean : '/$clean';
      return '$cleanBase$cleanPath';
    } catch (_) {
      return clean;
    }
  }

  Future<void> _loadAttendeeDetails({bool silent = false}) async {
    if (!silent && _details == null) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    } else {
      setState(() => _isRefreshing = true);
    }

    try {
      final repository = context.read<AttendeeRepository>();
      final fresh = await repository.getAttendeeDetails(widget.attendeeId);

      if (mounted) {
        setState(() {
          if (fresh != null) {
            _details = fresh;
          }
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    } catch (e) {
      debugPrint('[AttendeeDetailsScreen] Error loading attendee details: $e');
      if (mounted) {
        setState(() {
          if (_details == null) {
            _errorMessage = 'Unable to load attendee details. Please try again.';
          }
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  Future<void> _launchUrlString(String url) async {
    if (url.trim().isEmpty) return;
    try {
      final uri = Uri.parse(url.trim());
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  void _copyToClipboard(String text, String label) {
    HapticFeedback.lightImpact();
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        duration: const Duration(seconds: 2),
        backgroundColor: const Color(0xFF1E293B),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Color _getStatusTextColor(String? value) {
    if (value == null) return Colors.white;
    final lower = value.toLowerCase().trim();
    if (lower == 'confirmed' || lower == 'issued' || lower == 'paid') {
      return const Color(0xFF34D399); // Green
    }
    if (lower == 'cancelled' || lower == 'not issued' || lower == 'rejected') {
      return const Color(0xFFF87171); // Red
    }
    return Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    final effectiveEventName = _details?.eventName ?? widget.eventName ?? 'EventXPro';
    final fullName = _details?.fullName ?? 'Attendee Details';

    return Scaffold(
      backgroundColor: AppTheme.eventxproBg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background pattern with fade-in entrance
          Positioned.fill(
            child: const FadeInBackgroundImage(
              imagePath: 'assets/images/bg.png',
              duration: Duration(milliseconds: 800),
              curve: Curves.easeOutCubic,
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF131722).withValues(alpha: 0.35),
                    AppTheme.eventxproBg.withValues(alpha: 0.15),
                    const Color(0xFF0D111A).withValues(alpha: 0.65),
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // Top App Bar matching NewTopBarMain.jsx
                _buildTopBar(fullName, effectiveEventName),

                Expanded(
                  child: RefreshIndicator(
                    color: AppTheme.eventxproAccent,
                    backgroundColor: AppTheme.surfaceElevated,
                    onRefresh: () => _loadAttendeeDetails(silent: true),
                    child: _isLoading
                        ? _buildLoadingState()
                        : _errorMessage != null
                            ? _buildErrorState()
                            : SingleChildScrollView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    // 1. Hero Header Banner with Avatar
                                    _buildHeroBanner(),
                                    const SizedBox(height: 16),

                                    // 2. Profile Summary & Social Links
                                    _buildProfileSection(),
                                    const SizedBox(height: 16),

                                    // 3. Information Card (Designation, Company, Country, URN, etc.)
                                    _buildInformationCard(),
                                    const SizedBox(height: 12),

                                    // 4. Entrance Attendance History
                                    if (_details != null && _details!.entranceHistory.isNotEmpty)
                                      EntranceHistoryWidget(data: _details!.entranceHistory),

                                    // 5. Hall Attendance History
                                    if (_details != null && _details!.hallHistory.isNotEmpty)
                                      HallHistoryWidget(data: _details!.hallHistory),

                                    // 6. Agenda Attendance History
                                    if (_details != null && _details!.agendaHistory.isNotEmpty)
                                      AgendaHistoryWidget(data: _details!.agendaHistory),

                                    // Fallback if attendee has no punch history at all
                                    if (_details != null &&
                                        _details!.entranceHistory.isEmpty &&
                                        _details!.hallHistory.isEmpty &&
                                        _details!.agendaHistory.isEmpty)
                                      _buildNoHistoryPlaceholder(),

                                    const SizedBox(height: 40),
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
  Widget _buildTopBar(String title, String subtitle) {
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
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16.5,
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
                        subtitle,
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

          // Refresh Button
          IconButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              _loadAttendeeDetails(silent: false);
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
            tooltip: 'Refresh',
          ),
        ],
      ),
    );
  }

  // ── 1. Hero Banner with Circular Avatar Ring ─────────────────────
  Widget _buildHeroBanner() {
    final photoUrl = _resolveImageUrl(_details?.photoUrl);
    final initials = _details?.initials ?? 'P';

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.bottomCenter,
      children: [
        // Hero Background Card
        Container(
          height: 115,
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF2E0854),
                Color(0xFF1E1B4B),
                Color(0xFF111827),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                right: -20,
                bottom: -20,
                child: Icon(
                  Icons.badge_rounded,
                  size: 120,
                  color: Colors.white.withValues(alpha: 0.05),
                ),
              ),
            ],
          ),
        ),

        // Circular Avatar with Ring
        Positioned(
          bottom: -40,
          child: Container(
            width: 86,
            height: 86,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.eventxproBg,
              border: Border.all(color: Colors.white, width: 3.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipOval(
              child: photoUrl != null && photoUrl.isNotEmpty
                  ? Image.network(
                      photoUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          _buildAvatarInitials(initials),
                    )
                  : _buildAvatarInitials(initials),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAvatarInitials(String initials) {
    return Container(
      color: const Color(0xFFC10067),
      child: Center(
        child: Text(
          initials,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  // ── 2. Profile Summary & Social Links ────────────────────────────
  Widget _buildProfileSection() {
    final name = _details?.fullName ?? 'Attendee';
    final designation = _details?.designation;
    final company = _details?.companyName;
    final socialLinks = _details?.socialLinks ?? [];
    final isAllowed = _details?.isDetailsAllowed ?? true;

    return Container(
      margin: const EdgeInsets.only(top: 36),
      child: Column(
        children: [
          // Name
          Text(
            name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 4),

          // Designation
          if (designation != null && designation.isNotEmpty) ...[
            Text(
              designation.toUpperCase(),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 2),
          ],

          // Company
          if (company != null && company.isNotEmpty) ...[
            Text(
              company,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
          ],

          // Social Links (if allowed)
          if (isAllowed && socialLinks.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              children: socialLinks.map((s) => _buildSocialIcon(s)).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSocialIcon(SocialLinkItem item) {
    IconData icon;
    Color color;

    switch (item.type.toLowerCase()) {
      case 'twitter':
        icon = Icons.flutter_dash;
        color = const Color(0xFF38BDF8);
        break;
      case 'linkedin':
        icon = Icons.business_center_rounded;
        color = const Color(0xFF0A66C2);
        break;
      case 'facebook':
        icon = Icons.facebook_rounded;
        color = const Color(0xFF1877F2);
        break;
      case 'instagram':
        icon = Icons.camera_alt_rounded;
        color = const Color(0xFFE4405F);
        break;
      default:
        icon = Icons.link_rounded;
        color = Colors.white70;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _launchUrlString(item.url),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }

  // ── 3. Information Section Card ──────────────────────────────────
  Widget _buildInformationCard() {
    final d = _details;
    if (d == null) return const SizedBox.shrink();

    final isDetails = d.isDetailsAllowed;

    final infoItems = <(String, String?, Color, VoidCallback?)>[
      if (d.designation != null && d.designation!.isNotEmpty)
        ('Designation', d.designation!.toUpperCase(), Colors.white, null),
      if (d.companyName != null && d.companyName!.isNotEmpty)
        ('Company', d.companyName, Colors.white, null),
      if (d.country != null && d.country!.isNotEmpty)
        ('Country', d.country, Colors.white, null),
      if (d.uniqueId != null && d.uniqueId!.isNotEmpty)
        (
          'URN / Ticket Code',
          d.uniqueId,
          const Color(0xFF38BDF8),
          () => _copyToClipboard(d.uniqueId!, 'URN'),
        ),
      if (d.ticketName != null && d.ticketName!.isNotEmpty)
        ('Ticket Category', d.ticketName, Colors.white, null),
      if (d.paidStatus != null && d.paidStatus!.isNotEmpty)
        (
          'Paid Status',
          d.paidStatus,
          _getStatusTextColor(d.paidStatus),
          null,
        ),
      if (d.digitalBadgeIssue != null)
        (
          'Digital Badge',
          d.digitalBadgeIssue == true ? 'Issued' : 'Not Issued',
          _getStatusTextColor(d.digitalBadgeIssue == true ? 'issued' : 'not issued'),
          null,
        ),
      if (d.badgeIssue != null)
        (
          'Physical Badge',
          d.badgeIssue == true ? 'Issued' : 'Not Issued',
          _getStatusTextColor(d.badgeIssue == true ? 'issued' : 'not issued'),
          null,
        ),
      if (d.bookingStatus != null && d.bookingStatus!.isNotEmpty)
        (
          'Booking Status',
          d.bookingStatus,
          _getStatusTextColor(d.bookingStatus),
          null,
        ),
      if (isDetails && d.email != null && d.email!.isNotEmpty)
        (
          'Email',
          d.email,
          const Color(0xFF38BDF8),
          () => _launchUrlString('mailto:${d.email}'),
        ),
      if (isDetails && d.mobile != null && d.mobile!.isNotEmpty)
        (
          'Phone',
          d.mobile,
          const Color(0xFF38BDF8),
          () => _launchUrlString('tel:${d.mobile}'),
        ),
    ];

    if (infoItems.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                'INFORMATION',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.7,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          for (int i = 0; i < infoItems.length; i++) ...[
            if (i > 0)
              Divider(
                color: Colors.white.withValues(alpha: 0.08),
                height: 16,
              ),
            _buildInfoRow(
              label: infoItems[i].$1,
              value: infoItems[i].$2 ?? '',
              valueColor: infoItems[i].$3,
              onTap: infoItems[i].$4,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required String label,
    required String value,
    required Color valueColor,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 16),
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      value,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: valueColor,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        decoration: onTap != null ? TextDecoration.underline : null,
                      ),
                    ),
                  ),
                  if (onTap != null) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.open_in_new_rounded, size: 12, color: valueColor),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoHistoryPlaceholder() {
    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.history_toggle_off_rounded,
            size: 40,
            color: Colors.white.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 10),
          const Text(
            'No attendance history recorded yet',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Scans at entrances, halls, and sessions will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 11.5,
            ),
          ),
        ],
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
            'Loading Attendee Details & History...',
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

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: Color(0xFFF87171),
              size: 44,
            ),
            const SizedBox(height: 12),
            Text(
              _errorMessage ?? 'Failed to load attendee',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _loadAttendeeDetails(silent: false),
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.brandGradientStart,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
