import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../data/models/qr_blacklist_user_model.dart';
import '../../data/repositories/auth_repository.dart';

/// Modal bottom sheet displaying verified attendee details, mirroring
/// `AttendeeInfoSheet.jsx` in the reference React Native EventXPro app.
class AttendeeInfoSheet extends StatelessWidget {
  final QrUserDetailsModel attendee;
  final VoidCallback onClose;

  const AttendeeInfoSheet({
    super.key,
    required this.attendee,
    required this.onClose,
  });

  /// Displays the modal bottom sheet and auto-dismisses after 6 seconds.
  static Future<void> show({
    required BuildContext context,
    required QrUserDetailsModel attendee,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AttendeeInfoSheet(
        attendee: attendee,
        onClose: () => Navigator.of(ctx).pop(),
      ),
    );
  }

  String _resolveAvatarUrl(BuildContext context, String? photo) {
    if (photo == null || photo.trim().isEmpty) return '';
    final cleanPhoto = photo.trim();
    if (cleanPhoto.startsWith('http://') || cleanPhoto.startsWith('https://')) {
      return cleanPhoto;
    }
    try {
      final mediaUrl = context.read<AuthRepository>().mediaUrl;
      final cleanMedia = mediaUrl.endsWith('/')
          ? mediaUrl.substring(0, mediaUrl.length - 1)
          : mediaUrl;
      final cleanPath = cleanPhoto.startsWith('/') ? cleanPhoto : '/$cleanPhoto';
      return '$cleanMedia$cleanPath';
    } catch (_) {
      return cleanPhoto;
    }
  }

  String _getInitials(String fName, String lName, String? alt) {
    final first = fName.trim();
    final last = lName.trim();
    if (first.isNotEmpty && last.isNotEmpty) {
      return '${first[0]}${last[0]}'.toUpperCase();
    } else if (first.isNotEmpty) {
      return first[0].toUpperCase();
    } else if (last.isNotEmpty) {
      return last[0].toUpperCase();
    } else if (alt != null && alt.trim().isNotEmpty) {
      return alt.trim()[0].toUpperCase();
    }
    return 'P';
  }

  String _formatTime(String? timeStr) {
    if (timeStr == null || timeStr.trim().isEmpty) return '';
    try {
      final parts = timeStr.trim().split(':');
      if (parts.length >= 2) {
        final hour = int.tryParse(parts[0]) ?? 0;
        final minute = int.tryParse(parts[1]) ?? 0;
        final now = DateTime.now();
        final dt = DateTime(now.year, now.month, now.day, hour, minute);
        return DateFormat('hh:mm a').format(dt);
      }
      return timeStr;
    } catch (_) {
      return timeStr;
    }
  }

  Color _getSessionColor(int index) {
    const sessionColors = [
      Color(0xFF2563EB), // Blue
      Color(0xFF7C3AED), // Purple
      Color(0xFF059669), // Emerald
      Color(0xFFD97706), // Amber
      Color(0xFFDC2626), // Red
      Color(0xFF0891B2), // Cyan
    ];
    return sessionColors[index % sessionColors.length];
  }

  @override
  Widget build(BuildContext context) {
    final user = attendee.userDetails;
    final photoUrl = _resolveAvatarUrl(context, user.userImage);
    final initials = _getInitials(user.firstname, user.lastname, user.arabicName);
    final fullName = '${user.firstname} ${user.lastname}'.trim();
    final effectiveName = fullName.isNotEmpty
        ? fullName
        : (user.arabicName ?? 'Verified Attendee');

    final category = user.ticketCategory ?? user.ticketTypeCat;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header: Green banner (#23A618) matching React Native ────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              color: const Color(0xFF23A618),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.person_rounded,
                        color: Color(0xFF23A618),
                        size: 22,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Verified User',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Badge credentials verified successfully',
                          style: TextStyle(
                            color: Color(0xFFE8F5E9),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: onClose,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.25),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Body content ──────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Profile Row: Avatar + Details
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Avatar image or initials circle
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFF23A618),
                              width: 2.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.12),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: photoUrl.isNotEmpty
                                ? Image.network(
                                    photoUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) =>
                                        _buildInitials(initials),
                                  )
                                : _buildInitials(initials),
                          ),
                        ),
                        const SizedBox(width: 14),

                        // User Information Details
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                effectiveName.toUpperCase(),
                                style: const TextStyle(
                                  color: Color(0xFF111827),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.4,
                                ),
                              ),
                              if (user.companyName != null && user.companyName!.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  user.companyName!,
                                  style: const TextStyle(
                                    color: Color(0xFF4B5563),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 4),
                              Text(
                                'Ticket ID: ${user.uniqueId.isNotEmpty ? user.uniqueId : attendee.ticketId}',
                                style: const TextStyle(
                                  color: Color(0xFF6B7280),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (user.seatNo != null && user.seatNo!.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'Seat No: ${user.seatNo}',
                                  style: const TextStyle(
                                    color: Color(0xFF6B7280),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                              if (user.displayTicketCode != null && user.displayTicketCode!.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'Display Code: ${user.displayTicketCode}',
                                  style: const TextStyle(
                                    color: Color(0xFF6B7280),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                              if (user.country != null && user.country!.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'Country: ${user.country}',
                                  style: const TextStyle(
                                    color: Color(0xFF6B7280),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                              if (user.email != null && user.email!.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'Email: ${user.email}',
                                  style: const TextStyle(
                                    color: Color(0xFF6B7280),
                                    fontSize: 12,
                                  ),
                                ),
                              ],

                              // Ticket Category Chip Tail (#9D4AC5)
                              if (category != null && category.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF9D4AC5),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    category,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),

                    // Last Checkin Session Text
                    if (attendee.lastCheckinSession != null && attendee.lastCheckinSession!.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Divider(color: Color(0xFFE5E7EB), height: 1),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(
                            Icons.history_toggle_off_rounded,
                            size: 15,
                            color: Color(0xFF6B7280),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Last Checkin: ${attendee.lastCheckinSession} at ${_formatTime(attendee.lastCheckinTime)}',
                              style: const TextStyle(
                                color: Color(0xFF4B5563),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],

                    // Session Access List
                    if (attendee.sessionAccess.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      const Text(
                        'Access',
                        style: TextStyle(
                          color: Color(0xFF111827),
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: List.generate(
                          attendee.sessionAccess.length,
                          (i) {
                            final session = attendee.sessionAccess[i];
                            final color = _getSessionColor(i);
                            final timeText = _formatTime(session.startTm);
                            final hall = session.hallName != null && session.hallName!.isNotEmpty
                                ? ' - ${session.hallName}'
                                : '';

                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: color,
                                borderRadius: BorderRadius.circular(6),
                                boxShadow: [
                                  BoxShadow(
                                    color: color.withValues(alpha: 0.3),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (timeText.isNotEmpty || hall.isNotEmpty)
                                    Text(
                                      '$timeText$hall',
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.85),
                                        fontSize: 9,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  Text(
                                    session.title,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
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
          fontSize: 26,
          fontWeight: FontWeight.w900,
          letterSpacing: 1,
        ),
      ),
    );
  }
}
