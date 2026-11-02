import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/attendee_list_item_model.dart';
import '../../../data/repositories/attendee_repository.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../widgets/fade_in_background_image.dart';
import 'attendee_details_screen.dart';

/// Screen listing attendees matching `EventAttendees.jsx` and `Attendees.jsx`.
/// Supports both:
/// 1. Metric-based event attendee lists (Total Registration, Unique Visits, No Shows, Today Visits, Check-in)
/// 2. Session/Gate attendee lists with live search and manual Check-In / Check-Out punch buttons.
class EventAttendeesScreen extends StatefulWidget {
  final int eventId;
  final String eventName;
  final String title;

  // Mode 1: Event metric endpoint (e.g. 'event-register-users', 'totalattendees-list', etc.)
  final String? endPoint;

  // Mode 2: Session/Gate attendance mode (calls 'attend-user-checkin-checkout-list')
  final bool isSessionMode;
  final String? pageType; // 'entrance' | 'hall' | 'agenda' | 'session_type'
  final String? actionType; // 'check_in' | 'check_out'
  final int? gateId;
  final String? sectionLocation;

  const EventAttendeesScreen({
    super.key,
    required this.eventId,
    required this.eventName,
    required this.title,
    this.endPoint,
    this.isSessionMode = false,
    this.pageType,
    this.actionType,
    this.gateId,
    this.sectionLocation,
  });

  @override
  State<EventAttendeesScreen> createState() => _EventAttendeesScreenState();
}

