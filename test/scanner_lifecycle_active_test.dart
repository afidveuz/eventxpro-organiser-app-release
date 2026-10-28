import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scanner/data/adapters/simulated_hardware_adapter.dart';
import 'package:qr_scanner/data/datasources/django_scan_api_datasource.dart';
import 'package:qr_scanner/data/datasources/scanner_local_storage.dart';
import 'package:qr_scanner/data/repositories/scanner_repository_impl.dart';
import 'package:qr_scanner/presentation/bloc/scanner_bloc.dart';
import 'package:qr_scanner/presentation/bloc/scanner_event.dart';
import 'package:qr_scanner/presentation/bloc/scanner_state.dart';
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
  });

  tearDown(() {
    scannerBloc.close();
  });

  test('ScannerBloc ignores hardware scans when isScanningActive is false', () async {
    scannerBloc = ScannerBloc(
      repository: repository,
      localStorage: localStorage,
      activeAdapter: simulatorAdapter,
      isScanningActive: false, // Inactive by default
    );

    scannerBloc.add(const ScannerInitialized());
    await pumpEventQueue();

    // Fire scan while inactive
    scannerBloc.add(ScannerRawBarcodeReceived('VIP-TEST-TOKEN'));
    await pumpEventQueue();

    // State remains ScannerReadyState, not ScannerDecisionState
    expect(scannerBloc.state, isA<ScannerReadyState>());
    expect(repository.telemetry.totalScans, equals(0));
  });

  test('ScannerBloc processes scans after ScannerScanningResumed and stops on ScannerScanningPaused', () async {
    scannerBloc = ScannerBloc(
      repository: repository,
      localStorage: localStorage,
      activeAdapter: simulatorAdapter,
      isScanningActive: false,
    );

    scannerBloc.add(const ScannerInitialized());
    await pumpEventQueue();

    // 1. Resume scanning (e.g. KioskScannerScreen opened)
    scannerBloc.add(const ScannerScanningResumed());
    await pumpEventQueue();
    expect(scannerBloc.isScanningActive, isTrue);

    // 2. Fire scan while active
    final decisionFuture = expectLater(
      scannerBloc.stream,
      emitsThrough(isA<ScannerDecisionState>()),
    );
    scannerBloc.add(ScannerRawBarcodeReceived('VIP-TEST-TOKEN'));
    await decisionFuture;

    expect(scannerBloc.state, isA<ScannerDecisionState>());
    expect(repository.telemetry.totalScans, equals(1));

    // 3. Pause scanning (e.g. navigated to SettingsScreen or HomeScreen)
    scannerBloc.add(const ScannerScanningPaused());
    await pumpEventQueue();
    expect(scannerBloc.isScanningActive, isFalse);

    // 4. Fire scan while paused
    scannerBloc.add(ScannerRawBarcodeReceived('ANOTHER-TEST-TOKEN'));
    await pumpEventQueue();

    // Verify total scans processed did not increment
    expect(repository.telemetry.totalScans, equals(1));
  });
}
