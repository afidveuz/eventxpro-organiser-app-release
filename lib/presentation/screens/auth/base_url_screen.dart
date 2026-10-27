import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/config/app_constants.dart';
import '../../../core/services/remote_config_service.dart';
import '../../bloc/auth/auth_bloc.dart';
import '../../bloc/auth/auth_event.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../widgets/app_background.dart';
import '../../widgets/gradient_button.dart';

class BaseUrlScreen extends StatefulWidget {
  const BaseUrlScreen({super.key});

  @override
  State<BaseUrlScreen> createState() => _BaseUrlScreenState();
}

class _BaseUrlScreenState extends State<BaseUrlScreen> {
  final _masterPasswordController = TextEditingController();
  final _baseUrlController = TextEditingController();

  bool _isUnlocked = false;
  bool _isPasswordVisible = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final authRepo = context.read<AuthRepository>();
    _baseUrlController.text = authRepo.baseUrl;
    _syncRemoteConfig();
  }

  Future<void> _syncRemoteConfig() async {
    final updated = await RemoteConfigService().fetchAndActivate();
    if (updated && mounted) {
      final authRepo = context.read<AuthRepository>();
      if (!_isUnlocked && !authRepo.hasCustomBaseUrl) {
        setState(() {
          _baseUrlController.text = authRepo.baseUrl;
        });
      }
    }
  }

  @override
  void dispose() {
    _masterPasswordController.dispose();
    _baseUrlController.dispose();
    super.dispose();
  }

  void _unlockAction() {
    setState(() => _errorMessage = null);
    if (RemoteConfigService().verifyMasterPassword(_masterPasswordController.text)) {
      setState(() {
        _isUnlocked = true;
        _masterPasswordController.clear();
      });
    } else {
      setState(() {
        _errorMessage = 'Invalid master password';
      });
    }
  }

  bool _validateUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    return uri != null && (uri.isScheme('http') || uri.isScheme('https')) && uri.host.isNotEmpty;
  }

  void _saveBaseUrl() {
    final inputUrl = _baseUrlController.text.trim();
    if (inputUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid Base URL'),
          backgroundColor: AppConstants.brandError,
        ),
      );
      return;
    }

    if (_validateUrl(inputUrl)) {
      final cleanUrl = inputUrl.endsWith('/') ? inputUrl : '$inputUrl/';
      context.read<AuthBloc>().add(UpdateBaseUrlRequested(cleanUrl));

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Base URL updated successfully'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid URL (starting with https:// or http://)'),
          backgroundColor: AppConstants.brandError,
        ),
      );
    }
  }

  void _clearBaseUrl() {
    context.read<AuthBloc>().add(const ClearBaseUrlRequested());
    final defaultUrl = RemoteConfigService().getDefaultBaseUrl();
    setState(() {
      _baseUrlController.text = defaultUrl;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Base URL reset to default'),
        backgroundColor: Colors.blueAccent,
      ),
    );
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
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            _isUnlocked ? 'API Server Configuration' : 'Admin Security',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo
                Image.asset(
                  'assets/images/logo.png',
                  height: 60,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => const Icon(
                    Icons.settings_ethernet,
                    color: Colors.white,
                    size: 50,
                  ),
                ),
                const SizedBox(height: 32),

                // Error message banner if any
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppConstants.brandError,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 18),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                if (!_isUnlocked) ...[
                  const Text(
                    'Enter Master Password',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Access restricted to event technical administrators',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 24),

                  // Master Password Input
                  Container(
                    height: 50,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(50),
                      border: Border.all(color: AppConstants.brandBorder),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _masterPasswordController,
                            obscureText: !_isPasswordVisible,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              hintText: 'Master Password',
                              hintStyle: TextStyle(color: Colors.white60),
                              border: InputBorder.none,
                            ),
                            onSubmitted: (_) => _unlockAction(),
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

                  GradientButton(
                    text: 'Unlock',
                    onPressed: _unlockAction,
                  ),
                ] else ...[
                  const Text(
                    'Set Base URL',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Specify the EventXPro server endpoint for this event',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 24),

                  // URL Input
                  Container(
                    height: 50,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(50),
                      border: Border.all(color: AppConstants.brandBorder),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    alignment: Alignment.center,
                    child: TextField(
                      controller: _baseUrlController,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'eg: https://app.eventxpro.com',
                        hintStyle: TextStyle(color: Colors.white60),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  GradientButton(
                    text: 'Update Base URL',
                    onPressed: _saveBaseUrl,
                  ),
                  const SizedBox(height: 12),

                  GradientButton(
                    text: 'Reset to Default',
                    isFade: true,
                    onPressed: _clearBaseUrl,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
