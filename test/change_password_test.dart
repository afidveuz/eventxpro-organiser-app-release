import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scanner/core/network/api_client.dart';
import 'package:qr_scanner/data/datasources/auth_local_storage.dart';
import 'package:qr_scanner/data/datasources/auth_remote_datasource.dart';
import 'package:qr_scanner/data/datasources/scanner_local_storage.dart';
import 'package:qr_scanner/data/repositories/auth_repository.dart';
import 'package:qr_scanner/presentation/bloc/auth/auth_bloc.dart';
import 'package:qr_scanner/presentation/screens/auth/change_password_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockAuthRemoteDatasource extends AuthRemoteDatasource {
  MockAuthRemoteDatasource({required super.apiClient});

  bool changePasswordSuccess = true;
  String? lastPassword;
  String? lastConfirmPassword;
  String? mockErrorMessage;

  @override
  Future<Map<String, dynamic>> changePassword({
    required String password,
    required String confirmPassword,
  }) async {
    lastPassword = password;
    lastConfirmPassword = confirmPassword;

    if (changePasswordSuccess) {
      return {
        'status': true,
        'message': 'Password changed successfully',
      };
    } else {
      return {
        'status': false,
        'message': mockErrorMessage ?? 'Failed to update password',
      };
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockAuthRemoteDatasource mockDatasource;
  late AuthRepository authRepository;
  late ScannerLocalStorage scannerLocalStorage;
  late AuthBloc authBloc;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final localStorage = AuthLocalStorage(prefs);
    scannerLocalStorage = ScannerLocalStorage(prefs);
    final apiClient = ApiClient(localStorage: localStorage);
    mockDatasource = MockAuthRemoteDatasource(apiClient: apiClient);
    authRepository = AuthRepository(
      remoteDatasource: mockDatasource,
      localStorage: localStorage,
    );
    authBloc = AuthBloc(
      authRepository: authRepository,
      scannerLocalStorage: scannerLocalStorage,
    );
  });

  tearDown(() {
    authBloc.close();
  });

  Widget createChangePasswordWidget() {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<AuthRepository>.value(value: authRepository),
        RepositoryProvider<ScannerLocalStorage>.value(value: scannerLocalStorage),
      ],
      child: BlocProvider<AuthBloc>.value(
        value: authBloc,
        child: const MaterialApp(
          home: ChangePasswordScreen(),
        ),
      ),
    );
  }

  group('AuthRepository Change Password Unit Tests', () {
    test('changePassword passes password and confirm_password to remote datasource', () async {
      final result = await authRepository.changePassword(
        password: 'NewSecret@123',
        confirmPassword: 'NewSecret@123',
      );

      expect(result['status'], isTrue);
      expect(result['message'], 'Password changed successfully');
      expect(mockDatasource.lastPassword, 'NewSecret@123');
      expect(mockDatasource.lastConfirmPassword, 'NewSecret@123');
    });

    test('changePassword handles failure response gracefully', () async {
      mockDatasource.changePasswordSuccess = false;
      mockDatasource.mockErrorMessage = 'Old and new passwords cannot be identical';

      final result = await authRepository.changePassword(
        password: 'SamePassword@123',
        confirmPassword: 'SamePassword@123',
      );

      expect(result['status'], isFalse);
      expect(result['message'], 'Old and new passwords cannot be identical');
    });
  });

  group('ChangePasswordScreen UI and Validation Widget Tests', () {
    testWidgets('Renders all required elements', (tester) async {
      await tester.pumpWidget(createChangePasswordWidget());

      expect(find.text('Change Password'), findsOneWidget);
      expect(find.text('Set New Password'), findsOneWidget);
      expect(find.text('NEW PASSWORD'), findsOneWidget);
      expect(find.text('CONFIRM PASSWORD'), findsOneWidget);
      expect(find.text('SUBMIT'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2));
    });

    testWidgets('Validates empty new password', (tester) async {
      await tester.pumpWidget(createChangePasswordWidget());

      // Tap submit with empty fields
      await tester.tap(find.text('SUBMIT'));
      await tester.pumpAndSettle();

      expect(find.text('Please Enter New Password'), findsAtLeastNWidgets(1));
    });

    testWidgets('Validates empty confirm password', (tester) async {
      await tester.pumpWidget(createChangePasswordWidget());

      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(0), 'Password123');
      await tester.tap(find.text('SUBMIT'));
      await tester.pumpAndSettle();

      expect(find.text('Please Enter Confirm Password'), findsAtLeastNWidgets(1));
    });

    testWidgets('Validates password mismatch', (tester) async {
      await tester.pumpWidget(createChangePasswordWidget());

      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(0), 'Password123');
      await tester.enterText(textFields.at(1), 'DifferentPassword123');
      await tester.tap(find.text('SUBMIT'));
      await tester.pumpAndSettle();

      expect(find.text('Password does not match'), findsAtLeastNWidgets(1));
    });

    testWidgets('Validates password length < 6', (tester) async {
      await tester.pumpWidget(createChangePasswordWidget());

      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(0), '12345');
      await tester.enterText(textFields.at(1), '12345');
      await tester.tap(find.text('SUBMIT'));
      await tester.pumpAndSettle();

      expect(find.text('Password must be at least 6 characters long'), findsAtLeastNWidgets(1));
    });

    testWidgets('Toggles obscure text visibility', (tester) async {
      await tester.pumpWidget(createChangePasswordWidget());

      final eyeButtons = find.byType(IconButton);
      expect(eyeButtons, findsAtLeastNWidgets(2));

      TextField passwordField = tester.widget(find.byType(TextField).first);
      expect(passwordField.obscureText, isTrue);

      // Tap first eye icon
      await tester.tap(eyeButtons.at(1)); // First visibility toggle icon
      await tester.pumpAndSettle();

      passwordField = tester.widget(find.byType(TextField).first);
      expect(passwordField.obscureText, isFalse);
    });

    testWidgets('Successful submission calls repository with entered values', (tester) async {
      await tester.pumpWidget(createChangePasswordWidget());

      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(0), 'SecureNewPass@2026');
      await tester.enterText(textFields.at(1), 'SecureNewPass@2026');

      await tester.tap(find.text('SUBMIT'));
      await tester.pump();

      expect(mockDatasource.lastPassword, 'SecureNewPass@2026');
      expect(mockDatasource.lastConfirmPassword, 'SecureNewPass@2026');

      await tester.pumpAndSettle();
    });

    testWidgets('Displays backend error message on failure', (tester) async {
      mockDatasource.changePasswordSuccess = false;
      mockDatasource.mockErrorMessage = 'Password complexity requirements not met';

      await tester.pumpWidget(createChangePasswordWidget());

      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(0), 'simple');
      await tester.enterText(textFields.at(1), 'simple');

      await tester.tap(find.text('SUBMIT'));
      await tester.pumpAndSettle();

      expect(find.text('Password complexity requirements not met'), findsAtLeastNWidgets(1));
    });
  });
}
