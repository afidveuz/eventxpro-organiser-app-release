import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../core/services/offline_export_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_toast.dart';
import '../../../data/datasources/offline_database_helper.dart';
import '../../../data/models/checkin_record.dart';
import '../../bloc/scanner_bloc.dart';
import '../../bloc/scanner_event.dart';
import '../../widgets/fade_in_background_image.dart';

/// Check-in list screen matching `OfflineCheckInList.jsx` in the React Native EventXPro app.
/// Shows all offline records saved for a specific session (entrances, hall, agenda, or session).
/// Displays the code, gate location, and sync status with search filtering and detail inspector.
class OfflineCheckInListScreen extends StatefulWidget {
  final String sessionKey;
  final String sessionTitle;

  const OfflineCheckInListScreen({
    super.key,
    required this.sessionKey,
    required this.sessionTitle,
  });

  @override
  State<OfflineCheckInListScreen> createState() => _OfflineCheckInListScreenState();
}

class _OfflineCheckInListScreenState extends State<OfflineCheckInListScreen> {
  List<CheckinRecord> _records = [];
  bool _isLoading = true;
  String _selectedFilter = 'all'; // 'all', 'synced', 'unsynced', 'registered', 'unregistered'
  int _totalCount = 0;
  int _syncedCount = 0;
  int _unsyncedCount = 0;
  int _registeredCount = 0;
  int _unregisteredCount = 0;
  bool _isSyncing = false;
  bool _isDownloading = false;

  final OfflineExportService _exportService = OfflineExportService();

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final DateFormat _dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRecords() async {
    setState(() => _isLoading = true);
    final db = context.read<OfflineDatabaseHelper>();

    bool? syncFilter;
    bool? notExistFilter;

    if (_selectedFilter == 'synced') {
      syncFilter = true;
    } else if (_selectedFilter == 'unsynced') {
      syncFilter = false;
    } else if (_selectedFilter == 'registered') {
      notExistFilter = false;
    } else if (_selectedFilter == 'unregistered') {
      notExistFilter = true;
    }

    final stats = await db.getSectionStats(section: widget.sessionKey);
    final records = await db.getCheckins(
      section: widget.sessionKey,
      isSynced: syncFilter,
      isNotExist: notExistFilter,
      limit: 500,
    );

    if (mounted) {
      setState(() {
        _totalCount = stats['total'] ?? 0;
        _syncedCount = stats['synced'] ?? 0;
        _unsyncedCount = stats['unsynced'] ?? 0;
        _registeredCount = stats['registered'] ?? 0;
        _unregisteredCount = stats['unregistered'] ?? 0;
        _records = records;
        _isLoading = false;
      });
    }
  }

