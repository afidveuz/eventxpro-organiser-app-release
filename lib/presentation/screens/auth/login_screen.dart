import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/config/app_constants.dart';
import '../../../core/services/device_detection_service.dart';
import '../../../data/datasources/scanner_local_storage.dart';
import '../../bloc/auth/auth_bloc.dart';
import '../../bloc/auth/auth_event.dart';
import '../../bloc/auth/auth_state.dart';
import '../../widgets/app_background.dart';
import '../../widgets/gradient_button.dart';
import 'base_url_screen.dart';
import 'forgot_password_screen.dart';
import '../home/home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isPasswordVisible = false;

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      _usernameController.text = AppConstants.debugUsername;
      _passwordController.text = AppConstants.debugPassword;
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _onLoginPressed() {
    FocusScope.of(context).unfocus();
    context.read<AuthBloc>().add(
          LoginSubmitted(
            username: _usernameController.text,
            password: _passwordController.text,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthAuthenticated) {
          // Check device OEM (Honeywell / Zebra) immediately after login
          final storage = context.read<ScannerLocalStorage>();
          DeviceDetectionService().detectDevice(storage: storage);

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Welcome, ${state.user.name.isNotEmpty ? state.user.name : state.user.username}!'),
              backgroundColor: const Color(0xFF2E7D32),
              duration: const Duration(seconds: 2),
            ),
          );
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        } else if (state is AuthUnauthenticated) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
        }
      },
      child: AppBackground(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Stack(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: IntrinsicHeight(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // App Logo
                              Center(
                                child: Hero(
                                  tag: 'app_logo',
                                  child: Image.asset(
                                    'assets/images/logo.png',
                                    height: isKeyboardOpen ? 55 : 75,
                                    fit: BoxFit.contain,
                                    errorBuilder: (context, error, stackTrace) => Column(
                                      children: const [
                                        Icon(Icons.qr_code_scanner_rounded, size: 64, color: AppConstants.brandAccent),
                                        SizedBox(height: 8),
                                        Text(
                                          'EventXPro',
                                          style: TextStyle(
                                            fontSize: 22,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                            letterSpacing: 1.2,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(height: isKeyboardOpen ? 16 : 24),

                              // Error message banner
                              BlocBuilder<AuthBloc, AuthState>(
                                builder: (context, state) {
                                  if (state is AuthUnauthenticated && state.errorMessage != null) {
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 20),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                        decoration: BoxDecoration(
                                          color: AppConstants.brandError,
                                          borderRadius: BorderRadius.circular(8),
                                          boxShadow: const [
                                            BoxShadow(
                                              color: Color(0x40F14C4C),
                                              blurRadius: 8,
                                              offset: Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(
                                              Icons.warning_amber_rounded,
                                              color: Colors.white,
                                              size: 20,
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                state.errorMessage!,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                            GestureDetector(
                                              onTap: () {
                                                context.read<AuthBloc>().add(const ClearAuthError());
                                              },
                                              child: const Icon(
                                                Icons.close,
                                                color: Colors.white70,
                                                size: 18,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }
                                  return const SizedBox(height: 12);
                                },
                              ),

                              // Title
                              const Text(
                                'Login to your Account',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.3,
                                ),
                              ),
                              const SizedBox(height: 24),

                              // Username Input Field (Pill shape)
                              Container(
                                height: 50,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(50),
                                  border: Border.all(color: AppConstants.brandBorder, width: 1),
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                                alignment: Alignment.center,
                                child: TextField(
                                  controller: _usernameController,
                                  autocorrect: false,
                                  textInputAction: TextInputAction.next,
                                  scrollPadding: const EdgeInsets.only(bottom: 160),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    letterSpacing: 0.3,
                                  ),
                                  decoration: const InputDecoration(
                                    hintText: 'Username',
                                    hintStyle: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 15,
                                    ),
                                    border: InputBorder.none,
                                    isDense: true,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 18),

                              // Password Input Field (Pill shape with Toggle Eye)
                              Container(
                                height: 50,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(50),
                                  border: Border.all(color: AppConstants.brandBorder, width: 1),
                                ),
                                padding: const EdgeInsets.only(left: 20, right: 8),
                                alignment: Alignment.center,
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _passwordController,
                                        obscureText: !_isPasswordVisible,
                                        textInputAction: TextInputAction.done,
                                        scrollPadding: const EdgeInsets.only(bottom: 100),
                                        onSubmitted: (_) => _onLoginPressed(),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 15,
                                          letterSpacing: 0.3,
                                        ),
                                        decoration: const InputDecoration(
                                          hintText: 'Password',
                                          hintStyle: TextStyle(
                                            color: Colors.white70,
                                            fontSize: 15,
                                          ),
                                          border: InputBorder.none,
                                          isDense: true,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        _isPasswordVisible ? Icons.visibility : Icons.visibility_off,
                                        color: Colors.white70,
                                        size: 20,
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _isPasswordVisible = !_isPasswordVisible;
                                        });
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),

                              // Login Button
                              BlocBuilder<AuthBloc, AuthState>(
                                builder: (context, state) {
                                  final isLoading = state is AuthLoading;
                                  return GradientButton(
                                    text: 'Login',
                                    isLoading: isLoading,
                                    onPressed: _onLoginPressed,
                                  );
                                },
                              ),
                              const SizedBox(height: 18),

                              // Forgot Password Link
                              Center(
                                child: TextButton(
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const ForgotPasswordScreen(),
                                      ),
                                    );
                                  },
                                  child: const Text(
                                    'Forgot Password',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),

                              // App Version
                              const Center(
                                child: Text(
                                  'EventXPro ${AppConstants.appVersion}',
                                  style: TextStyle(
                                    color: Color(0xFFB7B6B6),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),

              // Bottom right Globe Icon for Base URL settings
              // Automatically hidden when keyboard is open to prevent overlapping form fields
              if (!isKeyboardOpen)
                Positioned(
                  bottom: 20,
                  right: 20,
                  child: Opacity(
                    opacity: 0.6,
                    child: Material(
                      color: Colors.transparent,
                      child: IconButton(
                        icon: const Icon(
                          Icons.language_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                        tooltip: 'Server Configuration',
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const BaseUrlScreen(),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
