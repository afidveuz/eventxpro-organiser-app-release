import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme/app_theme.dart';
import '../../data/adapters/simulated_hardware_adapter.dart';
import '../../data/adapters/zebra_datawedge_adapter.dart';
import '../bloc/scanner_bloc.dart';
import '../bloc/scanner_event.dart';
import '../bloc/scanner_state.dart';
import '../bloc/auth/auth_bloc.dart';
import '../bloc/auth/auth_event.dart';
import '../widgets/simple_scanner_view.dart';
import 'auth/login_screen.dart';

/// Clean, streamlined Scanner Screen for EventXPro gate staff.
/// Provides native Zebra hardware barcode broadcast listening with high-visibility attendee validation.
class KioskScannerScreen extends StatelessWidget {
  final ZebraDataWedgeAdapter zebraAdapter;
  final SimulatedHardwareAdapter simulatorAdapter;

  KioskScannerScreen({
    super.key,
    ZebraDataWedgeAdapter? zebraAdapter,
    SimulatedHardwareAdapter? simulatorAdapter,
  })  : zebraAdapter = zebraAdapter ?? ZebraDataWedgeAdapter(),
        simulatorAdapter = simulatorAdapter ?? SimulatedHardwareAdapter();

  void _handleLogout(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppTheme.surfaceElevated,
        title: const Text(
          'Log Out',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Are you sure you want to log out of EventXPro?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              context.read<AuthBloc>().add(const LogoutRequested());
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
            child: const Text(
              'Log Out',
              style: TextStyle(
                color: Color(0xFFFF6767),
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
      body: BlocConsumer<ScannerBloc, ScannerState>(
        listener: (context, state) {},
        builder: (context, state) {
          return SimpleScannerView(
            state: state,
            onLogout: () => _handleLogout(context),
            onResetToReady: () {
              context
                  .read<ScannerBloc>()
                  .add(const ScannerFeedbackTimeout());
            },
          );
        },
      ),
    );
  }
}
