import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

import '../../data/models/checkin_record.dart';
import 'device_detection_service.dart';

/// Result returned by every export operation so callers can display UI feedback.
class ExportResult {
  final bool success;
  final String? filePath;
  final String? errorMessage;
  final int recordCount;

  const ExportResult({
    required this.success,
    this.filePath,
    this.errorMessage,
    this.recordCount = 0,
  });
}

/// Service that handles exporting offline check-in records to Excel (.xlsx)
/// or CSV format, mirroring the `handleDownload` / `handleDownloadCsv`
/// functions found in `OfflineCheckInList.jsx` and `downloadAllData` in
/// `OfflineSection.jsx` of the reference React Native project.
///
/// Platform behaviour:
/// - **Android API >= 30**: saves directly to the public Downloads directory.
/// - **Android API < 30**: requests WRITE_EXTERNAL_STORAGE, then saves to
///   external storage directory.
/// - **iOS**: saves to app-documents directory, then summons the native
///   share sheet so the user can "Save to Files", AirDrop, or share via apps.
class OfflineExportService {
  static const String timestampPattern = 'dd-MM-yyyy_HH-mm-ss';
  static const String displayDatePattern = 'dd-MM-yyyy h:mm a';

  // ─── Pure Dart Generators (Unit-Testable without filesystem/platform) ───────

  /// Generates the raw bytes for an Excel (.xlsx) spreadsheet.
  /// Pure-Dart: fully testable in memory without platform channels or disk I/O.
  static List<int> generateExcelBytes({
    required List<CheckinRecord> records,
    required String sessionKey,
  }) {
    final workbook = xlsio.Workbook();
    final sheet = workbook.worksheets[0];
    sheet.name = 'Checkins';

    final isAllData = sessionKey == 'all' || sessionKey == 'offline-all-data';
    final idLabel = idLabelFor(sessionKey);
    final includeLocation = sessionKey == 'entrances';

    // Build headers matching reference project schema
    final List<String> headers;
    if (isAllData) {
      headers = [
        '#',
        'ID',
        'ENCRYPTED_CODE',
        'CODE',
        'ENTRANCE_ID',
        'ENTRANCE_LOCATION',
        'TYPE',
        'SECTION',
        'TIMESTAMP',
        'DATE & TIME',
        'IS_SYNCED',
        'IS_NOT_EXIST',
        'USER_ID',
      ];
    } else {
      headers = [
        '#',
        'ID',
        'ENCRYPTED_CODE',
        idLabel,
        'TYPE',
        'Status',
        'Registration Status',
        'DATE & TIME',
        if (includeLocation) 'ENTRANCE_LOCATION',
      ];
    }

    // Apply header row styles: bold, #607D8B background, white text
    for (int col = 0; col < headers.length; col++) {
      final cell = sheet.getRangeByIndex(1, col + 1);
      cell.setText(headers[col]);
      cell.cellStyle.bold = true;
      cell.cellStyle.backColor = '#607D8B';
      cell.cellStyle.fontColor = '#FFFFFF';
    }

    // Populate data rows
    for (int i = 0; i < records.length; i++) {
      final item = records[i];
      final row = i + 2; // Row index is 1-based, 1 is header
      int col = 1;

      sheet.getRangeByIndex(row, col++).setNumber((i + 1).toDouble()); // #
      sheet.getRangeByIndex(row, col++).setNumber((item.id ?? 0).toDouble()); // ID
      sheet.getRangeByIndex(row, col++).setText(item.encryptedCode); // ENCRYPTED_CODE

      if (isAllData) {
        sheet.getRangeByIndex(row, col++).setText(item.code); // CODE
        sheet.getRangeByIndex(row, col++).setNumber(item.entranceId.toDouble()); // ENTRANCE_ID
        sheet.getRangeByIndex(row, col++).setText(item.entranceLocation); // ENTRANCE_LOCATION
        sheet.getRangeByIndex(row, col++).setText(formatScanType(item.scanType)); // TYPE
        sheet.getRangeByIndex(row, col++).setText(item.section); // SECTION
        sheet.getRangeByIndex(row, col++).setNumber(item.timestamp.millisecondsSinceEpoch.toDouble()); // TIMESTAMP
        sheet.getRangeByIndex(row, col++).setText(formatDateTime(item.timestamp)); // DATE & TIME
        sheet.getRangeByIndex(row, col++).setText(item.isSynced ? 'Synced' : 'Unsynced'); // IS_SYNCED
        sheet.getRangeByIndex(row, col++).setText(item.isNotExist ? 'Unregistered' : 'Registered'); // IS_NOT_EXIST
        sheet.getRangeByIndex(row, col++).setText(item.userId ?? ''); // USER_ID
      } else {
        sheet.getRangeByIndex(row, col++).setNumber(item.entranceId.toDouble()); // idLabel
        sheet.getRangeByIndex(row, col++).setText(formatScanType(item.scanType)); // TYPE
        sheet.getRangeByIndex(row, col++).setText(item.isSynced ? 'Synced' : 'Unsynced'); // Status
        sheet.getRangeByIndex(row, col++).setText(item.isNotExist ? 'Unregistered' : 'Registered'); // Reg Status
        sheet.getRangeByIndex(row, col++).setText(formatDateTime(item.timestamp)); // DATE & TIME
        if (includeLocation) {
          sheet.getRangeByIndex(row, col++).setText(item.entranceLocation); // ENTRANCE_LOCATION
        }
      }
    }

    // Auto-fit columns for clear readability
    for (int col = 1; col <= headers.length; col++) {
      sheet.autoFitColumn(col);
    }

    final fileBytes = workbook.saveAsStream();
    workbook.dispose();
    return fileBytes;
  }

