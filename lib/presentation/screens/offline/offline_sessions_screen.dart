import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/services/offline_export_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_toast.dart';
import '../../../data/datasources/offline_database_helper.dart';
import '../../bloc/scanner_bloc.dart';
import '../../bloc/scanner_event.dart';
import '../../widgets/fade_in_background_image.dart';
import 'offline_checkin_list_screen.dart';

/// Offline Sessions screen matching `OfflineSection.jsx` in the React Native EventXPro app.
/// Lists sessions: Entrances, Halls, Agendas, and Sessions.
/// Allows syncing all pending records and viewing check-in tables per session.
class OfflineSessionsScreen extends StatefulWidget {
  final bool? isRootTab;

  const OfflineSessionsScreen({
    super.key,
    this.isRootTab,
  });

  @override
  State<OfflineSessionsScreen> createState() => _OfflineSessionsScreenState();
}

class _OfflineSessionsScreenState extends State<OfflineSessionsScreen> {
  Map<String, Map<String, int>> _sectionSummary = {
    'entrances': {'total': 0, 'unsynced': 0},
    'hall': {'total': 0, 'unsynced': 0},
    'agenda': {'total': 0, 'unsynced': 0},
    'session': {'total': 0, 'unsynced': 0},
  };
  bool _isLoading = true;
  bool _isSyncing = false;
  bool _isDownloading = false;
  final OfflineExportService _exportService = OfflineExportService();

