import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/services/gate_count_service.dart';
import '../../core/theme/app_theme.dart';

/// Mixin that enables viewport-based on-demand lazy loading for punch cards.
/// Instead of fetching counts immediately on widget mount (which causes 20+ parallel requests),
/// the card checks if it is within or near the visible scroll viewport (with prefetch buffer).
/// If off-screen, it subscribes to the enclosing ScrollPosition and loads only when scrolled near.
mixin LazyCountLoaderMixin<T extends StatefulWidget> on State<T> {
  ScrollPosition? _scrollPosition;
  bool _hasLoaded = false;
  bool _isLoading = false;
  bool _needsForceRefresh = false;
  bool _isActive = false;
  bool _isPostFrameScheduled = false;

  bool get isLoading => _isLoading;
  bool get hasLoaded => _hasLoaded;

  /// Abstract method implemented by punch cards to execute count retrieval
  Future<void> performLoadCount({bool forceRefresh = false});

  @override
  void initState() {
    super.initState();
    _isActive = true;
    // Schedule visibility check on next frame after layout completes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isActive && mounted) {
        checkVisibilityAndTrigger();
      }
    });
  }

  @override
  void activate() {
    super.activate();
    _isActive = true;
    if (!_hasLoaded && !_isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_isActive && mounted) {
          checkVisibilityAndTrigger();
        }
      });
    }
  }

  @override
  void deactivate() {
    _isActive = false;
    _unsubscribeFromScroll();
    super.deactivate();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isActive && !_hasLoaded && !_isLoading) {
      _updateScrollSubscription();
    }
  }

  /// Determines if the widget's RenderBox is within the visible viewport (+ prefetch buffer)
  bool isInViewport({double margin = 100.0}) {
    if (!_isActive || !mounted) return false;

    try {
      final renderObject = context.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize || !renderObject.attached) {
        return false;
      }

      final offset = renderObject.localToGlobal(Offset.zero);
      final top = offset.dy;
      final bottom = top + renderObject.size.height;
      final viewportHeight = _scrollPosition?.viewportDimension ?? 900.0;

      return bottom >= -margin && top <= viewportHeight + margin;
    } catch (_) {
      return false;
    }
  }

  void checkVisibilityAndTrigger({bool forceRefresh = false}) {
    if (!_isActive || !mounted) return;
    if ((_hasLoaded && !forceRefresh) || _isLoading) return;

    if (isInViewport()) {
      _unsubscribeFromScroll();
      _executeLoad(forceRefresh: forceRefresh);
    } else {
      _subscribeToScroll(forceRefresh: forceRefresh);
    }
  }

  void notifyConfigOrTriggerChanged({bool forceRefresh = false}) {
    _hasLoaded = false;
    if (forceRefresh) {
      _needsForceRefresh = true;
    }
    if (!_isActive || !mounted) return;

    if (!_isPostFrameScheduled) {
      _isPostFrameScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _isPostFrameScheduled = false;
        if (!_isActive || !mounted) return;
        final force = _needsForceRefresh;
        _needsForceRefresh = false;
        if (isInViewport()) {
          _unsubscribeFromScroll();
          _executeLoad(forceRefresh: force);
        } else {
          _subscribeToScroll(forceRefresh: force);
        }
      });
    }
  }

  void manualReload() {
    if (!_isActive || !mounted) return;
    _unsubscribeFromScroll();
    _executeLoad(forceRefresh: true);
  }

  void _executeLoad({bool forceRefresh = false}) {
    if (_isLoading || !_isActive || !mounted) return;
    setState(() => _isLoading = true);
    _hasLoaded = true;

    performLoadCount(forceRefresh: forceRefresh).whenComplete(() {
      if (_isActive && mounted) {
        setState(() => _isLoading = false);
      }
    });
  }

  void _updateScrollSubscription() {
    if (!_isActive || !mounted) return;
    try {
      final scrollable = Scrollable.maybeOf(context);
      if (scrollable == null) return;
      final currentPos = scrollable.position;
      if (_scrollPosition != currentPos) {
        _unsubscribeFromScroll();
        _scrollPosition = currentPos;
        _scrollPosition?.addListener(_handleScroll);
      }
    } catch (_) {}
  }

  void _subscribeToScroll({bool forceRefresh = false}) {
    if (!_isActive || !mounted) return;

    if (forceRefresh) {
      _needsForceRefresh = true;
    }

    try {
      final scrollable = Scrollable.maybeOf(context);
      if (scrollable == null) {
        _executeLoad(forceRefresh: forceRefresh);
        return;
      }

      final currentPos = scrollable.position;
      if (_scrollPosition != currentPos) {
        _unsubscribeFromScroll();
        _scrollPosition = currentPos;
        _scrollPosition?.addListener(_handleScroll);
      }
    } catch (_) {}
  }

  void _handleScroll() {
    if (!_isActive || !mounted) {
      _unsubscribeFromScroll();
      return;
    }

    if (_hasLoaded && !_needsForceRefresh) {
      _unsubscribeFromScroll();
      return;
    }

    if (isInViewport()) {
      final force = _needsForceRefresh;
      _unsubscribeFromScroll();
      _executeLoad(forceRefresh: force);
    }
  }

  void _unsubscribeFromScroll() {
    _scrollPosition?.removeListener(_handleScroll);
    _scrollPosition = null;
    _needsForceRefresh = false;
  }

  @override
  void dispose() {
    _isActive = false;
    _unsubscribeFromScroll();
    super.dispose();
  }
}

