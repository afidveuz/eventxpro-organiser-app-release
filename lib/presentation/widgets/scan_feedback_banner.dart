import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../bloc/scanner_state.dart';

class ScanFeedbackBanner extends StatelessWidget {
  final ScannerDecisionState state;
  final VoidCallback onRetry;

  const ScanFeedbackBanner({
    super.key,
    required this.state,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    Color primaryColor;
    Color bgColor;
    IconData statusIcon;
    String statusTitle;

    if (state.isSuccess) {
      primaryColor = AppTheme.statusSuccess;
      bgColor = AppTheme.statusSuccessBg;
      statusIcon = Icons.check_circle_rounded;
      statusTitle = 'ACCESS GRANTED';
    } else if (state.isWarning) {
      primaryColor = AppTheme.statusWarning;
      bgColor = AppTheme.statusWarningBg;
      statusIcon = Icons.warning_amber_rounded;
      statusTitle = 'ALREADY CHECKED IN';
    } else if (state.isRejected) {
      primaryColor = AppTheme.statusRejected;
      bgColor = AppTheme.statusRejectedBg;
      statusIcon = Icons.cancel_rounded;
      statusTitle = 'ACCESS DENIED';
    } else {
      primaryColor = AppTheme.statusPending;
      bgColor = AppTheme.statusPendingBg;
      statusIcon = Icons.sync_problem_rounded;
      statusTitle = 'NETWORK PENDING';
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: primaryColor, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withValues(alpha: 0.25),
            blurRadius: 28,
            spreadRadius: 2,
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Large Hero Status Icon
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: primaryColor.withValues(alpha: 0.15),
              border: Border.all(color: primaryColor.withValues(alpha: 0.4), width: 2),
            ),
            child: Icon(statusIcon, size: 72, color: primaryColor),
          ),

          const SizedBox(height: 18),

          // Status Title
          Text(
            statusTitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
              color: primaryColor,
            ),
          ),

          const SizedBox(height: 6),

          // Scanned Token Pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.surfaceBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.qr_code, size: 14, color: AppTheme.textSecondary),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    state.request.qrToken,
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Message from authoritative backend
          Text(
            state.response.message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: AppTheme.textPrimary,
              height: 1.3,
            ),
          ),

          // Attendee Details Card (ONLY shown on authorized response - zero PII on invalid)
          if (state.isSuccess && state.response.attendee != null) ...[
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surfaceElevated.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.surfaceBorder),
              ),
              child: Column(
                children: [
                  Text(
                    state.response.attendee!.name,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: primaryColor.withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      state.response.attendee!.badgeType.toUpperCase(),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                        color: primaryColor,
                      ),
                    ),
                  ),
                  if (state.response.attendee!.company != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      state.response.attendee!.company!,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],

          // Rejection Code Details (Machine code without personal data)
          if (state.isRejected) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.statusRejected.withValues(alpha: 0.3)),
              ),
              child: Text(
                'REASON CODE: ${state.response.code.code}',
                style: const TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                  color: AppTheme.statusRejected,
                ),
              ),
            ),
          ],

          // Network Retry Action
          if (state.isNetworkError) ...[
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('RETRY VALIDATION (SAME ID)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.statusPending,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
          // Test API Response Pill
          if (state.response.testApiResponse != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFF38BDF8).withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.api_rounded, size: 14, color: Color(0xFF38BDF8)),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'API: ${state.response.testApiResponse}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: Color(0xFF38BDF8),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 18),

          // Latency & Request ID Footer
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.speed, size: 14, color: primaryColor),
              const SizedBox(width: 4),
              Text(
                '${state.response.latencyMs} ms',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: primaryColor,
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 4,
                height: 4,
                decoration: const BoxDecoration(
                  color: AppTheme.textMuted,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'REQ: ${state.request.scanRequestId.length >= 8 ? state.request.scanRequestId.substring(0, 8) : state.request.scanRequestId}',
                style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: AppTheme.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
