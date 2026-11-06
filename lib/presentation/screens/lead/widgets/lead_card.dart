import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../data/models/lead_model.dart';
import '../../../../data/repositories/auth_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class LeadCard extends StatelessWidget {
  final LeadModel lead;
  final VoidCallback onTap;
  final EdgeInsetsGeometry? margin;

  const LeadCard({
    super.key,
    required this.lead,
    required this.onTap,
    this.margin,
  });

  String _formatDateTime() {
    try {
      if (lead.checkInDt != null && lead.checkInDt!.isNotEmpty) {
        final dt = DateTime.parse(lead.checkInDt!);
        final dateStr = DateFormat('MMM dd').format(dt);
        if (lead.checkInTm != null && lead.checkInTm!.isNotEmpty) {
          return '${lead.checkInTm} • $dateStr';
        }
        return dateStr;
      }
    } catch (_) {}
    return lead.checkInDt ?? '';
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

  Widget _buildLeadTypeBadge(String type) {
    final upper = type.toUpperCase();
    Color bg;
    Color border;
    Color text;
    IconData icon;
    String label;

    switch (upper) {
      case 'HOT':
        bg = const Color(0xFFEF4444).withValues(alpha: 0.12);
        border = const Color(0xFFEF4444).withValues(alpha: 0.28);
        text = const Color(0xFFF87171);
        icon = Icons.local_fire_department_rounded;
        label = 'HOT';
        break;
      case 'WARM':
        bg = const Color(0xFFF59E0B).withValues(alpha: 0.12);
        border = const Color(0xFFF59E0B).withValues(alpha: 0.28);
        text = const Color(0xFFFBBF24);
        icon = Icons.wb_sunny_rounded;
        label = 'WARM';
        break;
      case 'COLD':
      default:
        bg = const Color(0xFF3B82F6).withValues(alpha: 0.12);
        border = const Color(0xFF3B82F6).withValues(alpha: 0.28);
        text = const Color(0xFF60A5FA);
        icon = Icons.ac_unit_rounded;
        label = 'COLD';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7.5, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11.5, color: text),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: text,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final photoUrl = _resolveAvatarUrl(context, lead.photo);
    final dateStr = _formatDateTime();

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          splashColor: AppTheme.accentIndigo.withValues(alpha: 0.08),
          highlightColor: AppTheme.accentIndigo.withValues(alpha: 0.04),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar with initials fallback
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: photoUrl != null
                          ? Colors.white.withValues(alpha: 0.12)
                          : AppTheme.accentIndigo.withValues(alpha: 0.35),
                      width: 1.2,
                    ),
                  ),
                  child: ClipOval(
                    child: photoUrl != null
                        ? Image.network(
                            photoUrl,
                            fit: BoxFit.cover,
                            width: 48,
                            height: 48,
                            errorBuilder: (context, error, stackTrace) =>
                                _buildInitials(),
                          )
                        : _buildInitials(),
                  ),
                ),
                const SizedBox(width: 14),

                // Lead Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name & Lead Type Badge
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              lead.fullName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 15.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _buildLeadTypeBadge(lead.leadType),
                        ],
                      ),

                      if (lead.companyName != null &&
                          lead.companyName!.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          lead.companyName!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppTheme.textPrimary.withValues(alpha: 0.8),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],

                      if (lead.designation != null &&
                          lead.designation!.isNotEmpty) ...[
                        const SizedBox(height: 1.5),
                        Text(
                          lead.designation!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],

                      // Email & Capture Time
                      if ((lead.email != null && lead.email!.isNotEmpty) ||
                          dateStr.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            if (lead.email != null && lead.email!.isNotEmpty)
                              Expanded(
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.mail_outline_rounded,
                                      size: 13,
                                      color: AppTheme.textMuted,
                                    ),
                                    const SizedBox(width: 5),
                                    Expanded(
                                      child: Text(
                                        lead.email!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: AppTheme.textSecondary,
                                          fontSize: 11.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (dateStr.isNotEmpty) ...[
                              if (lead.email != null && lead.email!.isNotEmpty)
                                const SizedBox(width: 8),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.access_time_rounded,
                                    size: 11,
                                    color: AppTheme.textMuted,
                                  ),
                                  const SizedBox(width: 3.5),
                                  Text(
                                    dateStr,
                                    style: const TextStyle(
                                      color: AppTheme.textMuted,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ],
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

  Widget _buildInitials() {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.accentIndigo.withValues(alpha: 0.25),
            AppTheme.accentIndigo.withValues(alpha: 0.08),
          ],
        ),
      ),
      child: Center(
        child: Text(
          lead.initials,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 16.5,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}