  List<CheckinRecord> get _filteredRecords {
    if (_searchQuery.trim().isEmpty) return _records;
    final q = _searchQuery.trim().toLowerCase();
    return _records.where((r) {
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

  Future<void> _syncSection() async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);

    try {
      final completer = Completer<int>();
      context.read<ScannerBloc>().add(
        ScannerSyncOfflineRequested(
          section: widget.sessionKey,
          completer: completer,
        ),
      );

      final synced = await completer.future.timeout(
        const Duration(seconds: 45),
        onTimeout: () => 0,
      );

      await _loadRecords();

      if (mounted) {
        if (synced > 0) {
          AppToast.showSuccess(
            message: 'Successfully synchronized $synced records for ${widget.sessionTitle}.',
          );
        } else if (_unsyncedCount == 0) {
          AppToast.showSuccess(
            message: 'All records for ${widget.sessionTitle} are synchronized.',
          );
        } else {
          AppToast.showWarning(
            message: 'Sync finished. $_unsyncedCount records still pending.',
          );
        }
      }
    } catch (e) {
      await _loadRecords();
      if (mounted) {
        AppToast.showError(
          message: 'Synchronization failed for ${widget.sessionTitle}: $e',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  void _showRecordDetails(CheckinRecord record) {
    final displayCode = record.encryptedCode.isNotEmpty ? record.encryptedCode : record.code;
    final isCheckIn = record.scanType.toLowerCase().contains('in');
    final formattedDate = _dateFormat.format(record.timestamp);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppTheme.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetCtx).size.height * 0.9,
          ),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle Bar
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: AppTheme.accentIndigo.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppTheme.accentIndigo.withValues(alpha: 0.25),
                                  width: 1,
                                ),
                              ),
                              child: const Icon(
                                Icons.qr_code_2_rounded,
                                color: AppTheme.accentIndigo,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Offline Check-in #${record.id ?? '-'}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.1,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Session: ${widget.sessionTitle}',
                                    style: const TextStyle(
                                      color: AppTheme.textMuted,
                                      fontSize: 12.5,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 18),
                          onPressed: () => Navigator.of(sheetCtx).pop(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
                  const SizedBox(height: 16),

                  // Encrypted Code Section
                  _buildDetailInfoTile(
                    title: 'ENCRYPTED CODE',
                    value: displayCode,
                    icon: Icons.qr_code_2_rounded,
                    accentColor: AppTheme.accentIndigo,
                  ),

                  const SizedBox(height: 16),

                  // Metadata grid
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.035),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: Column(
                      children: [
                        _buildMetaRow(
                          'Punch Action',
                          isCheckIn ? 'Check-In' : 'Check-Out',
                          isCheckIn ? AppTheme.accentIndigo : AppTheme.eventxproDanger,
                          isPill: true,
                        ),
                        _buildMetaDivider(),
                        _buildMetaRow(
                          'Gate / Entrance',
                          'Gate #${record.entranceId} (${record.entranceLocation.isNotEmpty ? record.entranceLocation : widget.sessionTitle})',
                          Colors.white,
                        ),
                        _buildMetaDivider(),
                        _buildMetaRow(
                          'Timestamp',
                          formattedDate,
                          AppTheme.textSecondary,
                        ),
                        _buildMetaDivider(),
                        _buildMetaRow(
                          'Server Sync Status',
                          record.isSynced ? 'Synced to Server' : 'Pending Sync',
                          record.isSynced ? AppTheme.accentIndigo : AppTheme.accentOrange,
                          icon: record.isSynced ? Icons.check_circle_rounded : Icons.schedule_rounded,
                        ),
                        _buildMetaDivider(),
                        _buildMetaRow(
                          'Registration Status',
                          record.isNotExist ? 'Unregistered' : 'Registered',
                          record.isNotExist ? AppTheme.eventxproDanger : AppTheme.accentIndigo,
                          isPill: true,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Close button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accentIndigo,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => Navigator.of(sheetCtx).pop(),
                      child: const Text(
                        'Close',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailInfoTile({
    required String title,
    required String value,
    required IconData icon,
    required Color accentColor,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accentColor.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: accentColor),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  color: accentColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: value));
                    AppToast.showSuccess(message: 'Code copied to clipboard');
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.copy_rounded, size: 12, color: accentColor),
                        const SizedBox(width: 4),
                        Text(
                          'Copy',
                          style: TextStyle(
                            color: accentColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Divider(
        color: Colors.white.withValues(alpha: 0.05),
        height: 1,
      ),
    );
  }

  Widget _buildMetaRow(
    String label,
    String value,
    Color valueColor, {
    IconData? icon,
    bool isPill = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.textMuted,
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: isPill
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: valueColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: valueColor.withValues(alpha: 0.25),
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    value,
                    style: TextStyle(
                      color: valueColor,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 13, color: valueColor),
                      const SizedBox(width: 5),
                    ],
                    Flexible(
                      child: Text(
                        value,
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          color: valueColor,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredRecords;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface.withValues(alpha: 0.95),
        elevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.sessionTitle} Check-ins',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _unsyncedCount > 0
                  ? '$_totalCount records • $_unsyncedCount pending'
                  : '$_totalCount records • All synced',
              style: TextStyle(
                color: _unsyncedCount > 0 ? AppTheme.accentOrange : AppTheme.textSecondary,
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70, size: 21),
            onPressed: _loadRecords,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(
            color: Colors.white.withValues(alpha: 0.08),
            height: 1,
          ),
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const AppBackgroundLayer(),
          Column(
            children: [
              // ── Search Bar ────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.09),
                      width: 1,
                    ),
                  ),
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white, fontSize: 13.5),
                    cursorColor: AppTheme.accentIndigo,
                    decoration: InputDecoration(
                      hintText: 'Search code, gate, record #...',
                      hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                      prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textMuted, size: 20),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, color: Colors.white60, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onChanged: (val) {
                      setState(() => _searchQuery = val);
                    },
                  ),
                ),
              ),

              // ── Action Buttons Row (Sync & Export) ────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Row(
                  children: [
                    Expanded(child: _buildSyncButton()),
                    const SizedBox(width: 10),
                    Expanded(child: _buildDownloadButton()),
                  ],
                ),
              ),

              // ── Filter Chips Bar ──────────────────────────────────────────
              _buildFilterBar(),

              // ── Check-in Records List ─────────────────────────────────────
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: AppTheme.accentIndigo))
                    : filtered.isEmpty
                        ? _buildEmptyState()
                        : RefreshIndicator(
                            onRefresh: _loadRecords,
                            color: AppTheme.accentIndigo,
                            backgroundColor: AppTheme.surfaceElevated,
                            child: ListView.separated(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              itemCount: filtered.length,
                              separatorBuilder: (context, index) => const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                return _buildRecordCard(filtered[index]);
                              },
                            ),
                          ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSyncButton() {
    final hasPending = _unsyncedCount > 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isSyncing ? null : _syncSection,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _isSyncing
                ? AppTheme.accentIndigo.withValues(alpha: 0.35)
                : (hasPending
                    ? AppTheme.accentIndigo
                    : Colors.white.withValues(alpha: 0.04)),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: hasPending
                  ? AppTheme.accentIndigo
                  : Colors.white.withValues(alpha: 0.09),
              width: 1.0,
            ),
            boxShadow: hasPending
                ? [
                    BoxShadow(
                      color: AppTheme.accentIndigo.withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isSyncing)
                const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              else
                Icon(
                  hasPending
                      ? Icons.cloud_upload_rounded
                      : Icons.cloud_done_rounded,
                  size: 17,
                  color: hasPending ? Colors.white : AppTheme.accentIndigo,
                ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _isSyncing
                      ? 'Syncing...'
                      : (hasPending ? 'Sync ($_unsyncedCount)' : 'All Synced'),
                  style: TextStyle(
                    color: hasPending || _isSyncing
                        ? Colors.white
                        : AppTheme.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Download menu button shown in the Action Row below the search bar.
  /// Tapping it shows a popup menu with "Export Excel" and "Export CSV".
  Widget _buildDownloadButton() {
    return PopupMenuButton<_DownloadFormat>(
      tooltip: 'Export offline data',
      color: AppTheme.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      onSelected: (format) {
        if (format == _DownloadFormat.excel) {
          _downloadExcel();
        } else {
          _downloadCsv();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _DownloadFormat.excel,
          child: Row(
            children: const [
              Icon(Icons.table_chart_rounded, color: AppTheme.accentIndigo, size: 18),
              SizedBox(width: 10),
              Text(
                'Export Excel (.xlsx)',
                style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: _DownloadFormat.csv,
          child: Row(
            children: const [
              Icon(Icons.description_rounded, color: AppTheme.accentIndigo, size: 18),
              SizedBox(width: 10),
              Text(
                'Export CSV (.csv)',
                style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ],
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.09),
            width: 1.0,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isDownloading)
              const SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppTheme.accentIndigo,
                ),
              )
            else
              const Icon(
                Icons.file_download_outlined,
                color: AppTheme.accentIndigo,
                size: 17,
              ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                _isDownloading ? 'Exporting...' : 'Export Data',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: AppTheme.textMuted,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  /// Fetch all records for current section + active filter, then call
  /// [OfflineExportService.exportToExcel]. Mirrors `handleDownload` in
  /// the reference React Native project.
  Future<void> _downloadExcel() async {
    if (_isDownloading) return;
    setState(() => _isDownloading = true);
    try {
      final db = context.read<OfflineDatabaseHelper>();
      final records = await db.getAllCheckinsForExport(
        section: widget.sessionKey,
        isSynced: _syncFilterForExport(),
        isNotExist: _regFilterForExport(),
      );

      final result = await _exportService.exportToExcel(
        records: records,
        sessionKey: widget.sessionKey,
      );

      if (!mounted) return;
      _showExportFeedback(result);
    } catch (e) {
      if (mounted) {
        _showExportFeedback(const ExportResult(
          success: false,
          errorMessage: 'Failed to download Excel file.',
        ));
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  /// Fetch all records for current section + active filter, then call
  /// [OfflineExportService.exportToCsv]. Mirrors `handleDownloadCsv` in
  /// the reference React Native project.
  Future<void> _downloadCsv() async {
    if (_isDownloading) return;
    setState(() => _isDownloading = true);
    try {
      final db = context.read<OfflineDatabaseHelper>();
      final records = await db.getAllCheckinsForExport(
        section: widget.sessionKey,
        isSynced: _syncFilterForExport(),
        isNotExist: _regFilterForExport(),
      );

      final result = await _exportService.exportToCsv(
        records: records,
        sessionKey: widget.sessionKey,
      );

      if (!mounted) return;
      _showExportFeedback(result);
    } catch (e) {
      if (mounted) {
        _showExportFeedback(const ExportResult(
          success: false,
          errorMessage: 'Failed to download CSV file.',
        ));
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  /// Map current chip filter to the isSynced parameter for the DB query.
  bool? _syncFilterForExport() {
    if (_selectedFilter == 'synced') return true;
    if (_selectedFilter == 'unsynced') return false;
    return null;
  }

  /// Map current chip filter to the isNotExist parameter for the DB query.
  bool? _regFilterForExport() {
    if (_selectedFilter == 'registered') return false;
    if (_selectedFilter == 'unregistered') return true;
    return null;
  }

  /// Displays a toast notification with success or error feedback after an export.
  void _showExportFeedback(ExportResult result) {
    if (!mounted) return;
    if (result.success) {
      final savedAt = result.filePath?.replaceAll('/storage/emulated/0/', '') ?? '';
      AppToast.showSuccess(
        title: 'File downloaded successfully!',
        message: savedAt.isNotEmpty ? 'Saved at: $savedAt' : 'File ready for use.',
        duration: const Duration(seconds: 3),
      );
    } else {
      AppToast.showError(
        message: result.errorMessage ?? 'Failed to download file.',
        duration: const Duration(seconds: 3),
      );
    }
  }

  Widget _buildFilterBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.06),
            width: 1,
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            _buildFilterChip('All', 'all', _totalCount),
            const SizedBox(width: 8),
            _buildFilterChip('Synced', 'synced', _syncedCount),
            const SizedBox(width: 8),
            _buildFilterChip('Unsynced', 'unsynced', _unsyncedCount),
            const SizedBox(width: 8),
            _buildFilterChip('Registered', 'registered', _registeredCount),
            const SizedBox(width: 8),
            _buildFilterChip('Unregistered', 'unregistered', _unregisteredCount),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String key, int count) {
    final isSelected = _selectedFilter == key;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          if (_selectedFilter != key) {
            setState(() {
              _selectedFilter = key;
            });
            _loadRecords();
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.accentIndigo
                : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? AppTheme.accentIndigo
                  : Colors.white.withValues(alpha: 0.08),
              width: 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppTheme.accentIndigo.withValues(alpha: 0.28),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.22)
                      : Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: isSelected ? Colors.white : AppTheme.textMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecordCard(CheckinRecord record) {
    final isSynced = record.isSynced;
    final formattedDate = _dateFormat.format(record.timestamp);
    final isCheckIn = record.scanType.toLowerCase().contains('in');
    final displayCode = record.encryptedCode.isNotEmpty ? record.encryptedCode : record.code;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1.0,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showRecordDetails(record),
          borderRadius: BorderRadius.circular(16),
          splashColor: AppTheme.accentIndigo.withValues(alpha: 0.08),
          highlightColor: AppTheme.accentIndigo.withValues(alpha: 0.04),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Row 1: ID, Action Badge, and Status Badges
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Text(
                            '#${record.id ?? '-'}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isCheckIn
                                ? AppTheme.accentIndigo.withValues(alpha: 0.12)
                                : AppTheme.eventxproDanger.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isCheckIn
                                  ? AppTheme.accentIndigo.withValues(alpha: 0.25)
                                  : AppTheme.eventxproDanger.withValues(alpha: 0.25),
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            isCheckIn ? 'Check-in' : 'Check-out',
                            style: TextStyle(
                              color: isCheckIn ? AppTheme.accentIndigo : AppTheme.eventxproDanger,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),

                    // Right side: Registration status & Sync status
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (record.isNotExist) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppTheme.eventxproDanger.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: AppTheme.eventxproDanger.withValues(alpha: 0.3),
                                width: 0.8,
                              ),
                            ),
                            child: const Text(
                              'Unregistered',
                              style: TextStyle(
                                color: AppTheme.eventxproDanger,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isSynced
                                ? AppTheme.accentIndigo.withValues(alpha: 0.08)
                                : AppTheme.accentOrange.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSynced
                                  ? AppTheme.accentIndigo.withValues(alpha: 0.2)
                                  : AppTheme.accentOrange.withValues(alpha: 0.28),
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isSynced ? Icons.check_circle_rounded : Icons.schedule_rounded,
                                size: 12,
                                color: isSynced ? AppTheme.accentIndigo : AppTheme.accentOrange,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isSynced ? 'Synced' : 'Pending',
                                style: TextStyle(
                                  color: isSynced ? AppTheme.accentIndigo : AppTheme.accentOrange,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // Row 2: Encrypted Code Box
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppTheme.accentIndigo.withValues(alpha: 0.2),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.qr_code_2_rounded, color: AppTheme.accentIndigo, size: 14),
                      const SizedBox(width: 6),
                      const Text(
                        'CODE: ',
                        style: TextStyle(
                          color: AppTheme.accentIndigo,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          displayCode,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'monospace',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                // Row 3: Gate/Location & Timestamp
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          const Icon(Icons.meeting_room_outlined, size: 13, color: AppTheme.textMuted),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'Gate #${record.entranceId} (${record.entranceLocation.isNotEmpty ? record.entranceLocation : widget.sessionTitle})',
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 11.5,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.schedule_rounded, size: 12, color: AppTheme.textMuted),
                        const SizedBox(width: 4),
                        Text(
                          formattedDate,
                          style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    String filterLabel = '';
    if (_selectedFilter != 'all') {
      filterLabel = '${_selectedFilter.substring(0, 1).toUpperCase()}${_selectedFilter.substring(1)} ';
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppTheme.accentIndigo.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.qr_code_2_rounded,
              size: 36,
              color: AppTheme.accentIndigo,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isNotEmpty
                ? 'No check-ins match "$_searchQuery"'
                : 'No ${filterLabel.toLowerCase()}check-ins found',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Scanned ticket codes will appear here in real-time',
            style: TextStyle(
              color: AppTheme.textMuted,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Enum used by the download popup menu to distinguish export formats.
enum _DownloadFormat { excel, csv }

