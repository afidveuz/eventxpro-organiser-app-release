import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scanner/core/network/api_client.dart';
import 'package:qr_scanner/data/datasources/auth_local_storage.dart';
import 'package:qr_scanner/data/datasources/auth_remote_datasource.dart';
import 'package:qr_scanner/data/repositories/auth_repository.dart';
import 'package:qr_scanner/presentation/screens/auth/forgot_password_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockAuthRemoteDatasource extends AuthRemoteDatasource {
  MockAuthRemoteDatasource({required super.apiClient});

  bool generateOtpSuccess = true;
  bool validateOtpSuccess = true;
  bool resetPasswordSuccess = true;

  String? lastEmail;
  int? lastOtp;
  String? lastNewPassword;
  String? lastConfirmPassword;
  String? lastResetToken;

  @override
  Future<Map<String, dynamic>> generateOtp({required String email}) async {
    lastEmail = email;
    if (generateOtpSuccess) {
      return {'status': true, 'message': 'OTP sent successfully'};
    }
    return {'status': false, 'message': 'User not found'};
  }

  @override
  Future<Map<String, dynamic>> validateOtp({
    required String email,
    required int otp,
  }) async {
    lastEmail = email;
    lastOtp = otp;
    if (validateOtpSuccess) {
      return {
        'status': true,
        'Token': 'mock-reset-bearer-token-12345',
        'message': 'OTP verified',
      };
    }
    return {'status': false, 'message': 'Invalid OTP code'};
  }

  @override
  Future<Map<String, dynamic>> resetPassword({
    required String password,
    required String confirmPassword,
    required String resetToken,
  }) async {
    lastNewPassword = password;
    lastConfirmPassword = confirmPassword;
    lastResetToken = resetToken;
    if (resetPasswordSuccess) {
      return {'status': true, 'message': 'Password reset successfully'};
    }
    return {'status': false, 'message': 'Password reset failed'};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockAuthRemoteDatasource mockDatasource;
  late AuthRepository authRepository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final localStorage = AuthLocalStorage(prefs);
    final apiClient = ApiClient(localStorage: localStorage);
    mockDatasource = MockAuthRemoteDatasource(apiClient: apiClient);
    authRepository = AuthRepository(
      remoteDatasource: mockDatasource,
      localStorage: localStorage,
    );
  });

  group('AuthRepository Forgot Password Unit Tests', () {
    test('generateOtp calls datasource with email', () async {
      final result = await authRepository.generateOtp('user@test.com');
      expect(result['status'], isTrue);
      expect(mockDatasource.lastEmail, 'user@test.com');
    });

    test('validateOtp passes email and otp, receives reset Token', () async {
      final result = await authRepository.validateOtp(
        email: 'user@test.com',
        otp: 1234,
      );
      expect(result['status'], isTrue);
      expect(result['Token'], 'mock-reset-bearer-token-12345');
      expect(mockDatasource.lastOtp, 1234);
    });

    test('resetPassword sends password, confirm_password, and bearer token', () async {
      final result = await authRepository.resetPassword(
        password: 'Password@123',
        confirmPassword: 'Password@123',
        resetToken: 'mock-reset-bearer-token-12345',
      );
      expect(result['status'], isTrue);
      expect(mockDatasource.lastNewPassword, 'Password@123');
      expect(mockDatasource.lastConfirmPassword, 'Password@123');
      expect(mockDatasource.lastResetToken, 'mock-reset-bearer-token-12345');
    });
  });

  group('ForgotPasswordScreen 3-Step Flow Widget Tests', () {
    testWidgets('Complete 3-step Forgot Password flow', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RepositoryProvider<AuthRepository>.value(
            value: authRepository,
            child: const ForgotPasswordScreen(),
          ),
        ),
      );

      // Step 1: Initial state shows "Forgot Password" and email field
      expect(find.text('Forgot Password'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);

      // Enter valid email and press SUBMIT
      await tester.enterText(find.byType(TextField), 'organizer@veuz.com');
      await tester.tap(find.text('SUBMIT'));
      await tester.pumpAndSettle();

      // Step 2: Screen should now be on "Enter OTP" with 4 OTP input fields
      expect(find.text('Enter OTP'), findsOneWidget);
      expect(find.text('We have sent a 4-digit code to organizer@veuz.com'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(4));

      // Test "Change Email" button brings user back to Step 1
      await tester.tap(find.text('Change Email'));
      await tester.pumpAndSettle();
      expect(find.text('Forgot Password'), findsOneWidget);
      expect(find.text('organizer@veuz.com'), findsOneWidget); // Preserved email

      // Submit again to go back to Step 2
      await tester.tap(find.text('SUBMIT'));
      await tester.pumpAndSettle();
      expect(find.text('Enter OTP'), findsOneWidget);

      // Fill in all 4 OTP digits: 1, 2, 3, 4
      final otpFields = find.byType(TextField);
      await tester.enterText(otpFields.at(0), '1');
      await tester.enterText(otpFields.at(1), '2');
      await tester.enterText(otpFields.at(2), '3');
      await tester.enterText(otpFields.at(3), '4');
      await tester.pumpAndSettle();

      // Step 3: Screen transitions to "Set Password"
      expect(find.text('Set Password'), findsOneWidget);
      expect(find.text('Enter and confirm your new password.'), findsOneWidget);

      // Enter mismatched passwords first to test validation
      final passwordFields = find.byType(TextField);
      await tester.enterText(passwordFields.at(0), 'Secret@123');
      await tester.enterText(passwordFields.at(1), 'Secret@999');
      await tester.tap(find.text('SUBMIT'));
      await tester.pumpAndSettle();

      expect(find.text('Password does not match'), findsOneWidget);

      // Enter matching passwords
      await tester.enterText(passwordFields.at(1), 'Secret@123');
      await tester.tap(find.text('SUBMIT'));
      await tester.pumpAndSettle();

      // Verified reset password was called with proper token
      expect(mockDatasource.lastNewPassword, 'Secret@123');
      expect(mockDatasource.lastConfirmPassword, 'Secret@123');
      expect(mockDatasource.lastResetToken, 'mock-reset-bearer-token-12345');
    });
  });
}
