import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/config/app_constants.dart';
import '../../core/services/device_detection_service.dart';
import '../../core/theme/app_theme.dart';
import '../../data/datasources/scanner_local_storage.dart';
import '../bloc/scanner_bloc.dart';
import '../bloc/scanner_event.dart';
import '../bloc/scanner_state.dart';
import 'auth/change_password_screen.dart';
import '../widgets/app_background_layer.dart';

/// Settings screen matching the React Native EventXPro Organiser Settings screen.
/// Includes:
/// - Top-level tickets toggle with confirmation
/// - Short toast toggle with confirmation
/// - Offline mode toggle with confirmation
/// - Hardware scanner diagnostics and Honeywell / Zebra guides
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isTopLevelTickets = false;
  bool _isShortToast = false;
  bool _isOfflineMode = false;
  DeviceInfoResult? _deviceInfo;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final storage = context.read<ScannerLocalStorage>();
    final info = await DeviceDetectionService().detectDevice(storage: storage);

    if (mounted) {
      setState(() {
        _isTopLevelTickets = storage.isTopLevelTicketsEnabled;
        _isShortToast = storage.isShortToastEnabled;
        _isOfflineMode = storage.isOfflineModeEnabled;
        _deviceInfo = info;
      });
    }
  }

  Future<void> _showConfirmDialog({
    required String title,
    required String message,
    required VoidCallback onConfirm,
    bool isDestructive = false,
  }) async {
    return showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppTheme.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.surfaceBorder),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          message,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 14,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppTheme.textMuted),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isDestructive
                  ? const Color(0xFFFF6767)
                  : AppTheme.accentIndigo,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              onConfirm();
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleTopLevelTickets() async {
    final nextState = !_isTopLevelTickets;
    _showConfirmDialog(
      title: nextState
          ? 'Enable Top-Level Tickets'
          : 'Disable Top-Level Tickets',
      message: nextState
          ? 'Are you sure you want to enable top-level tickets for scanner admittance?'
          : 'Are you sure you want to disable top-level tickets?',
      onConfirm: () async {
        final storage = context.read<ScannerLocalStorage>();
        await storage.setTopLevelTickets(nextState);
        setState(() {
          _isTopLevelTickets = nextState;
        });
      },
    );
  }

  Future<void> _toggleShortToast() async {
    final nextState = !_isShortToast;
    _showConfirmDialog(
      title: nextState ? 'Enable Short Toast' : 'Disable Short Toast',
      message: nextState
          ? 'Enable short toast for rush periods? This keeps the scanner live for continuous rapid scanning and shows brief top notifications.'
          : 'Disable short toast? This will display the full attendee profile card after every scan.',
      onConfirm: () async {
        final storage = context.read<ScannerLocalStorage>();
        await storage.setShortToast(nextState);
        setState(() {
          _isShortToast = nextState;
        });
      },
    );
  }

  Future<void> _toggleOfflineMode() async {
    final nextState = !_isOfflineMode;
    _showConfirmDialog(
      title: nextState ? 'Enable Offline Mode' : 'Disable Offline Mode',
      message: nextState
          ? 'Are you sure you want to enable offline mode? All scans will be saved locally and queued for batch sync.'
          : 'Are you sure you want to disable offline mode and return to online authoritative validation?',
      onConfirm: () async {
        final storage = context.read<ScannerLocalStorage>();
        await storage.setOfflineMode(nextState);
        if (mounted) {
          context.read<ScannerBloc>().add(
            ScannerConfigChanged(offlineModeEnabled: nextState),
          );
          setState(() {
            _isOfflineMode = nextState;
          });
        }
      },
    );
  }



  void _showHoneywellGuideDialog() {
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppTheme.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.surfaceBorder),
        ),
        title: const Row(
          children: [
            Icon(Icons.tune_rounded, color: Color(0xFFEF5350), size: 20),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Honeywell EDA51 Settings',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'EventXPro automatically claims the Honeywell scanner engine. If your device MDM requires manual confirmation, verify these settings:',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              SizedBox(height: 12),
              _StepRow(step: '1', text: 'Open Android Settings on device'),
              _StepRow(
                step: '2',
                text: 'Select "Honeywell Settings" > "Scanning"',
              ),
              _StepRow(
                step: '3',
                text: 'Tap "Internal Scanner" > "Default Profile"',
              ),
              _StepRow(step: '4', text: 'Open "Data Processing Settings"'),
              _StepRow(step: '5', text: 'Enable "Data Intent"'),
              _StepRow(step: '6', text: 'Set Action to: com.eventxpro.SCAN'),
              _StepRow(
                step: '7',
                text: 'Disable "Wedge" (prevents typing delay)',
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF5350),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text(
              'Understood',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        centerTitle: false,
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
            size: 20,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Settings',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.3,
          ),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(color: AppTheme.surfaceBorder, height: 1),
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const AppBackgroundLayer(),
          RefreshIndicator(
            color: AppTheme.eventxproAccent,
            backgroundColor: AppTheme.surfaceElevated,
            onRefresh: _loadSettings,
            child: BlocBuilder<ScannerBloc, ScannerState>(
              builder: (context, state) {
                return ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    _buildTopLevelTicketsTile(),

                    const SizedBox(height: 10),

                    _buildShortToastTile(),

                    const SizedBox(height: 10),

                    _buildOfflineModeTile(),

                    if (!_isOfflineMode) ...[
                      const SizedBox(height: 10),
                      _buildChangePasswordTile(),
                    ],

                    // const SizedBox(height: 10),

                    // _buildHardwareDiagnosticsCard(state),

                    _buildVersionFooter(),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopLevelTicketsTile() {
    return _buildGlassCard(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        leading: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: AppTheme.accentIndigo.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.confirmation_number_outlined,
            color: AppTheme.accentIndigo,
            size: 22,
          ),
        ),
        title: const Text(
          'Top-Level Tickets',
          style: TextStyle(
            color: Colors.white,
            fontSize: 15.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
        trailing: _buildCustomSwitch(
          value: _isTopLevelTickets,
          onChanged: (_) => _toggleTopLevelTickets(),
        ),
        onTap: _toggleTopLevelTickets,
      ),
    );
  }

  Widget _buildShortToastTile() {
    return _buildGlassCard(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        leading: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: AppTheme.accentIndigo.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.bolt_rounded,
            color: AppTheme.accentIndigo,
            size: 22,
          ),
        ),
        title: const Text(
          'Short Toast',
          style: TextStyle(
            color: Colors.white,
            fontSize: 15.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
        trailing: _buildCustomSwitch(
          value: _isShortToast,
          onChanged: (_) => _toggleShortToast(),
        ),
        onTap: _toggleShortToast,
      ),
    );
  }

  Widget _buildOfflineModeTile() {
    return _buildGlassCard(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        leading: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: AppTheme.accentIndigo.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.cloud_off_rounded,
            color: AppTheme.accentIndigo,
            size: 22,
          ),
        ),
        title: const Text(
          'Offline Mode',
          style: TextStyle(
            color: Colors.white,
            fontSize: 15.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
        trailing: _buildCustomSwitch(
          value: _isOfflineMode,
          onChanged: (_) => _toggleOfflineMode(),
        ),
        onTap: _toggleOfflineMode,
      ),
    );
  }

  Widget _buildChangePasswordTile() {
    return _buildGlassCard(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        leading: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: AppTheme.accentIndigo.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.lock_outline_rounded,
            color: AppTheme.accentIndigo,
            size: 22,
          ),
        ),
        title: const Text(
          'Change Password',
          style: TextStyle(
            color: Colors.white,
            fontSize: 15.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
        trailing: const Icon(
          Icons.arrow_forward_ios_rounded,
          color: AppTheme.textMuted,
          size: 14,
        ),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ChangePasswordScreen()),
          );
        },
      ),
    );
  }

  Widget _buildCustomSwitch({
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44,
        height: 26,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: value ? AppTheme.accentIndigo : const Color(0xFF3F414D),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 20,
            height: 20,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildHardwareDiagnosticsCard(ScannerState state) {
    final dev = _deviceInfo;
    return _buildGlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: AppTheme.accentIndigo.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.developer_board_rounded,
                  color: AppTheme.accentIndigo,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Hardware Diagnostics',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
              const Spacer(),
              if (dev != null && dev.isHardwareScannerCapable)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.accentIndigo.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: AppTheme.accentIndigo.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    dev.isHoneywell ? 'HONEYWELL' : 'ZEBRA',
                    style: const TextStyle(
                      color: Color(0xFFC7D2FE),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
          const SizedBox(height: 10),
          _buildInfoRow('Device Model', dev?.displayName ?? 'Android Device'),
          _buildInfoRow(
            'Scanner Engine',
            dev?.scannerEngine ?? state.adapterName,
          ),
          if (dev != null && dev.osRelease.isNotEmpty)
            _buildInfoRow(
              'Operating System',
              'Android ${dev.osRelease} (API ${dev.sdkInt})',
            ),
          _buildInfoRow('Current Event ID', 'Event #${state.eventId}'),
          _buildInfoRow(
            'Gate / Scan Type',
            'Gate #${state.gateId} (${state.scanType})',
          ),
          if (dev == null || dev.isHoneywell) ...[
            const SizedBox(height: 10),
            Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
            const SizedBox(height: 8),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _showHoneywellGuideDialog,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const Icon(
                      Icons.settings_suggest_rounded,
                      color: AppTheme.accentIndigo,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Honeywell EDA51 Setup Guide',
                      style: TextStyle(
                        color: Color(0xFFC7D2FE),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    const Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: AppTheme.textMuted,
                      size: 13,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVersionFooter() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          children: [
            Text(
              'EventXPro Organiser • ${AppConstants.appVersion}',
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Connected to EventXPro Access Control',
              style: TextStyle(color: Color(0xFF4A4B56), fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlassCard({
    required Widget child,
    BorderRadius? borderRadius,
    EdgeInsetsGeometry? padding,
    Border? border,
  }) {
    final radius = borderRadius ?? BorderRadius.circular(14);
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: radius,
            border:
                border ??
                Border.all(
                  color: Colors.white.withValues(alpha: 0.12),
                  width: 1,
                ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
          ),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final String step;
  final String text;

  const _StepRow({required this.step, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: const Color(0xFFEF5350).withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                step,
                style: const TextStyle(
                  color: Color(0xFFFF8A80),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white70, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}
