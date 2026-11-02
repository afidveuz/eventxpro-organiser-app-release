import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/datasources/lead_remote_datasource.dart';
import '../../../data/models/lead_model.dart';
import '../../../data/repositories/lead_repository.dart';
import '../../widgets/fade_in_background_image.dart';
import 'lead_capture_screen.dart';
import 'lead_details_screen.dart';
import 'widgets/lead_card.dart';

/// Screen listing all captured exhibitor/organizer leads with search,
/// Hot/Warm/Cold category filters, pagination, export to Excel, and direct navigation to capture.
class LeadsListScreen extends StatefulWidget {
  final int? eventId;
  final String? eventName;
  final bool isRootTab;
  final VoidCallback? onOpenScanLead;

  const LeadsListScreen({
    super.key,
    this.eventId,
    this.eventName,
    this.isRootTab = false,
    this.onOpenScanLead,
  });

  @override
  State<LeadsListScreen> createState() => _LeadsListScreenState();
}

class _LeadsListScreenState extends State<LeadsListScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _debounceTimer;

  List<LeadModel> _leads = [];
  int? _nextPage;
  int _totalCount = 0;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _isExporting = false;
  String? _errorMessage;

  String _selectedRatingFilter = 'ALL'; // 'ALL', 'HOT', 'WARM', 'COLD'

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _searchController.addListener(_onSearchChanged);
    _fetchLeads(page: 1, reset: true);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        !_isLoading &&
        _nextPage != null) {
      _fetchLeads(page: _nextPage!);
    }
  }

  void _onSearchChanged() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      _fetchLeads(page: 1, reset: true);
    });
  }

  Future<void> _fetchLeads({required int page, bool reset = false}) async {
    if (reset) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        if (page == 1) _leads.clear();
      });
    } else {
      setState(() {
        _isLoadingMore = true;
      });
    }

    try {
      final repository = context.read<LeadRepository>();
      final keyword = _searchController.text.trim();

      final LeadPaginatedResult result = await repository.getLeads(
        pageNo: page,
        count: 20,
        keyword: keyword,
        eventId: widget.eventId,
      );

      if (mounted) {
        setState(() {
          _nextPage = result.nextPage;
          _totalCount = result.totalCount;

          if (reset) {
            _leads = result.leads;
          } else {
            // Append only unique IDs
            final existingIds = _leads.map((e) => e.id).toSet();
            final newLeads = result.leads.where((e) => !existingIds.contains(e.id));
            _leads.addAll(newLeads);
          }

          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  Future<void> _exportLeads() async {
    if (_isExporting) return;
    setState(() => _isExporting = true);

    try {
      final repository = context.read<LeadRepository>();
      final path = await repository.exportLeadsAndShare(fallbackLeads: _leads);

      if (mounted) {
        if (path != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Lead report generated successfully'),
              backgroundColor: AppTheme.statusSuccess,
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No lead data available to export'),
              backgroundColor: AppTheme.statusWarning,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: AppTheme.statusRejected,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  Future<void> _openCaptureScreen() async {
    if (widget.onOpenScanLead != null) {
      widget.onOpenScanLead!();
      return;
    }
    final captured = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => LeadCaptureScreen(
          eventId: widget.eventId,
          eventName: widget.eventName,
        ),
      ),
    );

    if (captured == true && mounted) {
      _fetchLeads(page: 1, reset: true);
    }
  }

  Future<void> _openLeadDetails(LeadModel lead) async {
    final updated = await Navigator.push<LeadModel>(
      context,
      MaterialPageRoute(
        builder: (_) => LeadDetailsScreen(
          leadId: lead.id,
          initialLead: lead,
        ),
      ),
    );

    if (updated != null && mounted) {
      setState(() {
        final index = _leads.indexWhere((l) => l.id == updated.id);
        if (index != -1) {
          _leads[index] = updated;
        }
      });
    }
  }

  List<LeadModel> get _filteredLeads {
    if (_selectedRatingFilter == 'ALL') {
      return _leads;
    }
    return _leads
        .where((l) => l.leadType.toUpperCase() == _selectedRatingFilter)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: widget.isRootTab
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.textPrimary, size: 20),
                onPressed: () => Navigator.of(context).pop(),
              ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Leads Management',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (widget.eventName != null && widget.eventName!.isNotEmpty)
              Text(
                widget.eventName!,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        actions: [
          // Export Button
          IconButton(
            tooltip: 'Export to Excel',
            onPressed: _isExporting ? null : _exportLeads,
            icon: _isExporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(AppTheme.accentCyan),
                    ),
                  )
                : Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: AppTheme.surfaceElevated,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.file_download_outlined,
                      color: AppTheme.accentCyan,
                      size: 20,
                    ),
                  ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCaptureScreen,
        elevation: 6,
        backgroundColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        label: Ink(
          decoration: BoxDecoration(
            gradient: AppTheme.brandGradient,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: AppTheme.brandGradientStart.withValues(alpha: 0.4),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text(
                  'Capture Lead',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const AppBackgroundLayer(),
          Column(
            children: [
              // Search & Metrics Header
              _buildSearchAndFiltersHeader(),
              // Lead Cards List
              Expanded(
                child: _buildBody(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFiltersHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
      ),
      child: Column(
        children: [
          // Search Input Bar
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(14),
            ),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search by attendee name, email, company...',
                hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textSecondary, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, color: AppTheme.textSecondary, size: 18),
                        onPressed: () {
                          _searchController.clear();
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Filter Chips and Total Count
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('ALL', 'All Leads', null),
                      const SizedBox(width: 8),
                      _buildFilterChip('HOT', 'Hot', const Color(0xFFEF4444)),
                      const SizedBox(width: 8),
                      _buildFilterChip('WARM', 'Warm', const Color(0xFFF59E0B)),
                      const SizedBox(width: 8),
                      _buildFilterChip('COLD', 'Cold', const Color(0xFF3B82F6)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Total Count Indicator
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.accentIndigo.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.people_alt_outlined, color: AppTheme.accentCyan, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      '$_totalCount',
                      style: const TextStyle(
                        color: AppTheme.accentCyan,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String key, String label, Color? accentColor) {
    final isSelected = _selectedRatingFilter == key;
    final color = accentColor ?? AppTheme.accentIndigo;

    return InkWell(
      onTap: () {
        setState(() {
          _selectedRatingFilter = key;
        });
      },
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.2) : AppTheme.surfaceElevated,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (accentColor != null) ...[
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accentColor,
                ),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: isSelected ? (accentColor ?? Colors.white) : AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _leads.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(AppTheme.accentIndigo),
        ),
      );
    }

    if (_errorMessage != null && _leads.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 48, color: AppTheme.statusRejected),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _fetchLeads(page: 1, reset: true),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try Again'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentIndigo,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final displayList = _filteredLeads;

    if (displayList.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: AppTheme.surfaceElevated,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.badge_outlined, size: 48, color: AppTheme.textMuted),
              ),
              const SizedBox(height: 16),
              Text(
                _selectedRatingFilter == 'ALL'
                    ? 'No leads captured yet'
                    : 'No $_selectedRatingFilter leads found',
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Scan attendee QR codes to capture their details, classify prospect intent, and export.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _openCaptureScreen,
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: const Text('Scan Attendee Badge'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentIndigo,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _fetchLeads(page: 1, reset: true),
      color: AppTheme.accentIndigo,
      backgroundColor: AppTheme.surface,
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        itemCount: displayList.length + (_isLoadingMore ? 1 : 0),
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index >= displayList.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(AppTheme.accentIndigo),
                  ),
                ),
              ),
            );
          }

          final lead = displayList[index];
          return LeadCard(
            lead: lead,
            onTap: () => _openLeadDetails(lead),
          );
        },
      ),
    );
  }
}
