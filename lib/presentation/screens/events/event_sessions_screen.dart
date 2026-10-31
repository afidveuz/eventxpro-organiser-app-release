import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/network/api_client.dart';
import '../../../core/services/gate_count_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/adapters/simulated_hardware_adapter.dart';
import '../../../data/adapters/zebra_datawedge_adapter.dart';
import '../../../data/datasources/scanner_local_storage.dart';
import '../../bloc/scanner_bloc.dart';
import '../../bloc/scanner_event.dart';
import '../kiosk_scanner_screen.dart';
import '../../widgets/session_punch_card.dart';

/// Parsed event sections for high-performance zero-delay rendering
class _ParsedSections {
  final List<Map<String, dynamic>> entranceList;
  final List<Map<String, dynamic>> hallList;
  final List<Map<String, dynamic>> agendaList;
  final List<Map<String, dynamic>> sessionList;

  const _ParsedSections({
    required this.entranceList,
    required this.hallList,
    required this.agendaList,
    required this.sessionList,
  });
}

/// Event Sessions Screen matching `EventDetails.jsx` in the reference React Native app.
/// Lists Entrances, Halls, Agendas, and Sessions with Check-In & Check-Out punch cards.
class EventSessionsScreen extends StatefulWidget {
  final int eventId;
  final String eventName;
  final Map<String, dynamic>? initialPermissions;
  final ZebraDataWedgeAdapter? zebraAdapter;
  final SimulatedHardwareAdapter? simulatorAdapter;

  const EventSessionsScreen({
    super.key,
    required this.eventId,
    required this.eventName,
    this.initialPermissions,
    this.zebraAdapter,
    this.simulatorAdapter,
  });

  @override
  State<EventSessionsScreen> createState() => _EventSessionsScreenState();
}