  final List<_SessionConfig> _sessions = const [
    _SessionConfig(
      key: 'entrances',
      title: 'Entrances',
      subtitle: 'Main event gate entry & exit check-ins',
      icon: Icons.meeting_room_outlined,
      accentColor: AppTheme.accentIndigo,
    ),
    _SessionConfig(
      key: 'hall',
      title: 'Halls',
      subtitle: 'Exhibition & convention hall access',
      icon: Icons.domain_outlined,
      accentColor: AppTheme.accentIndigo,
    ),
    _SessionConfig(
      key: 'agenda',
      title: 'Agendas',
      subtitle: 'Keynote & workshop attendee admittance',
      icon: Icons.event_note_outlined,
      accentColor: AppTheme.accentIndigo,
    ),
    _SessionConfig(
      key: 'session',
      title: 'Sessions',
      subtitle: 'Track-specific and breakout session check-ins',
      icon: Icons.co_present_outlined,
      accentColor: AppTheme.accentIndigo,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    setState(() => _isLoading = true);
    final db = context.read<OfflineDatabaseHelper>();
    final summary = await db.getSectionSummary();

    if (mounted) {
      setState(() {
        _sectionSummary = summary;
        _isLoading = false;
      });
    }
  }

  int get _totalUnsynced {
    int count = 0;
    for (final sec in _sectionSummary.values) {
      count += sec['unsynced'] ?? 0;
    }
    return count;
  }

  int get _totalScans {
    int count = 0;
    for (final sec in _sectionSummary.values) {
      count += sec['total'] ?? 0;
    }
    return count;
  }

  Future<void> _syncAll() async {
    setState(() => _isSyncing = true);
    final bloc = context.read<ScannerBloc>();
    bloc.add(const ScannerSyncOfflineRequested());

    // Wait briefly for repository chunk sync loop
    await Future.delayed(const Duration(milliseconds: 1500));
    await _loadSummary();

    if (mounted) {
      setState(() => _isSyncing = false);
      AppToast.showSuccess(
        message: 'Offline synchronization completed.',
      );
    }
  }

  Future<void> _clearSyncedRecords() async {
    final hasSyncedToClean = _totalScans > _totalUnsynced;
    if (!hasSyncedToClean) {
      AppToast.showWarning(
        message: 'No synced records to clean up.',
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        ),
        title: const Text(
          'Clean Up Synced Records',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 17,
          ),
        ),
        content: const Text(
          'This will delete all records that have already been synchronized with the server to free up local storage. Unsynced records will remain intact.',
          style: TextStyle(
            color: AppTheme.textSecondary,
            height: 1.45,
            fontSize: 13.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentIndigo,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear Synced'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final db = context.read<OfflineDatabaseHelper>();
      final deleted = await db.clearSyncedCheckins();
      await _loadSummary();

      if (mounted) {
        AppToast.showSuccess(
          message: 'Cleared $deleted synced records from local database.',
        );
      }
    }
  }

  /// Exports all offline check-ins across all sessions to Excel or CSV.
  /// Mirrors `downloadAllData` in `OfflineSection.jsx` of the reference project.
  Future<void> _downloadAllData({bool isExcel = true}) async {
    if (_isDownloading) return;
    setState(() => _isDownloading = true);
    try {
      final db = context.read<OfflineDatabaseHelper>();
      final records = await db.getAllCheckinsForExport();

      if (records.isEmpty) {
        if (!mounted) return;
        AppToast.showWarning(
          message: 'No offline data available to export.',
        );
        return;
      }

      final result = isExcel
          ? await _exportService.exportToExcel(
              records: records,
              sessionKey: 'all',
            )
          : await _exportService.exportToCsv(
              records: records,
              sessionKey: 'all',
            );

      if (!mounted) return;
      if (result.success) {
        final savedAt = result.filePath?.replaceAll('/storage/emulated/0/', '') ?? '';
        AppToast.showSuccess(
          title: 'Exported ${result.recordCount} records successfully!',
          message: savedAt.isNotEmpty ? 'Saved at: $savedAt' : 'File ready for use.',
          duration: const Duration(seconds: 4),
        );
      } else {
        AppToast.showError(
          message: result.errorMessage ?? 'Export failed.',
        );
      }
    } catch (e) {
      if (mounted) {
        AppToast.showError(
          message: isExcel ? 'Failed to export Excel file.' : 'Failed to export CSV file.',
        );
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  Widget _buildGlassCard({
    required Widget child,
    BorderRadius? borderRadius,
    EdgeInsetsGeometry? padding,
    Border? border,
    Color? color,
  }) {
    final radius = borderRadius ?? BorderRadius.circular(16);
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: color ?? Colors.white.withValues(alpha: 0.04),
            borderRadius: radius,
            border: border ??
                Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                  width: 1,
                ),
          ),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface.withValues(alpha: 0.95),
        elevation: 0,
        centerTitle: false,
        automaticallyImplyLeading: false,
        leading: (widget.isRootTab == true || !Navigator.canPop(context))
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                onPressed: () => Navigator.of(context).pop(),
              ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Offline Sessions',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _totalUnsynced > 0
                  ? '$_totalScans records • $_totalUnsynced pending sync'
                  : '$_totalScans records • All synced',
              style: TextStyle(
                color: _totalUnsynced > 0 ? AppTheme.accentOrange : AppTheme.textSecondary,
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<bool>(
            tooltip: 'Export all offline data',
            icon: _isDownloading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.accentIndigo,
                    ),
                  )
                : const Icon(
                    Icons.file_download_outlined,
                    color: AppTheme.accentIndigo,
                    size: 22,
                  ),
            color: AppTheme.surfaceElevated,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
            onSelected: (isExcel) => _downloadAllData(isExcel: isExcel),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: true,
                child: Row(
                  children: const [
                    Icon(Icons.table_chart_rounded, color: AppTheme.eventxproSuccess, size: 18),
                    SizedBox(width: 10),
                    Text(
                      'Export All to Excel (.xlsx)',
                      style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: false,
                child: Row(
                  children: const [
                    Icon(Icons.description_rounded, color: AppTheme.accentIndigo, size: 18),
                    SizedBox(width: 10),
                    Text(
                      'Export All to CSV (.csv)',
                      style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ],
          ),
          IconButton(
            tooltip: 'Refresh summary',
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70, size: 22),
            onPressed: _loadSummary,
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
          _isLoading
              ? const Center(child: CircularProgressIndicator(color: AppTheme.accentIndigo))
              : RefreshIndicator(
                  onRefresh: _loadSummary,
                  color: AppTheme.accentIndigo,
                  backgroundColor: AppTheme.surfaceElevated,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    children: [
                      // ── Top Stats Banner ──────────────────────────────────
                      _buildHeaderStats(),

                      const SizedBox(height: 22),

                      // ── SESSIONS Header ───────────────────────────────────
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        child: Row(
                          children: [
                            const Text(
                              'SESSION CATEGORIES',
                              style: TextStyle(
                                color: AppTheme.textMuted,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.1,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '${_sessions.length} sections',
                              style: TextStyle(
                                color: AppTheme.textMuted.withValues(alpha: 0.7),
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 8),

                      // ── Session Cards ─────────────────────────────────────
                      ..._sessions.map((session) => _buildSessionCard(session)),

                      const SizedBox(height: 16),
                    ],
                  ),
                ),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildBottomBar() {
    final hasPending = _totalUnsynced > 0 || _isSyncing;

    final syncButton = SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.accentIndigo,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppTheme.accentIndigo.withValues(alpha: 0.5),
          disabledForegroundColor: Colors.white60,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
        onPressed: _isSyncing ? null : _syncAll,
        icon: _isSyncing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.cloud_upload_rounded, size: 20),
        label: Text(
          _isSyncing
              ? 'Syncing records to server...'
              : 'Sync All ($_totalUnsynced Pending)',
          style: const TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );

    final cleanButton = SizedBox(
      width: double.infinity,
      height: 46,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.textSecondary,
          backgroundColor: Colors.white.withValues(alpha: 0.03),
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.1),
            width: 1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        onPressed: _clearSyncedRecords,
        icon: Icon(
          Icons.cleaning_services_outlined,
          size: 18,
          color: AppTheme.textSecondary.withValues(alpha: 0.8),
        ),
        label: const Text(
          'Clean Up Synced Records',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.1,
          ),
        ),
      ),
    );

    final exportButton = SizedBox(
      width: double.infinity,
      height: 46,
      child: PopupMenuButton<bool>(
        tooltip: 'Export All Offline Data',
        color: AppTheme.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        offset: const Offset(0, -110),
        onSelected: (isExcel) => _downloadAllData(isExcel: isExcel),
        itemBuilder: (context) => [
          PopupMenuItem(
            value: true,
            child: Row(
              children: const [
                Icon(Icons.table_chart_rounded, color: AppTheme.eventxproSuccess, size: 18),
                SizedBox(width: 10),
                Text(
                  'Export All to Excel (.xlsx)',
                  style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          PopupMenuItem(
            value: false,
            child: Row(
              children: const [
                Icon(Icons.description_rounded, color: AppTheme.accentIndigo, size: 18),
                SizedBox(width: 10),
                Text(
                  'Export All to CSV (.csv)',
                  style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.1),
              width: 1,
            ),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isDownloading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.accentIndigo,
                  ),
                )
              else
                const Icon(
                  Icons.file_download_outlined,
                  color: AppTheme.accentIndigo,
                  size: 20,
                ),
              const SizedBox(width: 8),
              Text(
                _isDownloading
                    ? 'Exporting All Data...'
                    : (_totalScans > 0
                        ? 'Export All ($_totalScans Records)'
                        : 'Export All Records'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.background.withValues(alpha: 0.88),
            border: Border(
              top: BorderSide(
                color: Colors.white.withValues(alpha: 0.08),
                width: 1,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 16,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasPending) ...[
                    syncButton,
                    const SizedBox(height: 10),
                  ],
                  cleanButton,
                  const SizedBox(height: 10),
                  exportButton,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderStats() {
    return _buildGlassCard(
      borderRadius: BorderRadius.circular(18),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          // Total Offline Scans
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: AppTheme.accentIndigo,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'TOTAL OFFLINE SCANS',
                          style: TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '$_totalScans',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 42,
            width: 1,
            color: Colors.white.withValues(alpha: 0.08),
          ),
          // Pending Sync
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: _totalUnsynced > 0
                              ? AppTheme.accentOrange
                              : AppTheme.eventxproSuccess,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'PENDING SYNC',
                            style: TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        '$_totalUnsynced',
                        style: TextStyle(
                          color: _totalUnsynced > 0
                              ? AppTheme.accentOrange
                              : AppTheme.eventxproSuccess,
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: (_totalUnsynced > 0
                                      ? AppTheme.accentOrange
                                      : AppTheme.eventxproSuccess)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: (_totalUnsynced > 0
                                        ? AppTheme.accentOrange
                                        : AppTheme.eventxproSuccess)
                                    .withValues(alpha: 0.28),
                                width: 1,
                              ),
                            ),
                            child: Text(
                              _totalUnsynced > 0 ? 'Pending' : 'Synced',
                              style: TextStyle(
                                color: _totalUnsynced > 0
                                    ? AppTheme.accentOrange
                                    : AppTheme.eventxproSuccess,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionCard(_SessionConfig config) {
    final stats = _sectionSummary[config.key] ?? {
      'total': 0,
      'unsynced': 0,
      'checkin': 0,
      'checkout': 0,
    };
    final total = stats['total'] ?? 0;
    final unsynced = stats['unsynced'] ?? 0;
    final checkin = stats['checkin'] ?? 0;
    final checkout = stats['checkout'] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: _buildGlassCard(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            splashColor: AppTheme.accentIndigo.withValues(alpha: 0.08),
            highlightColor: AppTheme.accentIndigo.withValues(alpha: 0.04),
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => OfflineCheckInListScreen(
                    sessionKey: config.key,
                    sessionTitle: config.title,
                  ),
                ),
              );
              _loadSummary();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  // Uniform accentIndigo leading icon badge
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppTheme.accentIndigo.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppTheme.accentIndigo.withValues(alpha: 0.22),
                        width: 1,
                      ),
                    ),
                    child: Icon(
                      config.icon,
                      color: AppTheme.accentIndigo,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  // Title and clean structured metrics
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          config.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (total == 0)
                          const Text(
                            'No records yet',
                            style: TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w400,
                            ),
                          )
                        else
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Row(
                              children: [
                                Text(
                                  '$total ${total == 1 ? 'record' : 'records'}',
                                  style: const TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 6),
                                  child: Text(
                                    '•',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.2),
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                                Text(
                                  'In: $checkin',
                                  style: const TextStyle(
                                    color: AppTheme.textMuted,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 5),
                                  child: Text(
                                    '·',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.2),
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                                Text(
                                  'Out: $checkout',
                                  style: const TextStyle(
                                    color: AppTheme.textMuted,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Trailing pending status chip + chevron
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (unsynced > 0)
                        Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                          decoration: BoxDecoration(
                            color: AppTheme.accentOrange.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppTheme.accentOrange.withValues(alpha: 0.28),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 5,
                                height: 5,
                                decoration: const BoxDecoration(
                                  color: AppTheme.accentOrange,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                '$unsynced pending',
                                style: const TextStyle(
                                  color: AppTheme.accentOrange,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.white.withValues(alpha: 0.35),
                        size: 20,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SessionConfig {
  final String key;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accentColor;

  const _SessionConfig({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.accentColor = AppTheme.accentIndigo,
  });
}
