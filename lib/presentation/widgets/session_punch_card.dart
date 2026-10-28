import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/services/gate_count_service.dart';
import '../../core/theme/app_theme.dart';

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
    required this.onCheckIn,
    required this.onCheckOut,
  });

  @override
  State<SessionPunchCard> createState() => _SessionPunchCardState();
}

class _SessionPunchCardState extends State<SessionPunchCard> {
  GateCheckInOutCount _count = const GateCheckInOutCount();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadCount();
  }

  @override
  void didUpdateWidget(covariant SessionPunchCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTrigger != widget.refreshTrigger ||
        oldWidget.sessionId != widget.sessionId ||
        oldWidget.eventId != widget.eventId ||
        oldWidget.section != widget.section) {
      _loadCount(forceRefresh: true);
    }
  }

  Future<void> _loadCount({bool forceRefresh = false}) async {
    final service = context.read<GateCountService>();

    // Instant O(1) in-memory cached lookup if available
    final cached = service.getCached(
      widget.eventId,
      widget.section,
      widget.sessionId,
      widget.sectionLocation,
    );
    if (cached != null) {
      _count = cached;
    }

    if (mounted) {
      setState(() => _isLoading = cached == null);
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
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: AppTheme.eventxproBorder,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Session / Gate Title
          Text(
            widget.title.toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
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
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Total Check-in
                if (widget.hasInAccess)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Total Check-in: ',
                        style: TextStyle(
                          color: AppTheme.eventxproSuccess, // #8DFFBB
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (_isLoading && _count.checkIn == 0)
                        const SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppTheme.eventxproSuccess,
                            ),
                          ),
                        )
                      else
                        Text(
                          '${_count.checkIn}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
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
                      const Text(
                        'Total Check-out: ',
                        style: TextStyle(
                          color: AppTheme.eventxproDanger, // #FF6767
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (_isLoading && _count.checkOut == 0)
                        const SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppTheme.eventxproDanger,
                            ),
                          ),
                        )
                      else
                        Text(
                          '${_count.checkOut}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  )
                else
                  const SizedBox.shrink(),
              ],
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
    required this.onCheckIn,
    required this.onCheckOut,
  });

  @override
  State<AgendaPunchCard> createState() => _AgendaPunchCardState();
}

class _AgendaPunchCardState extends State<AgendaPunchCard> {
  GateCheckInOutCount _count = const GateCheckInOutCount();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadCount();
  }

  @override
  void didUpdateWidget(covariant AgendaPunchCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTrigger != widget.refreshTrigger ||
        oldWidget.agendaId != widget.agendaId ||
        oldWidget.eventId != widget.eventId) {
      _loadCount(forceRefresh: true);
    }
  }

  Future<void> _loadCount({bool forceRefresh = false}) async {
    final service = context.read<GateCountService>();

    final cached = service.getCached(
      widget.eventId,
      'agenda',
      widget.agendaId,
    );
    if (cached != null) {
      _count = cached;
    }

    if (mounted) {
      setState(() => _isLoading = cached == null);
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
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: AppTheme.eventxproBorder,
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
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              if (widget.agendaType != null && widget.agendaType!.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.eventxproAccent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                    border:
                        Border.all(color: AppTheme.eventxproAccent, width: 0.8),
                  ),
                  child: Text(
                    widget.agendaType!.toUpperCase(),
                    style: const TextStyle(
                      color: AppTheme.eventxproAccent,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),

          // Date & Time metadata row
          if (widget.date != null || widget.start != null || widget.end != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                if (widget.date != null && widget.date!.isNotEmpty) ...[
                  const Icon(Icons.calendar_today_rounded,
                      size: 12, color: Colors.white60),
                  const SizedBox(width: 4),
                  Text(
                    widget.date!,
                    style:
                        const TextStyle(color: Colors.white60, fontSize: 11),
                  ),
                  const SizedBox(width: 12),
                ],
                if (widget.start != null || widget.end != null) ...[
                  const Icon(Icons.access_time_rounded,
                      size: 12, color: Colors.white60),
                  const SizedBox(width: 4),
                  Text(
                    '${widget.start ?? ''}${widget.start != null && widget.end != null ? ' - ' : ''}${widget.end ?? ''}',
                    style:
                        const TextStyle(color: Colors.white60, fontSize: 11),
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
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Total Check-in
                if (widget.hasInAccess)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Total Check-in: ',
                        style: TextStyle(
                          color: AppTheme.eventxproSuccess,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (_isLoading && _count.checkIn == 0)
                        const SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppTheme.eventxproSuccess,
                            ),
                          ),
                        )
                      else
                        Text(
                          '${_count.checkIn}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
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
                      const Text(
                        'Total Check-out: ',
                        style: TextStyle(
                          color: AppTheme.eventxproDanger,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (_isLoading && _count.checkOut == 0)
                        const SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppTheme.eventxproDanger,
                            ),
                          ),
                        )
                      else
                        Text(
                          '${_count.checkOut}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  )
                else
                  const SizedBox.shrink(),
              ],
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
  final Color badgeColor;
  final Color arrowColor;
  final VoidCallback onTap;

  const _PunchButton({
    required this.label,
    required this.badgeColor,
    required this.arrowColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.only(left: 10, right: 4, top: 4, bottom: 4),
        decoration: BoxDecoration(
          color: const Color(0x1FFFFFFF),
          borderRadius: BorderRadius.circular(50),
          border: Border.all(
            color: AppTheme.eventxproBorder,
            width: 1,
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
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 11.5,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: badgeColor,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Icon(
                  Icons.arrow_forward_rounded,
                  size: 14,
                  color: arrowColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