class _EventSessionsScreenState extends State<EventSessionsScreen> {
  bool _isLoading = true;
  _ParsedSections? _sections;
  int _countRefreshTrigger = 0;
  final int _serverRefreshTrigger = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initialPermissions != null) {
      _sections = _parseSections(widget.initialPermissions);
      _isLoading = false;
    } else {
      _loadPermissions();
    }
  }

  _ParsedSections _parseSections(Map<String, dynamic>? permission) {
    if (permission == null) {
      final defaultGate = context.read<ScannerLocalStorage>().getGateId();
      return _ParsedSections(
        entranceList: [
          {
            'entrance_id': defaultGate,
            'entrance_name': 'Main Entrance',
            'location': 'Gate #$defaultGate',
            'entrance_in_access': true,
            'entrance_out_access': true,
          },
        ],
        hallList: const [],
        agendaList: const [],
        sessionList: const [],
      );
    }

    // 1. Entrances
    List<Map<String, dynamic>> entranceList = [];
    final entrancePerm =
        permission['entrance_permission'] as Map<String, dynamic>?;
    if (entrancePerm != null && entrancePerm['access'] != false) {
      final rawList = entrancePerm['entrance_list'] as List<dynamic>? ?? [];
      entranceList = rawList.whereType<Map<String, dynamic>>().toList();
    }
    if (entranceList.isEmpty && permission['entrance'] is Map) {
      final ent = permission['entrance'] as Map<String, dynamic>;
      if (ent['access'] == true) {
        final gateId = context.read<ScannerLocalStorage>().getGateId();
        entranceList = [
          {
            'entrance_id': gateId,
            'entrance_name': 'Main Entrance',
            'location': 'Gate #$gateId',
            'entrance_in_access': ent['checkin'] != false,
            'entrance_out_access': ent['checkout'] != false,
          },
        ];
      }
    }

    // 2. Halls
    List<Map<String, dynamic>> hallList = [];
    final hallPerm = permission['hall_permission'] as Map<String, dynamic>?;
    if (hallPerm != null && hallPerm['access'] == true) {
      final rawList = hallPerm['hall_list'] as List<dynamic>? ?? [];
      hallList = rawList.whereType<Map<String, dynamic>>().toList();
    }

    // 3. Agendas
    List<Map<String, dynamic>> agendaList = [];
    final agendaPerm = permission['agenda_permission'] as Map<String, dynamic>?;
    if (agendaPerm != null && agendaPerm['access'] == true) {
      final rawList = agendaPerm['agenda_list'] as List<dynamic>? ?? [];
      agendaList = rawList.whereType<Map<String, dynamic>>().toList();
    }

    // 4. Sessions
    List<Map<String, dynamic>> sessionList = [];
    final sessionPerm =
        permission['sessiontype_permission'] as Map<String, dynamic>?;
    if (sessionPerm != null && sessionPerm['access'] == true) {
      final rawList = sessionPerm['sessiontype_list'] as List<dynamic>? ?? [];
      sessionList = rawList.whereType<Map<String, dynamic>>().toList();
    }

    return _ParsedSections(
      entranceList: entranceList,
      hallList: hallList,
      agendaList: agendaList,
      sessionList: sessionList,
    );
  }

  Future<void> _loadPermissions({bool silent = false}) async {
    if (!silent) {
      setState(() => _isLoading = true);
    }

    try {
      final apiClient = context.read<ApiClient>();
      final res = await apiClient.dio.get('organizer/event-permission/${widget.eventId}');
      if (res.statusCode == 200 && res.data != null) {
        Map<String, dynamic>? permMap;
        if (res.data is Map) {
          permMap = Map<String, dynamic>.from(res.data as Map);
        } else {
          final parsed = jsonDecode(res.data.toString());
          if (parsed is Map) {
            permMap = Map<String, dynamic>.from(parsed);
          }
        }
        if (mounted && permMap != null) {
          setState(() {
            _sections = _parseSections(permMap);
            _isLoading = false;
          });
          return;
        }
      }
    } catch (e) {
      debugPrint('[EventSessionsScreen] Error loading permissions: $e');
    }

    // Fallback: Offline cached data if network failed
    if (mounted) {
      final storage = context.read<ScannerLocalStorage>();
      final cachedRaw = storage.getOfflineData();
      if (cachedRaw != null && cachedRaw.isNotEmpty) {
        try {
          final cachedJson = jsonDecode(cachedRaw);
          if (cachedJson is Map && cachedJson['permission'] is Map) {
            final permMap = Map<String, dynamic>.from(cachedJson['permission'] as Map);
            setState(() {
              _sections = _parseSections(permMap);
              _isLoading = false;
            });
            return;
          }
        } catch (_) {}
      }

      setState(() {
        _sections ??= _parseSections(null);
        _isLoading = false;
      });
    }
  }

  void _launchScanner({
    required String punchType,
    required int gateId,
    required int eventId,
    String? gateName,
    String? eventName,
    String section = 'entrances',
    String? sectionLocation,
  }) {
    try {
      context.read<GateCountService>().resetSessionScans();
    } catch (_) {}

    context.read<ScannerBloc>().add(
      ScannerConfigChanged(
        scanType: punchType,
        gateId: gateId,
        eventId: eventId,
        section: section,
        sectionLocation: sectionLocation,
      ),
    );

    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => KioskScannerScreen(
              zebraAdapter: widget.zebraAdapter,
              simulatorAdapter: widget.simulatorAdapter,
              initialPunchType: punchType,
              initialGateId: gateId,
              initialEventId: eventId,
              gateName: gateName,
              eventName: eventName,
              section: section,
              sectionLocation: sectionLocation,
            ),
          ),
        )
        .then((_) {
          if (!mounted) return;
          setState(() {
            _countRefreshTrigger++;
          });
        });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.eventxproBg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background Image
          Positioned.fill(
            child: Image.asset('assets/images/bg.png', fit: BoxFit.cover),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF131722).withValues(alpha: 0.35),
                    AppTheme.eventxproBg.withValues(alpha: 0.20),
                    const Color(0xFF0D111A).withValues(alpha: 0.50),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(
                  child: RefreshIndicator(
                    color: AppTheme.eventxproAccent,
                    backgroundColor: AppTheme.surfaceElevated,
                    onRefresh: () => _loadPermissions(silent: true),
                    child: _isLoading
                        ? _buildLoadingState()
                        : _buildSessionsList(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Circular Back Button matching EventTopBar.jsx
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
          // Title & Event Name
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Sessions & Gates',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
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
          // Refresh Button
          IconButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              _loadPermissions(silent: false);
            },
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70, size: 20),
            tooltip: 'Refresh Gates',
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 2.8,
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.eventxproAccent),
            ),
          ),
          SizedBox(height: 14),
          Text(
            'Loading Gates & Sessions...',
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

  Widget _buildSessionsList() {
    final sections = _sections;
    if (sections == null ||
        (sections.entranceList.isEmpty &&
            sections.hallList.isEmpty &&
            sections.agendaList.isEmpty &&
            sections.sessionList.isEmpty)) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.meeting_room_outlined, size: 48, color: Colors.white.withValues(alpha: 0.3)),
              const SizedBox(height: 14),
              const Text(
                'No Gates Available',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                'No entrance, hall, or session gates assigned for this event.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 1. ENTRANCES ─────────────────────────────────────────
          if (sections.entranceList.isNotEmpty) ...[
            _buildCategoryHeader(
              title: 'ENTRANCES',
              icon: Icons.meeting_room_outlined,
              count: sections.entranceList.length,
              accentColor: AppTheme.accentCyan,
            ),
            const SizedBox(height: 10),
            ...sections.entranceList.map((item) {
              final int entranceId =
                  (item['entrance_id'] as num?)?.toInt() ??
                  (item['id'] as num?)?.toInt() ??
                  0;
              final String title = item['entrance_name']?.toString() ?? 'Entrance';
              final String? loc = item['location']?.toString();
              final String displayTitle =
                  loc != null && loc.isNotEmpty ? '$title - $loc' : title;
              final bool inAccess = item['entrance_in_access'] != false;
              final bool outAccess = item['entrance_out_access'] != false;

              return SessionPunchCard(
                eventId: widget.eventId,
                eventName: widget.eventName,
                sessionId: entranceId,
                title: displayTitle,
                section: 'entrances',
                sectionLocation: loc ?? title,
                hasInAccess: inAccess,
                hasOutAccess: outAccess,
                refreshTrigger: _countRefreshTrigger,
                serverRefreshTrigger: _serverRefreshTrigger,
                onCheckIn: () => _launchScanner(
                  punchType: 'check_in',
                  gateId: entranceId,
                  eventId: widget.eventId,
                  gateName: displayTitle,
                  eventName: widget.eventName,
                  section: 'entrances',
                  sectionLocation: loc ?? title,
                ),
                onCheckOut: () => _launchScanner(
                  punchType: 'check_out',
                  gateId: entranceId,
                  eventId: widget.eventId,
                  gateName: displayTitle,
                  eventName: widget.eventName,
                  section: 'entrances',
                  sectionLocation: loc ?? title,
                ),
              );
            }),
            if (sections.hallList.isNotEmpty ||
                sections.agendaList.isNotEmpty ||
                sections.sessionList.isNotEmpty)
              const SizedBox(height: 16),
          ],

          // ── 2. HALLS ─────────────────────────────────────────────
          if (sections.hallList.isNotEmpty) ...[
            _buildCategoryHeader(
              title: 'HALLS',
              icon: Icons.domain_outlined,
              count: sections.hallList.length,
              accentColor: AppTheme.accentIndigo,
            ),
            const SizedBox(height: 10),
            ...sections.hallList.map((item) {
              final int hallId =
                  (item['hall_id'] as num?)?.toInt() ??
                  (item['id'] as num?)?.toInt() ??
                  0;
              final String title = item['hall_name']?.toString() ?? 'Hall';
              final bool inAccess = item['hall_in_access'] == true;
              final bool outAccess = item['hall_out_access'] == true;

              return SessionPunchCard(
                eventId: widget.eventId,
                eventName: widget.eventName,
                sessionId: hallId,
                title: title,
                section: 'hall',
                sectionLocation: title,
                hasInAccess: inAccess,
                hasOutAccess: outAccess,
                refreshTrigger: _countRefreshTrigger,
                serverRefreshTrigger: _serverRefreshTrigger,
                onCheckIn: () => _launchScanner(
                  punchType: 'check_in',
                  gateId: hallId,
                  eventId: widget.eventId,
                  gateName: title,
                  eventName: widget.eventName,
                  section: 'hall',
                  sectionLocation: title,
                ),
                onCheckOut: () => _launchScanner(
                  punchType: 'check_out',
                  gateId: hallId,
                  eventId: widget.eventId,
                  gateName: title,
                  eventName: widget.eventName,
                  section: 'hall',
                  sectionLocation: title,
                ),
              );
            }),
            if (sections.agendaList.isNotEmpty || sections.sessionList.isNotEmpty)
              const SizedBox(height: 16),
          ],

          // ── 3. AGENDAS ───────────────────────────────────────────
          if (sections.agendaList.isNotEmpty) ...[
            _buildCategoryHeader(
              title: 'AGENDAS',
              icon: Icons.event_note_rounded,
              count: sections.agendaList.length,
              accentColor: const Color(0xFFA855F7),
            ),
            const SizedBox(height: 10),
            ...sections.agendaList.map((item) {
              final int agendaId = (item['agenda_id'] as num?)?.toInt() ?? 0;
              final String rawName = item['agendaname']?.toString() ?? 'Agenda';
              final dynamic day = item['day'];
              final String title = day != null ? 'Day-$day $rawName' : rawName;
              final String? date = item['agenda_dt']?.toString();
              final String? start = item['start_tm']?.toString();
              final String? end = item['end_tm']?.toString();
              final String? agendaType = item['agendatype']?.toString();
              final bool inAccess = item['agenda_in_access'] == true;
              final bool outAccess = item['agenda_out_access'] == true;

              return AgendaPunchCard(
                eventId: widget.eventId,
                eventName: widget.eventName,
                agendaId: agendaId,
                title: title,
                date: date,
                start: start,
                end: end,
                agendaType: agendaType,
                hasInAccess: inAccess,
                hasOutAccess: outAccess,
                refreshTrigger: _countRefreshTrigger,
                serverRefreshTrigger: _serverRefreshTrigger,
                onCheckIn: () => _launchScanner(
                  punchType: 'check_in',
                  gateId: agendaId,
                  eventId: widget.eventId,
                  gateName: title,
                  eventName: widget.eventName,
                  section: 'agenda',
                  sectionLocation: title,
                ),
                onCheckOut: () => _launchScanner(
                  punchType: 'check_out',
                  gateId: agendaId,
                  eventId: widget.eventId,
                  gateName: title,
                  eventName: widget.eventName,
                  section: 'agenda',
                  sectionLocation: title,
                ),
              );
            }),
            if (sections.sessionList.isNotEmpty) const SizedBox(height: 16),
          ],

          // ── 4. SESSIONS ──────────────────────────────────────────
          if (sections.sessionList.isNotEmpty) ...[
            _buildCategoryHeader(
              title: 'SESSIONS',
              icon: Icons.co_present_rounded,
              count: sections.sessionList.length,
              accentColor: const Color(0xFFFF9800),
            ),
            const SizedBox(height: 10),
            ...sections.sessionList.map((item) {
              final int sessId =
                  ((item['session_type_id'] ?? item['sessiontype_id']) as num?)?.toInt() ?? 0;
              final String title =
                  (item['sessiontype_name'] ?? item['session_type_name'])?.toString() ?? 'Session';
              final bool inAccess = item['sessiontype_in_access'] == true;
              final bool outAccess = item['sessiontype_out_access'] == true;

              return SessionPunchCard(
                eventId: widget.eventId,
                eventName: widget.eventName,
                sessionId: sessId,
                title: title,
                section: 'session',
                sectionLocation: title,
                hasInAccess: inAccess,
                hasOutAccess: outAccess,
                refreshTrigger: _countRefreshTrigger,
                serverRefreshTrigger: _serverRefreshTrigger,
                onCheckIn: () => _launchScanner(
                  punchType: 'check_in',
                  gateId: sessId,
                  eventId: widget.eventId,
                  gateName: title,
                  eventName: widget.eventName,
                  section: 'session',
                  sectionLocation: title,
                ),
                onCheckOut: () => _launchScanner(
                  punchType: 'check_out',
                  gateId: sessId,
                  eventId: widget.eventId,
                  gateName: title,
                  eventName: widget.eventName,
                  section: 'session',
                  sectionLocation: title,
                ),
              );
            }),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildCategoryHeader({
    required String title,
    required IconData icon,
    required int count,
    required Color accentColor,
  }) {
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 13, color: accentColor),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.9),
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}
