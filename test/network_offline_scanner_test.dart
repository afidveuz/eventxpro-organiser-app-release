import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qr_scanner/core/config/app_constants.dart';
import 'package:qr_scanner/data/adapters/simulated_hardware_adapter.dart';
import 'package:qr_scanner/data/datasources/django_scan_api_datasource.dart';
import 'package:qr_scanner/data/datasources/scanner_local_storage.dart';
import 'package:qr_scanner/data/repositories/scanner_repository_impl.dart';
import 'package:qr_scanner/domain/entities/scan_decision_code.dart';
import 'package:qr_scanner/domain/entities/scan_request.dart';
import 'package:qr_scanner/domain/entities/scan_response.dart';
import 'package:qr_scanner/presentation/bloc/scanner_bloc.dart';
import 'package:qr_scanner/presentation/bloc/scanner_state.dart';
import 'package:qr_scanner/presentation/widgets/simple_scanner_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  group('Network Offline Scanner UI Tests', () {
    testWidgets('SimpleScannerView renders dedicated Offline Network card when offline/network error occurs', (tester) async {
      await localStorage.setShortToast(false);

      final scanRequest = ScanRequest(
        qrToken: 'TICKET-OFFLINE-99',
        eventId: AppConstants.defaultEventId,
        gateId: AppConstants.defaultGateId,
        deviceId: 'dev-001',
        scanRequestId: 'req-offline-001',
      );

      final scanResponse = ScanResponse(
        code: ScanDecisionCode.networkError,
        status: 'QUEUED',
        message: 'Scan Saved Offline (No Internet)',
        attendee: null,
        alertType: 'warning',
      );

      final decState = ScannerDecisionState(
        eventId: 1,
        gateId: 1,
        scanType: 'ENTRY',
        deviceId: 'dev-001',
        adapterName: 'Simulator',
        isOfflineMode: false,
        queueDepth: 1,
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

      // Verify Header
      expect(find.text('No Internet Connection'), findsOneWidget);
      expect(find.text('Saved to Offline Queue'), findsOneWidget);

      // Verify Body (No raw DNS host lookup exceptions or duplicate text!)
      expect(find.text('Scan Recorded Offline'), findsOneWidget);
      expect(find.textContaining('Unable to reach EventXPro server'), findsOneWidget);
      expect(find.text('TICKET-OFFLINE-99'), findsOneWidget);
      expect(find.text('QUEUED'), findsOneWidget);

      // Verify Action Buttons
      expect(find.text('Ready For Next Attendee'), findsOneWidget);
      expect(find.text('Switch to Offline Mode'), findsOneWidget);
    });

    testWidgets('SimpleScannerView renders clean short toast banner when network error occurs in rush mode', (tester) async {
      await localStorage.setShortToast(true);

      final scanRequest = ScanRequest(
        qrToken: 'TICKET-RUSH-OFFLINE',
        eventId: AppConstants.defaultEventId,
        gateId: AppConstants.defaultGateId,
        deviceId: 'dev-001',
        scanRequestId: 'req-rush-001',
      );

      final scanResponse = ScanResponse(
        code: ScanDecisionCode.networkError,
        status: 'QUEUED',
        message: 'Scan Saved Offline (No Internet)',
        attendee: null,
        alertType: 'warning',
      );

      final decState = ScannerDecisionState(
        eventId: 1,
        gateId: 1,
        scanType: 'ENTRY',
        deviceId: 'dev-001',
        adapterName: 'Simulator',
        isOfflineMode: false,
        queueDepth: 1,
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

      // Verify Short Toast banner content
      expect(find.text('SCAN SAVED OFFLINE'), findsOneWidget);
      expect(find.text('No internet • Saved to queue for auto-sync'), findsOneWidget);
      expect(find.byIcon(Icons.wifi_off_rounded), findsWidgets);
    });
  });
}
