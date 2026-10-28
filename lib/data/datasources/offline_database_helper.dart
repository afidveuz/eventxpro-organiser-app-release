import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../models/checkin_record.dart';

/// High-Performance Offline Database using SQLite with Write-Ahead Logging (WAL).
///
/// Features:
/// 1. PRAGMA journal_mode = WAL (Concurrent reads without write lock)
/// 2. PRAGMA synchronous = NORMAL (Faster write speed without compromising safety)
/// 3. Indexed columns (code, is_synced) for sub-millisecond lookups
/// 4. Chunked reads (100 items per batch) to optimize batch HTTP sync
/// 5. Atomic transaction batch updates
class OfflineDatabaseHelper {
  static const String _databaseName = 'AppDB.db';
  static const int _databaseVersion = 1;
  static const String tableName = 'checkins';

  Database? _db;

  Future<Database> get database async {
    if (_db != null && _db!.isOpen) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    final databasesPath = await getDatabasesPath();
    final dbPath = p.join(databasesPath, _databaseName);

    return await openDatabase(
      dbPath,
      version: _databaseVersion,
      onCreate: _onCreate,
      onConfigure: _onConfigure,
    );
  }

  Future<void> _onConfigure(Database db) async {
    // ⚡ CRITICAL PERFORMANCE OPTIMIZATIONS
    // 1. Enable Write-Ahead-Logging for non-blocking concurrent writes
    // Note: 'PRAGMA journal_mode = WAL' returns a result row, so rawQuery must be used instead of execute on Android.
    try {
      await db.rawQuery('PRAGMA journal_mode = WAL;');
    } catch (e) {
      debugPrint('[OfflineDatabaseHelper] ⚠️ WAL journal_mode warning: $e');
    }

    // 2. Normal synchronous mode eliminates fsync delay on flash storage
    try {
      await db.execute('PRAGMA synchronous = NORMAL;');
    } catch (e) {
      debugPrint('[OfflineDatabaseHelper] ⚠️ synchronous warning: $e');
    }

    // 3. Cache up to 8MB of pages in RAM for blazing fast access
    try {
      await db.execute('PRAGMA cache_size = -8000;');
    } catch (e) {
      debugPrint('[OfflineDatabaseHelper] ⚠️ cache_size warning: $e');
    }

    // 4. Store temporary tables and indices in RAM
    try {
      await db.execute('PRAGMA temp_store = MEMORY;');
    } catch (e) {
      debugPrint('[OfflineDatabaseHelper] ⚠️ temp_store warning: $e');
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $tableName (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        scan_request_id TEXT UNIQUE,
        encrypted_code TEXT,
        code TEXT,
        entrance_id INTEGER,
        entrance_location TEXT,
        scan_type TEXT,
        section TEXT,
        timestamp INTEGER,
        is_synced INTEGER DEFAULT 0,
        is_not_exist INTEGER DEFAULT 0,
        user_id TEXT,
        event_id INTEGER DEFAULT 1
      );
    ''');

    // Create indices to make queries instantaneous
    await db.execute('CREATE INDEX IF NOT EXISTS idx_checkins_is_synced ON $tableName (is_synced);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_checkins_code ON $tableName (code);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_checkins_section ON $tableName (section, is_synced);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_checkins_not_exist ON $tableName (is_not_exist);');
  }

  /// Fast Insert: Writes directly to WAL buffer (< 2ms)
  Future<int> insertCheckin(CheckinRecord record) async {
    final client = await database;
    try {
      return await client.insert(
        tableName,
        record.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      debugPrint('[OfflineDatabaseHelper] ❌ insertCheckin error: $e');
      return -1;
    }
  }

  /// Get pending unsynced count
  Future<int> getUnsyncedCount({String? section}) async {
    final client = await database;
    try {
      String query = 'SELECT COUNT(*) as count FROM $tableName WHERE is_synced = 0';
      List<dynamic> args = [];
      if (section != null) {
        query += ' AND section = ?';
        args.add(section);
      }
      final result = await client.rawQuery(query, args);
      return Sqflite.firstIntValue(result) ?? 0;
    } catch (e) {
      debugPrint('[OfflineDatabaseHelper] ❌ getUnsyncedCount error: $e');
      return 0;
    }
  }

  /// Get total scanned count across all sections (synced + unsynced)
  Future<int> getTotalScannedCount() async {
    final client = await database;
    try {
      final result = await client.rawQuery('SELECT COUNT(*) as count FROM $tableName');
      return Sqflite.firstIntValue(result) ?? 0;
    } catch (e) {
      debugPrint('[OfflineDatabaseHelper] ❌ getTotalScannedCount error: $e');
      return 0;
    }
  }

  /// Get all unique codes to preload the RAM memory cache on app startup
  Future<List<String>> getAllScannedCodes() async {
    final client = await database;
    try {
      final results = await client.query(
        tableName,
        columns: ['code'],
      );
      return results
          .map((r) => r['code'] as String? ?? '')
          .where((c) => c.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('[OfflineDatabaseHelper] ❌ getAllScannedCodes error: $e');
      return [];
    }
  }

  /// Fetch a chunk of unsynced records (Default: 100 per chunk matching backend)
  Future<List<CheckinRecord>> getUnsyncedChunk({
    int limit = 100,
    String? section,
  }) async {
    final client = await database;
    try {
      String whereClause = 'is_synced = 0';
      List<dynamic> whereArgs = [];
      if (section != null) {
        whereClause += ' AND section = ?';
        whereArgs.add(section);
      }

      final results = await client.query(
        tableName,
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: 'id ASC',
        limit: limit,
      );

      return results.map((map) => CheckinRecord.fromMap(map)).toList();
    } catch (e) {
      debugPrint('[OfflineDatabaseHelper] ❌ getUnsyncedChunk error: $e');
      return [];
    }
  }

  /// Batch Update Status in a SINGLE atomic SQLite transaction
  Future<void> markBatchSynced({
    required List<int> updatedIds,
    List<int>? notExistIds,
  }) async {
    if (updatedIds.isEmpty && (notExistIds == null || notExistIds.isEmpty)) {
      return;
    }

    final client = await database;
    await client.transaction((txn) async {
      final batch = txn.batch();

      if (updatedIds.isNotEmpty) {
        final idsStr = updatedIds.join(',');
        batch.rawUpdate(
          'UPDATE $tableName SET is_synced = 1 WHERE id IN ($idsStr)',
        );
      }

      if (notExistIds != null && notExistIds.isNotEmpty) {
        final idsStr = notExistIds.join(',');
        batch.rawUpdate(
          'UPDATE $tableName SET is_synced = 1, is_not_exist = 1 WHERE id IN ($idsStr)',
        );
      }

      await batch.commit(noResult: true);
    });
  }

  /// Fetch check-ins with optional section, sync status, and registration status filters
  Future<List<CheckinRecord>> getCheckins({
    String? section,
    bool? isSynced,
    bool? isNotExist,
    int limit = 100,
    int offset = 0,
  }) async {
    final client = await database;
    try {
      final List<String> whereClauses = [];
      final List<dynamic> whereArgs = [];

      if (section != null) {
        whereClauses.add('section = ?');
        whereArgs.add(section);
      }

      if (isSynced != null) {
        whereClauses.add('is_synced = ?');
        whereArgs.add(isSynced ? 1 : 0);
      }

      if (isNotExist != null) {
        whereClauses.add('is_not_exist = ?');
        whereArgs.add(isNotExist ? 1 : 0);
      }

      final where = whereClauses.isNotEmpty ? whereClauses.join(' AND ') : null;

      final results = await client.query(
        tableName,
        where: where,
        whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
        orderBy: 'id DESC',
        limit: limit,
        offset: offset,
      );

      return results.map((map) => CheckinRecord.fromMap(map)).toList();
    } catch (e) {
      debugPrint('[OfflineDatabaseHelper] ❌ getCheckins error: $e');
      return [];
    }
  }

  /// Get aggregated counts for a section (total, synced, unsynced, registered, unregistered)
  Future<Map<String, int>> getSectionStats({String? section}) async {
    final client = await database;
    try {
      String query = '''
        SELECT 
          COUNT(*) as total,
          SUM(CASE WHEN is_synced = 1 THEN 1 ELSE 0 END) as synced,
          SUM(CASE WHEN is_synced = 0 THEN 1 ELSE 0 END) as unsynced,
          SUM(CASE WHEN is_not_exist = 0 THEN 1 ELSE 0 END) as registered,
          SUM(CASE WHEN is_not_exist = 1 THEN 1 ELSE 0 END) as unregistered
        FROM $tableName
      ''';
      final List<dynamic> args = [];
      if (section != null) {
        query += ' WHERE section = ?';
        args.add(section);
      }
      final result = await client.rawQuery(query, args);
      if (result.isNotEmpty) {
        final row = result.first;
        return {
          'total': (row['total'] as num?)?.toInt() ?? 0,
          'synced': (row['synced'] as num?)?.toInt() ?? 0,
          'unsynced': (row['unsynced'] as num?)?.toInt() ?? 0,
          'registered': (row['registered'] as num?)?.toInt() ?? 0,
          'unregistered': (row['unregistered'] as num?)?.toInt() ?? 0,
        };
      }
    } catch (e) {
      debugPrint('[OfflineDatabaseHelper] ❌ getSectionStats error: $e');
    }
    return {
      'total': 0,
      'synced': 0,
      'unsynced': 0,
      'registered': 0,
      'unregistered': 0,
    };
  }

  /// Get summary of check-ins categorized by section
  Future<Map<String, Map<String, int>>> getSectionSummary() async {
    final client = await database;
    final Map<String, Map<String, int>> summary = {
      'entrances': {'total': 0, 'unsynced': 0},
      'hall': {'total': 0, 'unsynced': 0},
      'agenda': {'total': 0, 'unsynced': 0},
      'session': {'total': 0, 'unsynced': 0},
    };

    try {
      final rows = await client.rawQuery('''
        SELECT 
          COALESCE(section, 'entrances') as section,
          COUNT(*) as total,
          SUM(CASE WHEN is_synced = 0 THEN 1 ELSE 0 END) as unsynced
        FROM $tableName
        GROUP BY section;
      ''');

      for (final row in rows) {
        final sec = (row['section'] as String?)?.toLowerCase() ?? 'entrances';
        final total = (row['total'] as num?)?.toInt() ?? 0;
        final unsynced = (row['unsynced'] as num?)?.toInt() ?? 0;

        summary[sec] = {
          'total': total,
          'unsynced': unsynced,
        };
      }
    } catch (e) {
      debugPrint('[OfflineDatabaseHelper] ❌ getSectionSummary error: $e');
    }

    return summary;
  }

  /// Delete already synced records to optimize storage
  Future<int> clearSyncedCheckins({String? section}) async {
    final client = await database;
    try {
      if (section != null) {
        return await client.delete(
          tableName,
          where: 'is_synced = 1 AND section = ?',
          whereArgs: [section],
        );
      }
      return await client.delete(
        tableName,
        where: 'is_synced = 1',
      );
    } catch (e) {
      debugPrint('[OfflineDatabaseHelper] ❌ clearSyncedCheckins error: $e');
      return 0;
    }
  }

  /// Fetch check-ins for export without any pagination limit.
  /// If [section] is null or 'all', fetches records across all sections
  /// (mirrors `getAllCheckinsFull` in the reference React Native project).
  /// If [section] is specified, filters records by that section
  /// (mirrors `getAllCheckinsChunk` / `getAllFilterCheckinsChunk`).
  Future<List<CheckinRecord>> getAllCheckinsForExport({
    String? section,
    bool? isSynced,
    bool? isNotExist,
  }) async {
    final client = await database;
    try {
      final List<String> whereClauses = [];
      final List<dynamic> whereArgs = [];

      if (section != null && section.isNotEmpty && section != 'all') {
        whereClauses.add('section = ?');
        whereArgs.add(section);
      }

      if (isSynced != null) {
        whereClauses.add('is_synced = ?');
        whereArgs.add(isSynced ? 1 : 0);
      }

      if (isNotExist != null) {
        whereClauses.add('is_not_exist = ?');
        whereArgs.add(isNotExist ? 1 : 0);
      }

      final results = await client.query(
        tableName,
        where: whereClauses.isNotEmpty ? whereClauses.join(' AND ') : null,
        whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
        orderBy: 'id ASC',
      );

      return results.map((map) => CheckinRecord.fromMap(map)).toList();
    } catch (e) {
      debugPrint('[OfflineDatabaseHelper] ❌ getAllCheckinsForExport error: $e');
      return [];
    }
  }

  /// Clear all check-ins (e.g. on user reset)
  Future<void> clearAll() async {

    final client = await database;
    await client.delete(tableName);
  }

  /// Close database connection
  Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
    }
  }
}
