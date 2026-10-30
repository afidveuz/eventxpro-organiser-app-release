import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../data/models/lead_model.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/repositories/lead_repository.dart';
import '../lead_info_screen.dart';

class LeadCapturedModalSheet extends StatefulWidget {
  final LeadModel lead;
  final VoidCallback onDismiss;
  final ValueChanged<LeadModel>? onLeadUpdated;

  const LeadCapturedModalSheet({
    super.key,
    required this.lead,
    required this.onDismiss,
    this.onLeadUpdated,
  });

  @override
  State<LeadCapturedModalSheet> createState() => _LeadCapturedModalSheetState();
}

class _LeadCapturedModalSheetState extends State<LeadCapturedModalSheet> {
  late LeadModel _currentLead;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _currentLead = widget.lead;
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

  Future<void> _updateLeadType(String type) async {
    if (_isUpdating || _currentLead.leadType == type) return;
    setState(() => _isUpdating = true);

    final leadRepo = context.read<LeadRepository>();
    final success = await leadRepo.updateLead(
      id: _currentLead.id,
      leadType: type,
      notes: _currentLead.notes ?? '',
    );

    if (mounted) {
      if (success) {
        final updated = _currentLead.copyWith(leadType: type);
        setState(() {
          _currentLead = updated;
          _isUpdating = false;
        });
        widget.onLeadUpdated?.call(updated);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lead marked as $type'),
            backgroundColor: AppTheme.eventxproSuccess,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 1),
          ),
        );
      } else {
        setState(() => _isUpdating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update lead status'),
            backgroundColor: AppTheme.eventxproDanger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final photoUrl = _resolveAvatarUrl(context, _currentLead.photo);

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF131722),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle Bar
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),

            // Top Status Bar
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00E676).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.4)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_rounded, size: 14, color: Color(0xFF00E676)),
                      SizedBox(width: 5),
                      Text(
                        'LEAD CAPTURED',
                        style: TextStyle(
                          color: Color(0xFF00E676),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  onPressed: widget.onDismiss,
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Profile & Info
            Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppTheme.brandGradientStart,
                      width: 2,
                    ),
                  ),
                  child: ClipOval(
                    child: photoUrl != null
                        ? Image.network(
                            photoUrl,
                            fit: BoxFit.cover,
                            width: 64,
                            height: 64,
                            errorBuilder: (context, error, stackTrace) => _buildInitials(),
                          )
                        : _buildInitials(),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _currentLead.fullName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_currentLead.companyName != null && _currentLead.companyName!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          _currentLead.companyName!,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                      if (_currentLead.designation != null && _currentLead.designation!.isNotEmpty) ...[
                        const SizedBox(height: 1),
                        Text(
                          _currentLead.designation!,
                          style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      if (_currentLead.email != null && _currentLead.email!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          _currentLead.email!,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Ticket Info Box
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'TICKET ID',
                          style: TextStyle(color: AppTheme.textMuted, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _currentLead.uniqueId.isNotEmpty ? _currentLead.uniqueId : 'N/A',
                          style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  Container(height: 28, width: 1, color: Colors.white.withValues(alpha: 0.1)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'TICKET CLASS',
                          style: TextStyle(color: AppTheme.textMuted, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _currentLead.ticketType ?? 'General',
                          style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Lead Classification Rating (HOT, WARM, COLD)
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'CLASSIFY LEAD RATING',
                style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            const SizedBox(height: 8),

            Row(
              children: [
                Expanded(
                  child: _buildTypeButton(
                    type: 'COLD',
                    label: 'COLD',
                    icon: Icons.ac_unit_rounded,
                    activeColor: const Color(0xFF007AFF),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildTypeButton(
                    type: 'WARM',
                    label: 'WARM',
                    icon: Icons.wb_sunny_rounded,
                    activeColor: const Color(0xFFFF9500),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildTypeButton(
                    type: 'HOT',
                    label: 'HOT',
                    icon: Icons.local_fire_department_rounded,
                    activeColor: const Color(0xFFFF3B30),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Action Row: "Notes & Details" + "Next Scan"
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () async {
                      Navigator.of(context).pop();
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => LeadInfoScreen(lead: _currentLead),
                        ),
                      );
                    },
                    icon: const Icon(Icons.edit_note_rounded, size: 18, color: AppTheme.brandGradientStart),
                    label: const Text(
                      'Add Notes',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.brandGradientStart,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    onPressed: widget.onDismiss,
                    child: const Text(
                      'Scan Next',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeButton({
    required String type,
    required String label,
    required IconData icon,
    required Color activeColor,
  }) {
    final isSelected = _currentLead.leadType.toUpperCase() == type;

    return InkWell(
      onTap: _isUpdating ? null : () => _updateLeadType(type),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? activeColor : Colors.white.withValues(alpha: 0.1),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: isSelected ? activeColor : Colors.white60),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected ? activeColor : Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInitials() {
    return Container(
      color: const Color(0xFF232A3B),
      child: Center(
        child: Text(
          _currentLead.initials,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
      ),
    );
  }
}
