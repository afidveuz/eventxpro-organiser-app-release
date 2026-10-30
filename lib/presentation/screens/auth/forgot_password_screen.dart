import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/config/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../widgets/app_background.dart';
import '../../widgets/gradient_button.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  // Step 1: Email, Step 2: OTP, Step 3: Set Password
  int _currentStep = 1;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  // 4-digit OTP controllers and focus nodes
  final List<TextEditingController> _otpControllers =
      List.generate(4, (_) => TextEditingController());
  final List<FocusNode> _otpFocusNodes =
      List.generate(4, (_) => FocusNode());

  bool _isNewPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _isLoading = false;
  String? _errorMessage;

  // 30-second countdown timer for OTP resend
  Timer? _timer;
  int _timerSeconds = 30;

  // Stored token received from OTP verification for the reset-password call
  String _resetToken = '';

  @override
  void dispose() {
    _timer?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    for (final c in _otpControllers) {
      c.dispose();
    }
    for (final fn in _otpFocusNodes) {
      fn.dispose();
    }
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _timerSeconds = 30);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_timerSeconds > 0) {
        setState(() => _timerSeconds--);
      } else {
        timer.cancel();
      }
    });
  }

  bool _isValidEmail(String email) {
    final validRegex = RegExp(
      r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)*$",
    );
    return validRegex.hasMatch(email.trim());
  }

  String get _enteredOtp {
    return _otpControllers.map((c) => c.text.trim()).join();
  }

  void _clearOtp() {
    for (final c in _otpControllers) {
      c.clear();
    }
  }

  // --- Step 1: Generate OTP ---
  Future<void> _generateOtp() async {
    final email = _emailController.text.trim();
    if (!_isValidEmail(email)) {
      setState(() => _errorMessage = 'Please Enter Valid Email');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final authRepo = context.read<AuthRepository>();
    final result = await authRepo.generateOtp(email);

    if (!mounted) return;

    if (result['status'] == true) {
      setState(() {
        _isLoading = false;
        _currentStep = 2;
        _errorMessage = null;
      });
      _clearOtp();
      _startTimer();
      // Auto-focus first OTP field
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_otpFocusNodes.isNotEmpty && mounted) {
          _otpFocusNodes[0].requestFocus();
        }
      });
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = (result['message'] as String?)?.isNotEmpty == true
            ? result['message'] as String
            : 'Could not send OTP. Please try again.';
      });
    }
  }

  // --- Step 2: Validate OTP ---
  Future<void> _submitOtp([String? explicitOtp]) async {
    final otpStr = explicitOtp ?? _enteredOtp;
    if (otpStr.length < 4) {
      setState(() => _errorMessage = 'Please Enter OTP');
      return;
    }

    final otpNum = int.tryParse(otpStr);
    if (otpNum == null) {
      setState(() => _errorMessage = 'Invalid OTP format');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final authRepo = context.read<AuthRepository>();
    final result = await authRepo.validateOtp(
      email: _emailController.text.trim(),
      otp: otpNum,
    );

    if (!mounted) return;

    if (result['status'] == true) {
      // Backend may return token under 'Token' (matching React Native res.data.Token) or 'token'
      final token = (result['Token'] ??
              result['token'] ??
              result['data']?['Token'] ??
              result['data']?['token'])
          ?.toString() ??
          '';

      setState(() {
        _isLoading = false;
        _resetToken = token;
        _currentStep = 3;
        _errorMessage = null;
      });
      _clearOtp();
      _timer?.cancel();
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = (result['message'] as String?)?.isNotEmpty == true
            ? result['message'] as String
            : 'Invalid OTP. Please try again.';
      });
    }
  }

  // --- Step 3: Reset Password ---
  Future<void> _resetPassword() async {
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (password.isEmpty) {
      setState(() => _errorMessage = 'Please enter new password');
      return;
    }
    if (confirmPassword.isEmpty) {
      setState(() => _errorMessage = 'Please confirm password');
      return;
    }
    if (password != confirmPassword) {
      setState(() => _errorMessage = 'Password does not match');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final authRepo = context.read<AuthRepository>();
    final result = await authRepo.resetPassword(
      password: password,
      confirmPassword: confirmPassword,
      resetToken: _resetToken,
    );

    if (!mounted) return;

    if (result['status'] == true) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            (result['message'] as String?)?.isNotEmpty == true
                ? result['message'] as String
                : 'Password reset successfully! Please login with your new password.',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
      Navigator.of(context).pop();
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = (result['message'] as String?)?.isNotEmpty == true
            ? result['message'] as String
            : 'Failed to reset password. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_new,
              color: Colors.white,
              size: 20,
            ),
            onPressed: () {
              if (_currentStep == 2) {
                setState(() {
                  _currentStep = 1;
                  _errorMessage = null;
                });
              } else if (_currentStep == 3) {
                setState(() {
                  _currentStep = 2;
                  _errorMessage = null;
                });
              } else {
                Navigator.of(context).pop();
              }
            },
          ),
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // App Logo matching React Native VeuzLight / Logo
                  Image.asset(
                    'assets/images/logo.png',
                    height: 56,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => const Icon(
                      Icons.lock_reset_rounded,
                      color: Colors.white,
                      size: 50,
                    ),
                  ),
                  const SizedBox(height: 36),

                  // Error Banner
                  if (_errorMessage != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: AppConstants.brandError,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Step Views
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: _buildCurrentStep(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 1:
        return _buildEmailStep();
      case 2:
        return _buildOtpStep();
      case 3:
        return _buildPasswordStep();
      default:
        return _buildEmailStep();
    }
  }

  // --- Step 1: Email Form ---
  Widget _buildEmailStep() {
    return Column(
      key: const ValueKey(1),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Forgot Password',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Enter your registered email address to receive an OTP.',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        const SizedBox(height: 24),

        // Rounded Email input matching React Native
        Container(
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(50),
            border: Border.all(color: AppConstants.brandBorder, width: 1.0),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          alignment: Alignment.center,
          child: TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _generateOtp(),
            style: const TextStyle(color: Colors.white, fontSize: 15),
            decoration: const InputDecoration(
              hintText: 'Email',
              hintStyle: TextStyle(color: Colors.white60, fontSize: 14),
              border: InputBorder.none,
              isDense: true,
            ),
          ),
        ),
        const SizedBox(height: 24),

        GradientButton(
          text: _isLoading ? 'Please Wait' : 'SUBMIT',
          isLoading: _isLoading,
          isRound: true,
          onPressed: _generateOtp,
        ),
      ],
    );
  }

  // --- Step 2: OTP Form ---
  Widget _buildOtpStep() {
    return Column(
      key: const ValueKey(2),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Enter OTP',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'We have sent a 4-digit code to ${_emailController.text.trim()}',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        const SizedBox(height: 24),

        // 4-digit OTP input boxes matching React Native OtpInput
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(4, (index) {
            return SizedBox(
              width: 60,
              height: 52,
              child: TextField(
                controller: _otpControllers[index],
                focusNode: _otpFocusNodes[index],
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 1,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  counterText: '',
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                      color: AppConstants.brandBorder,
                      width: 1.0,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                      color: AppTheme.brandGradientStart,
                      width: 2.0,
                    ),
                  ),
                ),
                onChanged: (value) {
                  if (value.isNotEmpty) {
                    if (index < 3) {
                      _otpFocusNodes[index + 1].requestFocus();
                    } else {
                      _otpFocusNodes[index].unfocus();
                      // Auto-submit when all 4 digits entered
                      _submitOtp();
                    }
                  } else if (index > 0) {
                    _otpFocusNodes[index - 1].requestFocus();
                  }
                },
              ),
            );
          }),
        ),
        const SizedBox(height: 24),

        GradientButton(
          text: _isLoading ? 'Please Wait' : 'SUBMIT',
          isLoading: _isLoading,
          isRound: true,
          onPressed: () => _submitOtp(),
        ),
        const SizedBox(height: 18),

        // Resend Timer & Change Email row matching React Native
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_timerSeconds == 0)
              GestureDetector(
                onTap: _isLoading
                    ? null
                    : () {
                        _startTimer();
                        _generateOtp();
                      },
                child: const Text(
                  'Resend OTP',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline,
                  ),
                ),
              )
            else
              Text(
                'Resend OTP in $_timerSeconds',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                '|',
                style: TextStyle(color: Colors.white38, fontSize: 14),
              ),
            ),
            GestureDetector(
              onTap: _isLoading
                  ? null
                  : () {
                      _timer?.cancel();
                      setState(() {
                        _currentStep = 1;
                        _errorMessage = null;
                      });
                    },
              child: const Text(
                'Change Email',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // --- Step 3: Set Password Form ---
  Widget _buildPasswordStep() {
    return Column(
      key: const ValueKey(3),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Set Password',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Enter and confirm your new password.',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        const SizedBox(height: 24),

        // New Password
        Container(
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(50),
            border: Border.all(color: AppConstants.brandBorder, width: 1.0),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          alignment: Alignment.center,
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _passwordController,
                  obscureText: !_isNewPasswordVisible,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  decoration: const InputDecoration(
                    hintText: 'New Password',
                    hintStyle: TextStyle(color: Colors.white60, fontSize: 14),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  _isNewPasswordVisible
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: Colors.white70,
                  size: 20,
                ),
                onPressed: () {
                  setState(() {
                    _isNewPasswordVisible = !_isNewPasswordVisible;
                  });
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Confirm Password
        Container(
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(50),
            border: Border.all(color: AppConstants.brandBorder, width: 1.0),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          alignment: Alignment.center,
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _confirmPasswordController,
                  obscureText: !_isConfirmPasswordVisible,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _resetPassword(),
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  decoration: const InputDecoration(
                    hintText: 'Confirm Password',
                    hintStyle: TextStyle(color: Colors.white60, fontSize: 14),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  _isConfirmPasswordVisible
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: Colors.white70,
                  size: 20,
                ),
                onPressed: () {
                  setState(() {
                    _isConfirmPasswordVisible = !_isConfirmPasswordVisible;
                  });
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        GradientButton(
          text: _isLoading ? 'Please Wait' : 'SUBMIT',
          isLoading: _isLoading,
          isRound: true,
          onPressed: _resetPassword,
        ),
      ],
    );
  }
}
