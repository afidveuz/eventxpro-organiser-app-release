import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme/app_theme.dart';
import '../../data/adapters/simulated_hardware_adapter.dart';
import '../../data/adapters/zebra_datawedge_adapter.dart';
import '../bloc/scanner_bloc.dart';
import '../bloc/scanner_event.dart';
import '../bloc/scanner_state.dart';
import '../widgets/kiosk_header_hud.dart';
import '../widgets/ready_scanner_target.dart';
import '../widgets/scan_feedback_banner.dart';
import 'diagnostics_screen.dart';
import 'provisioning_screen.dart';
import 'simulator_screen.dart';

class KioskScannerScreen extends StatelessWidget {
  final ZebraDataWedgeAdapter zebraAdapter;
  final SimulatedHardwareAdapter simulatorAdapter;

  const KioskScannerScreen({
    super.key,
    required this.zebraAdapter,
    required this.simulatorAdapter,
  });

  void _openDiagnostics(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const DiagnosticsScreen()));
  }

  void _openSimulator(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SimulatorScreen(simulatorAdapter: simulatorAdapter),
      ),
    );
  }

  void _openProvisioning(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProvisioningScreen(
          zebraAdapter: zebraAdapter,
          simulatorAdapter: simulatorAdapter,
        ),
      ),
    );
  }

  void _syncOffline(BuildContext context) {
    context.read<ScannerBloc>().add(const ScannerSyncOfflineRequested());
  }

  void _openHistory(BuildContext context, ScannerState state) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final scans = state.recentScans;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'RECENT SCANNED DETAILS',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    '${scans.length} Scans',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (scans.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 36),
                  child: Center(
                    child: Text(
                      'No scans captured yet.\nTrigger TC15 laser or tap a Quick Test button.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: scans.length,
                    separatorBuilder: (context, index) =>
                        const Divider(color: AppTheme.surfaceBorder, height: 12),
                    itemBuilder: (ctx, index) {
                      final item = scans[index];
                      Color statusColor;
                      if (item.code.isSuccess) {
                        statusColor = AppTheme.statusSuccess;
                      } else if (item.code.isWarning) {
                        statusColor = AppTheme.statusWarning;
                      } else if (item.code.isRejected) {
                        statusColor = AppTheme.statusRejected;
                      } else {
                        statusColor = AppTheme.statusPending;
                      }

                      return Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: statusColor.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: statusColor.withValues(alpha: 0.5),
                                    ),
                                  ),
                                  child: Text(
                                    item.code.code,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: statusColor,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  '${item.latencyMs} ms',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: statusColor,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Token: ${item.qrToken}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                fontFamily: 'monospace',
                              ),
                            ),
                            if (item.attendeeName != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                'Attendee: ${item.attendeeName} • ${item.badgeType ?? ''}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ],
                            if (item.testApiResponse != null) ...[
                              const SizedBox(height: 3),
                              Text(
                                'Login API: ${item.testApiResponse}',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontFamily: 'monospace',
                                  color: Color(0xFF38BDF8),
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            const SizedBox(height: 2),
                            Text(
                              'Time: ${item.timestamp.toLocal().toString().substring(11, 19)} • Req: ${item.scanRequestId.substring(0, 8)}',
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppTheme.textMuted,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: BlocConsumer<ScannerBloc, ScannerState>(
        listener: (context, state) {
          // Listen to state changes if needed
        },
        builder: (context, state) {
          return Column(
            children: [
              // Top Bar HUD
              KioskHeaderHud(
                state: state,
                onOpenDiagnostics: () => _openDiagnostics(context),
                onOpenSimulator: () => _openSimulator(context),
                onOpenSettings: () => _openProvisioning(context),
                onSyncOffline: () => _syncOffline(context),
                onOpenHistory: () => _openHistory(context, state),
              ),

              // Main Active View Area
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 580),
                      child: _buildMainStateContent(context, state),
                    ),
                  ),
                ),
              ),

              // Bottom Quick Testing & Operational Bar
              _buildBottomQuickBar(context, state),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMainStateContent(BuildContext context, ScannerState state) {
    if (state is ScannerProcessingState) {
      return Container(
        padding: const EdgeInsets.all(36),
        decoration: BoxDecoration(
          color: AppTheme.surfaceElevated,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: AppTheme.accentIndigo.withValues(alpha: 0.5),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 64,
              height: 64,
              child: CircularProgressIndicator(
                strokeWidth: 4,
                valueColor: AlwaysStoppedAnimation<Color>(
                  AppTheme.accentIndigo,
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'AUTHORIZING ADMISSION...',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Token: ${state.tokenSnippet}',
              style: const TextStyle(
                fontSize: 13,
                fontFamily: 'monospace',
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Idempotency Request ID: ${state.scanRequestId.substring(0, 8)}',
              style: const TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: AppTheme.textMuted,
              ),
            ),
          ],
        ),
      ).animate().fadeIn(duration: 150.ms).scale(begin: const Offset(0.95, 0.95));
    }

    if (state is ScannerDecisionState) {
      return ScanFeedbackBanner(
            state: state,
            onRetry: () {
              context.read<ScannerBloc>().add(const ScannerRetryLast());
            },
          )
          .animate()
          .fadeIn(duration: 180.ms)
          .scale(begin: const Offset(0.92, 0.92));
    }

    // Default: Ready to Scan State
    return ReadyScannerTarget(
      statusText: (state is ScannerReadyState)
          ? state.statusMessage
          : 'READY TO SCAN',
      adapterName: state.adapterName,
    ).animate().fadeIn(duration: 250.ms);
  }

  Widget _buildBottomQuickBar(BuildContext context, ScannerState state) {
    final telemetry = state.telemetry;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          top: BorderSide(color: AppTheme.surfaceBorder, width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Quick Operational Telemetry Summary
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildCompactStat(
                    label: 'TOTAL',
                    value: '${telemetry.totalScans}',
                    color: Colors.white,
                  ),
                  const SizedBox(width: 16),
                  _buildCompactStat(
                    label: 'ACCEPTED',
                    value: '${telemetry.acceptedCount}',
                    color: AppTheme.statusSuccess,
                  ),
                  const SizedBox(width: 16),
                  _buildCompactStat(
                    label: 'WARNINGS',
                    value: '${telemetry.warningCount}',
                    color: AppTheme.statusWarning,
                  ),
                  const SizedBox(width: 16),
                  _buildCompactStat(
                    label: 'REJECTED',
                    value: '${telemetry.rejectedCount}',
                    color: AppTheme.statusRejected,
                  ),
                  const SizedBox(width: 16),
                  _buildCompactStat(
                    label: 'SUPPRESSED',
                    value: '${telemetry.duplicateSuppressedCount}',
                    color: Colors.tealAccent,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // Quick Hardware Simulation Triggers
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  const Text(
                    'Quick Test:',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textMuted,
                    ),
                  ),
                  const SizedBox(width: 8),

                  _buildQuickButton(
                    label: 'VIP Attendee',
                    color: AppTheme.statusSuccess,
                    icon: Icons.check,
                    onTap: () {
                      final token =
                          'VIP-2026-VICTORIA-STERLING-${DateTime.now().millisecondsSinceEpoch % 1000}';
                      context
                          .read<ScannerBloc>()
                          .add(ScannerRawBarcodeReceived(token));
                      simulatorAdapter.triggerScan(token);
                    },
                  ),
                  const SizedBox(width: 6),

                  _buildQuickButton(
                    label: 'Already Admitted',
                    color: AppTheme.statusWarning,
                    icon: Icons.warning_amber,
                    onTap: () {
                      const token = 'USED-BADGE-CHECKED-IN-001';
                      context
                          .read<ScannerBloc>()
                          .add(ScannerRawBarcodeReceived(token));
                      simulatorAdapter.triggerScan(token);
                    },
                  ),
                  const SizedBox(width: 6),

                  _buildQuickButton(
                    label: 'Wrong Event',
                    color: AppTheme.statusRejected,
                    icon: Icons.close,
                    onTap: () {
                      const token = 'WRONG-EVT-1025-BADGE';
                      context
                          .read<ScannerBloc>()
                          .add(ScannerRawBarcodeReceived(token));
                      simulatorAdapter.triggerScan(token);
                    },
                  ),
                  const SizedBox(width: 6),

                  _buildQuickButton(
                    label: 'Burst 8x (300ms Dedupe)',
                    color: Colors.tealAccent,
                    icon: Icons.bolt,
                    onTap: () {
                      final token =
                          'BURST-${DateTime.now().millisecondsSinceEpoch % 1000}';
                      for (int i = 0; i < 8; i++) {
                        Future.delayed(Duration(milliseconds: i * 30), () {
                          if (context.mounted) {
                            context
                                .read<ScannerBloc>()
                                .add(ScannerRawBarcodeReceived(token));
                          }
                        });
                      }
                      simulatorAdapter.triggerBurst(
                        barcode: token,
                        count: 8,
                        interval: const Duration(milliseconds: 30),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactStat({
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: color,
            fontFamily: 'monospace',
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildQuickButton({
    required String label,
    required Color color,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
