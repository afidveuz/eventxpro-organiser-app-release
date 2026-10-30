import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/lead_model.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/lead_repository.dart';
import 'lead_info_screen.dart';

/// Screen displaying comprehensive profile, contact info, ratings, notes,
/// and check-in/out history of a captured lead.
class LeadDetailsScreen extends StatefulWidget {
  final int leadId;
  final LeadModel? initialLead;

  const LeadDetailsScreen({
    super.key,
    required this.leadId,
    this.initialLead,
  });

  @override
  State<LeadDetailsScreen> createState() => _LeadDetailsScreenState();
}

class _LeadDetailsScreenState extends State<LeadDetailsScreen> {
  LeadModel? _lead;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _lead = widget.initialLead;
    _fetchDetails();
  }

  Future<void> _fetchDetails() async {
    if (_lead == null) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
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
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
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
    final clean = mobile.replaceAll(RegExp(r'\s+'), '');
    final uri = Uri.parse('tel:$clean');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open phone dialer for $mobile'),
            backgroundColor: AppTheme.statusRejected,
          ),
        );
      }
    }
  }

  Future<void> _sendEmail(String? email) async {
    if (email == null || email.trim().isEmpty) return;
    final uri = Uri.parse('mailto:${email.trim()}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open email client for $email'),
            backgroundColor: AppTheme.statusRejected,
          ),
        );
      }
    }
  }

  Future<void> _navigateToEdit() async {
    if (_lead == null) return;
    final updatedLead = await Navigator.push<LeadModel>(
      context,
      MaterialPageRoute(
        builder: (_) => LeadInfoScreen(lead: _lead!),
      ),
    );

    if (updatedLead != null && mounted) {
      setState(() {
        _lead = updatedLead;
      });
      _fetchDetails();
    }
  }

  @override
  Widget build(BuildContext context) {
    final lead = _lead;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.textPrimary, size: 20),
          onPressed: () => Navigator.of(context).pop(_lead),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              lead?.fullName ?? 'Lead Details',
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (lead?.eventName != null && lead!.eventName!.isNotEmpty)
              Text(
                lead.eventName!,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        actions: [
          if (lead != null)
            IconButton(
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.accentIndigo.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.edit_rounded, color: AppTheme.accentCyan, size: 18),
              ),
              tooltip: 'Edit Rating & Notes',
              onPressed: _navigateToEdit,
            ),
        ],
      ),
      body: _isLoading && lead == null
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.accentIndigo),
              ),
            )
          : _errorMessage != null && lead == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            size: 48, color: AppTheme.statusRejected),
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppTheme.textSecondary),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _fetchDetails,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Try Again'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.accentIndigo,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _fetchDetails,
                  color: AppTheme.accentIndigo,
                  backgroundColor: AppTheme.surface,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHeroCard(lead!),
                        const SizedBox(height: 16),
                        _buildContactActions(lead),
                        const SizedBox(height: 16),
                        _buildNotesCard(lead),
                        const SizedBox(height: 16),
                        _buildInformationCard(lead),
                        const SizedBox(height: 16),
                        if (lead.checkinHistory != null && lead.checkinHistory!.isNotEmpty)
                          _buildHistorySection(lead),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildHeroCard(LeadModel lead) {
    final photoUrl = _resolveAvatarUrl(context, lead.photo);
    final (typeColor, typeIcon, typeLabel) = _getLeadTypeProps(lead.leadType);

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.surfaceBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Banner Top Accent
          Container(
            height: 6,
            decoration: const BoxDecoration(
              gradient: AppTheme.brandGradient,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // Avatar with Badge
                Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.accentCyan, width: 2.5),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.accentCyan.withValues(alpha: 0.25),
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
                                errorBuilder: (context, error, stackTrace) => _buildInitialsAvatar(lead),
                              )
                            : _buildInitialsAvatar(lead),
                      ),
                    ),
                    // Rating Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: typeColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(typeIcon, color: Colors.white, size: 12),
                          const SizedBox(width: 3),
                          Text(
                            typeLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Full Name
                Text(
                  lead.fullName.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
                if (lead.designation != null && lead.designation!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    lead.designation!.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppTheme.accentCyan,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
                if (lead.companyName != null && lead.companyName!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.business_rounded, color: AppTheme.textSecondary, size: 14),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          lead.companyName!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (lead.ticketType != null && lead.ticketType!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceElevated,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.surfaceBorder),
                    ),
                    child: Text(
                      lead.ticketType!,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
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

  Widget _buildInitialsAvatar(LeadModel lead) {
    return Container(
      color: AppTheme.surfaceElevated,
      alignment: Alignment.center,
      child: Text(
        lead.initials,
        style: const TextStyle(
          color: AppTheme.accentCyan,
          fontSize: 32,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _buildContactActions(LeadModel lead) {
    final hasMobile = lead.mobile != null && lead.mobile!.trim().isNotEmpty;
    final hasEmail = lead.email != null && lead.email!.trim().isNotEmpty;

    return Row(
      children: [
        if (hasMobile)
          Expanded(
            child: _buildActionTile(
              icon: Icons.phone_rounded,
              label: 'Call',
              color: AppTheme.statusSuccess,
              onTap: () => _makePhoneCall(lead.mobile),
            ),
          ),
        if (hasMobile && hasEmail) const SizedBox(width: 12),
        if (hasEmail)
          Expanded(
            child: _buildActionTile(
              icon: Icons.email_rounded,
              label: 'Email',
              color: AppTheme.accentCyan,
              onTap: () => _sendEmail(lead.email),
            ),
          ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildActionTile(
            icon: Icons.rate_review_rounded,
            label: 'Rate / Note',
            color: AppTheme.brandGradientStart,
            onTap: _navigateToEdit,
          ),
        ),
      ],
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotesCard(LeadModel lead) {
    final hasNotes = lead.notes != null && lead.notes!.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.notes_rounded, color: AppTheme.accentIndigo, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Lead Notes',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: _navigateToEdit,
                borderRadius: BorderRadius.circular(6),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Text(
                    'EDIT',
                    style: TextStyle(
                      color: AppTheme.accentCyan,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (hasNotes)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.surfaceElevated,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.surfaceBorder),
              ),
              child: Text(
                lead.notes!,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            )
          else
            InkWell(
              onTap: _navigateToEdit,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceElevated.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.surfaceBorder, style: BorderStyle.solid),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_circle_outline_rounded,
                        color: AppTheme.textSecondary, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'No notes captured yet. Tap to add.',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInformationCard(LeadModel lead) {
    final infoItems = <(IconData, String, String?, VoidCallback?)>[
      if (lead.email != null && lead.email!.isNotEmpty)
        (Icons.email_outlined, 'Email', lead.email, () => _sendEmail(lead.email)),
      if (lead.mobile != null && lead.mobile!.isNotEmpty)
        (Icons.phone_outlined, 'Mobile', lead.mobile, () => _makePhoneCall(lead.mobile)),
      if (lead.department != null && lead.department!.isNotEmpty)
        (Icons.domain_outlined, 'Department', lead.department, null),
      if (lead.city != null && lead.city!.isNotEmpty && lead.city!.toLowerCase() != 'n/a')
        (Icons.location_city_outlined, 'City', lead.city, null),
      if (lead.country != null && lead.country!.isNotEmpty)
        (Icons.public_outlined, 'Country', lead.country, null),
      if (lead.uniqueId.isNotEmpty)
        (Icons.qr_code_rounded, 'Badge ID', lead.uniqueId, null),
    ];

    if (infoItems.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.badge_outlined, color: AppTheme.accentCyan, size: 20),
              SizedBox(width: 8),
              Text(
                'Attendee Information',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (int i = 0; i < infoItems.length; i++) ...[
            if (i > 0)
              const Divider(color: AppTheme.surfaceBorder, height: 16),
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.textSecondary, size: 18),
            const SizedBox(width: 12),
            SizedBox(
              width: 90,
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
                style: TextStyle(
                  color: onTap != null ? AppTheme.accentCyan : AppTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  decoration: onTap != null ? TextDecoration.underline : null,
                ),
              ),
            ),
            if (onTap != null)
              const Icon(Icons.open_in_new_rounded, color: AppTheme.accentCyan, size: 14),
          ],
        ),
      ),
    );
  }

  Widget _buildHistorySection(LeadModel lead) {
    final historyList = lead.checkinHistory!;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.history_rounded, color: AppTheme.accentOrange, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Check-in History',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceElevated,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.surfaceBorder),
                ),
                child: Text(
                  '${historyList.length}',
                  style: const TextStyle(
                    color: AppTheme.accentOrange,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (int i = 0; i < historyList.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            _buildHistoryItem(historyList[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildHistoryItem(dynamic item) {
    if (item is! Map) return const SizedBox.shrink();

    final checkInDt = item['main_check_in_dt']?.toString();
    final checkInTm = item['main_check_in_tm']?.toString();
    final checkOutDt = item['main_check_out_dt']?.toString();
    final checkOutTm = item['main_check_out_tm']?.toString();

    String formattedIn = _formatDateTime(checkInDt, checkInTm);
    String? formattedOut = (checkOutTm != null && checkOutTm.isNotEmpty)
        ? _formatDateTime(checkOutDt, checkOutTm)
        : null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.surfaceBorder),
      ),
      child: Row(
        children: [
          // Check-in
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.login_rounded, color: AppTheme.statusSuccess, size: 14),
                    SizedBox(width: 4),
                    Text(
                      'CHECK-IN',
                      style: TextStyle(
                        color: AppTheme.statusSuccess,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
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
          if (formattedOut != null) ...[
            Container(
              height: 36,
              width: 1,
              color: AppTheme.surfaceBorder,
              margin: const EdgeInsets.symmetric(horizontal: 10),
            ),
            // Check-out
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.logout_rounded, color: AppTheme.statusRejected, size: 14),
                      SizedBox(width: 4),
                      Text(
                        'CHECK-OUT',
                        style: TextStyle(
                          color: AppTheme.statusRejected,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formattedOut,
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
        ],
      ),
    );
  }

  String _formatDateTime(String? dateStr, String? timeStr) {
    if (dateStr == null && timeStr == null) return 'TBA';
    try {
      DateTime? dt;
      if (dateStr != null && dateStr.isNotEmpty) {
        dt = DateTime.tryParse(dateStr);
      }
      final dateFormatted = dt != null ? DateFormat('MMM dd, yyyy').format(dt) : (dateStr ?? '');

      if (timeStr != null && timeStr.isNotEmpty) {
        // time might be "14:30:00" or "14:30"
        final parts = timeStr.split(':');
        if (parts.length >= 2) {
          final hour = int.tryParse(parts[0]) ?? 0;
          final min = int.tryParse(parts[1]) ?? 0;
          final tod = TimeOfDay(hour: hour, minute: min);
          final now = DateTime.now();
          final timeDt = DateTime(now.year, now.month, now.day, tod.hour, tod.minute);
          final timeFormatted = DateFormat('hh:mm a').format(timeDt);
          return '$dateFormatted • $timeFormatted';
        }
      }
      return dateFormatted;
    } catch (_) {
      return '${dateStr ?? ''} ${timeStr ?? ''}'.trim();
    }
  }

  (Color, IconData, String) _getLeadTypeProps(String type) {
    switch (type.toUpperCase()) {
      case 'HOT':
        return (const Color(0xFFEF4444), Icons.whatshot_rounded, 'HOT');
      case 'WARM':
        return (const Color(0xFFF59E0B), Icons.wb_sunny_rounded, 'WARM');
      case 'COLD':
      default:
        return (const Color(0xFF3B82F6), Icons.ac_unit_rounded, 'COLD');
    }
  }
}