  /// Generates the raw CSV string.
  /// Pure-Dart: fully testable in memory without platform channels or disk I/O.
  static String generateCsvString({
    required List<CheckinRecord> records,
    required String sessionKey,
  }) {
    final isAllData = sessionKey == 'all' || sessionKey == 'offline-all-data';
    final idLabel = isAllData ? 'ENTRANCE_ID' : idLabelFor(sessionKey);

    final buffer = StringBuffer();

    // CSV header row matching reference project
    buffer.writeln(csvRow([
      'ID',
      'ENCRYPTED_CODE',
      'CODE',
      idLabel,
      'ENTRANCE_LOCATION',
      'TYPE',
      'SECTION',
      'TIMESTAMP',
      'DATE & TIME',
      'IS_SYNCED',
      'IS_NOT_EXIST',
      'USER_ID',
    ]));

    for (final item in records) {
      buffer.writeln(csvRow([
        (item.id ?? '').toString(),
        item.encryptedCode,
        item.code,
        item.entranceId.toString(),
        item.entranceLocation,
        item.scanType,
        item.section,
        item.timestamp.millisecondsSinceEpoch.toString(),
        formatDateTime(item.timestamp),
        item.isSynced ? 'Synced' : 'Unsynced',
        item.isNotExist ? 'Unregistered' : 'Registered',
        item.userId ?? '',
      ]));
    }

    return buffer.toString();
  }

  // ─── Format & Helper Utilities ──────────────────────────────────────────────

  /// Display scan type: 'check_in' / 'entry' → 'Check-In', 'check_out' / 'exit' → 'Check-Out'.
  static String formatScanType(String type) {
    final lower = type.toLowerCase();
    if (lower.contains('in') || lower == 'entry') return 'Check-In';
    if (lower.contains('out') || lower == 'exit') return 'Check-Out';
    return type;
  }

  /// Column header label per session type (mirrors reference project sessionIdLabels).
  static String idLabelFor(String session) {
    switch (session) {
      case 'entrances':
        return 'ENTRANCE_ID';
      case 'hall':
        return 'HALL_ID';
      case 'agenda':
        return 'AGENDA_ID';
      case 'session':
        return 'SESSION_ID';
      default:
        return 'ENTRANCE_ID';
    }
  }

  /// Format date & time for Excel / CSV export matching reference format 'DD-MM-YYYY h:mm A'.
  static String formatDateTime(DateTime dt) {
    return DateFormat(displayDatePattern).format(dt);
  }

  /// Format output filename: e.g. 'entrances-27-10-2026_16-30-00.xlsx' or
  /// 'offline-all-data-27-10-2026_16-30-00.csv'.
  static String formatFileName(String sessionKey, String extension, [DateTime? now]) {
    final timestamp = DateFormat(timestampPattern).format(now ?? DateTime.now());
    if (sessionKey == 'all' || sessionKey == 'offline-all-data') {
      return 'offline-all-data-$timestamp.$extension';
    }
    return '$sessionKey-$timestamp.$extension';
  }

