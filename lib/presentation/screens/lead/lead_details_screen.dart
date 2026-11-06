import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/lead_model.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/lead_repository.dart';
import '../../widgets/fade_in_background_image.dart';
import 'lead_info_screen.dart';

/// Screen displaying comprehensive profile, contact info, ratings, notes,
/// and check-in/out history of a captured lead, styled to match the HomeScreen theme.
class LeadDetailsScreen extends StatefulWidget {
  final int leadId;
  final LeadModel? initialLead;

  const LeadDetailsScreen({super.key, required this.leadId, this.initialLead});

  @override
  State<LeadDetailsScreen> createState() => _LeadDetailsScreenState();
}

class _LeadDetailsScreenState extends State<LeadDetailsScreen> {
  LeadModel? _lead;
  bool _isLoading = false;
  bool _isRefreshing = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _lead = widget.initialLead;
    _fetchDetails();
  }

  Future<void> _fetchDetails({bool silent = false}) async {
    if (_lead == null && !silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    } else if (silent) {
      setState(() => _isRefreshing = true);
    }

    try {
      final repository = context.read<LeadRepository>();
      final freshLead = await repository.getLeadDetails(widget.leadId);

      if (mounted) {
        setState(() {
          if (freshLead != null) {
            _lead = freshLead;
          }
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          if (_lead == null) {
            _errorMessage = e.toString();
          }
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  String? _resolveAvatarUrl(BuildContext context, String? photo) {
    if (photo == null || photo.trim().isEmpty) return null;
    final cleanPhoto = photo.trim();
    if (cleanPhoto.startsWith('http://') || cleanPhoto.startsWith('https://')) {
      return cleanPhoto;
    }
    final mediaUrl = context.read<AuthRepository>().mediaUrl;
    final cleanMedia = mediaUrl.endsWith('/')
        ? mediaUrl.substring(0, mediaUrl.length - 1)
        : mediaUrl;
    final cleanPath = cleanPhoto.startsWith('/') ? cleanPhoto : '/$cleanPhoto';
    return '$cleanMedia$cleanPath';
  }

  Future<void> _makePhoneCall(String? mobile) async {
    if (mobile == null || mobile.trim().isEmpty) return;
    HapticFeedback.lightImpact();
    final clean = mobile.replaceAll(RegExp(r'\s+'), '');
    final uri = Uri.parse('tel:$clean');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open phone dialer for $mobile'),
            backgroundColor: const Color(0xFFFF5252),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _sendEmail(String? email) async {
    if (email == null || email.trim().isEmpty) return;
    HapticFeedback.lightImpact();
    final uri = Uri.parse('mailto:${email.trim()}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open email client for $email'),
            backgroundColor: const Color(0xFFFF5252),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
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

  Future<void> _navigateToEdit() async {
    if (_lead == null) return;
    HapticFeedback.lightImpact();
    final updatedLead = await Navigator.push<LeadModel>(
      context,
      MaterialPageRoute(builder: (_) => LeadInfoScreen(lead: _lead!)),
    );

    if (updatedLead != null && mounted) {
      setState(() {
        _lead = updatedLead;
      });
      _fetchDetails(silent: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lead = _lead;
    final eventSubtitle = lead?.eventName != null && lead!.eventName!.isNotEmpty
        ? lead.eventName!
        : 'Lead Profile';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pop(_lead);
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Base background image with hardware-accelerated fade-in entrance
            Positioned.fill(
              child: const FadeInBackgroundImage(
                imagePath: 'assets/images/bg.png',
                duration: Duration(milliseconds: 800),
                curve: Curves.easeOutCubic,
              ),
            ),

            // 2. Multi-point Aurora Glow Orbs for ambient depth (matching theme)
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
                        AppTheme.accentIndigo.withValues(alpha: 0.15),
                        const Color(0xFF4F46E5).withValues(alpha: 0.06),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.45, 1.0],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 120,
              left: -80,
              child: IgnorePointer(
                child: Container(
                  width: 290,
                  height: 290,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppTheme.accentIndigo.withValues(alpha: 0.12),
                        const Color(0xFF312E81).withValues(alpha: 0.05),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.45, 1.0],
                    ),
                  ),
                ),
              ),
            ),

            // 3. Subtle contrast & depth overlay
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppTheme.background.withValues(alpha: 0.65),
                        AppTheme.background.withValues(alpha: 0.50),
                        AppTheme.background.withValues(alpha: 0.85),
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
                  _buildTopBar(lead?.fullName ?? 'Lead Details', eventSubtitle),
                  Expanded(
                    child: _isLoading && lead == null
                        ? _buildLoadingState()
                        : _errorMessage != null && lead == null
                        ? _buildErrorState()
                        : RefreshIndicator(
                            onRefresh: () => _fetchDetails(silent: true),
                            color: AppTheme.accentIndigo,
                            backgroundColor: AppTheme.surfaceElevated,
                            child: SingleChildScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // 1. Hero Profile Card
                                  _buildHeroCard(lead!),
                                  const SizedBox(height: 12),

                                  // 2. High-contrast Quick Action Buttons
                                  _buildContactActions(lead),
                                  const SizedBox(height: 12),

                                  // 3. Lead Notes & Rating Card
                                  _buildNotesCard(lead),
                                  const SizedBox(height: 12),

                                  // 4. Attendee Details Information Card
                                  _buildInformationCard(lead),
                                  const SizedBox(height: 12),

                                  // 5. Check-In & Punch History Logs
                                  if (lead.checkinHistory != null &&
                                      lead.checkinHistory!.isNotEmpty)
                                    _buildHistorySection(lead),

                                  const SizedBox(height: 36),
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
      ),
    );
  }

  // ── Top Bar ────────────────────────────────────────────────────────
  Widget _buildTopBar(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // Circular Back Button
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.of(context).pop(_lead);
              },
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                    width: 1.0,
                  ),
                ),
                child: const Center(
                  child: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    size: 16,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Title & Event Subtitle
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
                    color: AppTheme.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(
                      Icons.event_note_rounded,
                      size: 12,
                      color: AppTheme.accentIndigo,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Top Right Action Buttons
          if (_lead != null) ...[
            // Edit Note / Rating Button
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _navigateToEdit,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.accentIndigo.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.accentIndigo.withValues(alpha: 0.25),
                      width: 1.0,
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.edit_note_rounded,
                        color: AppTheme.accentIndigo,
                        size: 18,
                      ),
                      SizedBox(width: 5),
                      Text(
                        'Edit',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Refresh Button
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _isRefreshing
                    ? null
                    : () {
                        HapticFeedback.lightImpact();
                        _fetchDetails(silent: true);
                      },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.1),
                      width: 1.0,
                    ),
                  ),
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
                            Icons.sync_rounded,
                            color: AppTheme.textSecondary,
                            size: 18,
                          ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Hero Profile Card ──────────────────────────────────────────────
  Widget _buildHeroCard(LeadModel lead) {
    final photoUrl = _resolveAvatarUrl(context, lead.photo);
    final (typeColor, typeBg, typeBorder, typeIcon, typeLabel) =
        _getLeadTypeProps(lead.leadType);

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Top accent gradient bar
          Container(
            height: 3,
            decoration: const BoxDecoration(
              gradient: AppTheme.indigoGradient,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Column(
              children: [
                // Top Row: Lead ID pill (left) + Lead Quality Badge (right)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3.5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
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
                              color: AppTheme.statusSuccess,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'LEAD #${lead.id}',
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Lead Quality Badge (HOT / WARM / COLD)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3.5,
                      ),
                      decoration: BoxDecoration(
                        color: typeBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: typeBorder, width: 0.8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(typeIcon, color: typeColor, size: 11),
                          const SizedBox(width: 4),
                          Text(
                            '$typeLabel LEAD',
                            style: TextStyle(
                              color: typeColor,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Clean Circular Avatar with Indigo Ambient Glow
                Container(
                  width: 86,
                  height: 86,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: photoUrl != null
                          ? Colors.white.withValues(alpha: 0.15)
                          : AppTheme.accentIndigo.withValues(alpha: 0.4),
                      width: 2.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.accentIndigo.withValues(alpha: 0.18),
                        blurRadius: 14,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: photoUrl != null
                        ? Image.network(
                            photoUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                _buildInitialsAvatar(lead),
                          )
                        : _buildInitialsAvatar(lead),
                  ),
                ),
                const SizedBox(height: 14),

                // Full Name
                Text(
                  lead.fullName.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                    height: 1.25,
                  ),
                ),

                // Designation
                if (lead.designation != null &&
                    lead.designation!.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    lead.designation!.trim().toUpperCase(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppTheme.accentIndigo,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],

                // Company Name
                if (lead.companyName != null &&
                    lead.companyName!.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.business_rounded,
                        color: AppTheme.textMuted,
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          lead.companyName!.trim(),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 12),

                // Metadata Pills Row (Ticket Category & Badge ID)
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    // Ticket Type Pill
                    if (lead.ticketType != null &&
                        lead.ticketType!.trim().isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08),
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
                                color: AppTheme.statusSuccess,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              lead.ticketType!.trim().toUpperCase(),
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Badge ID Pill (with copy tap)
                    if (lead.uniqueId.isNotEmpty)
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () =>
                              _copyToClipboard(lead.uniqueId, 'Badge ID'),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.accentIndigo.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: AppTheme.accentIndigo.withValues(alpha: 0.25),
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.qr_code_rounded,
                                  color: AppTheme.accentIndigo,
                                  size: 13,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  lead.uniqueId,
                                  style: const TextStyle(
                                    color: AppTheme.accentIndigo,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.copy_rounded,
                                  color: AppTheme.textMuted,
                                  size: 11,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInitialsAvatar(LeadModel lead) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.accentIndigo.withValues(alpha: 0.28),
            AppTheme.accentIndigo.withValues(alpha: 0.10),
          ],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        lead.initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 30,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  // ── Unified Tactile Quick Action Buttons ───────────────────────────
  Widget _buildContactActions(LeadModel lead) {
    final hasMobile = lead.mobile != null && lead.mobile!.trim().isNotEmpty;
    final hasEmail = lead.email != null && lead.email!.trim().isNotEmpty;

    return Row(
      children: [
        // CALL BUTTON
        if (hasMobile)
          Expanded(
            child: _buildActionButton(
              label: 'CALL',
              icon: Icons.phone_rounded,
              onTap: () => _makePhoneCall(lead.mobile),
            ),
          ),

        if (hasMobile && (hasEmail || true)) const SizedBox(width: 8),

        // EMAIL BUTTON
        if (hasEmail)
          Expanded(
            child: _buildActionButton(
              label: 'EMAIL',
              icon: Icons.email_rounded,
              onTap: () => _sendEmail(lead.email),
            ),
          ),

        if (hasEmail) const SizedBox(width: 8),

        // RATE & NOTE BUTTON
        Expanded(
          child: _buildActionButton(
            label: 'RATE / NOTE',
            icon: Icons.rate_review_rounded,
            onTap: _navigateToEdit,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        borderRadius: BorderRadius.circular(12),
        splashColor: AppTheme.accentIndigo.withValues(alpha: 0.08),
        highlightColor: AppTheme.accentIndigo.withValues(alpha: 0.04),
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: AppTheme.surfaceElevated.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
              width: 1.0,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: AppTheme.accentIndigo),
              const SizedBox(width: 6),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 11.5,
                      letterSpacing: 0.3,
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

  // ── Lead Notes & Rating Assessment Card ───────────────────────────
  Widget _buildNotesCard(LeadModel lead) {
    final hasNotes = lead.notes != null && lead.notes!.trim().isNotEmpty;
    final (typeColor, typeBg, typeBorder, typeIcon, typeLabel) =
        _getLeadTypeProps(lead.leadType);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Header
          Row(
            children: [
              Container(
                width: 3.5,
                height: 14,
                decoration: BoxDecoration(
                  gradient: AppTheme.indigoGradient,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'LEAD ASSESSMENT & NOTES',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
              const Spacer(),
              // Edit button
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _navigateToEdit,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.accentIndigo.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppTheme.accentIndigo.withValues(alpha: 0.25),
                        width: 0.8,
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'EDIT',
                          style: TextStyle(
                            color: AppTheme.accentIndigo,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                        SizedBox(width: 4),
                        Icon(
                          Icons.edit_rounded,
                          size: 11,
                          color: AppTheme.accentIndigo,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Rating Status Indicator Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.07),
                width: 0.8,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text(
                    'Lead Quality',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 3.5,
                  ),
                  decoration: BoxDecoration(
                    color: typeBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: typeBorder, width: 0.8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(typeIcon, color: typeColor, size: 12),
                      const SizedBox(width: 5),
                      Text(
                        '$typeLabel LEAD',
                        style: TextStyle(
                          color: typeColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Notes Content Box
          if (hasNotes)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.07),
                  width: 0.8,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.format_quote_rounded,
                        size: 16,
                        color: AppTheme.accentIndigo,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Captured Note:',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    lead.notes!.trim(),
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 13.5,
                      height: 1.45,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            )
          else
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _navigateToEdit,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    vertical: 18,
                    horizontal: 14,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.02),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.07),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_comment_rounded,
                        color: AppTheme.accentIndigo,
                        size: 17,
                      ),
                      SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'No notes added yet. Tap to add notes.',
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Attendee Information Card ──────────────────────────────────────
  Widget _buildInformationCard(LeadModel lead) {
    final infoItems = <(IconData, String, String?, VoidCallback?)>[
      if (lead.email != null && lead.email!.trim().isNotEmpty)
        (
          Icons.email_outlined,
          'Email',
          lead.email!.trim(),
          () => _sendEmail(lead.email),
        ),
      if (lead.mobile != null && lead.mobile!.trim().isNotEmpty)
        (
          Icons.phone_outlined,
          'Mobile',
          lead.mobile!.trim(),
          () => _makePhoneCall(lead.mobile),
        ),
      if (lead.department != null && lead.department!.trim().isNotEmpty)
        (Icons.domain_rounded, 'Department', lead.department!.trim(), null),
      if (lead.city != null &&
          lead.city!.trim().isNotEmpty &&
          lead.city!.toLowerCase() != 'n/a')
        (Icons.location_city_rounded, 'City', lead.city!.trim(), null),
      if (lead.country != null && lead.country!.trim().isNotEmpty)
        (Icons.public_rounded, 'Country', lead.country!.trim(), null),
      if (lead.uniqueId.isNotEmpty)
        (
          Icons.qr_code_2_rounded,
          'Badge ID / URN',
          lead.uniqueId,
          () => _copyToClipboard(lead.uniqueId, 'Badge ID'),
        ),
      if (lead.eventName != null && lead.eventName!.trim().isNotEmpty)
        (Icons.event_available_rounded, 'Event', lead.eventName!.trim(), null),
    ];

    if (infoItems.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 3.5,
                height: 14,
                decoration: BoxDecoration(
                  gradient: AppTheme.indigoGradient,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'ATTENDEE INFORMATION',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (int i = 0; i < infoItems.length; i++) ...[
            if (i > 0)
              Divider(
                color: Colors.white.withValues(alpha: 0.06),
                height: 16,
                thickness: 0.8,
              ),
            _buildInfoRow(
              icon: infoItems[i].$1,
              label: infoItems[i].$2,
              value: infoItems[i].$3 ?? '',
              onTap: infoItems[i].$4,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    VoidCallback? onTap,
  }) {
    final rowContent = Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.textMuted, size: 17),
          const SizedBox(width: 12),
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: onTap != null ? AppTheme.accentIndigo : AppTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 6),
            const Icon(
              Icons.open_in_new_rounded,
              color: AppTheme.accentIndigo,
              size: 13,
            ),
          ],
        ],
      ),
    );

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          splashColor: AppTheme.accentIndigo.withValues(alpha: 0.08),
          highlightColor: AppTheme.accentIndigo.withValues(alpha: 0.04),
          child: rowContent,
        ),
      );
    }
    return rowContent;
  }

  // ── Check-In History Section ───────────────────────────────────────
  Widget _buildHistorySection(LeadModel lead) {
    final historyList = lead.checkinHistory!;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 3.5,
                height: 14,
                decoration: BoxDecoration(
                  color: AppTheme.statusSuccess,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'CHECK-IN & OUT HISTORY',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2.5,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.statusSuccess.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppTheme.statusSuccess.withValues(alpha: 0.25),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  '${historyList.length} ${historyList.length == 1 ? 'RECORD' : 'RECORDS'}',
                  style: const TextStyle(
                    color: AppTheme.statusSuccess,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (int i = 0; i < historyList.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _buildHistoryItem(historyList[i], index: historyList.length - i),
          ],
        ],
      ),
    );
  }

  Widget _buildHistoryItem(dynamic item, {required int index}) {
    if (item is! Map) return const SizedBox.shrink();

    final checkInDt = item['main_check_in_dt']?.toString();
    final checkInTm = item['main_check_in_tm']?.toString();
    final checkOutDt = item['main_check_out_dt']?.toString();
    final checkOutTm = item['main_check_out_tm']?.toString();

    final formattedIn = _formatDateTime(checkInDt, checkInTm);
    final hasCheckOut = checkOutTm != null && checkOutTm.trim().isNotEmpty;
    final formattedOut = hasCheckOut
        ? _formatDateTime(checkOutDt, checkOutTm)
        : null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.07),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Visit Header Bar
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: hasCheckOut
                      ? AppTheme.textMuted
                      : AppTheme.statusSuccess,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'VISIT #$index',
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              if (!hasCheckOut)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.statusSuccess.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: AppTheme.statusSuccess.withValues(alpha: 0.3),
                      width: 0.8,
                    ),
                  ),
                  child: const Text(
                    'IN VENUE',
                    style: TextStyle(
                      color: AppTheme.statusSuccess,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // In & Out Columns
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // CHECK-IN
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 3,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppTheme.statusSuccess,
                        borderRadius: BorderRadius.circular(1.5),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.login_rounded,
                                color: AppTheme.statusSuccess,
                                size: 13,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'CHECK-IN',
                                style: TextStyle(
                                  color: AppTheme.statusSuccess,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            formattedIn,
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Divider
              Container(
                height: 36,
                width: 1,
                color: Colors.white.withValues(alpha: 0.08),
                margin: const EdgeInsets.symmetric(horizontal: 10),
              ),

              // CHECK-OUT
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 3,
                      height: 32,
                      decoration: BoxDecoration(
                        color: hasCheckOut
                            ? AppTheme.statusRejected
                            : AppTheme.textMuted,
                        borderRadius: BorderRadius.circular(1.5),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.logout_rounded,
                                color: hasCheckOut
                                    ? AppTheme.statusRejected
                                    : AppTheme.textMuted,
                                size: 13,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'CHECK-OUT',
                                style: TextStyle(
                                  color: hasCheckOut
                                      ? AppTheme.statusRejected
                                      : AppTheme.textMuted,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            formattedOut ?? 'Active',
                            style: TextStyle(
                              color: hasCheckOut
                                  ? AppTheme.textPrimary
                                  : AppTheme.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Loading & Error States ─────────────────────────────────────────
  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.surfaceElevated.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: const CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.accentIndigo),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Loading lead details...',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppTheme.surfaceElevated.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: AppTheme.statusRejected.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.error_outline_rounded,
                  size: 28,
                  color: AppTheme.statusRejected,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Unable to load lead details',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage ?? 'Something went wrong.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: () => _fetchDetails(),
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text(
                  'Try Again',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentIndigo,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Helper Utilities ───────────────────────────────────────────────
  String _formatDateTime(String? dateStr, String? timeStr) {
    if (dateStr == null && timeStr == null) return 'TBA';
    try {
      DateTime? dt;
      if (dateStr != null && dateStr.isNotEmpty) {
        dt = DateTime.tryParse(dateStr);
      }
      final dateFormatted = dt != null
          ? DateFormat('MMM dd, yyyy').format(dt)
          : (dateStr ?? '');

      if (timeStr != null && timeStr.isNotEmpty) {
        final parts = timeStr.split(':');
        if (parts.length >= 2) {
          final hour = int.tryParse(parts[0]) ?? 0;
          final min = int.tryParse(parts[1]) ?? 0;
          final tod = TimeOfDay(hour: hour, minute: min);
          final now = DateTime.now();
          final timeDt = DateTime(
            now.year,
            now.month,
            now.day,
            tod.hour,
            tod.minute,
          );
          final timeFormatted = DateFormat('hh:mm a').format(timeDt);
          return '$dateFormatted • $timeFormatted';
        }
      }
      return dateFormatted;
    } catch (_) {
      return '${dateStr ?? ''} ${timeStr ?? ''}'.trim();
    }
  }

  (Color, Color, Color, IconData, String) _getLeadTypeProps(String type) {
    switch (type.toUpperCase()) {
      case 'HOT':
        return (
          const Color(0xFFF87171),
          const Color(0xFFEF4444).withValues(alpha: 0.12),
          const Color(0xFFEF4444).withValues(alpha: 0.28),
          Icons.local_fire_department_rounded,
          'HOT',
        );
      case 'WARM':
        return (
          const Color(0xFFFBBF24),
          const Color(0xFFF59E0B).withValues(alpha: 0.12),
          const Color(0xFFF59E0B).withValues(alpha: 0.28),
          Icons.wb_sunny_rounded,
          'WARM',
        );
      case 'COLD':
      default:
        return (
          const Color(0xFF60A5FA),
          const Color(0xFF3B82F6).withValues(alpha: 0.12),
          const Color(0xFF3B82F6).withValues(alpha: 0.28),
          Icons.ac_unit_rounded,
          'COLD',
        );
    }
  }
}
