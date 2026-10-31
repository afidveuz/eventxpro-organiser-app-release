import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/qr_blacklist_user_model.dart';

class BlacklistInfoBottomSheet extends StatelessWidget {
  final QrUserDetailsModel data;
  final String mediaBaseUrl;
  final VoidCallback onClose;
  final Function(bool isCurrentlyBlocked) onToggleBlacklist;

  const BlacklistInfoBottomSheet({
    super.key,
    required this.data,
    required this.mediaBaseUrl,
    required this.onClose,
    required this.onToggleBlacklist,
  });

  String? _resolveImageUrl(String? path) {
    if (path == null || path.trim().isEmpty) return null;
    final cleanPath = path.trim();
    if (cleanPath.startsWith('http://') || cleanPath.startsWith('https://')) {
      return cleanPath;
    }
    final cleanBase = mediaBaseUrl.endsWith('/')
        ? mediaBaseUrl.substring(0, mediaBaseUrl.length - 1)
        : mediaBaseUrl;
    final prefix = cleanPath.startsWith('/') ? '' : '/';
    return '$cleanBase$prefix$cleanPath';
  }

  @override
  Widget build(BuildContext context) {
    final user = data.userDetails;
    final isBlocked = user.blacklistStatus;
    final imageUrl = _resolveImageUrl(user.userImage);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(
          top: BorderSide(color: AppTheme.surfaceBorder, width: 1.5),
          left: BorderSide(color: AppTheme.surfaceBorder, width: 1.5),
          right: BorderSide(color: AppTheme.surfaceBorder, width: 1.5),
        ),
      ),
      child: SafeArea(
        top: false,
        left: false,
        right: false,
        bottom: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: const BoxDecoration(
                color: Color(0xFF23A618),
                borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.person_rounded,
                      color: Color(0xFF23A618),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Badge Information',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: onClose,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close_rounded, color: Colors.white, size: 16),
                    ),
                  ),
                ],
              ),
            ),

            // Scrollable Attendee Content
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(18, 16, 18, 20 + (bottomInset > 0 ? 8 : 12)),
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Profile Row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Avatar
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 2),
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                        child: ClipOval(
                          child: imageUrl != null
                              ? Image.network(
                                  imageUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => _buildInitials(user.initials),
                                )
                              : _buildInitials(user.initials),
                        ),
                      ),
                      const SizedBox(width: 14),

                      // User Info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user.fullName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.2,
                              ),
                            ),
                            if (user.companyName != null && user.companyName!.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                user.companyName!,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                            const SizedBox(height: 6),
                            _buildMetaLine(Icons.badge_outlined, 'Ticket ID', user.uniqueId),
                            if (user.seatNo != null && user.seatNo!.isNotEmpty)
                              _buildMetaLine(Icons.chair_outlined, 'Seat No', user.seatNo!),
                            if (user.displayTicketCode != null && user.displayTicketCode!.isNotEmpty)
                              _buildMetaLine(Icons.qr_code_rounded, 'Display Code', user.displayTicketCode!),
                            if (user.country != null && user.country!.isNotEmpty)
                              _buildMetaLine(Icons.public_rounded, 'Country', user.country!),
                            if (user.email != null && user.email!.isNotEmpty)
                              _buildMetaLine(Icons.email_outlined, 'Email', user.email!),

                            // Category Tag
                            if (user.ticketCategory != null) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  gradient: AppTheme.brandGradient,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  user.ticketCategory!,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Last Checkin Banner
                  if (data.lastCheckinSession != null && data.lastCheckinSession!.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.history_rounded, size: 16, color: AppTheme.brandGradientStart),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Last Checkin: ${data.lastCheckinSession}${data.lastCheckinTime != null ? ' at ${data.lastCheckinTime}' : ''}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Session Access Tags
                  if (data.sessionAccess.isNotEmpty) ...[
                    const Text(
                      'Session Access',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: data.sessionAccess.map((s) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                s.title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (s.startTm != null || s.hallName != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  [s.startTm, s.hallName].whereType<String>().join(' • '),
                                  style: const TextStyle(
                                    color: Colors.white60,
                                    fontSize: 10.5,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Action Button (Block / Unblock)
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isBlocked
                            ? const Color(0xFF2E7D32)
                            : const Color(0xFFD32F2F),
                        foregroundColor: Colors.white,
                        elevation: 3,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => onToggleBlacklist(isBlocked),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            isBlocked ? Icons.lock_open_rounded : Icons.block_rounded,
                            size: 19,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isBlocked ? 'Unblock' : 'Block',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
  }

  Widget _buildInitials(String initials) {
    return Center(
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _buildMetaLine(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          Icon(icon, size: 12.5, color: Colors.white38),
          const SizedBox(width: 5),
          Text(
            '$label: ',
            style: const TextStyle(color: Colors.white38, fontSize: 11.5),
          ),
          Expanded(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