class _EventAttendeesScreenState extends State<EventAttendeesScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _searchDebounce;

  List<AttendeeListItemModel> _attendees = [];
  bool _isLoading = true;
  bool _isSearchLoading = false;
  bool _isLoadingMore = false;
  bool _hasNextPage = false;
  int _pageNo = 1;
  int _totalCount = 0;
  String _searchQuery = '';
  String? _errorMessage;

  // Active Filters
  String? _selectedBookingStatus; // 'confirmed', 'cancelled', 'pending'
  String? _selectedBadgeIssue; // '1' (Issued), '0' (Not Issued)
  DateTime? _selectedDate;

  // Punch in-progress state for specific attendee pk
  int? _punchingPk;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadAttendees(reset: true);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 250 &&
        !_isLoadingMore &&
        _hasNextPage &&
        !_isLoading) {
      _loadMoreAttendees();
    }
  }

  void _onSearchChanged(String val) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) {
        setState(() {
          _searchQuery = val.trim();
        });
        _loadAttendees(reset: true, isSearch: true);
      }
    });
  }

  String? _resolveImageUrl(String? path) {
    if (path == null || path.trim().isEmpty) return null;
    final clean = path.trim();
    if (clean.startsWith('http://') || clean.startsWith('https://')) return clean;

    try {
      final authRepo = context.read<AuthRepository>();
      final baseUrl = authRepo.mediaUrl;
      final cleanBase = baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl;
      final cleanPath = clean.startsWith('/') ? clean : '/$clean';
      return '$cleanBase$cleanPath';
    } catch (_) {
      return clean;
    }
  }

  Future<void> _loadAttendees({bool reset = false, bool isSearch = false}) async {
    if (reset) {
      _pageNo = 1;
      _hasNextPage = false;
      if (isSearch) {
        setState(() => _isSearchLoading = true);
      } else {
        setState(() {
          _isLoading = true;
          _errorMessage = null;
        });
      }
    }

    try {
      final repository = context.read<AttendeeRepository>();

      if (widget.isSessionMode) {
        // Mode 2: Gate / Session Attendees
        final result = await repository.getSessionAttendees(
          eventId: widget.eventId,
          pageType: widget.pageType ?? 'entrance',
          actionType: widget.actionType ?? 'check_in',
          pageNo: _pageNo,
          count: 20,
          keyword: _searchQuery,
          entranceId: widget.pageType == 'entrance' ? widget.gateId : null,
          hallId: widget.pageType == 'hall' ? widget.gateId : null,
          agendaId: widget.pageType == 'agenda' ? widget.gateId : null,
        );

        if (mounted) {
          setState(() {
            _attendees = reset ? result.attendees : [..._attendees, ...result.attendees];
            _hasNextPage = result.hasNextPage;
            _totalCount = result.totalCount;
            _isLoading = false;
            _isSearchLoading = false;
          });
        }
      } else {
        // Mode 1: Event Metrics List
        final filterObj = <String, dynamic>{
          if (_selectedBookingStatus != null)
            'booking_status': [_selectedBookingStatus],
          if (_selectedBadgeIssue != null)
            'badge_issue': [_selectedBadgeIssue],
          if (_selectedDate != null)
            'created_dt': '${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}',
        };

        final effectiveEndpoint = widget.endPoint ?? 'event-register-users';

        final result = await repository.getEventAttendees(
          eventId: widget.eventId,
          endPoint: effectiveEndpoint,
          pageNo: _pageNo,
          count: 20,
          keyword: _searchQuery,
          filterObj: filterObj.isNotEmpty ? filterObj : null,
        );

        if (mounted) {
          setState(() {
            _attendees = reset ? result.attendees : [..._attendees, ...result.attendees];
            _hasNextPage = result.hasNextPage;
            _totalCount = result.totalCount;
            _isLoading = false;
            _isSearchLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('[EventAttendeesScreen] Error loading attendees: $e');
      if (mounted) {
        setState(() {
          if (reset && _attendees.isEmpty) {
            _errorMessage = 'Could not load attendees. Please try again.';
          }
          _isLoading = false;
          _isSearchLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  Future<void> _loadMoreAttendees() async {
    if (_isLoadingMore || !_hasNextPage) return;
    setState(() => _isLoadingMore = true);
    _pageNo++;

    try {
      final repository = context.read<AttendeeRepository>();

      if (widget.isSessionMode) {
        final result = await repository.getSessionAttendees(
          eventId: widget.eventId,
          pageType: widget.pageType ?? 'entrance',
          actionType: widget.actionType ?? 'check_in',
          pageNo: _pageNo,
          count: 20,
          keyword: _searchQuery,
          entranceId: widget.pageType == 'entrance' ? widget.gateId : null,
          hallId: widget.pageType == 'hall' ? widget.gateId : null,
          agendaId: widget.pageType == 'agenda' ? widget.gateId : null,
        );

        if (mounted) {
          setState(() {
            _attendees.addAll(result.attendees);
            _hasNextPage = result.hasNextPage;
            _isLoadingMore = false;
          });
        }
      } else {
        final filterObj = <String, dynamic>{
          if (_selectedBookingStatus != null)
            'booking_status': [_selectedBookingStatus],
          if (_selectedBadgeIssue != null)
            'badge_issue': [_selectedBadgeIssue],
        };

        final effectiveEndpoint = widget.endPoint ?? 'event-register-users';

        final result = await repository.getEventAttendees(
          eventId: widget.eventId,
          endPoint: effectiveEndpoint,
          pageNo: _pageNo,
          count: 20,
          keyword: _searchQuery,
          filterObj: filterObj.isNotEmpty ? filterObj : null,
        );

        if (mounted) {
          setState(() {
            _attendees.addAll(result.attendees);
            _hasNextPage = result.hasNextPage;
            _isLoadingMore = false;
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  /// Manual Punch toggle (Check-In or Check-Out) from session list card
  Future<void> _punchAttendee(AttendeeListItemModel attendee) async {
    if (_punchingPk != null) return;
    setState(() => _punchingPk = attendee.pk);
    HapticFeedback.mediumImpact();

    final repository = context.read<AttendeeRepository>();
    final isCheckIn = (widget.actionType ?? 'check_in') == 'check_in';
    final type = isCheckIn ? 'check_in' : 'check_out';

    String endpoint = 'organizer/event-entrance';
    Map<String, dynamic> payload = {
      'event_id': widget.eventId,
      'type': type,
      'user_input': attendee.uniqueId ?? attendee.pk.toString(),
      'scan_type': 1,
      'user_latitude': 11.0,
      'user_longitude': 12.0,
      'user_city': '',
    };

    if (widget.pageType == 'hall') {
      endpoint = 'organizer/event-hall-entrance';
      payload['hall_id'] = widget.gateId ?? 0;
    } else if (widget.pageType == 'agenda') {
      endpoint = 'organizer/event-agenda-entrance';
      payload['agenda_id'] = widget.gateId ?? 0;
    } else if (widget.pageType == 'session_type') {
      endpoint = 'organizer/event-sessiontype-entrance';
      payload['sessiontype_id'] = widget.gateId ?? 0;
    } else {
      endpoint = 'organizer/event-entrance';
      if (widget.gateId != null && widget.gateId! > 0) {
        payload['entrance_id'] = widget.gateId;
      }
      if (widget.sectionLocation != null) {
        payload['location'] = widget.sectionLocation;
      }
    }

    final res = await repository.punchAttendee(
      endpoint: endpoint,
      payload: payload,
    );

    if (mounted) {
      setState(() => _punchingPk = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.message ?? (res.isSuccess ? 'Punch recorded' : 'Punch failed')),
          backgroundColor: res.isSuccess
              ? const Color(0xFF10B981)
              : const Color(0xFFEF4444),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _openAttendeeDetails(AttendeeListItemModel item) {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AttendeeDetailsScreen(
          attendeeId: item.pk,
          eventName: widget.eventName,
        ),
      ),
    );
  }

  void _openFilterDialog() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A202C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Filter Attendees',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setModalState(() {
                            _selectedBookingStatus = null;
                            _selectedBadgeIssue = null;
                            _selectedDate = null;
                          });
                        },
                        child: const Text('Reset', style: TextStyle(color: Color(0xFFF43F5E))),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Booking Status Filter
                  const Text(
                    'BOOKING STATUS',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: ['confirmed', 'cancelled', 'pending'].map((status) {
                      final isSelected = _selectedBookingStatus == status;
                      return ChoiceChip(
                        label: Text(status.toUpperCase()),
                        selected: isSelected,
                        onSelected: (val) {
                          setModalState(() {
                            _selectedBookingStatus = val ? status : null;
                          });
                        },
                        selectedColor: AppTheme.brandGradientStart,
                        backgroundColor: Colors.white.withValues(alpha: 0.08),
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  // Badge Issue Status
                  const Text(
                    'BADGE STATUS',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ('Issued', '1'),
                      ('Not Issued', '0'),
                    ].map((entry) {
                      final isSelected = _selectedBadgeIssue == entry.$2;
                      return ChoiceChip(
                        label: Text(entry.$1),
                        selected: isSelected,
                        onSelected: (val) {
                          setModalState(() {
                            _selectedBadgeIssue = val ? entry.$2 : null;
                          });
                        },
                        selectedColor: const Color(0xFF10B981),
                        backgroundColor: Colors.white.withValues(alpha: 0.08),
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),

                  // Apply Filter Button
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _loadAttendees(reset: true);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.brandGradientStart,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Apply Filters',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.eventxproBg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const AppBackgroundLayer(),

          SafeArea(
            child: Column(
              children: [
                // Top App Bar
                _buildTopBar(),

                // Search & Filter Row
                _buildSearchAndFilterRow(),

                // Total Count Card
                if (_totalCount > 0) _buildTotalCountCard(),

                // Attendee List Body
                Expanded(
                  child: RefreshIndicator(
                    color: AppTheme.eventxproAccent,
                    backgroundColor: AppTheme.surfaceElevated,
                    onRefresh: () => _loadAttendees(reset: true),
                    child: _isSearchLoading
                        ? _buildSearchLoadingState()
                        : _isLoading
                            ? _buildLoadingState()
                            : _errorMessage != null
                                ? _buildErrorState()
                                : _attendees.isEmpty
                                    ? _buildEmptyState()
                                    : _buildAttendeeList(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Top Bar ───────────────────────────────────────────────────────
  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.of(context).pop();
              },
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    size: 14,
                    color: Color(0xFF131722),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(
                      Icons.event_note_rounded,
                      size: 11,
                      color: AppTheme.brandGradientStart,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        widget.eventName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.65),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Search & Filter Row ──────────────────────────────────────────
  Widget _buildSearchAndFilterRow() {
    final hasActiveFilters = _selectedBookingStatus != null ||
        _selectedBadgeIssue != null ||
        _selectedDate != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          // Search Input
          Expanded(
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.16),
                  width: 1,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  const Icon(Icons.search_rounded, color: Colors.white70, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: _onSearchChanged,
                      style: const TextStyle(color: Colors.white, fontSize: 13.5),
                      cursorColor: AppTheme.brandGradientStart,
                      decoration: const InputDecoration(
                        hintText: 'Search attendee, ticket, URN...',
                        hintStyle: TextStyle(color: Colors.white54, fontSize: 13),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  if (_searchController.text.isNotEmpty)
                    InkWell(
                      onTap: () {
                        _searchController.clear();
                        _onSearchChanged('');
                      },
                      child: const Icon(Icons.clear_rounded, color: Colors.white70, size: 18),
                    ),
                ],
              ),
            ),
          ),

          // Filter Button (in event metric mode)
          if (!widget.isSessionMode) ...[
            const SizedBox(width: 10),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _openFilterDialog,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 44,
                  width: 44,
                  decoration: BoxDecoration(
                    color: hasActiveFilters
                        ? AppTheme.brandGradientStart.withValues(alpha: 0.25)
                        : Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: hasActiveFilters
                          ? AppTheme.brandGradientStart
                          : Colors.white.withValues(alpha: 0.16),
                      width: 1.2,
                    ),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        Icons.filter_list_rounded,
                        color: hasActiveFilters
                            ? AppTheme.brandGradientStart
                            : Colors.white70,
                        size: 20,
                      ),
                      if (hasActiveFilters)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              color: AppTheme.brandGradientStart,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Total Count Card ─────────────────────────────────────────────
  Widget _buildTotalCountCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.12),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.people_alt_rounded,
                  size: 16,
                  color: AppTheme.brandGradientStart,
                ),
                const SizedBox(width: 8),
                Text(
                  widget.isSessionMode ? 'Attendees Found' : 'Total Count',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.brandGradientStart.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppTheme.brandGradientStart.withValues(alpha: 0.5),
                ),
              ),
              child: Text(
                '$_totalCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Attendee List View ───────────────────────────────────────────
  Widget _buildAttendeeList() {
    return ListView.builder(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _attendees.length + (_hasNextPage ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _attendees.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                ),
              ),
            ),
          );
        }

        final attendee = _attendees[index];
        return _buildAttendeeCard(attendee);
      },
    );
  }

  Widget _buildAttendeeCard(AttendeeListItemModel item) {
    final photoUrl = _resolveImageUrl(item.photoUrl);
    final isPunching = _punchingPk == item.pk;
    final isCheckIn = (widget.actionType ?? 'check_in') == 'check_in';
    final authRepo = context.read<AuthRepository>();
    final isAdmin = authRepo.currentUser?.isAdmin == true;

    final hasDesignation = item.designation != null && item.designation!.trim().isNotEmpty;
    final hasCompany = item.companyName != null && item.companyName!.trim().isNotEmpty;
    final roleCompanyText = [
      if (hasDesignation) item.designation!.trim(),
      if (hasCompany) item.companyName!.trim(),
    ].join(' • ');

    final hasTicketName = item.ticketName != null && item.ticketName!.trim().isNotEmpty;
    final hasUrn = item.uniqueId != null && item.uniqueId!.trim().isNotEmpty;
    final hasCountry = item.country != null && item.country!.trim().isNotEmpty;
    final isCheckedIn = item.isCheckedIn == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1E2538),
            Color(0xFF131722),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.32),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openAttendeeDetails(item),
          onLongPress: hasUrn
              ? () {
                  Clipboard.setData(ClipboardData(text: item.uniqueId!));
                  HapticFeedback.lightImpact();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('URN copied: ${item.uniqueId}'),
                      duration: const Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              : null,
          borderRadius: BorderRadius.circular(16),
          splashColor: AppTheme.brandGradientStart.withValues(alpha: 0.1),
          highlightColor: Colors.white.withValues(alpha: 0.04),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── 1. Avatar with Fallback & Checked-In Indicator ────────
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: item.avatarColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: item.avatarColor.withValues(alpha: 0.45),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: item.avatarColor.withValues(alpha: 0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12.5),
                        child: photoUrl != null && photoUrl.isNotEmpty
                            ? Image.network(
                                photoUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    _buildAvatarFallback(item),
                              )
                            : _buildAvatarFallback(item),
                      ),
                    ),
                    if (isCheckedIn)
                      Positioned(
                        bottom: -2,
                        right: -2,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFF131722),
                              width: 2,
                            ),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.check_rounded,
                              size: 10,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 13),

                // ── 2. Information Column ──────────────────────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Full Name
                      Text(
                        item.fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 3),

                      // Ticket Name Pill / Category Badge
                      if (hasTicketName) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFC10067).withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: const Color(0xFFC10067).withValues(alpha: 0.35),
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.confirmation_number_outlined,
                                size: 10.5,
                                color: Color(0xFFFF4081),
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  item.ticketName!.toUpperCase(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFFFF6497),
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],

                      // Designation & Company Row
                      if (roleCompanyText.isNotEmpty) ...[
                        Row(
                          children: [
                            const Icon(
                              Icons.business_center_outlined,
                              size: 12,
                              color: Color(0xFF94A3B8),
                            ),
                            const SizedBox(width: 4.5),
                            Expanded(
                              child: Text(
                                roleCompanyText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontWeight: FontWeight.w500,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                      ],

                      // Chips Row: URN, Location, Checked-in Status
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (hasUrn)
                            InkWell(
                              onTap: () {
                                Clipboard.setData(ClipboardData(text: item.uniqueId!));
                                HapticFeedback.lightImpact();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('URN copied: ${item.uniqueId}'),
                                    duration: const Duration(seconds: 1),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              },
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6.5,
                                  vertical: 2.5,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: const Color(0xFF3B82F6).withValues(alpha: 0.28),
                                    width: 0.8,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.fingerprint_rounded,
                                      size: 11,
                                      color: Color(0xFF60A5FA),
                                    ),
                                    const SizedBox(width: 3.5),
                                    Text(
                                      item.uniqueId!,
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        color: Color(0xFF93C5FD),
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          if (hasCountry)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2.5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  width: 0.8,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.location_on_outlined,
                                    size: 10.5,
                                    color: Color(0xFF94A3B8),
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    item.country!,
                                    style: const TextStyle(
                                      color: Color(0xFFCBD5E1),
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (isCheckedIn)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2.5,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.35),
                                  width: 0.8,
                                ),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.check_circle_rounded,
                                    size: 10.5,
                                    color: Color(0xFF34D399),
                                  ),
                                  SizedBox(width: 3),
                                  Text(
                                    'Checked In',
                                    style: TextStyle(
                                      color: Color(0xFF6EE7B7),
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),

                // ── 3. Right Rail: Session Punch Button or Chevron + Admin OTP ──
                if (widget.isSessionMode) ...[
                  isPunching
                      ? const SizedBox(
                          width: 32,
                          height: 32,
                          child: Padding(
                            padding: EdgeInsets.all(6),
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                            ),
                          ),
                        )
                      : Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: isCheckIn
                                  ? [const Color(0xFF10B981), const Color(0xFF059669)]
                                  : [const Color(0xFFF43F5E), const Color(0xFFE11D48)],
                            ),
                            borderRadius: BorderRadius.circular(9),
                            boxShadow: [
                              BoxShadow(
                                color: (isCheckIn
                                        ? const Color(0xFF10B981)
                                        : const Color(0xFFF43F5E))
                                    .withValues(alpha: 0.3),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => _punchAttendee(item),
                              borderRadius: BorderRadius.circular(9),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 7,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isCheckIn
                                          ? Icons.login_rounded
                                          : Icons.logout_rounded,
                                      size: 12,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      isCheckIn ? 'IN' : 'OUT',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 11.5,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                ] else ...[
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Circular Chevron
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08),
                            width: 1,
                          ),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.arrow_forward_ios_rounded,
                            color: Colors.white70,
                            size: 11,
                          ),
                        ),
                      ),

                      // Admin OTP Action Button
                      if (isAdmin && item.uid != null && item.uid!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => _showOtpDialog(item),
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF59E0B).withValues(alpha: 0.14),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
                                  width: 1,
                                ),
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.key_rounded,
                                  color: Color(0xFFFBBF24),
                                  size: 14,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarFallback(AttendeeListItemModel item) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            item.avatarColor,
            item.avatarColor.withValues(alpha: 0.75),
          ],
        ),
      ),
      child: Center(
        child: Text(
          item.initials,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 18,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  /// Admin dialog to view and copy Attendee Registration OTP matching React Native
  Future<void> _showOtpDialog(AttendeeListItemModel item) async {
    if (item.uid == null || item.uid!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Missing user identifier for OTP lookup'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    HapticFeedback.lightImpact();

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return FutureBuilder<Map<String, dynamic>?>(
          future: context.read<AttendeeRepository>().getAttendeeOtp(uid: item.uid!),
          builder: (context, snapshot) {
            final isLoading = snapshot.connectionState == ConnectionState.waiting;
            final data = snapshot.data;
            final isSuccess = data != null && data['status'] == true;
            final email = data?['email']?.toString() ?? item.email ?? '';
            final otp = data?['otp']?.toString() ?? '';
            final message = data?['message']?.toString() ?? 'Unable to retrieve OTP.';

            return Dialog(
              backgroundColor: const Color(0xFF131722),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: Colors.white.withValues(alpha: 0.12),
                  width: 1,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF59E0B).withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.key_rounded,
                                color: Color(0xFFF59E0B),
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              'Access OTP',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: Colors.white60, size: 20),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => Navigator.of(dialogCtx).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (isLoading) ...[
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFF59E0B)),
                          ),
                        ),
                      ),
                    ] else if (!isSuccess || otp.isEmpty) ...[
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFF87171),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ] else ...[
                      if (email.isNotEmpty) ...[
                        const Text(
                          'EMAIL',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          email,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      const Text(
                        'REGISTRATION OTP',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              otp,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                color: Color(0xFFFBBF24),
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 4,
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: otp));
                                HapticFeedback.lightImpact();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('OTP copied to clipboard!'),
                                    duration: Duration(seconds: 1),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              },
                              icon: const Icon(Icons.copy_rounded, size: 14),
                              label: const Text('Copy'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFC10067),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.person_search_rounded,
              size: 56,
              color: Colors.white.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 14),
            const Text(
              'No Attendees Found',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No results matched "$_searchQuery"'
                  : 'There are currently no attendees listed under this category.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchLoadingState() {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: 5,
      itemBuilder: (context, index) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF131722),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.05),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 140,
                    height: 14,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 90,
                    height: 11,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 180,
                    height: 11,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 30,
            height: 30,
            child: CircularProgressIndicator(
              strokeWidth: 2.8,
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.eventxproAccent),
            ),
          ),
          SizedBox(height: 14),
          Text(
            'Loading Attendees...',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: Color(0xFFF87171),
              size: 40,
            ),
            const SizedBox(height: 12),
            Text(
              _errorMessage ?? 'Failed to load attendees',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _loadAttendees(reset: true),
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.brandGradientStart,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
