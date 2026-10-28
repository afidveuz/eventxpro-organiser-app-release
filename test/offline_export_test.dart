import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scanner/core/services/offline_export_service.dart';
import 'package:qr_scanner/data/models/checkin_record.dart';

/// Comprehensive unit tests for the offline data export (download) feature.
///
/// Validates data mapping, CSV generation, Excel byte generation,
/// filename formatting, column labels, scan type formatting, and error handling.
/// All tests are pure-Dart and can run in any environment without physical devices.
void main() {
  // ─── Shared test fixtures ─────────────────────────────────────────────────

  final baseTs = DateTime(2026, 10, 27, 14, 30);

  final entranceRecord = CheckinRecord(
    id: 1,
    scanRequestId: 'req-100',
    encryptedCode: 'ENC_ENTRANCE',
    code: 'DEC_ENTRANCE',
    entranceId: 5,
    entranceLocation: 'Main Gate',
    scanType: 'check_in',
    section: 'entrances',
    timestamp: baseTs,
    isSynced: true,
    isNotExist: false,
    userId: 'user-1',
    eventId: 42,
  );

  final hallRecord = CheckinRecord(
    id: 2,
    scanRequestId: 'req-200',
    encryptedCode: 'ENC_HALL',
    code: 'DEC_HALL',
    entranceId: 10,
    entranceLocation: 'Hall B',
    scanType: 'check_out',
    section: 'hall',
    timestamp: baseTs.add(const Duration(minutes: 5)),
    isSynced: false,
    isNotExist: true,
    userId: 'user-2',
    eventId: 42,
  );

  final agendaRecord = CheckinRecord(
    id: 3,
    scanRequestId: 'req-300',
    encryptedCode: 'ENC_AGENDA',
    code: 'DEC_AGENDA',
    entranceId: 20,
    entranceLocation: 'Keynote Hall',
    scanType: 'check_in',
    section: 'agenda',
    timestamp: baseTs.add(const Duration(minutes: 10)),
    isSynced: true,
    isNotExist: false,
    userId: null,
    eventId: 42,
  );

  final sessionRecord = CheckinRecord(
    id: 4,
    scanRequestId: 'req-400',
    encryptedCode: 'ENC_SESSION',
    code: 'DEC_SESSION',
    entranceId: 30,
    entranceLocation: 'Room 3',
    scanType: 'check_out',
    section: 'session',
    timestamp: baseTs.add(const Duration(hours: 1)),
    isSynced: false,
    isNotExist: true,
    userId: 'user-4',
    eventId: 42,
  );

  // ─── 1. Column label mapping ───────────────────────────────────────────────

  group('OfflineExportService.idLabelFor: section → column header mapping', () {
    test('entrances → ENTRANCE_ID', () {
      expect(OfflineExportService.idLabelFor('entrances'), 'ENTRANCE_ID');
    });
    test('hall → HALL_ID', () {
      expect(OfflineExportService.idLabelFor('hall'), 'HALL_ID');
    });
    test('agenda → AGENDA_ID', () {
      expect(OfflineExportService.idLabelFor('agenda'), 'AGENDA_ID');
    });
    test('session → SESSION_ID', () {
      expect(OfflineExportService.idLabelFor('session'), 'SESSION_ID');
    });
    test('unknown → ENTRANCE_ID (safe default)', () {
      expect(OfflineExportService.idLabelFor('xyz'), 'ENTRANCE_ID');
    });
  });

  // ─── 2. Scan-type formatting ───────────────────────────────────────────────

  group('OfflineExportService.formatScanType: scan_type → display label', () {
    test('check_in → Check-In', () {
      expect(OfflineExportService.formatScanType('check_in'), 'Check-In');
    });
    test('check_out → Check-Out', () {
      expect(OfflineExportService.formatScanType('check_out'), 'Check-Out');
    });
    test('ENTRY (uppercase in) → Check-In', () {
      expect(OfflineExportService.formatScanType('ENTRY'), 'Check-In');
    });
    test('EXIT (uppercase out) → Check-Out', () {
      expect(OfflineExportService.formatScanType('EXIT'), 'Check-Out');
    });
    test('in → Check-In', () {
      expect(OfflineExportService.formatScanType('in'), 'Check-In');
    });
    test('out → Check-Out', () {
      expect(OfflineExportService.formatScanType('out'), 'Check-Out');
    });
    test('unknown type → returned as-is', () {
      expect(OfflineExportService.formatScanType('walk'), 'walk');
    });
  });

  // ─── 3. isSynced / isNotExist display labels ──────────────────────────────

  group('Status and Registration Status field mapping', () {
    test('isSynced=true → "Synced"', () {
      expect(entranceRecord.isSynced ? 'Synced' : 'Unsynced', 'Synced');
    });
    test('isSynced=false → "Unsynced"', () {
      expect(hallRecord.isSynced ? 'Synced' : 'Unsynced', 'Unsynced');
    });
    test('isNotExist=false → "Registered"', () {
      expect(entranceRecord.isNotExist ? 'Unregistered' : 'Registered', 'Registered');
    });
    test('isNotExist=true → "Unregistered"', () {
      expect(hallRecord.isNotExist ? 'Unregistered' : 'Registered', 'Unregistered');
    });
  });

  // ─── 4. CSV row serialisation ─────────────────────────────────────────────

  group('OfflineExportService.csvRow: field quoting and comma escaping', () {
    test('basic fields are wrapped in double-quotes', () {
      final row = OfflineExportService.csvRow(['ID', 'ENCRYPTED_CODE', 'STATUS']);
      expect(row, '"ID","ENCRYPTED_CODE","STATUS"');
    });

    test('commas inside field values are safely enclosed', () {
      final row = OfflineExportService.csvRow(['Venue, Main', 'check_in']);
      expect(row, '"Venue, Main","check_in"');
    });

    test('embedded double-quotes are escaped as ""', () {
      final row = OfflineExportService.csvRow(['Say "hello"', 'normal']);
      expect(row, '"Say ""hello""","normal"');
    });

    test('empty string fields produce two consecutive double-quotes', () {
      final row = OfflineExportService.csvRow(['', 'something']);
      expect(row, '"","something"');
    });
  });

  // ─── 5. Filename formatting ───────────────────────────────────────────────

  group('OfflineExportService.formatFileName: session key and timestamp', () {
    final fixedTime = DateTime(2026, 10, 27, 16, 30, 45);

    test('section specific format: <session>-<timestamp>.<ext>', () {
      final name = OfflineExportService.formatFileName('entrances', 'xlsx', fixedTime);
      expect(name, 'entrances-27-10-2026_16-30-45.xlsx');
    });

    test('all sessions format: offline-all-data-<timestamp>.<ext>', () {
      final name = OfflineExportService.formatFileName('all', 'csv', fixedTime);
      expect(name, 'offline-all-data-27-10-2026_16-30-45.csv');
    });

    test('offline-all-data key matches all format', () {
      final name = OfflineExportService.formatFileName('offline-all-data', 'xlsx', fixedTime);
      expect(name, 'offline-all-data-27-10-2026_16-30-45.xlsx');
    });
  });

  // ─── 6. Pure CSV String Generation ────────────────────────────────────────

  group('OfflineExportService.generateCsvString', () {
    test('generates valid CSV with correct headers for entrances section', () {
      final csv = OfflineExportService.generateCsvString(
        records: [entranceRecord],
        sessionKey: 'entrances',
      );

      final lines = csv.trim().split('\n');
      expect(lines.length, 2);

      // Header row check
      expect(lines[0], contains('"ENTRANCE_ID"'));
      expect(lines[0], contains('"ENTRANCE_LOCATION"'));
      expect(lines[0], contains('"IS_SYNCED"'));
      expect(lines[0], contains('"IS_NOT_EXIST"'));

      // Data row check
      expect(lines[1], contains('"1"')); // ID
      expect(lines[1], contains('"ENC_ENTRANCE"'));
      expect(lines[1], contains('"DEC_ENTRANCE"'));
      expect(lines[1], contains('"5"')); // entranceId
      expect(lines[1], contains('"Main Gate"'));
      expect(lines[1], contains('"Synced"'));
      expect(lines[1], contains('"Registered"'));
    });

    test('generates valid CSV with correct headers for all sessions', () {
      final csv = OfflineExportService.generateCsvString(
        records: [entranceRecord, hallRecord, agendaRecord, sessionRecord],
        sessionKey: 'all',
      );

      final lines = csv.trim().split('\n');
      expect(lines.length, 5); // 1 header + 4 data rows
      expect(lines[0], contains('"SECTION"'));
      expect(lines[2], contains('"hall"'));
      expect(lines[2], contains('"Unsynced"'));
      expect(lines[2], contains('"Unregistered"'));
    });
  });

  // ─── 7. Pure Excel Bytes Generation ───────────────────────────────────────

  group('OfflineExportService.generateExcelBytes', () {
    test('generates non-empty valid XLSX zip package for entrances section', () {
      final bytes = OfflineExportService.generateExcelBytes(
        records: [entranceRecord, hallRecord],
        sessionKey: 'entrances',
      );

      expect(bytes, isNotEmpty);
      // Valid XLSX starts with PK zip magic header [0x50, 0x4B, 0x03, 0x04]
      expect(bytes[0], equals(0x50));
      expect(bytes[1], equals(0x4B));
      expect(bytes[2], equals(0x03));
      expect(bytes[3], equals(0x04));
    });

    test('generates valid XLSX zip package for all sessions export', () {
      final bytes = OfflineExportService.generateExcelBytes(
        records: [entranceRecord, hallRecord, agendaRecord, sessionRecord],
        sessionKey: 'all',
      );

      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(1000));
      expect(bytes[0], equals(0x50));
      expect(bytes[1], equals(0x4B));
    });
  });

  // ─── 8. Export filter logic ───────────────────────────────────────────────

  group('Export filter logic (mirrors _syncFilterForExport / _regFilterForExport)', () {
    bool? syncFilterForExport(String selectedFilter) {
      if (selectedFilter == 'synced') return true;
      if (selectedFilter == 'unsynced') return false;
      return null;
    }

    bool? regFilterForExport(String selectedFilter) {
      if (selectedFilter == 'registered') return false;
      if (selectedFilter == 'unregistered') return true;
      return null;
    }

    test('"all" filter produces null sync filter', () {
      expect(syncFilterForExport('all'), isNull);
    });
    test('"synced" filter produces true sync filter', () {
      expect(syncFilterForExport('synced'), isTrue);
    });
    test('"unsynced" filter produces false sync filter', () {
      expect(syncFilterForExport('unsynced'), isFalse);
    });
    test('"all" filter produces null reg filter', () {
      expect(regFilterForExport('all'), isNull);
    });
    test('"registered" filter produces false reg filter', () {
      expect(regFilterForExport('registered'), isFalse);
    });
    test('"unregistered" filter produces true reg filter', () {
      expect(regFilterForExport('unregistered'), isTrue);
    });
    test('synced filter does not affect reg filter', () {
      expect(regFilterForExport('synced'), isNull);
    });
    test('registered filter does not affect sync filter', () {
      expect(syncFilterForExport('registered'), isNull);
    });
  });

  // ─── 9. Empty data guard ──────────────────────────────────────────────────

  group('Empty data guard', () {
    test('empty records list should produce error result in exportToExcel', () async {
      final service = OfflineExportService();
      final result = await service.exportToExcel(records: [], sessionKey: 'entrances');
      expect(result.success, isFalse);
      expect(result.errorMessage, equals('No data available to download.'));
    });

    test('empty records list should produce error result in exportToCsv', () async {
      final service = OfflineExportService();
      final result = await service.exportToCsv(records: [], sessionKey: 'entrances');
      expect(result.success, isFalse);
      expect(result.errorMessage, equals('No data available to download.'));
    });
  });

  // ─── 10. ExportResult value object ────────────────────────────────────────

  group('ExportResult value object', () {
    test('success result has success=true, valid filePath, and recordCount', () {
      const result = ExportResult(
        success: true,
        filePath: '/storage/emulated/0/Download/entrances.xlsx',
        recordCount: 15,
      );
      expect(result.success, isTrue);
      expect(result.filePath, equals('/storage/emulated/0/Download/entrances.xlsx'));
      expect(result.recordCount, equals(15));
      expect(result.errorMessage, isNull);
    });

    test('fail result has success=false and errorMessage', () {
      const result = ExportResult(
        success: false,
        errorMessage: 'Storage permission denied.',
      );
      expect(result.success, isFalse);
      expect(result.errorMessage, equals('Storage permission denied.'));
      expect(result.filePath, isNull);
      expect(result.recordCount, equals(0));
    });

    test('filePath strips /storage/emulated/0/ prefix for display', () {
      const rawPath = '/storage/emulated/0/Download/entrances.xlsx';
      final displayPath = rawPath.replaceAll('/storage/emulated/0/', '');
      expect(displayPath, 'Download/entrances.xlsx');
    });
  });

  // ─── 11. CheckinRecord serialisation round-trip ───────────────────────────

  group('CheckinRecord serialisation round-trip (used in getAllCheckinsForExport)', () {
    test('all fields are preserved after toMap → fromMap', () {
      final map = entranceRecord.toMap();
      final reconstructed = CheckinRecord.fromMap(map);

      expect(reconstructed.id, entranceRecord.id);
      expect(reconstructed.scanRequestId, entranceRecord.scanRequestId);
      expect(reconstructed.encryptedCode, entranceRecord.encryptedCode);
      expect(reconstructed.code, entranceRecord.code);
      expect(reconstructed.entranceId, entranceRecord.entranceId);
      expect(reconstructed.entranceLocation, entranceRecord.entranceLocation);
      expect(reconstructed.scanType, entranceRecord.scanType);
      expect(reconstructed.section, entranceRecord.section);
      expect(reconstructed.timestamp.millisecondsSinceEpoch,
          entranceRecord.timestamp.millisecondsSinceEpoch);
      expect(reconstructed.isSynced, entranceRecord.isSynced);
      expect(reconstructed.isNotExist, entranceRecord.isNotExist);
      expect(reconstructed.userId, entranceRecord.userId);
      expect(reconstructed.eventId, entranceRecord.eventId);
    });

    test('null userId is preserved as null after round-trip', () {
      final map = agendaRecord.toMap();
      final reconstructed = CheckinRecord.fromMap(map);
      expect(reconstructed.userId, isNull);
    });
  });
}
