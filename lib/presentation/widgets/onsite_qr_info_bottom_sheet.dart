import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/onsite_coupon_details_model.dart';

class OnsiteQrInfoBottomSheet extends StatefulWidget {
  final OnsiteCouponModel data;
  final String mediaBaseUrl;
  final VoidCallback onClose;

  const OnsiteQrInfoBottomSheet({
    super.key,
    required this.data,
    required this.mediaBaseUrl,
    required this.onClose,
  });

  @override
  State<OnsiteQrInfoBottomSheet> createState() =>
      _OnsiteQrInfoBottomSheetState();
}

class _OnsiteQrInfoBottomSheetState extends State<OnsiteQrInfoBottomSheet> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  String? _resolveImageUrl(String? path) {
    if (path == null || path.trim().isEmpty) return null;
    final cleanPath = path.trim();
    if (cleanPath.startsWith('http://') || cleanPath.startsWith('https://')) {
      return cleanPath;
    }
    final cleanBase = widget.mediaBaseUrl.endsWith('/')
        ? widget.mediaBaseUrl.substring(0, widget.mediaBaseUrl.length - 1)
        : widget.mediaBaseUrl;
    final prefix = cleanPath.startsWith('/') ? '' : '/';
    return '$cleanBase$prefix$cleanPath';
  }

  String _formatTimestamp(String? isoString) {
    if (isoString == null || isoString.isEmpty) return 'N/A';
    try {
      final dt = DateTime.parse(isoString);
      return DateFormat('dd MMM, yyyy hh:mm a').format(dt);
    } catch (_) {
      return isoString;
    }
  }

  @override
  Widget build(BuildContext context) {
    final users = widget.data.redeemedUsers;
    final promoType = widget.data.coupon?.promocodeType;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(
          top: BorderSide(color: AppTheme.surfaceBorder, width: 1.5),
          left: BorderSide(color: AppTheme.surfaceBorder, width: 1.5),
          right: BorderSide(color: AppTheme.surfaceBorder, width: 1.5),
        ),
      ),
      child: SafeArea(
        top: false,
        left: false,
        right: false,
        bottom: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: const BoxDecoration(
              color: Color(0xFF23A618),
              borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.confirmation_number_outlined,
                    color: Color(0xFF23A618),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'On-Site QR Information',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                if (users.length > 1) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_currentIndex + 1} / ${users.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                InkWell(
                  onTap: widget.onClose,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.25),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close_rounded, color: Colors.white, size: 16),
                  ),
                ),
              ],
            ),
          ),

          // Content
          if (users.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: const Icon(
                      Icons.qr_code_2_rounded,
                      color: Colors.white38,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'QR Code Unused',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'This voucher code has not been redeemed by any attendee yet.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            )
          else ...[
            Flexible(
              child: SizedBox(
                height: 420,
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: users.length,
                  onPageChanged: (idx) {
                    setState(() {
                      _currentIndex = idx;
                    });
                  },
                  itemBuilder: (ctx, index) {
                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
                      child: _buildUserCard(users[index], promoType),
                    );
                  },
                ),
              ),
            ),

            // Pagination Dots
            if (users.length > 1) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(users.length, (idx) {
                    final isActive = _currentIndex == idx;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: isActive ? 18 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: isActive ? const Color(0xFF23A618) : Colors.white24,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ],
        ],
      ),
    ),
  );
  }

  Widget _buildUserCard(RedeemedUserItem item, String? promoType) {
    final info = item.userInfo;
    final isNew = item.ticketState.toLowerCase() == 'new';
    final imageUrl = _resolveImageUrl(item.userImage);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Profile Header Row
          Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                  color: Colors.white.withValues(alpha: 0.08),
                ),
                child: ClipOval(
                  child: imageUrl != null
                      ? Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _buildInitials(info.initials),
                        )
                      : _buildInitials(info.initials),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      info.fullName.isNotEmpty ? info.fullName : 'Attendee',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: isNew ? const Color(0xFFEAF6EA) : const Color(0xFFF6EEEA),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        item.ticketState.toUpperCase(),
                        style: TextStyle(
                          color: isNew ? const Color(0xFF23A618) : const Color(0xFFDE4B3B),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 12),

          // Detail rows
          _buildInfoRow('Company', info.companyName),
          _buildInfoRow('Designation', info.designation),
          _buildInfoRow('Email', info.email),
          _buildInfoRow('Phone', info.mobile),
          _buildInfoRow('URN', info.uniqueId),
          _buildInfoRow('Exhibitor', info.exhibitorName),
          _buildInfoRow('QR Type', promoType),
          _buildInfoRow('Created By', info.createdBy),
          _buildInfoRow('Used On', _formatTimestamp(item.usedDtTm)),
        ],
      ),
    );
  }

  Widget _buildInitials(String initials) {
    return Center(
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String? value) {
    if (value == null || value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Text(': ', style: TextStyle(color: Colors.white38, fontSize: 12)),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
