import 'package:flutter/material.dart';
import 'forgot_password_screen.dart';

/// Backward-compatible wrapper that directs to the full 3-step [ForgotPasswordScreen].
class ForgotPasswordDialog extends StatelessWidget {
  const ForgotPasswordDialog({super.key});

  static Future<void> show(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => const ForgotPasswordScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const ForgotPasswordScreen();
  }
}