/// Reusable Check-in & Check-out card for Entrances, Halls, and Sessions.
/// Replicates React Native EventSections.jsx & SessionInOutCard.jsx with separate check-in and check-out counts.
class SessionPunchCard extends StatefulWidget {
  final int eventId;
  final String eventName;
  final int sessionId;
  final String title;
  final String section;
  final String sectionLocation;
  final bool hasInAccess;
  final bool hasOutAccess;
  final int refreshTrigger;
  final int serverRefreshTrigger;
  final VoidCallback onCheckIn;
  final VoidCallback onCheckOut;

  const SessionPunchCard({
    super.key,
    required this.eventId,
    required this.eventName,
    required this.sessionId,
    required this.title,
    required this.section,
    required this.sectionLocation,
    required this.hasInAccess,
    required this.hasOutAccess,
    this.refreshTrigger = 0,
    this.serverRefreshTrigger = 0,
    required this.onCheckIn,
    required this.onCheckOut,
  });

  @override
  State<SessionPunchCard> createState() => _SessionPunchCardState();
}

class _SessionPunchCardState extends State<SessionPunchCard>
    with LazyCountLoaderMixin<SessionPunchCard> {
  GateCheckInOutCount _count = const GateCheckInOutCount();
  GateCountService? _gateCountService;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _gateCountService ??= context.read<GateCountService>();
    if (_count == const GateCheckInOutCount()) {
      final cached = _gateCountService?.getCached(
        widget.eventId,
        widget.section,
        widget.sessionId,
        widget.sectionLocation,
      );
      if (cached != null) {
        _count = cached;
      }
    }
  }

  @override
  void didUpdateWidget(covariant SessionPunchCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool configChanged = oldWidget.sessionId != widget.sessionId ||
        oldWidget.eventId != widget.eventId ||
        oldWidget.section != widget.section;
    final bool serverTriggerChanged =
        oldWidget.serverRefreshTrigger != widget.serverRefreshTrigger;
    final bool localTriggerChanged =
        oldWidget.refreshTrigger != widget.refreshTrigger;

    if (configChanged || serverTriggerChanged) {
      notifyConfigOrTriggerChanged(forceRefresh: true);
    } else if (localTriggerChanged) {
      // Local sync only: zero network requests
      _syncFromLocalCache();
    }
  }

  void _syncFromLocalCache() {
    final service = _gateCountService ?? (mounted ? context.read<GateCountService>() : null);
    if (service == null) return;

    final cached = service.getCached(
      widget.eventId,
      widget.section,
      widget.sessionId,
      widget.sectionLocation,
    );
    if (cached != null) {
      if (cached != _count && mounted) {
        setState(() => _count = cached);
      }
    } else {
      service.getLocalCountOnly(
        eventId: widget.eventId,
        section: widget.section,
        actionId: widget.sessionId,
        location: widget.sectionLocation,
      ).then((local) {
        if (mounted && local != _count) {
          setState(() => _count = local);
        }
      });
    }
  }

  @override
  Future<void> performLoadCount({bool forceRefresh = false}) async {
    final service = _gateCountService ?? (mounted ? context.read<GateCountService>() : null);
    if (service == null) return;

    final cached = service.getCached(
      widget.eventId,
      widget.section,
      widget.sessionId,
      widget.sectionLocation,
    );
    if (cached != null && mounted) {
      setState(() => _count = cached);
    }

    try {
      final fresh = await service.getCounts(
        eventId: widget.eventId,
        section: widget.section,
        actionId: widget.sessionId,
        location: widget.sectionLocation,
        forceRefresh: forceRefresh,
      );

      if (mounted) {
        setState(() {
          _count = fresh;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF181F2E).withValues(alpha: 0.70),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Session / Gate Title Row
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: AppTheme.accentCyan,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.title.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Check-in & Check-out Buttons Row (Matching OfflineEventSection.jsx)
          Row(
            children: [
              // CHECK-IN BUTTON
              if (widget.hasInAccess)
                Expanded(
                  child: _PunchButton(
                    label: 'CHECK-IN',
                    badgeColor: AppTheme.eventxproSuccess, // #8DFFBB
                    arrowColor: Colors.black,
                    onTap: widget.onCheckIn,
                  ),
                ),

              if (widget.hasInAccess && widget.hasOutAccess)
                const SizedBox(width: 10),

              // CHECK-OUT BUTTON
              if (widget.hasOutAccess)
                Expanded(
                  child: _PunchButton(
                    label: 'CHECK-OUT',
                    badgeColor: AppTheme.eventxproDanger, // #FF6767
                    arrowColor: Colors.white,
                    onTap: widget.onCheckOut,
                  ),
                ),
            ],
          ),

          // Total Check-In & Check-Out counts row
          // Matching React Native EventSections.jsx & SessionInOutCard.jsx styles.timeWrapper
          if (widget.hasInAccess || widget.hasOutAccess) ...[
            const SizedBox(height: 10),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.lightImpact();
                manualReload();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Total Check-in
                    if (widget.hasInAccess)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.login_rounded, size: 12, color: Color(0xFF10B981)),
                          const SizedBox(width: 5),
                          const Text(
                            'Total In: ',
                            style: TextStyle(
                              color: Color(0xFF34D399),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (isLoading && _count.checkIn == 0)
                            const SizedBox(
                              width: 10,
                              height: 10,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Color(0xFF10B981),
                                ),
                              ),
                            )
                          else
                            Text(
                              '${_count.checkIn}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                        ],
                      )
                    else
                      const SizedBox.shrink(),

                    // Total Check-out
                    if (widget.hasOutAccess)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.logout_rounded, size: 12, color: Color(0xFFF43F5E)),
                          const SizedBox(width: 5),
                          const Text(
                            'Total Out: ',
                            style: TextStyle(
                              color: Color(0xFFFB7185),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (isLoading && _count.checkOut == 0)
                            const SizedBox(
                              width: 10,
                              height: 10,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Color(0xFFF43F5E),
                                ),
                              ),
                            )
                          else
                            Text(
                              '${_count.checkOut}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                        ],
                      )
                    else
                      const SizedBox.shrink(),

                    Icon(
                      Icons.sync_rounded,
                      size: 13,
                      color: isLoading ? AppTheme.eventxproAccent : Colors.white30,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Reusable Check-in & Check-out card for Agendas.
/// Replicates React Native AgendaInOutCard.jsx with metadata and separate check-in and check-out counts.
class AgendaPunchCard extends StatefulWidget {
  final int eventId;
  final String eventName;
  final int agendaId;
  final String title;
  final String? date;
  final String? start;
  final String? end;
  final String? agendaType;
  final bool hasInAccess;
  final bool hasOutAccess;
  final int refreshTrigger;
  final int serverRefreshTrigger;
  final VoidCallback onCheckIn;
  final VoidCallback onCheckOut;

  const AgendaPunchCard({
    super.key,
    required this.eventId,
    required this.eventName,
    required this.agendaId,
    required this.title,
    this.date,
    this.start,
    this.end,
    this.agendaType,
    required this.hasInAccess,
    required this.hasOutAccess,
    this.refreshTrigger = 0,
    this.serverRefreshTrigger = 0,
    required this.onCheckIn,
    required this.onCheckOut,
  });

  @override
  State<AgendaPunchCard> createState() => _AgendaPunchCardState();
}

class _AgendaPunchCardState extends State<AgendaPunchCard>
    with LazyCountLoaderMixin<AgendaPunchCard> {
  GateCheckInOutCount _count = const GateCheckInOutCount();
  GateCountService? _gateCountService;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _gateCountService ??= context.read<GateCountService>();
    if (_count == const GateCheckInOutCount()) {
      final cached = _gateCountService?.getCached(
        widget.eventId,
        'agenda',
        widget.agendaId,
      );
      if (cached != null) {
        _count = cached;
      }
    }
  }

  @override
  void didUpdateWidget(covariant AgendaPunchCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool configChanged = oldWidget.agendaId != widget.agendaId ||
        oldWidget.eventId != widget.eventId;
    final bool serverTriggerChanged =
        oldWidget.serverRefreshTrigger != widget.serverRefreshTrigger;
    final bool localTriggerChanged =
        oldWidget.refreshTrigger != widget.refreshTrigger;

    if (configChanged || serverTriggerChanged) {
      notifyConfigOrTriggerChanged(forceRefresh: true);
    } else if (localTriggerChanged) {
      // Local sync only: zero network requests
      _syncFromLocalCache();
    }
  }

  void _syncFromLocalCache() {
    final service = _gateCountService ?? (mounted ? context.read<GateCountService>() : null);
    if (service == null) return;

    final cached = service.getCached(
      widget.eventId,
      'agenda',
      widget.agendaId,
    );
    if (cached != null) {
      if (cached != _count && mounted) {
        setState(() => _count = cached);
      }
    } else {
      service.getLocalCountOnly(
        eventId: widget.eventId,
        section: 'agenda',
        actionId: widget.agendaId,
      ).then((local) {
        if (mounted && local != _count) {
          setState(() => _count = local);
        }
      });
    }
  }

  @override
  Future<void> performLoadCount({bool forceRefresh = false}) async {
    final service = _gateCountService ?? (mounted ? context.read<GateCountService>() : null);
    if (service == null) return;

    final cached = service.getCached(
      widget.eventId,
      'agenda',
      widget.agendaId,
    );
    if (cached != null && mounted) {
      setState(() => _count = cached);
    }

    try {
      final fresh = await service.getCounts(
        eventId: widget.eventId,
        section: 'agenda',
        actionId: widget.agendaId,
        forceRefresh: forceRefresh,
      );

      if (mounted) {
        setState(() {
          _count = fresh;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF181F2E).withValues(alpha: 0.70),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  widget.title.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              if (widget.agendaType != null && widget.agendaType!.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: AppTheme.eventxproAccent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppTheme.eventxproAccent.withValues(alpha: 0.5), width: 0.8),
                  ),
                  child: Text(
                    widget.agendaType!.toUpperCase(),
                    style: const TextStyle(
                      color: AppTheme.eventxproAccent,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
            ],
          ),

          // Date & Time metadata row
          if (widget.date != null || widget.start != null || widget.end != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (widget.date != null && widget.date!.isNotEmpty) ...[
                  const Icon(Icons.calendar_today_rounded, size: 11, color: Colors.white60),
                  const SizedBox(width: 4),
                  Text(
                    widget.date!,
                    style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(width: 12),
                ],
                if (widget.start != null || widget.end != null) ...[
                  const Icon(Icons.access_time_rounded, size: 11, color: Colors.white60),
                  const SizedBox(width: 4),
                  Text(
                    '${widget.start ?? ''}${widget.start != null && widget.end != null ? ' - ' : ''}${widget.end ?? ''}',
                    style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500),
                  ),
                ],
              ],
            ),
          ],

          const SizedBox(height: 12),

          // Check-in & Check-out Buttons Row
          Row(
            children: [
              if (widget.hasInAccess)
                Expanded(
                  child: _PunchButton(
                    label: 'CHECK-IN',
                    badgeColor: AppTheme.eventxproSuccess,
                    arrowColor: Colors.black,
                    onTap: widget.onCheckIn,
                  ),
                ),

              if (widget.hasInAccess && widget.hasOutAccess)
                const SizedBox(width: 10),

              if (widget.hasOutAccess)
                Expanded(
                  child: _PunchButton(
                    label: 'CHECK-OUT',
                    badgeColor: AppTheme.eventxproDanger,
                    arrowColor: Colors.white,
                    onTap: widget.onCheckOut,
                  ),
                ),
            ],
          ),

          // Total Check-In & Check-Out counts row (Matching AgendaInOutCard.jsx)
          if (widget.hasInAccess || widget.hasOutAccess) ...[
            const SizedBox(height: 10),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.lightImpact();
                manualReload();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Total Check-in
                    if (widget.hasInAccess)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.login_rounded, size: 12, color: Color(0xFF10B981)),
                          const SizedBox(width: 5),
                          const Text(
                            'Total In: ',
                            style: TextStyle(
                              color: Color(0xFF34D399),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (isLoading && _count.checkIn == 0)
                            const SizedBox(
                              width: 10,
                              height: 10,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Color(0xFF10B981),
                                ),
                              ),
                            )
                          else
                            Text(
                              '${_count.checkIn}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                        ],
                      )
                    else
                      const SizedBox.shrink(),

                    // Total Check-out
                    if (widget.hasOutAccess)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.logout_rounded, size: 12, color: Color(0xFFF43F5E)),
                          const SizedBox(width: 5),
                          const Text(
                            'Total Out: ',
                            style: TextStyle(
                              color: Color(0xFFFB7185),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (isLoading && _count.checkOut == 0)
                            const SizedBox(
                              width: 10,
                              height: 10,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Color(0xFFF43F5E),
                                ),
                              ),
                            )
                          else
                            Text(
                              '${_count.checkOut}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                        ],
                      )
                    else
                      const SizedBox.shrink(),

                    Icon(
                      Icons.sync_rounded,
                      size: 13,
                      color: isLoading ? AppTheme.eventxproAccent : Colors.white30,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Pill button with circular forward arrow badge
/// (Matching React Native OfflineEventSection styles.btn & styles.arrowBtn)
class _PunchButton extends StatelessWidget {
  final String label;
  final Color? badgeColor;
  final Color? arrowColor;
  final VoidCallback onTap;

  const _PunchButton({
    required this.label,
    this.badgeColor,
    this.arrowColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool isCheckIn = label.toUpperCase().contains('IN');
    // High-contrast vibrant colors: Emerald Green for Check-In, Ruby Rose-Red for Check-Out
    final Color primaryColor = isCheckIn ? const Color(0xFF10B981) : const Color(0xFFF43F5E);
    final Color bgColor = isCheckIn
        ? const Color(0xFF082F1E).withValues(alpha: 0.85)
        : const Color(0xFF381018).withValues(alpha: 0.85);
    final Color textColor = isCheckIn ? const Color(0xFFD1FAE5) : const Color(0xFFFFE4E6);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        borderRadius: BorderRadius.circular(30),
        child: Container(
          padding: const EdgeInsets.only(left: 14, right: 4, top: 4, bottom: 4),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: primaryColor.withValues(alpha: 0.50),
              width: 1.2,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: primaryColor,
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    size: 15,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
