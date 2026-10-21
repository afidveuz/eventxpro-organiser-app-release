import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme/app_theme.dart';
import '../bloc/scanner_bloc.dart';
import '../bloc/scanner_state.dart';

class DiagnosticsScreen extends StatelessWidget {
  const DiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Service-Level Measurements & Telemetry'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Metrics',
            onPressed: () {
              // Trigger rebuild
              (context as Element).markNeedsBuild();
            },
          ),
        ],
      ),
      body: BlocBuilder<ScannerBloc, ScannerState>(
        builder: (context, state) {
          final telemetry = state.telemetry;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Header Card
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1E1B4B), Color(0xFF312E81)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF4338CA)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.speed, size: 36, color: Color(0xFF818CF8)),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Real-Time Ingestion Performance',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Adapter: ${state.adapterName} • Device: ${state.deviceId.substring(0, 8)}...',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFFC7D2FE),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // Section: Latency Benchmarks (Section 11)
              const Text(
                'END-TO-END LATENCY PERCENTILES',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 10),

              Row(
                children: [
                  _buildMetricTile(
                    label: 'p50 (Median)',
                    value: '${telemetry.p50.toStringAsFixed(0)} ms',
                    color: AppTheme.statusSuccess,
                    subtitle: '50% under this latency',
                  ),
                  const SizedBox(width: 12),
                  _buildMetricTile(
                    label: 'p95 Target',
                    value: '${telemetry.p95.toStringAsFixed(0)} ms',
                    color: Colors.amberAccent,
                    subtitle: '95% under this latency',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _buildMetricTile(
                    label: 'p99 Tail',
                    value: '${telemetry.p99.toStringAsFixed(0)} ms',
                    color: AppTheme.accentIndigo,
                    subtitle: 'Worst 1% latency peak',
                  ),
                  const SizedBox(width: 12),
                  _buildMetricTile(
                    label: 'Average',
                    value: '${telemetry.averageLatency.toStringAsFixed(0)} ms',
                    color: Colors.cyanAccent,
                    subtitle: 'Overall mean latency',
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Section: Accuracy & Integrity (Section 11)
              const Text(
                'ACCURACY & INTEGRITY METRICS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 10),

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _buildRow(
                        icon: Icons.qr_code,
                        label: 'Total Scans Processed',
                        value: '${telemetry.totalScans}',
                        valueColor: Colors.white,
                      ),
                      const Divider(color: AppTheme.surfaceBorder),
                      _buildRow(
                        icon: Icons.check_circle_outline,
                        label: 'Authorized Admissions (Green)',
                        value: '${telemetry.acceptedCount}',
                        valueColor: AppTheme.statusSuccess,
                      ),
                      const Divider(color: AppTheme.surfaceBorder),
                      _buildRow(
                        icon: Icons.warning_amber_outlined,
                        label: 'Already Checked In (Amber)',
                        value: '${telemetry.warningCount}',
                        valueColor: AppTheme.statusWarning,
                      ),
                      const Divider(color: AppTheme.surfaceBorder),
                      _buildRow(
                        icon: Icons.highlight_off,
                        label: 'Rejected Badges (Red)',
                        value: '${telemetry.rejectedCount}',
                        valueColor: AppTheme.statusRejected,
                      ),
                      const Divider(color: AppTheme.surfaceBorder),
                      _buildRow(
                        icon: Icons.filter_alt_outlined,
                        label: 'Duplicate Callbacks Suppressed (300ms)',
                        value: '${telemetry.duplicateSuppressedCount}',
                        valueColor: Colors.tealAccent,
                      ),
                      const Divider(color: AppTheme.surfaceBorder),
                      _buildRow(
                        icon: Icons.storage_outlined,
                        label: 'FIFO Overflow Drops (Safe overflow)',
                        value: '${telemetry.queueDropCount}',
                        valueColor: telemetry.queueDropCount > 0
                            ? AppTheme.statusRejected
                            : AppTheme.textSecondary,
                      ),
                      const Divider(color: AppTheme.surfaceBorder),
                      _buildRow(
                        icon: Icons.wifi_off_outlined,
                        label: 'Network Timeouts (3s limit)',
                        value: '${telemetry.networkTimeoutCount}',
                        valueColor: telemetry.networkTimeoutCount > 0
                            ? AppTheme.statusRejected
                            : AppTheme.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Section: Device & Environment Health
              const Text(
                'DEVICE & GATE CONFIGURATION',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 10),

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _buildRow(
                        icon: Icons.meeting_room_outlined,
                        label: 'Gate / Direction',
                        value: 'Gate #${state.gateId} (${state.scanType})',
                        valueColor: Colors.white,
                      ),
                      const Divider(color: AppTheme.surfaceBorder),
                      _buildRow(
                        icon: Icons.event,
                        label: 'Configured Event ID',
                        value: 'Event #${state.eventId}',
                        valueColor: Colors.white,
                      ),
                      const Divider(color: AppTheme.surfaceBorder),
                      _buildRow(
                        icon: Icons.cloud_done_outlined,
                        label: 'Offline Admission Mode',
                        value: state.isOfflineMode ? 'ENABLED (Queue active)' : 'DISABLED (Authoritative)',
                        valueColor: state.isOfflineMode ? Colors.amber : AppTheme.statusSuccess,
                      ),
                      const Divider(color: AppTheme.surfaceBorder),
                      _buildRow(
                        icon: Icons.fingerprint,
                        label: 'Device UUID',
                        value: state.deviceId,
                        valueColor: AppTheme.textMuted,
                        isMono: true,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    required Color color,
    required String subtitle,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surfaceElevated,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.surfaceBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: color,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 10,
                color: AppTheme.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow({
    required IconData icon,
    required String label,
    required String value,
    required Color valueColor,
    bool isMono = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              fontFamily: isMono ? 'monospace' : null,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}
