import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/navigation/app_route_observer.dart';
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
class KioskScannerScreen extends StatefulWidget {
  final ZebraDataWedgeAdapter zebraAdapter;
  final SimulatedHardwareAdapter simulatorAdapter;
  final String? initialPunchType;
  final int? initialGateId;
  final int? initialEventId;

  final String? gateName;
  final String? eventName;
  final String? section;
  final String? sectionLocation;

  KioskScannerScreen({
    super.key,
    ZebraDataWedgeAdapter? zebraAdapter,
    SimulatedHardwareAdapter? simulatorAdapter,
    this.initialPunchType,
    this.initialGateId,
    this.initialEventId,
    this.gateName,
    this.eventName,
    this.section,
    this.sectionLocation,
  })  : zebraAdapter = zebraAdapter ?? ZebraDataWedgeAdapter(),
        simulatorAdapter = simulatorAdapter ?? SimulatedHardwareAdapter();

  @override
  State<KioskScannerScreen> createState() => _KioskScannerScreenState();
}

class _KioskScannerScreenState extends State<KioskScannerScreen>
    with RouteAware, WidgetsBindingObserver {
  ScannerBloc? _scannerBloc;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _scannerBloc = context.read<ScannerBloc>();
    // Enable hardware scanning when scanner screen is active
    _scannerBloc?.add(const ScannerScanningResumed());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.initialPunchType != null ||
          widget.initialGateId != null ||
          widget.initialEventId != null ||
          widget.section != null) {
        _scannerBloc?.add(
              ScannerConfigChanged(
                scanType: widget.initialPunchType,
                gateId: widget.initialGateId,
                eventId: widget.initialEventId,
                section: widget.section,
                sectionLocation: widget.sectionLocation,
              ),
            );
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scannerBloc = context.read<ScannerBloc>();
    final modalRoute = ModalRoute.of(context);
    if (modalRoute is PageRoute) {
      appRouteObserver.subscribe(this, modalRoute);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    appRouteObserver.unsubscribe(this);
    // Pause scanning when leaving the scanner screen safely via saved bloc reference
    _scannerBloc?.add(const ScannerScanningPaused());
    super.dispose();
  }

  // RouteAware overrides
  @override
  void didPush() {
    // Screen pushed and visible
    _scannerBloc?.add(const ScannerScanningResumed());
  }

  @override
  void didPopNext() {
    // Screen foregrounded again (e.g. Settings screen closed)
    _scannerBloc?.add(const ScannerScanningResumed());
  }

  @override
  void didPushNext() {
    // Another screen pushed on top of scanner (e.g. Settings screen opened)
    _scannerBloc?.add(const ScannerScanningPaused());
  }

  @override
  void didPop() {
    // Scanner screen popped back to home
    _scannerBloc?.add(const ScannerScanningPaused());
  }

  // WidgetsBindingObserver overrides
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.resumed) {
      final isCurrent = ModalRoute.of(context)?.isCurrent ?? false;
      if (isCurrent) {
        _scannerBloc?.add(const ScannerScanningResumed());
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _scannerBloc?.add(const ScannerScanningPaused());
    }
  }

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
      backgroundColor: AppTheme.eventxproBg,
      body: BlocConsumer<ScannerBloc, ScannerState>(
        listener: (context, state) {},
        builder: (context, state) {
          return SimpleScannerView(
            state: state,
            gateName: widget.gateName,
            eventName: widget.eventName,
            section: widget.section,
            sectionLocation: widget.sectionLocation,
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
