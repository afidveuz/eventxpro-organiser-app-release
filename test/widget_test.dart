import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scanner/core/config/app_constants.dart';
import 'package:qr_scanner/data/adapters/simulated_hardware_adapter.dart';
import 'package:qr_scanner/data/datasources/django_scan_api_datasource.dart';
import 'package:qr_scanner/data/datasources/scanner_local_storage.dart';
import 'package:qr_scanner/data/repositories/scanner_repository_impl.dart';
import 'package:qr_scanner/domain/entities/scan_decision_code.dart';
import 'package:qr_scanner/domain/entities/scan_request.dart';
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
    scannerBloc = ScannerBloc(
      repository: repository,
      localStorage: localStorage,
      activeAdapter: simulatorAdapter,
    );
  });

  tearDown(() {
    scannerBloc.close();
  });

  group('Section 7 & 8: Central Scan Controller Tests', () {
    test('Initializes into ScannerReadyState', () async {
      scannerBloc.add(const ScannerInitialized());
      await expectLater(
        scannerBloc.stream,
        emitsInOrder([
          isA<ScannerReadyState>(),
        ]),
      );
    });

    test('Valid scan produces ENTRY_ALLOWED with attendee details', () async {
      scannerBloc.add(const ScannerInitialized());
      await pumpEventQueue();

      final scanRequest = ScanRequest(
        qrToken: 'VIP-2026-VICTORIA',
        eventId: AppConstants.defaultEventId,
        gateId: AppConstants.defaultGateId,
        deviceId: 'device-123',
        scanRequestId: 'req-001',
      );

      final response = await repository.validateScan(scanRequest);

      expect(response.code, equals(ScanDecisionCode.entryAllowed));
      expect(response.status, equals('ACCEPTED'));
      expect(response.attendee, isNotNull);
      expect(response.attendee!.name, equals('Victoria Sterling'));
      expect(response.attendee!.badgeType, equals('VIP Speaker'));
    });

    test('Section 8 Privacy Rule: Rejected scan never exposes attendee PII', () async {
      final invalidRequest = ScanRequest(
        qrToken: 'WRONG-EVT-1025-INVALID',
        eventId: AppConstants.defaultEventId,
        gateId: AppConstants.defaultGateId,
        deviceId: 'device-123',
        scanRequestId: 'req-002',
      );

      final response = await repository.validateScan(invalidRequest);

      expect(response.code, equals(ScanDecisionCode.wrongEvent));
      expect(response.status, equals('REJECTED'));
      expect(response.attendee, isNull, reason: 'Zero PII must be revealed on invalid badge results');
    });

    test('Section 7: 300 ms identical value duplicate suppression', () async {
      scannerBloc.add(const ScannerInitialized());
      await pumpEventQueue();

      // Fire 1st scan
      final now = DateTime.now();
      scannerBloc.add(ScannerRawBarcodeReceived('VIP-TEST-TOKEN', now));
      await pumpEventQueue();

      // Fire 2nd identical scan 50ms later (should be suppressed by 300ms rule)
      scannerBloc.add(ScannerRawBarcodeReceived(
        'VIP-TEST-TOKEN',
        now.add(const Duration(milliseconds: 50)),
      ));
      await pumpEventQueue();

      // Fire 3rd identical scan 120ms later (should also be suppressed)
      scannerBloc.add(ScannerRawBarcodeReceived(
        'VIP-TEST-TOKEN',
        now.add(const Duration(milliseconds: 120)),
      ));
      await pumpEventQueue();

      expect(repository.telemetry.duplicateSuppressedCount, equals(2));
    });

    test('Section 11: Real-time telemetry percentiles computation', () {
      final telemetry = repository.telemetry;
      telemetry.recordLatency(35);
      telemetry.recordLatency(40);
      telemetry.recordLatency(45);
      telemetry.recordLatency(50);
      telemetry.recordLatency(120);

      expect(telemetry.p50, greaterThanOrEqualTo(35));
      expect(telemetry.p95, greaterThanOrEqualTo(50));
      expect(telemetry.p99, greaterThanOrEqualTo(50));
      expect(telemetry.averageLatency, greaterThan(0));
    });

    test('Test Login API call formats and returns cleanly', () async {
      final res = await remoteDatasource.callTestLoginApi(
        scannedCode: 'UNIT_TEST_PASSWORD',
        username: 'user@example.com',
      );
      expect(res, isNotEmpty);
      expect(res, contains('HTTP 400'));
    });
  });
}
