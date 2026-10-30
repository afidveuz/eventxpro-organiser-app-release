import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;
import '../../core/network/api_client.dart';
import '../datasources/lead_remote_datasource.dart';
import '../models/lead_model.dart';

class LeadRepository {
  final LeadRemoteDatasource _remoteDatasource;

  LeadRepository({required LeadRemoteDatasource remoteDatasource})
      : _remoteDatasource = remoteDatasource;

  Future<LeadCaptureResult> captureLead({
    required String uniqueId,
    int scanType = 0,
  }) async {
    try {
      return await _remoteDatasource.captureLead(
        uniqueId: uniqueId,
        scanType: scanType,
      );
    } on DioException catch (e) {
      final msg = ApiClient.formatDioError(e);
      return LeadCaptureResult(isSuccess: false, message: msg);
    } catch (e) {
      return LeadCaptureResult(isSuccess: false, message: e.toString());
    }
  }

  Future<LeadPaginatedResult> getLeads({
    int pageNo = 1,
    int count = 20,
    String keyword = '',
    int? eventId,
  }) async {
    try {
      return await _remoteDatasource.getLeads(
        pageNo: pageNo,
        count: count,
        keyword: keyword,
        eventId: eventId,
      );
    } on DioException catch (e) {
      debugPrint('[LeadRepository] ❌ getLeads error: ${ApiClient.formatDioError(e)}');
      rethrow;
    }
  }

  Future<LeadModel?> getLeadDetails(int id) async {
    try {
      return await _remoteDatasource.getLeadDetails(id);
    } catch (e) {
      debugPrint('[LeadRepository] ❌ getLeadDetails error: $e');
      return null;
    }
  }

  Future<bool> updateLead({
    required int id,
    required String leadType,
    required String notes,
  }) async {
    try {
      final res = await _remoteDatasource.updateLead(
        id: id,
        leadType: leadType,
        notes: notes,
      );
      return res['status'] == true;
    } catch (e) {
      debugPrint('[LeadRepository] ❌ updateLead error: $e');
      return false;
    }
  }

  /// Exports leads to an Excel (.xlsx) file and triggers native sharing.
  /// 1. Attempts remote export endpoint 'organizer/lead-export-organizer'
  /// 2. If remote blob is unavailable, generates a high-quality Excel file using Syncfusion
  Future<String?> exportLeadsAndShare({
    List<LeadModel>? fallbackLeads,
  }) async {
    try {
      // 1. Try server-side export first
      try {
        final serverExport = await _remoteDatasource.exportLeads();
        final blobData = serverExport['blob_data']?.toString();
        final filename = serverExport['filename']?.toString() ?? 'eventxpro_leads.xlsx';

        if (blobData != null && blobData.isNotEmpty) {
          final bytes = base64Decode(blobData);
          final tempDir = await getTemporaryDirectory();
          final file = File('${tempDir.path}/$filename');
          await file.writeAsBytes(bytes);

          await SharePlus.instance.share(
            ShareParams(
              files: [XFile(file.path, mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')],
              text: 'EventXPro Leads Export',
            ),
          );
          return file.path;
        }
      } catch (serverErr) {
        debugPrint('[LeadRepository] ⚠️ Server export failed, using local generation: $serverErr');
      }

      // 2. Client-side fallback generation with Syncfusion
      if (fallbackLeads != null && fallbackLeads.isNotEmpty) {
        final workbook = xlsio.Workbook();
        final sheet = workbook.worksheets[0];
        sheet.name = 'Leads';

        // Headers
        final headers = [
          'Lead ID',
          'Name',
          'Company',
          'Designation',
          'Email',
          'Mobile',
          'Lead Rating',
          'Notes',
          'Ticket Type',
          'Event',
          'Captured Date',
          'Captured Time',
        ];

        for (int i = 0; i < headers.length; i++) {
          final cell = sheet.getRangeByIndex(1, i + 1);
          cell.setText(headers[i]);
          cell.cellStyle.bold = true;
          cell.cellStyle.backColor = '#171C26';
          cell.cellStyle.fontColor = '#FFFFFF';
        }

        // Data rows
        for (int row = 0; row < fallbackLeads.length; row++) {
          final lead = fallbackLeads[row];
          final r = row + 2;
          sheet.getRangeByIndex(r, 1).setNumber(lead.id.toDouble());
          sheet.getRangeByIndex(r, 2).setText(lead.fullName);
          sheet.getRangeByIndex(r, 3).setText(lead.companyName ?? '');
          sheet.getRangeByIndex(r, 4).setText(lead.designation ?? '');
          sheet.getRangeByIndex(r, 5).setText(lead.email ?? '');
          sheet.getRangeByIndex(r, 6).setText(lead.mobile ?? '');
          sheet.getRangeByIndex(r, 7).setText(lead.leadType);
          sheet.getRangeByIndex(r, 8).setText(lead.notes ?? '');
          sheet.getRangeByIndex(r, 9).setText(lead.ticketType ?? '');
          sheet.getRangeByIndex(r, 10).setText(lead.eventName ?? '');
          sheet.getRangeByIndex(r, 11).setText(lead.checkInDt ?? '');
          sheet.getRangeByIndex(r, 12).setText(lead.checkInTm ?? '');
        }

        final List<int> bytes = workbook.saveAsStream();
        workbook.dispose();

        final tempDir = await getTemporaryDirectory();
        final timeStr = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
        final file = File('${tempDir.path}/EventXPro_Leads_$timeStr.xlsx');
        await file.writeAsBytes(bytes);

        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path, mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')],
            text: 'EventXPro Leads Export',
          ),
        );
        return file.path;
      }
    } catch (e) {
      debugPrint('[LeadRepository] ❌ exportLeadsAndShare error: $e');
    }
    return null;
  }
}
