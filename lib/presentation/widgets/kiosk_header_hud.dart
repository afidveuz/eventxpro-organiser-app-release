import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../bloc/scanner_state.dart';

class KioskHeaderHud extends StatelessWidget {
  final ScannerState state;
  final VoidCallback onOpenDiagnostics;
  final VoidCallback onOpenSimulator;
  final VoidCallback onOpenSettings;
  final VoidCallback onSyncOffline;
  final VoidCallback onOpenHistory;

  const KioskHeaderHud({
    super.key,
    required this.state,
    required this.onOpenDiagnostics,
    required this.onOpenSimulator,
    required this.onOpenSettings,
    required this.onSyncOffline,
    required this.onOpenHistory,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.95),
        border: const Border(
          bottom: BorderSide(color: AppTheme.surfaceBorder, width: 1),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top Row: Brand & Gate on left, Action buttons on right
            Row(
              children: [
                // App Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    ),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: const Text(
                    'EventXPro',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Event & Gate Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'EVT #${state.eventId} • GATE ${state.gateId.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        state.scanType,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.accentIndigo,
                        ),
                      ),
                    ],
                  ),
                ),

                // Action Buttons
                IconButton(
                  icon: const Icon(Icons.history, size: 20),
                  tooltip: 'Recent Scans Log',
                  onPressed: onOpenHistory,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                ),
                IconButton(
                  icon: const Icon(Icons.analytics_outlined, size: 20),
                  tooltip: 'Telemetry & Benchmarks',
                  onPressed: onOpenDiagnostics,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                ),
                IconButton(
                  icon: const Icon(Icons.qr_code_scanner, size: 20),
                  tooltip: 'Scanner Simulator',
                  onPressed: onOpenSimulator,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                ),
                IconButton(
                  icon: const Icon(Icons.settings_outlined, size: 20),
                  tooltip: 'DataWedge Provisioning',
                  onPressed: onOpenSettings,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                ),
              ],
            ),

            const SizedBox(height: 6),

            // Sub-Row: Adapter Badge & Offline Queue Status
            Row(
              children: [
                // Adapter Indicator Pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: state.adapterName.contains('Native')
                        ? const Color(0xFF064E3B)
                        : const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: state.adapterName.contains('Native')
                          ? const Color(0xFF10B981)
                          : const Color(0xFF475569),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        state.adapterName.contains('Native')
                            ? Icons.bolt
                            : Icons.developer_mode,
                        size: 11,
                        color: state.adapterName.contains('Native')
                            ? const Color(0xFF34D399)
                            : Colors.amberAccent,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        state.adapterName.contains('Native')
                            ? 'Zebra DataWedge Native'
                            : 'Virtual Simulator',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: state.adapterName.contains('Native')
                              ? const Color(0xFFD1FAE5)
                              : Colors.amberAccent,
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // Offline Queue Pill (if items pending)
                if (state.queueDepth > 0)
                  InkWell(
                    onTap: onSyncOffline,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade900.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amber.shade600),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.cloud_upload_outlined,
                              size: 11, color: Colors.amber),
                          const SizedBox(width: 4),
                          Text(
                            '${state.queueDepth} Queued (Sync)',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.amber,
                            ),
                          ),
                        ],
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
}
