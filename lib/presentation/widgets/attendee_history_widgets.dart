import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/models/attendee_details_model.dart';

/// Helper to format a date string (YYYY-MM-DD) into 'DD MMM, YYYY'
String formatHistoryDate(String? rawDate) {
  if (rawDate == null || rawDate.trim().isEmpty) return '';
  try {
    final dt = DateTime.parse(rawDate.trim());
    return DateFormat('dd MMM, yyyy').format(dt);
  } catch (_) {
    return rawDate;
  }
}

/// Helper to format a time string (HH:mm or HH:mm:ss) into 'hh:mm a'
String formatHistoryTime(String? rawTime) {
  if (rawTime == null || rawTime.trim().isEmpty) return '';
  try {
    final parts = rawTime.trim().split(':');
    if (parts.length >= 2) {
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      final now = DateTime.now();
      final dt = DateTime(now.year, now.month, now.day, hour, minute);
      return DateFormat('hh:mm a').format(dt);
    }
  } catch (_) {}
  return rawTime;
}

/// Entrance History Widget matching `EntranceHistory.jsx` in `eventxproorganiser`
class EntranceHistoryWidget extends StatelessWidget {
  final List<EntranceHistoryGroup> data;

  const EntranceHistoryWidget({
    super.key,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Title
          _buildSectionHeader(
            title: 'ENTRANCE HISTORY',
            icon: Icons.door_sliding_outlined,
            color: const Color(0xFF38BDF8),
          ),
          const SizedBox(height: 10),

          // Cards per date
          ...data.map((item) => _buildEntranceCard(item)),
        ],
      ),
    );
  }

  Widget _buildEntranceCard(EntranceHistoryGroup group) {
    final formattedDate = formatHistoryDate(group.checkInDate);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date Row with Divider
          Row(
            children: [
              Text(
                formattedDate,
                style: const TextStyle(
                  color: Color(0xFF1E293B),
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  height: 1.2,
                  color: const Color(0xFFE2E8F0),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // In/Out Logs
          if (group.logs.isEmpty)
            const Text(
              'No punch timestamps recorded',
              style: TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            )
          else
            ...group.logs.map((log) => _buildPunchRow(log)),
        ],
      ),
    );
  }

  Widget _buildPunchRow(HistoryLogItem log) {
    final hasIn = log.checkInTime != null && log.checkInTime!.isNotEmpty;
    final hasOut = log.checkOutTime != null && log.checkOutTime!.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Check-in
          if (hasIn)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: const BoxDecoration(
                    color: Color(0xFF34C38F),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'Check-in: ',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  formatHistoryTime(log.checkInTime),
                  style: const TextStyle(
                    color: Color(0xFF34C38F),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            )
          else
            const SizedBox.shrink(),

          // Check-out
          if (hasOut)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: const BoxDecoration(
                    color: Color(0xFFED4C5C),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'Check-out: ',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  formatHistoryTime(log.checkOutTime),
                  style: const TextStyle(
                    color: Color(0xFFED4C5C),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            )
          else
            const SizedBox.shrink(),
        ],
      ),
    );
  }
}

/// Hall History Widget matching `HallHistory.jsx` in `eventxproorganiser`
class HallHistoryWidget extends StatelessWidget {
  final List<HallHistoryGroup> data;

  const HallHistoryWidget({
    super.key,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Title
          _buildSectionHeader(
            title: 'HALL HISTORY',
            icon: Icons.meeting_room_outlined,
            color: const Color(0xFFA855F7),
          ),
          const SizedBox(height: 10),

          // Cards per hall
          ...data.map((item) => _buildHallCard(item)),
        ],
      ),
    );
  }

  Widget _buildHallCard(HallHistoryGroup group) {
    final formattedDate = formatHistoryDate(group.checkInDate);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hall Name Title
          Text(
            group.hallName ?? 'Hall',
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w800,
              fontSize: 13.5,
            ),
          ),
          const SizedBox(height: 6),

          // Date Row with Divider
          Row(
            children: [
              Text(
                formattedDate,
                style: const TextStyle(
                  color: Color(0xFF475569),
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  height: 1.2,
                  color: const Color(0xFFE2E8F0),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // In/Out Logs
          if (group.logs.isEmpty)
            const Text(
              'No punch timestamps recorded',
              style: TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            )
          else
            ...group.logs.map((log) => _buildPunchRow(log)),
        ],
      ),
    );
  }

  Widget _buildPunchRow(HistoryLogItem log) {
    final hasIn = log.checkInTime != null && log.checkInTime!.isNotEmpty;
    final hasOut = log.checkOutTime != null && log.checkOutTime!.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (hasIn)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: const BoxDecoration(
                    color: Color(0xFF34C38F),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'Check-in: ',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  formatHistoryTime(log.checkInTime),
                  style: const TextStyle(
                    color: Color(0xFF34C38F),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            )
          else
            const SizedBox.shrink(),

          if (hasOut)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: const BoxDecoration(
                    color: Color(0xFFED4C5C),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'Check-out: ',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  formatHistoryTime(log.checkOutTime),
                  style: const TextStyle(
                    color: Color(0xFFED4C5C),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            )
          else
            const SizedBox.shrink(),
        ],
      ),
    );
  }
}

/// Agenda History Widget matching `AgendaHistory.jsx` in `eventxproorganiser`
class AgendaHistoryWidget extends StatelessWidget {
  final List<AgendaHistoryGroup> data;

  const AgendaHistoryWidget({
    super.key,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Title
          _buildSectionHeader(
            title: 'AGENDA / SESSION HISTORY',
            icon: Icons.event_available_outlined,
            color: const Color(0xFFF59E0B),
          ),
          const SizedBox(height: 10),

          // Cards per agenda
          ...data.map((item) => _buildAgendaCard(item)),
        ],
      ),
    );
  }

  Widget _buildAgendaCard(AgendaHistoryGroup group) {
    final formattedDate = formatHistoryDate(group.checkInDate);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Agenda Title
          Text(
            group.agendaTitle ?? 'Agenda',
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w800,
              fontSize: 13.5,
            ),
          ),
          const SizedBox(height: 6),

          // Date Row with Divider
          Row(
            children: [
              Text(
                formattedDate,
                style: const TextStyle(
                  color: Color(0xFF475569),
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  height: 1.2,
                  color: const Color(0xFFE2E8F0),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // In/Out Logs
          if (group.logs.isEmpty)
            const Text(
              'No punch timestamps recorded',
              style: TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            )
          else
            ...group.logs.map((log) => _buildPunchRow(log)),
        ],
      ),
    );
  }

  Widget _buildPunchRow(HistoryLogItem log) {
    final hasIn = log.checkInTime != null && log.checkInTime!.isNotEmpty;
    final hasOut = log.checkOutTime != null && log.checkOutTime!.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (hasIn)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: const BoxDecoration(
                    color: Color(0xFF34C38F),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'Check-in: ',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  formatHistoryTime(log.checkInTime),
                  style: const TextStyle(
                    color: Color(0xFF34C38F),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            )
          else
            const SizedBox.shrink(),

          if (hasOut)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: const BoxDecoration(
                    color: Color(0xFFED4C5C),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'Check-out: ',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  formatHistoryTime(log.checkOutTime),
                  style: const TextStyle(
                    color: Color(0xFFED4C5C),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            )
          else
            const SizedBox.shrink(),
        ],
      ),
    );
  }
}

Widget _buildSectionHeader({
  required String title,
  required IconData icon,
  required Color color,
}) {
  return Row(
    children: [
      Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, color: color, size: 15),
      ),
      const SizedBox(width: 8),
      Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
    ],
  );
}
