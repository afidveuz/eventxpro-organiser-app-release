import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/services/offline_export_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/datasources/offline_database_helper.dart';
import '../../bloc/scanner_bloc.dart';
import '../../bloc/scanner_event.dart';
import 'offline_checkin_list_screen.dart';

/// Offline Sessions screen matching `OfflineSection.jsx` in the React Native EventXPro app.
/// Lists sessions: Entrances, Halls, Agendas, and Sessions.
/// Allows syncing all pending records and viewing check-in tables per session.
class OfflineSessionsScreen extends StatefulWidget {
  const OfflineSessionsScreen({super.key});

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
      accentColor: AppTheme.accentCyan,
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
      accentColor: Color(0xFF9D65FF),
    ),
    _SessionConfig(
      key: 'session',
      title: 'Sessions',
      subtitle: 'Track-specific and breakout session check-ins',
      icon: Icons.co_present_outlined,
      accentColor: Color(0xFFFF8B3D),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Offline synchronization completed.'),
          backgroundColor: AppTheme.statusSuccess,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _clearSyncedRecords() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.surfaceBorder),
        ),
        title: const Text(
          'Clean Up Synced Records',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'This will delete all records that have already been synchronized with the server to free up local storage. Unsynced records will remain intact.',
          style: TextStyle(color: AppTheme.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.eventxproAccent,
              foregroundColor: Colors.white,
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cleared $deleted synced records from local database.'),
            backgroundColor: AppTheme.statusSuccess,
            behavior: SnackBarBehavior.floating,
          ),
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No offline data available to export.'),
            backgroundColor: AppTheme.statusWarning,
            behavior: SnackBarBehavior.floating,
          ),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Exported ${result.recordCount} records successfully!\nSaved at: $savedAt',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            backgroundColor: AppTheme.eventxproSuccessDark,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    result.errorMessage ?? 'Export failed.',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            backgroundColor: AppTheme.statusRejected,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isExcel ? 'Failed to export Excel file.' : 'Failed to export CSV file.',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            backgroundColor: AppTheme.statusRejected,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Offline Sessions',
              style: TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '$_totalScans records • $_totalUnsynced pending sync',
              style: const TextStyle(
                color: AppTheme.eventxproAccent,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        actions: [
          if (_totalScans > 0)
            PopupMenuButton<bool>(
              tooltip: 'Export all offline data',
              icon: _isDownloading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.eventxproAccent,
                      ),
                    )
                  : const Icon(Icons.download_rounded, color: AppTheme.eventxproAccent),
              color: AppTheme.surfaceElevated,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppTheme.surfaceBorder),
              ),
              onSelected: (isExcel) => _downloadAllData(isExcel: isExcel),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: true,
                  child: Row(
                    children: const [
                      Icon(Icons.table_chart_rounded, color: AppTheme.eventxproSuccess, size: 18),
                      SizedBox(width: 10),
                      Text('Export All to Excel (.xlsx)', style: TextStyle(color: Colors.white, fontSize: 13)),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: false,
                  child: Row(
                    children: const [
                      Icon(Icons.description_rounded, color: AppTheme.accentCyan, size: 18),
                      SizedBox(width: 10),
                      Text('Export All to CSV (.csv)', style: TextStyle(color: Colors.white, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          IconButton(
            tooltip: 'Refresh summary',
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: _loadSummary,
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(color: AppTheme.surfaceBorder, height: 1),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.eventxproAccent))
          : RefreshIndicator(
              onRefresh: _loadSummary,
              color: AppTheme.eventxproAccent,
              backgroundColor: AppTheme.surfaceElevated,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                children: [
                  // ── Top Stats Banner ──────────────────────────────────
                  _buildHeaderStats(),

                  const SizedBox(height: 20),

                  // ── SESSIONS Header ───────────────────────────────────
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Text(
                      'SESSION CATEGORIES',
                      style: TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // ── Session Cards ─────────────────────────────────────
                  ..._sessions.map((session) => _buildSessionCard(session)),

                  const SizedBox(height: 16),
                ],
              ),
            ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget? _buildBottomBar() {
    final hasPending = _totalUnsynced > 0 || _isSyncing;
    final hasSyncedToClean = _totalScans > _totalUnsynced;
    final hasOfflineData = _totalScans > 0;

    if (!hasPending && !hasSyncedToClean && !hasOfflineData) return null;

    final syncButton = SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.eventxproAccent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppTheme.eventxproAccent.withValues(alpha: 0.6),
          disabledForegroundColor: Colors.white70,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
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
            : const Icon(Icons.cloud_upload_rounded),
        label: Text(
          _isSyncing
              ? 'Syncing records to server...'
              : 'Sync All ($_totalUnsynced Pending)',
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );

    final cleanButton = SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.textSecondary,
          side: const BorderSide(color: AppTheme.surfaceBorder),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed: _clearSyncedRecords,
        icon: const Icon(Icons.cleaning_services_outlined, size: 18),
        label: const Text(
          'Clean Up Synced Records',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
    );

    final exportButton = SizedBox(
      width: double.infinity,
      height: 48,
      child: PopupMenuButton<bool>(
        tooltip: 'Export All Offline Data',
        color: AppTheme.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppTheme.surfaceBorder),
        ),
        onSelected: (isExcel) => _downloadAllData(isExcel: isExcel),
        itemBuilder: (context) => [
          PopupMenuItem(
            value: true,
            child: Row(
              children: const [
                Icon(Icons.table_chart_rounded, color: AppTheme.eventxproSuccess, size: 18),
                SizedBox(width: 10),
                Text('Export All (Excel .xlsx)', style: TextStyle(color: Colors.white, fontSize: 13)),
              ],
            ),
          ),
          PopupMenuItem(
            value: false,
            child: Row(
              children: const [
                Icon(Icons.description_rounded, color: AppTheme.accentCyan, size: 18),
                SizedBox(width: 10),
                Text('Export All (CSV .csv)', style: TextStyle(color: Colors.white, fontSize: 13)),
              ],
            ),
          ),
        ],
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF131722),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.surfaceBorder),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isDownloading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.eventxproAccent),
                )
              else
                const Icon(Icons.download_rounded, color: AppTheme.eventxproAccent, size: 20),
              const SizedBox(width: 8),
              Text(
                _isDownloading ? 'Exporting All Data...' : 'Export All ($_totalScans Records)',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: const Border(
          top: BorderSide(color: AppTheme.surfaceBorder, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasPending) syncButton,
              if (hasPending && (hasSyncedToClean || hasOfflineData)) const SizedBox(height: 8),
              if (hasSyncedToClean) cleanButton,
              if (hasSyncedToClean && hasOfflineData) const SizedBox(height: 8),
              if (hasOfflineData) exportButton,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderStats() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.surfaceBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Total Offline Scans',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  '$_totalScans',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Container(height: 38, width: 1, color: AppTheme.surfaceBorder),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Pending Sync',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$_totalUnsynced',
                    style: TextStyle(
                      color: _totalUnsynced > 0 ? AppTheme.accentOrange : AppTheme.eventxproSuccess,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
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
    final stats = _sectionSummary[config.key] ?? {'total': 0, 'unsynced': 0};
    final total = stats['total'] ?? 0;
    final unsynced = stats['unsynced'] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.surfaceBorder),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: config.accentColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(config.icon, color: config.accentColor, size: 24),
        ),
        title: Text(
          config.title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Total: $total (In: ${stats['checkin'] ?? 0} • Out: ${stats['checkout'] ?? 0}) • $unsynced unsynced',
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
            ),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (unsynced > 0)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.accentOrange.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.accentOrange),
                ),
                child: Text(
                  '$unsynced pending',
                  style: const TextStyle(
                    color: AppTheme.accentOrange,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              color: AppTheme.textMuted,
              size: 16,
            ),
          ],
        ),
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
    required this.accentColor,
  });
}
