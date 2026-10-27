import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../bloc/auth/auth_bloc.dart';
import '../../bloc/auth/auth_event.dart';
import '../../bloc/auth/auth_state.dart';
import '../../widgets/app_background.dart';
import 'login_screen.dart';

import '../../../core/services/app_update_service.dart';
import '../../widgets/update_dialog.dart';

class SplashScreen extends StatefulWidget {
  final Widget authenticatedHome;

  const SplashScreen({super.key, required this.authenticatedHome});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _checkingUpdate = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkUpdateAndProceed();
    });
  }

  Future<void> _checkUpdateAndProceed() async {
    // 1. Check for app updates via Firebase Remote Config
    final updateInfo = await AppUpdateService().checkForUpdate();

    if (!mounted) return;

    if (updateInfo.isForceUpdate) {
      // Force update: show non-dismissible dialog and halt progression
      debugPrint('[SplashScreen] 🚨 Triggering Force Update dialog');
      await UpdateDialog.show(context, updateInfo);
      return;
    }

    if (updateInfo.isRegularUpdate) {
      // Regular update: show prompt with "Later" option
      debugPrint('[SplashScreen] ℹ️ Triggering Regular Update dialog');
      await UpdateDialog.show(context, updateInfo);
    }

    if (!mounted) return;

    setState(() {
      _checkingUpdate = false;
    });

    // 2. Proceed to check auth status and navigate
    context.read<AuthBloc>().add(const CheckAuthStatus());
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AuthBloc, AuthState>(
      listener: (context, state) {
        if (_checkingUpdate) return; // Prevent navigation while update check is active
        if (state is AuthAuthenticated) {
          Navigator.of(context).pushReplacement(
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) =>
                  widget.authenticatedHome,
              transitionsBuilder:
                  (context, animation, secondaryAnimation, child) =>
                      FadeTransition(opacity: animation, child: child),
              transitionDuration: const Duration(milliseconds: 600),
            ),
          );
        } else if (state is AuthUnauthenticated) {
          Navigator.of(context).pushReplacement(
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) =>
                  const LoginScreen(),
              transitionsBuilder:
                  (context, animation, secondaryAnimation, child) =>
                      FadeTransition(opacity: animation, child: child),
              transitionDuration: const Duration(milliseconds: 600),
            ),
          );
        }
      },
      builder: (context, state) {
        return AppBackground(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Hero(
                  tag: 'app_logo',
                  child: Image.asset(
                    'assets/images/logo.png',
                    width: 180,
                    height: 180,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => const Icon(
                      Icons.qr_code_scanner_rounded,
                      size: 96,
                      color: Colors.white,
                    ),
                  ),
                )
                    .animate()
                    .scale(
                      duration: 800.ms,
                      curve: Curves.easeOutBack,
                      begin: const Offset(0.6, 0.6),
                      end: const Offset(1.0, 1.0),
                    )
                    .fadeIn(duration: 600.ms),
                const SizedBox(height: 24),
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
