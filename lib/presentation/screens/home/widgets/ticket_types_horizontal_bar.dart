import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../data/models/ticket_type_model.dart';

/// A horizontal scrollable list of ticket types displayed above the Event Card on the Home Screen.
/// Styled to match other cards on the HomeScreen:
/// - Dark navy background: `Color(0xFF131926)`
/// - Subtle border: `Color(0xFF1F293D)`
/// - Border radius: `10px`
/// - Tinted icon container: `Color(0xFF6366F1)` at 16% alpha
/// - Ticket name and optional category pill tag
class TicketTypesHorizontalBar extends StatelessWidget {
  final List<TicketTypeModel> tickets;
  final bool isLoading;
  final ValueChanged<TicketTypeModel>? onTicketTap;

  const TicketTypesHorizontalBar({
    super.key,
    required this.tickets,
    this.isLoading = false,
    this.onTicketTap,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading && tickets.isEmpty) {
      return _buildShimmerLoading();
    }

    if (tickets.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 2, bottom: 12),
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: tickets.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final ticket = tickets[index];
          return _buildTicketChip(context, ticket);
        },
      ),
    );
  }

  /// Skeleton shimmer cards matching the HomeScreen card theme
  Widget _buildShimmerLoading() {
    return Container(
      margin: const EdgeInsets.only(top: 2, bottom: 12),
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 4,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, index) {
          return Container(
                width: index == 0 ? 120 : (index == 1 ? 105 : 135),
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF131926),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFF1F293D),
                    width: 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E273A),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        height: 12,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E273A),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ],
                ),
              )
              .animate(onPlay: (controller) => controller.repeat(reverse: true))
              .fade(begin: 0.4, end: 0.85, duration: 800.ms);
        },
      ),
    );
  }

  /// Ticket card matching `_buildMetricCard` and `_buildEventInfoCard`
  Widget _buildTicketChip(BuildContext context, TicketTypeModel ticket) {
    final title = ticket.displayName;

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF131926),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1F293D), width: 1.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Icon badge matching HomeScreen metric icon container
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Center(
              child: Icon(
                Icons.confirmation_number_rounded,
                size: 14,
                color: Color(0xFF818CF8),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Ticket Name
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 13,
              letterSpacing: 0.2,
            ),
          ),

          // Optional Category Tag matching event ID badge style
          if (ticket.ticketTypeCat != null &&
              ticket.ticketTypeCat!.trim().isNotEmpty) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF1E273A),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFF28364F), width: 0.8),
              ),
              child: Text(
                ticket.ticketTypeCat!.trim(),
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );

    if (onTicketTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTicketTap!(ticket);
          },
          borderRadius: BorderRadius.circular(10),
          child: chip,
        ),
      );
    }

    return chip;
  }
}
