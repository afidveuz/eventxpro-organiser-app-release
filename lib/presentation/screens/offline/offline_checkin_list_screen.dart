import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/datasources/offline_database_helper.dart';
import '../../../data/models/checkin_record.dart';
import '../../bloc/scanner_bloc.dart';
import '../../bloc/scanner_event.dart';

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
      context.read<ScannerBloc>().add(const ScannerSyncOfflineRequested());
      await Future.delayed(const Duration(milliseconds: 1500));
      await _loadRecords();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Synchronization completed for ${widget.sessionTitle}.'),
                ),
              ],
            ),
            backgroundColor: AppTheme.statusSuccess,
            behavior: SnackBarBehavior.floating,
          ),
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
      backgroundColor: AppTheme.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.eventxproAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.qr_code_2_rounded, color: AppTheme.eventxproAccent, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Offline Check-in #${record.id ?? '-'}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Session: ${widget.sessionTitle}',
                            style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    onPressed: () => Navigator.of(sheetCtx).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Divider(color: AppTheme.surfaceBorder, height: 1),
              const SizedBox(height: 16),

              // Encrypted Code Section (matches eventxproorganiser)
              _buildDetailInfoTile(
                title: 'ENCRYPTED CODE',
                value: displayCode,
                icon: Icons.qr_code_2_rounded,
                accentColor: AppTheme.eventxproAccent,
              ),

              const SizedBox(height: 16),

              // Metadata grid
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF131722),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.surfaceBorder),
                ),
                child: Column(
                  children: [
                    _buildMetaRow('Punch Action', isCheckIn ? 'Check-In' : 'Check-Out', isCheckIn ? AppTheme.eventxproSuccess : const Color(0xFFFF6767)),
                    const SizedBox(height: 8),
                    _buildMetaRow('Gate / Entrance', 'Gate #${record.entranceId} (${record.entranceLocation.isNotEmpty ? record.entranceLocation : widget.sessionTitle})', Colors.white),
                    const SizedBox(height: 8),
                    _buildMetaRow('Timestamp', formattedDate, Colors.white70),
                    const SizedBox(height: 8),
                    _buildMetaRow('Server Sync Status', record.isSynced ? 'Synced to Server' : 'Local SQLite Pending', record.isSynced ? AppTheme.eventxproSuccess : AppTheme.accentOrange),
                    const SizedBox(height: 8),
                    _buildMetaRow('Registration Status', record.isNotExist ? 'Unregistered' : 'Registered', record.isNotExist ? const Color(0xFFFF6767) : AppTheme.eventxproSuccess),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Close button
              SizedBox(
                width: double.infinity,
                height: 46,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: AppTheme.surfaceBorder),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.of(sheetCtx).pop(),
                  child: const Text('Close', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
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
        color: const Color(0xFF131722),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accentColor.withValues(alpha: 0.35)),
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
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SelectableText(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaRow(String label, String value, Color valueColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
        Text(
          value,
          style: TextStyle(color: valueColor, fontSize: 12, fontWeight: FontWeight.w600),
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
            Text(
              '${widget.sessionTitle} Check-ins',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Text(
              'Offline Records',
              style: TextStyle(
                color: AppTheme.eventxproAccent,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
        actions: [
          _buildSyncButton(),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(color: AppTheme.surfaceBorder, height: 1),
        ),
      ),
      body: Column(
        children: [
          // ── Search Bar ────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: AppTheme.surface,
            child: Container(
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFF131722),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.surfaceBorder),
              ),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.white, fontSize: 13.5),
                decoration: InputDecoration(
                  hintText: 'Search code, gate, record #...',
                  hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 12.5),
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
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onChanged: (val) {
                  setState(() => _searchQuery = val);
                },
              ),
            ),
          ),

          // ── Filter Chips Bar ──────────────────────────────────────────
          _buildFilterBar(),

          // ── Check-in Records List ─────────────────────────────────────
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.eventxproAccent))
                : filtered.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _loadRecords,
                        color: AppTheme.eventxproAccent,
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
    );
  }

  Widget _buildSyncButton() {
    final hasPending = _unsyncedCount > 0;

    return Padding(
      padding: const EdgeInsets.only(right: 14, top: 9, bottom: 9),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isSyncing ? null : _syncSection,
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            decoration: BoxDecoration(
              color: _isSyncing
                  ? AppTheme.eventxproAccent.withValues(alpha: 0.25)
                  : (hasPending
                      ? AppTheme.eventxproAccent
                      : const Color(0xFF131722)),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _isSyncing
                    ? AppTheme.eventxproAccent
                    : (hasPending
                        ? AppTheme.eventxproAccent
                        : AppTheme.surfaceBorder),
                width: 1.0,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isSyncing)
                  const SizedBox(
                    width: 13,
                    height: 13,
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
                    size: 15,
                    color: hasPending ? Colors.white : AppTheme.eventxproSuccess,
                  ),
                const SizedBox(width: 6),
                Text(
                  _isSyncing
                      ? 'Syncing...'
                      : (hasPending ? 'Sync ($_unsyncedCount)' : 'Synced'),
                  style: TextStyle(
                    color: hasPending || _isSyncing
                        ? Colors.white
                        : AppTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.surfaceBorder, width: 1)),
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
    return GestureDetector(
      onTap: () {
        if (_selectedFilter != key) {
          setState(() {
            _selectedFilter = key;
          });
          _loadRecords();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.eventxproAccent : AppTheme.surfaceElevated,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppTheme.eventxproAccent : AppTheme.surfaceBorder,
          ),
        ),
        child: Text(
          '$label ($count)',
          style: TextStyle(
            color: isSelected ? Colors.white : AppTheme.textSecondary,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
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

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showRecordDetails(record),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.surfaceElevated,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSynced
                  ? AppTheme.surfaceBorder
                  : AppTheme.accentOrange.withValues(alpha: 0.4),
              width: isSynced ? 1.0 : 1.2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: ID, Action Type Badge, and Sync Status
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppTheme.surfaceBorder),
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
                              ? AppTheme.eventxproSuccess.withValues(alpha: 0.15)
                              : const Color(0xFFFF6767).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isCheckIn
                                ? AppTheme.eventxproSuccess.withValues(alpha: 0.4)
                                : const Color(0xFFFF6767).withValues(alpha: 0.4),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          isCheckIn ? 'Check-in' : 'Check-out',
                          style: TextStyle(
                            color: isCheckIn ? AppTheme.eventxproSuccess : const Color(0xFFFF6767),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Right side: Registration status & Sync status pills
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: record.isNotExist
                              ? const Color(0xFFFF6767).withValues(alpha: 0.15)
                              : const Color(0xFF00D2B4).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: record.isNotExist
                                ? const Color(0xFFFF6767).withValues(alpha: 0.5)
                                : const Color(0xFF00D2B4).withValues(alpha: 0.5),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          record.isNotExist ? 'Unregistered' : 'Registered',
                          style: TextStyle(
                            color: record.isNotExist
                                ? const Color(0xFFFF6767)
                                : const Color(0xFF00D2B4),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isSynced
                              ? AppTheme.eventxproSuccess.withValues(alpha: 0.15)
                              : AppTheme.accentOrange.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSynced ? AppTheme.eventxproSuccess : AppTheme.accentOrange,
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isSynced ? Icons.check_circle_outline_rounded : Icons.schedule_rounded,
                              size: 12,
                              color: isSynced ? AppTheme.eventxproSuccess : AppTheme.accentOrange,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isSynced ? 'Synced' : 'Pending',
                              style: TextStyle(
                                color: isSynced ? AppTheme.eventxproSuccess : AppTheme.accentOrange,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Row 2: Encrypted Code Box (matches eventxproorganiser)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF131722),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.eventxproAccent.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.qr_code_2_rounded, color: AppTheme.eventxproAccent, size: 14),
                    const SizedBox(width: 6),
                    const Text(
                      'ENCRYPTED CODE: ',
                      style: TextStyle(
                        color: AppTheme.eventxproAccent,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.6,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        displayCode,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
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
                  Row(
                    children: [
                      const Icon(Icons.meeting_room_outlined, size: 13, color: AppTheme.textMuted),
                      const SizedBox(width: 4),
                      Text(
                        'Gate #${record.entranceId} (${record.entranceLocation.isNotEmpty ? record.entranceLocation : widget.sessionTitle})',
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                  Row(
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
          Icon(
            Icons.qr_code_2_rounded,
            size: 56,
            color: AppTheme.textMuted.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 12),
          Text(
            _searchQuery.isNotEmpty
                ? 'No check-ins match "$_searchQuery"'
                : 'No ${filterLabel.toLowerCase()}check-ins found',
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Scanned ticket codes will appear here in real-time',
            style: TextStyle(
              color: AppTheme.textMuted,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
