import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scanner/core/crypto/ticket_encryption_service.dart';
import 'package:qr_scanner/data/models/checkin_record.dart';
import 'package:qr_scanner/domain/entities/scan_decision_code.dart';
import 'package:qr_scanner/domain/entities/scan_request.dart';
import 'package:qr_scanner/data/datasources/offline_database_helper.dart';
import 'package:qr_scanner/data/datasources/scanner_local_storage.dart';
import 'package:qr_scanner/data/datasources/django_scan_api_datasource.dart';
import 'package:qr_scanner/data/repositories/scanner_repository_impl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeOfflineDatabaseHelper extends OfflineDatabaseHelper {
  final List<CheckinRecord> saved = [];

  @override
  Future<int> insertCheckin(CheckinRecord record) async {
    saved.add(record);
    return saved.length;
  }

  @override
  Future<int> getUnsyncedCount({String? section}) async {
    return saved.where((r) => !r.isSynced).length;
  }

  @override
  Future<List<String>> getAllScannedCodes() async {
    return saved.map((r) => r.code).toList();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TicketEncryptionService Tests (DES ECB matching React Native EventXPro)', () {
    final crypto = TicketEncryptionService();

    test('Valid message can be encrypted and decrypted correctly', () {
      const ticketId = 'ATTENDEE-998822';
      final encryptedBase32 = crypto.encryptTicket(ticketId);
      expect(encryptedBase32.isNotEmpty, true);

      final decrypted = crypto.decryptTicket(encryptedBase32);
      expect(decrypted, ticketId);

      final bytes = crypto.base32ToBytes('GB6HEYSKIAY4DWCJIGD67G4UVY======');
      print('DEBUG: bytes length = ${bytes.length}');
      for (final keyStr in ['yGm7P48x50k=', 'Veuz@url4788', '']) {
        try {
          final res = crypto.decryptTicket('GB6HEYSKIAY4DWCJIGD67G4UVY======', keyString: keyStr.isEmpty ? null : keyStr);
          print('DEBUG: key="$keyStr" -> decrypted="$res"');
        } catch (e) {
          print('DEBUG: key="$keyStr" -> error: $e');
        }
      }

      final result = crypto.validateTicket(
        rawQrToken: encryptedBase32,
        allowTestPrefixes: false,
      );
      expect(result.isValid, true);
      expect(result.decryptedPayload, ticketId);
    });

    test('Random unencrypted gibberish is flagged as INVALID QR code', () {
      const randomJunk = 'THIS_IS_TOTALLY_RANDOM_INVALID_NONSENSE_STRING_12345';
      final result = crypto.validateTicket(
        rawQrToken: randomJunk,
        allowTestPrefixes: false,
      );
      expect(result.isValid, false);
      expect(result.errorMessage, 'Invalid QR Code');
    });

    test('Sample token with ASCII padding is cleaned and validated', () {
      const sample = 'TICKET-TEST-1234\u0002\u0002';
      final encrypted = crypto.encryptTicket(sample);
      final result = crypto.validateTicket(rawQrToken: encrypted);
      expect(result.isValid, true);
      expect(result.decryptedPayload, 'TICKET-TEST-1234');
    });
  });

  group('Offline Mode Code Validation Flow in Repository', () {
    late ScannerLocalStorage localStorage;
    late FakeOfflineDatabaseHelper dbHelper;
    late ScannerRepositoryImpl repository;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'scanner_offline_mode_enabled': true,
        'scanner_event_id': 1,
        'scanner_gate_id': 1,
      });

      localStorage = await ScannerLocalStorage.create();
      dbHelper = FakeOfflineDatabaseHelper();
      final remoteDs = DjangoScanApiDatasource()..useMockServer = true;

      repository = ScannerRepositoryImpl(
        remoteDatasource: remoteDs,
        localStorage: localStorage,
        dbHelper: dbHelper,
      );
    });

    test('Valid encrypted ticket produces ACCEPTED response in offline mode', () async {
      final crypto = TicketEncryptionService();
      final validToken = crypto.encryptTicket('EVENTX-USER-4567');

      final request = ScanRequest(
        qrToken: validToken,
        eventId: 1,
        gateId: 1,
        scanType: 'ENTRY',
        deviceId: 'device-test',
        scanRequestId: 'req-valid-1',
        scannedAt: DateTime.now(),
      );

      final response = await repository.validateScan(request);
      expect(response.code, ScanDecisionCode.entryAllowed);
      expect(response.status, 'ACCEPTED');
      expect(response.message.contains('Successful'), true);
      expect(dbHelper.saved.length, 1);
    });

    test('Invalid random barcode produces REJECTED response in offline mode', () async {
      final request = ScanRequest(
        qrToken: 'COMPLETELY_INVALID_UNKNOWN_QR_DATA_5589',
        eventId: 1,
        gateId: 1,
        scanType: 'ENTRY',
        deviceId: 'device-test',
        scanRequestId: 'req-invalid-1',
        scannedAt: DateTime.now(),
      );

      final response = await repository.validateScan(request);
      expect(response.code, ScanDecisionCode.invalidBadge);
      expect(response.status, 'REJECTED');
      expect(response.message, 'Invalid QR Code');
      // Should NOT be saved to SQLite queue
      expect(dbHelper.saved.isEmpty, true);
    });

    test('Repeated scan and check-out in offline mode are accepted and saved to SQLite (matching eventxproorganiser)', () async {
      final crypto = TicketEncryptionService();
      final validToken = crypto.encryptTicket('EVENTX-USER-MULTI-PUNCH');

      // 1. First Scan: Check-In
      final req1 = ScanRequest(
        qrToken: validToken,
        eventId: 1,
        gateId: 1,
        scanType: 'check_in',
        deviceId: 'device-test',
        scanRequestId: 'req-multi-1',
        scannedAt: DateTime.now(),
      );

      final resp1 = await repository.validateScan(req1);
      expect(resp1.code, ScanDecisionCode.entryAllowed);
      expect(resp1.status, 'ACCEPTED');
      expect(resp1.message, 'Check-In Successful');
      expect(dbHelper.saved.length, 1);
      expect(dbHelper.saved.first.scanType, 'check_in');

      // 2. Second Scan: Check-Out for the same ticket
      final req2 = ScanRequest(
        qrToken: validToken,
        eventId: 1,
        gateId: 1,
        scanType: 'check_out',
        deviceId: 'device-test',
        scanRequestId: 'req-multi-2',
        scannedAt: DateTime.now(),
      );

      final resp2 = await repository.validateScan(req2);
      expect(resp2.code, ScanDecisionCode.entryAllowed);
      expect(resp2.status, 'ACCEPTED');
      expect(resp2.message, 'Check-Out Successful');
      expect(dbHelper.saved.length, 2);
      expect(dbHelper.saved[1].scanType, 'check_out');

      // 3. Third Scan: Re-entry Check-In for the same ticket
      final req3 = ScanRequest(
        qrToken: validToken,
        eventId: 1,
        gateId: 1,
        scanType: 'check_in',
        deviceId: 'device-test',
        scanRequestId: 'req-multi-3',
        scannedAt: DateTime.now(),
      );

      final resp3 = await repository.validateScan(req3);
      expect(resp3.code, ScanDecisionCode.entryAllowed);
      expect(resp3.status, 'ACCEPTED');
      expect(resp3.message, 'Check-In Successful');
      expect(dbHelper.saved.length, 3);
      expect(dbHelper.saved[2].scanType, 'check_in');
    });
  });
}
