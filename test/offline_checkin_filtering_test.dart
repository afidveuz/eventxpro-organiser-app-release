import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scanner/data/models/checkin_record.dart';

void main() {
  group('Offline Checkin Registration and Filter Tests', () {
    final now = DateTime.now();

    final testRecords = [
      CheckinRecord(
        id: 1,
        scanRequestId: 'req-1',
        encryptedCode: 'CODE1',
        code: 'CODE1',
        entranceId: 1,
        entranceLocation: 'Gate #1',
        scanType: 'check_in',
        section: 'entrances',
        timestamp: now,
        isSynced: true,
        isNotExist: false, // Registered & Synced
      ),
      CheckinRecord(
        id: 2,
        scanRequestId: 'req-2',
        encryptedCode: 'CODE2',
        code: 'CODE2',
        entranceId: 1,
        entranceLocation: 'Gate #1',
        scanType: 'check_in',
        section: 'entrances',
        timestamp: now,
        isSynced: true,
        isNotExist: true, // Unregistered & Synced
      ),
      CheckinRecord(
        id: 3,
        scanRequestId: 'req-3',
        encryptedCode: 'CODE3',
        code: 'CODE3',
        entranceId: 2,
        entranceLocation: 'Gate #2',
        scanType: 'check_out',
        section: 'entrances',
        timestamp: now,
        isSynced: false,
        isNotExist: false, // Registered & Unsynced
      ),
      CheckinRecord(
        id: 4,
        scanRequestId: 'req-4',
        encryptedCode: 'CODE4',
        code: 'CODE4',
        entranceId: 2,
        entranceLocation: 'Gate #2',
        scanType: 'check_in',
        section: 'hall',
        timestamp: now,
        isSynced: false,
        isNotExist: true, // Different section
      ),
    ];

    test('CheckinRecord toMap and fromMap serialization of isNotExist', () {
      final regRecord = CheckinRecord(
        id: 10,
        scanRequestId: 'req-reg',
        encryptedCode: 'ENC1',
        code: 'DEC1',
        entranceId: 1,
        entranceLocation: 'VIP Gate',
        scanType: 'check_in',
        section: 'entrances',
        timestamp: DateTime(2026, 10, 27, 12, 0),
        isSynced: true,
        isNotExist: false,
      );

      final regMap = regRecord.toMap();
      expect(regMap['is_not_exist'], 0);
      expect(regMap['is_synced'], 1);

      final restoredReg = CheckinRecord.fromMap(regMap);
      expect(restoredReg.isNotExist, false);
      expect(restoredReg.isSynced, true);

      final unregRecord = CheckinRecord(
        id: 11,
        scanRequestId: 'req-unreg',
        encryptedCode: 'ENC2',
        code: 'DEC2',
        entranceId: 2,
        entranceLocation: 'Standard Gate',
        scanType: 'check_in',
        section: 'entrances',
        timestamp: DateTime(2026, 10, 27, 12, 5),
        isSynced: true,
        isNotExist: true,
      );

      final unregMap = unregRecord.toMap();
      expect(unregMap['is_not_exist'], 1);
      expect(unregMap['is_synced'], 1);

      final restoredUnreg = CheckinRecord.fromMap(unregMap);
      expect(restoredUnreg.isNotExist, true);
      expect(restoredUnreg.isSynced, true);
    });

    test('Filter logic: All, Synced, Unsynced, Registered, Unregistered for entrances section', () {
      final entranceRecords = testRecords.where((r) => r.section == 'entrances').toList();
      expect(entranceRecords.length, 3);

      // 1. All Filter
      final allFiltered = entranceRecords;
      expect(allFiltered.length, 3);

      // 2. Synced Filter
      final syncedFiltered = entranceRecords.where((r) => r.isSynced).toList();
      expect(syncedFiltered.length, 2);
      expect(syncedFiltered.map((r) => r.id), containsAll([1, 2]));

      // 3. Unsynced Filter
      final unsyncedFiltered = entranceRecords.where((r) => !r.isSynced).toList();
      expect(unsyncedFiltered.length, 1);
      expect(unsyncedFiltered.first.id, 3);

      // 4. Registered Filter (isNotExist == false)
      final registeredFiltered = entranceRecords.where((r) => !r.isNotExist).toList();
      expect(registeredFiltered.length, 2);
      expect(registeredFiltered.map((r) => r.id), containsAll([1, 3]));

      // 5. Unregistered Filter (isNotExist == true)
      final unregisteredFiltered = entranceRecords.where((r) => r.isNotExist).toList();
      expect(unregisteredFiltered.length, 1);
      expect(unregisteredFiltered.first.id, 2);
    });

    test('Section stats calculations match individual filters', () {
      final entranceRecords = testRecords.where((r) => r.section == 'entrances').toList();

      final total = entranceRecords.length;
      final synced = entranceRecords.where((r) => r.isSynced).length;
      final unsynced = entranceRecords.where((r) => !r.isSynced).length;
      final registered = entranceRecords.where((r) => !r.isNotExist).length;
      final unregistered = entranceRecords.where((r) => r.isNotExist).length;

      expect(total, 3);
      expect(synced, 2);
      expect(unsynced, 1);
      expect(registered, 2);
      expect(unregistered, 1);
    });

    test('Search filter properly matches registration status keywords', () {
      final entranceRecords = testRecords.where((r) => r.section == 'entrances').toList();

      List<CheckinRecord> searchFilter(String query) {
        final q = query.trim().toLowerCase();
        return entranceRecords.where((r) {
          final codeMatch = r.code.toLowerCase().contains(q);
          final encMatch = r.encryptedCode.toLowerCase().contains(q);
          final idMatch = (r.id?.toString() ?? '').contains(q);
          final gateMatch = r.entranceId.toString().contains(q);
          final locationMatch = r.entranceLocation.toLowerCase().contains(q);

          final regMatch = q.contains('unreg')
              ? r.isNotExist
              : (q.contains('reg') ? !r.isNotExist : false);

          final syncMatch = (q.contains('unsync') || q.contains('pend'))
              ? !r.isSynced
              : (q.contains('sync') ? r.isSynced : false);

          return codeMatch || encMatch || idMatch || gateMatch || locationMatch || regMatch || syncMatch;
        }).toList();
      }

      // Search 'unregistered'
      final unregResults = searchFilter('unreg');
      expect(unregResults.length, 1);
      expect(unregResults.first.id, 2);

      // Search 'registered'
      final regResults = searchFilter('registered');
      expect(regResults.length, 2);
      expect(regResults.map((r) => r.id), containsAll([1, 3]));

      // Search 'Gate #2'
      final gate2Results = searchFilter('Gate #2');
      expect(gate2Results.length, 1);
      expect(gate2Results.first.id, 3);
    });
  });
}
