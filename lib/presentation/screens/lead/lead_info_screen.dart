import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/lead_model.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/lead_repository.dart';
import '../../widgets/fade_in_background_image.dart';

const int _maxNotesLength = 500;

class LeadInfoScreen extends StatefulWidget {
  final LeadModel lead;

  const LeadInfoScreen({
    super.key,
    required this.lead,
  });

  @override
  State<LeadInfoScreen> createState() => _LeadInfoScreenState();
}

class _LeadInfoScreenState extends State<LeadInfoScreen> {
  late String _leadType;
  late TextEditingController _notesController;
  bool _isSaving = false;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _leadType = widget.lead.leadType.toUpperCase();
    _notesController = TextEditingController(text: widget.lead.notes ?? '');
    _notesController.addListener(_onNotesChanged);
  }

  void _onNotesChanged() {
    final originalNotes = widget.lead.notes ?? '';
    final hasNoteChange = _notesController.text.trim() != originalNotes.trim();
    final hasTypeChange = _leadType != widget.lead.leadType.toUpperCase();

    if (_hasChanges != (hasNoteChange || hasTypeChange)) {
      setState(() {
        _hasChanges = hasNoteChange || hasTypeChange;
      });
    }
  }

  @override
  void dispose() {
    _notesController.removeListener(_onNotesChanged);
    _notesController.dispose();
    super.dispose();
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

  Future<void> _saveLeadInfo([String? newType]) async {
    final targetType = newType ?? _leadType;
    if (_isSaving) return;

    setState(() => _isSaving = true);
    final leadRepo = context.read<LeadRepository>();

    final success = await leadRepo.updateLead(
      id: widget.lead.id,
      leadType: targetType,
      notes: _notesController.text.trim(),
    );

    if (mounted) {
      setState(() {
        _isSaving = false;
        if (success) {
          _leadType = targetType;
          _hasChanges = false;
        }
      });

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Lead updated successfully'),
            backgroundColor: AppTheme.eventxproSuccess,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update lead information'),
            backgroundColor: AppTheme.eventxproDanger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<bool> _onWillPop() async {
    if (!_hasChanges) return true;

    final shouldDiscard = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppTheme.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Unsaved Changes', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text(
          'You have unsaved changes in notes or rating. Are you sure you want to discard them?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Keep Editing', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.eventxproDanger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );

    return shouldDiscard ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final photoUrl = _resolveAvatarUrl(context, widget.lead.photo);
    final remainingChars = _maxNotesLength - _notesController.text.length;

    return PopScope(
      canPop: !_hasChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          backgroundColor: AppTheme.surface,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
            onPressed: () async {
              if (_hasChanges) {
                final shouldPop = await _onWillPop();
                if (shouldPop && context.mounted) {
                  Navigator.of(context).pop();
                }
              } else {
                Navigator.of(context).pop();
              }
            },
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Lead Info',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              if (widget.lead.eventName != null)
                Text(
                  widget.lead.eventName!,
                  style: const TextStyle(color: AppTheme.brandGradientStart, fontSize: 11, fontWeight: FontWeight.w600),
                ),
            ],
          ),
          actions: [
            if (_hasChanges)
              TextButton(
                onPressed: _isSaving ? null : () => _saveLeadInfo(),
                child: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.brandGradientStart),
                      )
                    : const Text(
                        'Save',
                        style: TextStyle(
                          color: AppTheme.brandGradientStart,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
              ),
          ],
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: Divider(color: AppTheme.surfaceBorder, height: 1),
          ),
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            const AppBackgroundLayer(),
            SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: Column(
                children: [
                  // Attendee Header Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceElevated,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.surfaceBorder),
                    ),
                    child: Column(
                      children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppTheme.brandGradientStart,
                          width: 2.5,
                        ),
                      ),
                      child: ClipOval(
                        child: photoUrl != null
                            ? Image.network(
                                photoUrl,
                                fit: BoxFit.cover,
                                width: 80,
                                height: 80,
                                errorBuilder: (context, error, stackTrace) => _buildInitials(),
                              )
                            : _buildInitials(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.lead.fullName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (widget.lead.designation != null && widget.lead.designation!.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        widget.lead.designation!.toUpperCase(),
                        style: const TextStyle(
                          color: AppTheme.brandGradientStart,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    if (widget.lead.companyName != null && widget.lead.companyName!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.lead.companyName!,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 14),

                    // Quick Contact Shortcuts
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (widget.lead.mobile != null && widget.lead.mobile!.isNotEmpty)
                          _buildContactShortcut(
                            icon: Icons.phone_rounded,
                            label: 'Call',
                            onTap: () {
                              final phone = '${widget.lead.countryCode ?? ''}${widget.lead.mobile}'.replaceAll(' ', '');
                              launchUrl(Uri.parse('tel:$phone'));
                            },
                          ),
                        if (widget.lead.mobile != null && widget.lead.email != null)
                          const SizedBox(width: 16),
                        if (widget.lead.email != null && widget.lead.email!.isNotEmpty)
                          _buildContactShortcut(
                            icon: Icons.email_rounded,
                            label: 'Email',
                            onTap: () {
                              launchUrl(Uri.parse('mailto:${widget.lead.email}'));
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Rating Selection
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceElevated,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppTheme.surfaceBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'LEAD STATUS / RATING',
                      style: TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTypePill(
                            type: 'COLD',
                            icon: Icons.ac_unit_rounded,
                            color: const Color(0xFF007AFF),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildTypePill(
                            type: 'WARM',
                            icon: Icons.wb_sunny_rounded,
                            color: const Color(0xFFFF9500),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildTypePill(
                            type: 'HOT',
                            icon: Icons.local_fire_department_rounded,
                            color: const Color(0xFFFF3B30),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Notes Text Area
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceElevated,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppTheme.surfaceBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'INTERACTION NOTES',
                          style: TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                        Text(
                          '$remainingChars left',
                          style: TextStyle(
                            color: remainingChars < 50 ? AppTheme.eventxproDanger : AppTheme.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _notesController,
                      maxLength: _maxNotesLength,
                      maxLines: 6,
                      style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: 'Enter notes about attendee requirements, deal potential, conversation summary...',
                        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 13),
                        filled: true,
                        fillColor: Colors.black.withValues(alpha: 0.25),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppTheme.brandGradientStart),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Update Button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.brandGradientStart,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        onPressed: _isSaving ? null : () => _saveLeadInfo(),
                        icon: _isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.check_rounded, size: 20),
                        label: Text(
                          _isSaving ? 'Updating...' : 'Save Lead Notes',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
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
  ),
);
  }

  Widget _buildTypePill({
    required String type,
    required IconData icon,
    required Color color,
  }) {
    final isSelected = _leadType == type;

    return InkWell(
      onTap: () {
        setState(() {
          _leadType = type;
        });
        _onNotesChanged();
        _saveLeadInfo(type);
      },
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.white.withValues(alpha: 0.1),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: isSelected ? color : Colors.white60),
            const SizedBox(width: 6),
            Text(
              type,
              style: TextStyle(
                color: isSelected ? color : Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactShortcut({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppTheme.brandGradientStart),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
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
          widget.lead.initials,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 26,
          ),
        ),
      ),
    );
  }
}
