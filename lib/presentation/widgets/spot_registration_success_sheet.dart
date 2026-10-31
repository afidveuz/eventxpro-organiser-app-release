import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/spot_registration_model.dart';
import '../../data/repositories/attendee_repository.dart';
import '../screens/attendees/attendee_details_screen.dart';

/// Modal bottom sheet presented upon successful spot registration
class SpotRegistrationSuccessSheet extends StatefulWidget {
  final int eventId;
  final String eventName;
  final SpotRegistrationResult result;
  final VoidCallback onRegisterAnother;

  const SpotRegistrationSuccessSheet({
    super.key,
    required this.eventId,
    required this.eventName,
    required this.result,
    required this.onRegisterAnother,
  });

  static Future<void> show(
    BuildContext context, {
    required int eventId,
    required String eventName,
    required SpotRegistrationResult result,
    required VoidCallback onRegisterAnother,
  }) {
    return showModalBottomSheet(
      context: context,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => SpotRegistrationSuccessSheet(
        eventId: eventId,
        eventName: eventName,
        result: result,
        onRegisterAnother: onRegisterAnother,
      ),
    );
  }

  @override
  State<SpotRegistrationSuccessSheet> createState() =>
      _SpotRegistrationSuccessSheetState();
}

class _SpotRegistrationSuccessSheetState
    extends State<SpotRegistrationSuccessSheet> {
  bool _isPunching = false;
  bool _isCheckInSuccess = false;
  String? _checkInMessage;

  Future<void> _punchInstantCheckIn() async {
    if (_isPunching || _isCheckInSuccess) return;

    setState(() {
      _isPunching = true;
      _checkInMessage = null;
    });
    HapticFeedback.mediumImpact();

    final repo = context.read<AttendeeRepository>();
    final userInput = widget.result.uniqueId ??
        widget.result.attendeeId?.toString() ??
        widget.result.email ??
        '';

    final payload = {
      'event_id': widget.eventId,
      'type': 'check_in',
      'user_input': userInput,
      'scan_type': 1,
      'user_latitude': 11.0,
      'user_longitude': 12.0,
      'user_city': '',
    };

    final punchRes = await repo.punchAttendee(
      endpoint: 'organizer/event-entrance',
      payload: payload,
    );

    if (mounted) {
      setState(() {
        _isPunching = false;
        _isCheckInSuccess = punchRes.isSuccess;
        _checkInMessage = punchRes.message ??
            (punchRes.isSuccess
                ? 'Checked in successfully!'
                : 'Check-in failed');
      });
      HapticFeedback.heavyImpact();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF131722),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: Color(0xFF2A3447), width: 1),
          left: BorderSide(color: Color(0xFF2A3447), width: 1),
          right: BorderSide(color: Color(0xFF2A3447), width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bottomPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 18),

              // Success Icon with Glow
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF10B981).withValues(alpha: 0.16),
                  border: Border.all(
                    color: const Color(0xFF10B981).withValues(alpha: 0.4),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Color(0xFF10B981),
                  size: 36,
                ),
              ),
              const SizedBox(height: 14),

              // Title
              const Text(
                'Registration Completed!',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),

              Text(
                widget.eventName,
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              // Attendee summary card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Column(
                  children: [
                    if (widget.result.fullName != null &&
                        widget.result.fullName!.isNotEmpty)
                      Text(
                        widget.result.fullName!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    if (widget.result.email != null &&
                        widget.result.email!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        widget.result.email!,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ],
                    if (widget.result.uniqueId != null &&
                        widget.result.uniqueId!.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.brandGradientStart.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppTheme.brandGradientStart.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text(
                          'URN: ${widget.result.uniqueId}',
                          style: const TextStyle(
                            color: AppTheme.brandGradientStart,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Action 1: Instant Check-In Punch
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _isPunching || _isCheckInSuccess
                      ? null
                      : _punchInstantCheckIn,
                  icon: _isPunching
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          _isCheckInSuccess
                              ? Icons.verified_rounded
                              : Icons.login_rounded,
                          size: 20,
                          color: Colors.white,
                        ),
                  label: Text(
                    _isCheckInSuccess
                        ? (_checkInMessage ?? 'Checked In!')
                        : '1-Tap Instant Check-In',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isCheckInSuccess
                        ? const Color(0xFF10B981)
                        : const Color(0xFF2563EB),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Action 2 & 3: Register Another & View Profile/Badge
              Row(
                children: [
                  // Register Next Attendee
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        widget.onRegisterAnother();
                      },
                      icon: const Icon(
                        Icons.person_add_alt_1_rounded,
                        size: 18,
                        color: Colors.white,
                      ),
                      label: const Text(
                        'Register Next',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // View Profile / Close
                  if (widget.result.attendeeId != null)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => AttendeeDetailsScreen(
                                attendeeId: widget.result.attendeeId!,
                                eventName: widget.eventName,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(
                          Icons.badge_rounded,
                          size: 18,
                          color: AppTheme.accentCyan,
                        ),
                        label: const Text(
                          'View Details',
                          style: TextStyle(
                            color: AppTheme.accentCyan,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: AppTheme.accentCyan.withValues(alpha: 0.4),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.2),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text(
                          'Done',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
