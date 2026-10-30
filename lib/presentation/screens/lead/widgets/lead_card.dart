import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../data/models/lead_model.dart';
import '../../../../data/repositories/auth_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class LeadCard extends StatelessWidget {
  final LeadModel lead;
  final VoidCallback onTap;

  const LeadCard({
    super.key,
    required this.lead,
    required this.onTap,
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
        bg = const Color(0xFFFF3B30).withValues(alpha: 0.15);
        border = const Color(0xFFFF3B30).withValues(alpha: 0.5);
        text = const Color(0xFFFF5252);
        icon = Icons.local_fire_department_rounded;
        label = 'HOT';
        break;
      case 'WARM':
        bg = const Color(0xFFFF9500).withValues(alpha: 0.15);
        border = const Color(0xFFFF9500).withValues(alpha: 0.5);
        text = const Color(0xFFFFA726);
        icon = Icons.wb_sunny_rounded;
        label = 'WARM';
        break;
      case 'COLD':
      default:
        bg = const Color(0xFF007AFF).withValues(alpha: 0.15);
        border = const Color(0xFF007AFF).withValues(alpha: 0.5);
        text = const Color(0xFF42A5F5);
        icon = Icons.ac_unit_rounded;
        label = 'COLD';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: text),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: text,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
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
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF131722),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
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
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar with initials fallback
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppTheme.brandGradientStart.withValues(alpha: 0.5),
                      width: 1.5,
                    ),
                  ),
                  child: ClipOval(
                    child: photoUrl != null
                        ? Image.network(
                            photoUrl,
                            fit: BoxFit.cover,
                            width: 50,
                            height: 50,
                            errorBuilder: (context, error, stackTrace) => _buildInitials(),
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
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _buildLeadTypeBadge(lead.leadType),
                        ],
                      ),

                      if (lead.companyName != null && lead.companyName!.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          lead.companyName!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.75),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],

                      if (lead.designation != null && lead.designation!.isNotEmpty) ...[
                        const SizedBox(height: 1),
                        Text(
                          lead.designation!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 11.5,
                          ),
                        ),
                      ],

                      const SizedBox(height: 8),

                      // Email & Capture Time
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          if (lead.email != null && lead.email!.isNotEmpty)
                            Expanded(
                              child: Row(
                                children: [
                                  const Icon(Icons.email_outlined, size: 12, color: Colors.white38),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      lead.email!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.5),
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (dateStr.isNotEmpty)
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
      color: const Color(0xFF232A3B),
      child: Center(
        child: Text(
          lead.initials,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
    );
  }
}
