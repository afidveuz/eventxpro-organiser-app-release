import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scanner/core/network/api_client.dart';
import 'package:qr_scanner/data/adapters/simulated_hardware_adapter.dart';
import 'package:qr_scanner/data/datasources/auth_local_storage.dart';
import 'package:qr_scanner/data/datasources/auth_remote_datasource.dart';
import 'package:qr_scanner/data/datasources/django_scan_api_datasource.dart';
import 'package:qr_scanner/data/datasources/lead_remote_datasource.dart';
import 'package:qr_scanner/data/datasources/scanner_local_storage.dart';
import 'package:qr_scanner/data/models/lead_model.dart';
import 'package:qr_scanner/data/repositories/auth_repository.dart';
import 'package:qr_scanner/data/repositories/lead_repository.dart';
import 'package:qr_scanner/data/repositories/scanner_repository_impl.dart';
import 'package:qr_scanner/presentation/bloc/scanner_bloc.dart';
import 'package:qr_scanner/presentation/screens/lead/lead_capture_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeLeadRemoteDatasource extends LeadRemoteDatasource {
  LeadCaptureResult mockResult = const LeadCaptureResult(isSuccess: false);
  bool didCallUpdate = false;

  FakeLeadRemoteDatasource(ApiClient apiClient) : super(apiClient: apiClient);

  @override
  Future<LeadCaptureResult> captureLead({
    required String uniqueId,
    int scanType = 0,
  }) async {
    return mockResult;
  }

  @override
  Future<Map<String, dynamic>> updateLead({
    required int id,
    required String leadType,
    required String notes,
  }) async {
    didCallUpdate = true;
    return {'status': true};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late ScannerLocalStorage scannerLocalStorage;
  late AuthLocalStorage authLocalStorage;
  late AuthRepository authRepository;
  late FakeLeadRemoteDatasource fakeLeadDatasource;
  late LeadRepository leadRepository;
  late ScannerBloc scannerBloc;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    scannerLocalStorage = ScannerLocalStorage(prefs);
    authLocalStorage = AuthLocalStorage(prefs);
    final apiClient = ApiClient(localStorage: authLocalStorage);
    authRepository = AuthRepository(
      remoteDatasource: AuthRemoteDatasource(apiClient: apiClient),
      localStorage: authLocalStorage,
    );
    fakeLeadDatasource = FakeLeadRemoteDatasource(apiClient);
    leadRepository = LeadRepository(remoteDatasource: fakeLeadDatasource);

    final remoteDatasource = DjangoScanApiDatasource()..useMockServer = true;
    final repository = ScannerRepositoryImpl(
      remoteDatasource: remoteDatasource,
      localStorage: scannerLocalStorage,
    );
    final simulatorAdapter = SimulatedHardwareAdapter();
    scannerBloc = ScannerBloc(
      repository: repository,
      localStorage: scannerLocalStorage,
      activeAdapter: simulatorAdapter,
    );
  });

  tearDown(() {
    scannerBloc.close();
  });

  Widget createSubject({String? eventName}) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<ScannerLocalStorage>.value(value: scannerLocalStorage),
        RepositoryProvider<AuthRepository>.value(value: authRepository),
        RepositoryProvider<LeadRepository>.value(value: leadRepository),
        BlocProvider<ScannerBloc>.value(value: scannerBloc),
      ],
      child: MaterialApp(
        home: LeadCaptureScreen(
          eventName: eventName ?? 'Tech Expo 2026',
        ),
      ),
    );
  }

  group('LeadCaptureScreen - Check-in Scanner UI Parity Tests', () {
    testWidgets('Renders authentic check-in scanner UI layout (TopBar, Viewfinder, Dock, Footer)',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createSubject());
      await tester.pump(const Duration(milliseconds: 200));

      // Top Bar
      expect(find.textContaining('Lead'), findsWidgets);
      expect(find.textContaining('Capture'), findsWidgets);
      expect(find.text('Tech Expo 2026'), findsNWidgets(2));
      expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsOneWidget);
      expect(find.byIcon(Icons.list_alt_rounded), findsOneWidget);

      // Viewfinder guidance
      expect(find.text('Scan any QR'), findsOneWidget);
      expect(
        find.text('Position the attendee QR code within the frame'),
        findsOneWidget,
      );

      // Active Listening Indicator Pill
      expect(
        find.text('Hardware Scanner Ready'),
        findsOneWidget,
      );

      // Control Dock icons
      expect(find.byIcon(Icons.videocam_rounded), findsOneWidget);
      expect(find.byIcon(Icons.bolt_rounded), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_alt_outlined), findsOneWidget);

      // Telemetry Footer
      expect(find.text('0 Captured'), findsOneWidget);
      expect(find.text('EDA51 / Zebra'), findsOneWidget);
    });

    testWidgets('Tapping mode switch button switches to camera mode with flash and camera flip controls',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createSubject());
      await tester.pump(const Duration(milliseconds: 200));

      // Tap Mode Switcher button (starts in hardware mode)
      await tester.tap(find.byIcon(Icons.videocam_rounded));
      await tester.pump(const Duration(milliseconds: 200));

      // Should now show camera controls and camera active indicator
      expect(find.text('Camera Active'), findsOneWidget);
      expect(find.byIcon(Icons.flash_off_rounded), findsOneWidget);
      expect(find.byIcon(Icons.cameraswitch_rounded), findsOneWidget);
      expect(find.byIcon(Icons.qr_code_scanner_rounded), findsOneWidget);
    });

    testWidgets('Tapping rush mode button activates continuous scan mode with visual confirmation',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createSubject());
      await tester.pump(const Duration(milliseconds: 200));

      // Tap Rush Mode button
      await tester.tap(find.byIcon(Icons.bolt_rounded));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.textContaining('Rush Mode Activated'), findsOneWidget);
    });

    testWidgets('Tapping manual entry button opens the manual ticket entry modal sheet',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createSubject());
      await tester.pump(const Duration(milliseconds: 200));

      // Tap Manual Entry Button
      await tester.tap(find.byIcon(Icons.keyboard_alt_outlined));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Manual Lead Entry'), findsOneWidget);
      expect(
        find.text('Enter or paste the attendee badge token or unique ID to manually capture lead.'),
        findsOneWidget,
      );
      expect(find.text('CAPTURE LEAD'), findsOneWidget);
    });

    testWidgets('Manual entry captures lead and displays Authoritative Lead Decision Card with rating pills',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const mockLead = LeadModel(
        id: 42,
        uniqueId: 'ATT-9901',
        firstname: 'Eleanor',
        lastname: 'Vance',
        companyName: 'Apex Innovations',
        designation: 'VP of Engineering',
        ticketType: 'VIP Buyer',
        leadType: 'COLD',
      );

      fakeLeadDatasource.mockResult = const LeadCaptureResult(
        isSuccess: true,
        lead: mockLead,
      );

      await tester.pumpWidget(createSubject());
      await tester.pump(const Duration(milliseconds: 200));

      // Open manual entry sheet
      await tester.tap(find.byIcon(Icons.keyboard_alt_outlined));
      await tester.pump(const Duration(milliseconds: 300));

      // Enter token and submit via done action
      await tester.enterText(find.byType(TextField), 'ATT-9901');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      // Decision Card Header
      expect(find.text('LEAD CAPTURED'), findsOneWidget);

      // Lead Details in Card Body
      expect(find.text('ELEANOR VANCE'), findsOneWidget);
      expect(find.text('Apex Innovations'), findsOneWidget);
      expect(find.text('VP of Engineering'), findsOneWidget);
      expect(find.text('VIP BUYER'), findsOneWidget);

      // Lead Rating Pills
      expect(find.text('Rate this Lead'), findsOneWidget);
      expect(find.text('HOT'), findsOneWidget);
      expect(find.text('WARM'), findsOneWidget);
      expect(find.text('COLD'), findsOneWidget);

      // Ready For Next Lead button
      expect(find.text('Ready For Next Lead'), findsOneWidget);

      // Telemetry footer count incremented
      expect(find.text('1 Captured'), findsOneWidget);

      // Tap HOT rating pill
      await tester.tap(find.text('HOT'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(fakeLeadDatasource.didCallUpdate, isTrue);

      // Tap Ready For Next Lead to reset back to viewfinder
      await tester.tap(find.text('Ready For Next Lead'));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Scan any QR'), findsOneWidget);
    });

    testWidgets('Failed lead capture displays error decision card with rejection message',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      fakeLeadDatasource.mockResult = const LeadCaptureResult(
        isSuccess: false,
        message: 'Badge has already been captured by another exhibitor booth',
      );

      await tester.pumpWidget(createSubject());
      await tester.pump(const Duration(milliseconds: 200));

      // Open manual entry sheet
      await tester.tap(find.byIcon(Icons.keyboard_alt_outlined));
      await tester.pump(const Duration(milliseconds: 300));

      // Enter token and submit via done action
      await tester.enterText(find.byType(TextField), 'BAD-TOKEN');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      // Error Decision Card Header
      expect(find.text('CAPTURE REJECTED'), findsOneWidget);
      expect(
        find.text('Badge has already been captured by another exhibitor booth'),
        findsOneWidget,
      );

      // Reset to scanner
      await tester.tap(find.text('Ready For Next Lead'));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Scan any QR'), findsOneWidget);
    });
  });
}
