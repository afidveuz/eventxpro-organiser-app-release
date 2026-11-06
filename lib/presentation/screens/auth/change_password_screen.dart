import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_toast.dart';
import '../../../data/datasources/scanner_local_storage.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../bloc/auth/auth_bloc.dart';
import '../../bloc/auth/auth_event.dart';
import '../../widgets/app_background_layer.dart';
import '../../widgets/gradient_button.dart';
import 'login_screen.dart';

/// Screen for updating an authenticated organizer's password.
/// Matches the React Native EventXPro Organiser NewPassword screen flow
/// and hits the 'organizer/change-password' API endpoint.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final _passwordFocusNode = FocusNode();
  final _confirmPasswordFocusNode = FocusNode();

  bool _isPasswordObscured = true;
  bool _isConfirmPasswordObscured = true;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _passwordFocusNode.dispose();
    _confirmPasswordFocusNode.dispose();
    super.dispose();
  }

  Future<void> _submitChangePassword() async {
    // 1. Guard against offline mode
    final storage = context.read<ScannerLocalStorage>();
    if (storage.isOfflineModeEnabled) {
      const offlineMsg =
          'Password change is disabled while offline mode is active. Please switch to online mode.';
      setState(() => _errorMessage = offlineMsg);
      AppToast.showWarning(context: context, message: offlineMsg);
      return;
    }

    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    // 2. Client-side validations matching React Native NewPassword.jsx
    if (password.trim().isEmpty) {
      const msg = 'Please Enter New Password';
      setState(() => _errorMessage = msg);
      AppToast.showWarning(context: context, message: msg);
      _passwordFocusNode.requestFocus();
      return;
    }

    if (confirmPassword.trim().isEmpty) {
      const msg = 'Please Enter Confirm Password';
      setState(() => _errorMessage = msg);
      AppToast.showWarning(context: context, message: msg);
      _confirmPasswordFocusNode.requestFocus();
      return;
    }

    if (password != confirmPassword) {
      const msg = 'Password does not match';
      setState(() => _errorMessage = msg);
      AppToast.showWarning(context: context, message: msg);
      _confirmPasswordFocusNode.requestFocus();
      return;
    }

    if (password.length < 6) {
      const msg = 'Password must be at least 6 characters long';
      setState(() => _errorMessage = msg);
      AppToast.showWarning(context: context, message: msg);
      _passwordFocusNode.requestFocus();
      return;
    }

    // 3. Clear keyboard and initiate submit
    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authRepo = context.read<AuthRepository>();
      final result = await authRepo.changePassword(
        password: password,
        confirmPassword: confirmPassword,
      );

      if (!mounted) return;

      final isSuccess = result['status'] == true;
      if (isSuccess) {
        // Matching React Native: clear local tokens & user and redirect to login
        context.read<AuthBloc>().add(const LogoutRequested());
        await authRepo.logout();

        if (!mounted) return;

        final successMsg = (result['message'] as String?)?.isNotEmpty == true
            ? result['message'] as String
            : 'Password changed successfully! Please log in with your new password.';

        AppToast.showSuccess(
          context: context,
          message: successMsg,
          duration: const Duration(seconds: 4),
        );

        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      } else {
        final errorMsg = (result['message'] as String?)?.isNotEmpty == true
            ? result['message'] as String
            : 'Failed to update password. Please try again.';

        setState(() {
          _isLoading = false;
          _errorMessage = errorMsg;
        });

        AppToast.showError(context: context, message: errorMsg);
      }
    } catch (e) {
      if (!mounted) return;
      const errorMsg = 'An unexpected error occurred. Please try again.';
      setState(() {
        _isLoading = false;
        _errorMessage = errorMsg;
      });
      AppToast.showError(context: context, message: errorMsg);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
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
            'Change Password',
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
            SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Lock header icon & title
                  Center(
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.accentIndigo.withValues(alpha: 0.12),
                        border: Border.all(
                          color: AppTheme.accentIndigo.withValues(alpha: 0.3),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.accentIndigo.withValues(alpha: 0.2),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.lock_reset_rounded,
                        color: AppTheme.accentIndigo,
                        size: 36,
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  const Text(
                    'Set New Password',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                  ),

                  const SizedBox(height: 8),

                  const Text(
                    'Choose a strong password with at least 6 characters. You will need to log in again after updating.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13.5,
                      height: 1.45,
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Error Banner
                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.statusError.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppTheme.statusError.withValues(alpha: 0.4),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            color: AppTheme.statusError,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(
                                color: AppTheme.statusError,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // New Password Field
                  _buildInputField(
                    label: 'NEW PASSWORD',
                    placeholder: 'Enter new password',
                    controller: _passwordController,
                    focusNode: _passwordFocusNode,
                    isObscured: _isPasswordObscured,
                    onToggleObscure: () {
                      setState(() {
                        _isPasswordObscured = !_isPasswordObscured;
                      });
                    },
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) {
                      _confirmPasswordFocusNode.requestFocus();
                    },
                  ),

                  const SizedBox(height: 20),

                  // Confirm Password Field
                  _buildInputField(
                    label: 'CONFIRM PASSWORD',
                    placeholder: 'Re-enter new password',
                    controller: _confirmPasswordController,
                    focusNode: _confirmPasswordFocusNode,
                    isObscured: _isConfirmPasswordObscured,
                    onToggleObscure: () {
                      setState(() {
                        _isConfirmPasswordObscured = !_isConfirmPasswordObscured;
                      });
                    },
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submitChangePassword(),
                  ),

                  const SizedBox(height: 36),

                  // Submit Button
                  GradientButton(
                    text: 'SUBMIT',
                    isLoading: _isLoading,
                    onPressed: _isLoading ? null : _submitChangePassword,
                    isRound: true,
                    color: AppTheme.accentIndigo,
                  ),

                  const SizedBox(height: 20),

                  // Password criteria tips card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceElevated.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppTheme.surfaceBorder.withValues(alpha: 0.6),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.security_rounded,
                              color: AppTheme.accentCyan,
                              size: 16,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Security Recommendation',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '• Minimum 6 characters\n• Include letters, numbers, and symbols for better safety\n• Do not reuse old passwords',
                          style: TextStyle(
                            color: AppTheme.textMuted.withValues(alpha: 0.9),
                            fontSize: 12,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputField({
    required String label,
    required String placeholder,
    required TextEditingController controller,
    required FocusNode focusNode,
    required bool isObscured,
    required VoidCallback onToggleObscure,
    required TextInputAction textInputAction,
    required ValueChanged<String> onSubmitted,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            label,
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
        ),
        Container(
          height: 50,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(50),
            border: Border.all(
              color: focusNode.hasFocus
                  ? AppTheme.accentIndigo
                  : AppTheme.surfaceBorder,
              width: focusNode.hasFocus ? 1.4 : 1.0,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: [
              const Icon(
                Icons.lock_outline_rounded,
                color: AppTheme.textMuted,
                size: 19,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  obscureText: isObscured,
                  textInputAction: textInputAction,
                  onSubmitted: onSubmitted,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    letterSpacing: 0.4,
                  ),
                  decoration: InputDecoration(
                    hintText: placeholder,
                    hintStyle: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 14,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              IconButton(
                splashRadius: 20,
                icon: Icon(
                  isObscured
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: AppTheme.textMuted,
                  size: 19,
                ),
                onPressed: onToggleObscure,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