  /// RFC 4180 standard CSV row formatting with double-quote escaping.
  static String csvRow(List<String> fields) {
    return fields.map((f) => '"${f.replaceAll('"', '""')}"').join(',');
  }

  // ─── Public Export APIs ─────────────────────────────────────────────────────

  /// Export [records] from [sessionKey] to an Excel (.xlsx) file.
  /// Mirrors `handleDownload` in OfflineCheckInList.jsx.
  Future<ExportResult> exportToExcel({
    required List<CheckinRecord> records,
    required String sessionKey,
  }) async {
    try {
      if (records.isEmpty) {
        return const ExportResult(
          success: false,
          errorMessage: 'No data available to download.',
          recordCount: 0,
        );
      }

      final fileBytes = generateExcelBytes(
        records: records,
        sessionKey: sessionKey,
      );

      final fileName = formatFileName(sessionKey, 'xlsx');
      final filePath = await _resolveFilePath(fileName);

      if (filePath == null) {
        return const ExportResult(
          success: false,
          errorMessage: 'Permission denied. Cannot save file.',
          recordCount: 0,
        );
      }

      String effectivePath = filePath;
      try {
        final file = File(effectivePath);
        await file.writeAsBytes(fileBytes);
      } catch (ioError) {
        debugPrint('[OfflineExportService] Primary path write failed ($filePath): $ioError. Attempting fallback...');
        final fallbackDir = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
        final fallbackPath = '${fallbackDir.path}/$fileName';
        final fallbackFile = File(fallbackPath);
        await fallbackFile.writeAsBytes(fileBytes);
        effectivePath = fallbackPath;
      }

      if (Platform.isIOS) {
        try {
          await SharePlus.instance.share(
            ShareParams(
              files: [
                XFile(
                  effectivePath,
                  mimeType:
                      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
                )
              ],
            ),
          );
        } catch (shareErr) {
          debugPrint('[OfflineExportService] iOS Share sheet error (file still saved): $shareErr');
        }
      }

      return ExportResult(
        success: true,
        filePath: effectivePath,
        recordCount: records.length,
      );
    } catch (e, st) {
      debugPrint('[OfflineExportService] exportToExcel error: $e\n$st');
      return const ExportResult(
        success: false,
        errorMessage: 'Failed to download Excel file.',
      );
    }
  }

  /// Export [records] from [sessionKey] to a CSV file.
  /// Mirrors `handleDownloadCsv` in OfflineCheckInList.jsx.
  Future<ExportResult> exportToCsv({
    required List<CheckinRecord> records,
    required String sessionKey,
  }) async {
    try {
      if (records.isEmpty) {
        return const ExportResult(
          success: false,
          errorMessage: 'No data available to download.',
          recordCount: 0,
        );
      }

      final csvContent = generateCsvString(
        records: records,
        sessionKey: sessionKey,
      );

      final fileName = formatFileName(sessionKey, 'csv');
      final filePath = await _resolveFilePath(fileName);

      if (filePath == null) {
        return const ExportResult(
          success: false,
          errorMessage: 'Permission denied. Cannot save file.',
          recordCount: 0,
        );
      }

      String effectivePath = filePath;
      try {
        final file = File(effectivePath);
        await file.writeAsString(csvContent, flush: true);
      } catch (ioError) {
        debugPrint('[OfflineExportService] Primary path write failed ($filePath): $ioError. Attempting fallback...');
        final fallbackDir = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
        final fallbackPath = '${fallbackDir.path}/$fileName';
        final fallbackFile = File(fallbackPath);
        await fallbackFile.writeAsString(csvContent, flush: true);
        effectivePath = fallbackPath;
      }

      if (Platform.isIOS) {
        try {
          await SharePlus.instance.share(
            ShareParams(
              files: [XFile(effectivePath, mimeType: 'text/csv')],
            ),
          );
        } catch (shareErr) {
          debugPrint('[OfflineExportService] iOS Share sheet error (file still saved): $shareErr');
        }
      }

      return ExportResult(
        success: true,
        filePath: effectivePath,
        recordCount: records.length,
      );
    } catch (e, st) {
      debugPrint('[OfflineExportService] exportToCsv error: $e\n$st');
      return const ExportResult(
        success: false,
        errorMessage: 'Failed to download CSV file.',
      );
    }
  }

  // ─── Private Platform Resolution ────────────────────────────────────────────

  /// Determine the correct platform + API-level file path.
  /// Requests WRITE_EXTERNAL_STORAGE on Android < API 30.
  Future<String?> _resolveFilePath(String fileName) async {
    if (Platform.isAndroid) {
      final isModernAndroid = await _isAndroidApi30OrHigher();

      if (!isModernAndroid) {
        // Android 10 and below – must request runtime permission
        final status = await Permission.storage.request();
        if (!status.isGranted) return null;

        final extDir = await getExternalStorageDirectory();
        return '${extDir?.path ?? '/storage/emulated/0'}/$fileName';
      } else {
        // Android 11+ – write to public Downloads without runtime permission
        Directory downloadsDir = Directory('/storage/emulated/0/Download');
        if (!downloadsDir.existsSync()) {
          try {
            downloadsDir.createSync(recursive: true);
          } catch (_) {
            final fallback = await getExternalStorageDirectory();
            if (fallback != null) {
              downloadsDir = fallback;
            }
          }
        }
        return '${downloadsDir.path}/$fileName';
      }
    } else {
      // iOS
      final docsDir = await getApplicationDocumentsDirectory();
      return '${docsDir.path}/$fileName';
    }
  }

  /// Detects whether current device is Android API 30 (Android 11) or higher.
  Future<bool> _isAndroidApi30OrHigher() async {
    try {
      final info = await DeviceDetectionService().detectDevice();
      if (info.sdkInt > 0) {
        return info.sdkInt >= 30;
      }
    } catch (_) {}

    try {
      return Directory('/storage/emulated/0/Download').existsSync();
    } catch (_) {
      return true;
    }
  }
}
