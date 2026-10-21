import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme/app_theme.dart';
import '../../data/adapters/simulated_hardware_adapter.dart';
import '../bloc/scanner_bloc.dart';
import '../bloc/scanner_event.dart';

class SimulatorScreen extends StatefulWidget {
  final SimulatedHardwareAdapter simulatorAdapter;

  const SimulatorScreen({
    super.key,
    required this.simulatorAdapter,
  });

  @override
  State<SimulatorScreen> createState() => _SimulatorScreenState();
}

class _SimulatorScreenState extends State<SimulatorScreen> {
  final TextEditingController _customTokenController = TextEditingController();
  bool _isBurstRunning = false;

  @override
  void dispose() {
    _customTokenController.dispose();
    super.dispose();
  }

  void _triggerScan(String code) {
    context.read<ScannerBloc>().add(ScannerRawBarcodeReceived(code));
    widget.simulatorAdapter.triggerScan(code);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Injected hardware decode: "$code"'),
        duration: const Duration(milliseconds: 900),
        backgroundColor: AppTheme.accentIndigo,
      ),
    );
  }

  Future<void> _runDuplicateSuppressionBurst() async {
    setState(() => _isBurstRunning = true);
    final code = 'VIP-BURST-TEST-${DateTime.now().millisecondsSinceEpoch % 1000}';

    // Fire 8 identical scans in 240ms (each 30ms apart)
    // Expectation: 1st admitted, 7 suppressed by 300ms benchmark!
    for (int i = 0; i < 8; i++) {
      Future.delayed(Duration(milliseconds: i * 30), () {
        if (mounted) {
          context.read<ScannerBloc>().add(ScannerRawBarcodeReceived(code));
        }
      });
    }
    await widget.simulatorAdapter.triggerBurst(
      barcode: code,
      count: 8,
      interval: const Duration(milliseconds: 30),
    );

    if (mounted) {
      setState(() => _isBurstRunning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Burst complete: 8 scans fired in 240ms. Check diagnostics for 7 suppressed duplicates!'),
          backgroundColor: Colors.teal,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _runQueueOverflowStressTest() async {
    setState(() => _isBurstRunning = true);

    // Fire 55 unique scans rapidly to exceed bounded FIFO limit (max 50)
    for (int i = 0; i < 55; i++) {
      widget.simulatorAdapter.triggerScan('STRESS-CODE-$i-${DateTime.now().millisecondsSinceEpoch}');
      await Future.delayed(const Duration(milliseconds: 5));
    }

    if (mounted) {
      setState(() => _isBurstRunning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Stress burst complete: 55 codes fired. Safe bounded FIFO queue overflow tested!'),
          backgroundColor: Colors.indigo,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hardware Scanner Simulator'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Banner
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: const Row(
              children: [
                Icon(Icons.science_outlined, color: Colors.amberAccent, size: 32),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Simulate physical laser scan triggers, hardware intent events, and burst stress tests without Zebra hardware.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.textPrimary,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Custom Input Injection
          const Text(
            'CUSTOM QR TOKEN INJECTION',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),

          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _customTokenController,
                  decoration: InputDecoration(
                    hintText: 'Enter test QR token (e.g. VIP-TEST-01)',
                    filled: true,
                    fillColor: AppTheme.surfaceElevated,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.surfaceBorder),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: () {
                  final text = _customTokenController.text.trim();
                  if (text.isNotEmpty) {
                    _triggerScan(text);
                  }
                },
                icon: const Icon(Icons.flash_on, size: 18),
                label: const Text('TRIGGER'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentIndigo,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Presets
          const Text(
            'ADMISSION TEST PRESETS',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 10),

          _buildPresetCard(
            title: 'Valid VIP Speaker (Victoria Sterling)',
            code: 'VIP-2026-VICTORIA-STERLING',
            expected: 'ENTRY_ALLOWED • Green Success',
            expectedColor: AppTheme.statusSuccess,
            icon: Icons.check_circle,
            onTap: () => _triggerScan('VIP-2026-VICTORIA-STERLING'),
          ),

          const SizedBox(height: 8),

          _buildPresetCard(
            title: 'Valid Exhibitor (Marcus Vance)',
            code: 'EXH-ZEBRA-PARTNER-009',
            expected: 'ENTRY_ALLOWED • Green Success',
            expectedColor: AppTheme.statusSuccess,
            icon: Icons.badge_outlined,
            onTap: () => _triggerScan('EXH-ZEBRA-PARTNER-009'),
          ),

          const SizedBox(height: 8),

          _buildPresetCard(
            title: 'Already Admitted Badge (Replay Test)',
            code: 'USED-BADGE-CHECKED-IN-001',
            expected: 'ALREADY_CHECKED_IN • Amber Warning',
            expectedColor: AppTheme.statusWarning,
            icon: Icons.warning_amber,
            onTap: () => _triggerScan('USED-BADGE-CHECKED-IN-001'),
          ),

          const SizedBox(height: 8),

          _buildPresetCard(
            title: 'Wrong Event Badge (Scanned at Event #1025)',
            code: 'WRONG-EVT-1025-TOKEN',
            expected: 'WRONG_EVENT • Red Rejection (Zero PII)',
            expectedColor: AppTheme.statusRejected,
            icon: Icons.cancel,
            onTap: () => _triggerScan('WRONG-EVT-1025-TOKEN'),
          ),

          const SizedBox(height: 8),

          _buildPresetCard(
            title: 'Expired Badge Validity',
            code: 'EXPIRED-PASS-OCT18',
            expected: 'EXPIRED • Red Rejection',
            expectedColor: AppTheme.statusRejected,
            icon: Icons.history_toggle_off,
            onTap: () => _triggerScan('EXPIRED-PASS-OCT18'),
          ),

          const SizedBox(height: 8),

          _buildPresetCard(
            title: 'Malformed / Unreadable QR Payload',
            code: 'MALFORMED##%!',
            expected: 'INVALID_BADGE • Red Rejection',
            expectedColor: AppTheme.statusRejected,
            icon: Icons.error_outline,
            onTap: () => _triggerScan('MALFORMED##%!'),
          ),

          const SizedBox(height: 24),

          // Stress Tests
          const Text(
            'STRESS & CONCURRENCY TESTS (SECTIONS 7 & 9)',
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '1. Hardware Duplicate Callback Suppression (300ms benchmark)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Fires 8 rapid hardware events of the exact same barcode within 240ms. The controller must suppress 7 duplicate events and make only 1 API request.',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isBurstRunning ? null : _runDuplicateSuppressionBurst,
                      icon: const Icon(Icons.bolt, size: 18),
                      label: const Text('RUN 300MS DEDUPLICATION BURST'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.tealAccent,
                        side: const BorderSide(color: Colors.tealAccent),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),
                  const Divider(color: AppTheme.surfaceBorder),
                  const SizedBox(height: 12),

                  const Text(
                    '2. Bounded FIFO Queue Overflow Stress Test',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Fires 55 distinct scans at high frequency to verify the 50-item bounded queue limit and safe overflow drop handling without app crashes.',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isBurstRunning ? null : _runQueueOverflowStressTest,
                      icon: const Icon(Icons.speed, size: 18),
                      label: const Text('RUN 55-SCAN FIFO OVERFLOW TEST'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.indigoAccent,
                        side: const BorderSide(color: Colors.indigoAccent),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildPresetCard({
    required String title,
    required String code,
    required String expected,
    required Color expectedColor,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: expectedColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: expectedColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Token: $code',
                      style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      expected,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: expectedColor,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.play_circle_fill, color: AppTheme.accentIndigo),
                onPressed: onTap,
                tooltip: 'Scan Now',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
