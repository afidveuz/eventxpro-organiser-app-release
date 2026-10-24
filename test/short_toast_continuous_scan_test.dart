import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qr_scanner/core/config/app_constants.dart';
import 'package:qr_scanner/data/adapters/simulated_hardware_adapter.dart';
import 'package:qr_scanner/data/datasources/django_scan_api_datasource.dart';
import 'package:qr_scanner/data/datasources/scanner_local_storage.dart';
import 'package:qr_scanner/data/repositories/scanner_repository_impl.dart';
import 'package:qr_scanner/domain/entities/attendee.dart';
import 'package:qr_scanner/domain/entities/scan_decision_code.dart';
import 'package:qr_scanner/domain/entities/scan_request.dart';
import 'package:qr_scanner/domain/entities/scan_response.dart';
import 'package:qr_scanner/presentation/bloc/scanner_bloc.dart';
import 'package:qr_scanner/presentation/bloc/scanner_event.dart';
import 'package:qr_scanner/presentation/bloc/scanner_state.dart';
import 'package:qr_scanner/presentation/widgets/simple_scanner_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  late ScannerLocalStorage localStorage;
  late DjangoScanApiDatasource remoteDatasource;
  late ScannerRepositoryImpl repository;
  late SimulatedHardwareAdapter simulatorAdapter;
  late ScannerBloc scannerBloc;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    localStorage = await ScannerLocalStorage.create();
    remoteDatasource = DjangoScanApiDatasource()..useMockServer = true;
    repository = ScannerRepositoryImpl(
      remoteDatasource: remoteDatasource,
      localStorage: localStorage,
    );
    simulatorAdapter = SimulatedHardwareAdapter();
    scannerBloc = ScannerBloc(
      repository: repository,
      localStorage: localStorage,
      activeAdapter: simulatorAdapter,
    );
  });

  tearDown(() {
    scannerBloc.close();
  });

  group('Short Toast & Continuous Rush Scanning Tests', () {
    test('ScannerLocalStorage persists isShortToastEnabled correctly', () async {
      expect(localStorage.isShortToastEnabled, isFalse);
      await localStorage.setShortToast(true);
      expect(localStorage.isShortToastEnabled, isTrue);
      await localStorage.setShortToast(false);
      expect(localStorage.isShortToastEnabled, isFalse);
    });

    test('ScannerBloc accelerates reset timer to 1800ms when short toast is enabled', () async {
      await localStorage.setShortToast(true);
      scannerBloc.add(const ScannerInitialized());
      await expectLater(
        scannerBloc.stream,
        emitsThrough(isA<ScannerReadyState>()),
      );

      scannerBloc.add(ScannerRawBarcodeReceived('VIP-TEST-TOKEN'));
      await expectLater(
        scannerBloc.stream,
        emitsThrough(isA<ScannerDecisionState>()),
      );

      expect(scannerBloc.state, isA<ScannerDecisionState>());
    });

    test('ScannerBloc allows continuous consecutive scans of different tokens without blocking', () async {
      await localStorage.setShortToast(true);
      scannerBloc.add(const ScannerInitialized());
      await expectLater(
        scannerBloc.stream,
        emitsThrough(isA<ScannerReadyState>()),
      );

      // Scan 1
      scannerBloc.add(ScannerRawBarcodeReceived('TICKET-USER-A'));
      await expectLater(
        scannerBloc.stream,
        emitsThrough(isA<ScannerDecisionState>()),
      );
      final firstDecision = scannerBloc.state as ScannerDecisionState;
      expect(firstDecision.request.qrToken, equals('TICKET-USER-A'));

      // Scan 2 immediately afterwards (continuous scanning during rush)
      scannerBloc.add(ScannerRawBarcodeReceived('TICKET-USER-B'));
      await expectLater(
        scannerBloc.stream,
        emitsThrough(isA<ScannerDecisionState>()),
      );
      final secondDecision = scannerBloc.state as ScannerDecisionState;
      expect(secondDecision.request.qrToken, equals('TICKET-USER-B'));
    });

    testWidgets('SimpleScannerView renders floating short toast banner when short toast is enabled', (tester) async {
      await localStorage.setShortToast(true);

      const attendee = Attendee(
        name: 'Alexander Hamilton',
        badgeType: 'VIP Delegate',
        category: 'VIP',
        company: 'Treasury Corp',
      );

      final scanRequest = ScanRequest(
        qrToken: 'VIP-ALEXANDER',
        eventId: AppConstants.defaultEventId,
        gateId: AppConstants.defaultGateId,
        deviceId: 'dev-001',
        scanRequestId: 'req-001',
      );

      final scanResponse = ScanResponse(
        code: ScanDecisionCode.entryAllowed,
        status: 'ACCEPTED',
        message: 'Checked In Successfully!',
        attendee: attendee,
        alertType: 'success',
      );

      final decState = ScannerDecisionState(
        eventId: 1,
        gateId: 1,
        scanType: 'ENTRY',
        deviceId: 'dev-001',
        adapterName: 'Simulator',
        isOfflineMode: false,
        queueDepth: 0,
        telemetry: repository.telemetry,
        request: scanRequest,
        response: scanResponse,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ScannerLocalStorage>.value(value: localStorage),
            BlocProvider<ScannerBloc>.value(value: scannerBloc),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SimpleScannerView(
                state: decState,
                onLogout: () {},
                onResetToReady: () {},
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Viewfinder headline stays visible because short toast keeps viewfinder alive
      expect(find.text('Scan any QR'), findsOneWidget);

      // Short toast banner displays attendee's name and message
      expect(find.text('ALEXANDER HAMILTON'), findsOneWidget);
      expect(find.textContaining('Checked In Successfully!'), findsOneWidget);
      expect(find.text('Details'), findsOneWidget);
    });

    testWidgets('SimpleScannerView renders full decision card when short toast is disabled', (tester) async {
      await localStorage.setShortToast(false);

      const attendee = Attendee(
        name: 'Alexander Hamilton',
        badgeType: 'VIP Delegate',
        category: 'VIP',
        company: 'Treasury Corp',
      );

      final scanRequest = ScanRequest(
        qrToken: 'VIP-ALEXANDER',
        eventId: AppConstants.defaultEventId,
        gateId: AppConstants.defaultGateId,
        deviceId: 'dev-001',
        scanRequestId: 'req-001',
      );

      final scanResponse = ScanResponse(
        code: ScanDecisionCode.entryAllowed,
        status: 'ACCEPTED',
        message: 'Checked In Successfully!',
        attendee: attendee,
        alertType: 'success',
      );

      final decState = ScannerDecisionState(
        eventId: 1,
        gateId: 1,
        scanType: 'ENTRY',
        deviceId: 'dev-001',
        adapterName: 'Simulator',
        isOfflineMode: false,
        queueDepth: 0,
        telemetry: repository.telemetry,
        request: scanRequest,
        response: scanResponse,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ScannerLocalStorage>.value(value: localStorage),
            BlocProvider<ScannerBloc>.value(value: scannerBloc),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SimpleScannerView(
                state: decState,
                onLogout: () {},
                onResetToReady: () {},
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // In detailed mode (short toast disabled), the viewfinder is replaced by the decision card
      expect(find.text('Ready For Next Attendee'), findsOneWidget);
    });
  });
}
