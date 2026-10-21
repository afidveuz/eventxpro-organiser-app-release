import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_theme.dart';
import '../bloc/scanner_state.dart';

/// A clean, modern, focused scanning UI designed specifically for event gate staff.
/// Eliminates diagnostic clutter, technical telemetry, and simulator buttons,
/// providing high-visibility attendee validation and quick check-in / check-out toggling.
class SimpleScannerView extends StatefulWidget {
  final ScannerState state;
  final VoidCallback onToggleMode;
  final VoidCallback onOpenSettings;
  final VoidCallback onLogout;
  final ValueChanged<String> onChangeScanType;
  final VoidCallback onResetToReady;

  const SimpleScannerView({
    super.key,
    required this.state,
    required this.onToggleMode,
    required this.onOpenSettings,
    required this.onLogout,
    required this.onChangeScanType,
    required this.onResetToReady,
  });

  @override
  State<SimpleScannerView> createState() => _SimpleScannerViewState();
}

class _SimpleScannerViewState extends State<SimpleScannerView>
    with SingleTickerProviderStateMixin {
  late AnimationController _laserController;
  late Animation<double> _laserAnimation;

  @override
  void initState() {
    super.initState();
    _laserController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _laserAnimation = Tween<double>(begin: 0.05, end: 0.95).animate(
      CurvedAnimation(parent: _laserController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _laserController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isCheckIn = widget.state.scanType.toUpperCase() != 'EXIT' &&
        widget.state.scanType.toLowerCase() != 'check_out';

    return SafeArea(
      child: Column(
        children: [
          // ── Clean Header ──────────────────────────────────────────
          _buildHeader(isCheckIn),

          // ── Main View Area ────────────────────────────────────────
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: _buildBody(),
                ),
              ),
            ),
          ),

          // ── Simple Footer ─────────────────────────────────────────
          _buildFooter(isCheckIn),
        ],
      ),
    );
  }

  // ── 1. Top Header ────────────────────────────────────────────────
  Widget _buildHeader(bool isCheckIn) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          bottom: BorderSide(color: AppTheme.surfaceBorder, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Event Title & Badge
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.qr_code_scanner_rounded,
                      size: 20,
                      color: AppTheme.accentIndigo,
                    ),
                    const SizedBox(width: 8),
                    const Flexible(
                      child: Text(
                        'Eventxpro',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.3,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceElevated,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppTheme.surfaceBorder),
                      ),
                      child: Text(
                        'EVT #${widget.state.eventId}',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Gate #${widget.state.gateId} • ${isCheckIn ? 'Entrance Check-in' : 'Exit Check-out'}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          // Punch Type Quick Toggle Pill (Check-in / Check-out)
          InkWell(
            onTap: () {
              final newType = isCheckIn ? 'EXIT' : 'ENTRY';
              widget.onChangeScanType(newType);
            },
            borderRadius: BorderRadius.circular(20),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isCheckIn
                    ? AppTheme.statusSuccess.withValues(alpha: 0.15)
                    : AppTheme.statusWarning.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isCheckIn
                      ? AppTheme.statusSuccess
                      : AppTheme.statusWarning,
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isCheckIn ? Icons.login_rounded : Icons.logout_rounded,
                    size: 14,
                    color: isCheckIn
                        ? AppTheme.statusSuccess
                        : AppTheme.statusWarning,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isCheckIn ? 'Check-in' : 'Check-out',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: isCheckIn
                          ? AppTheme.statusSuccess
                          : AppTheme.statusWarning,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 8),

          // Mode Switcher (Switch to Advanced Kiosk UI)
          IconButton(
            tooltip: 'Switch to Advanced Kiosk HUD',
            icon: const Icon(
              Icons.dashboard_customize_outlined,
              size: 20,
              color: AppTheme.textSecondary,
            ),
            onPressed: widget.onToggleMode,
          ),

          // Settings Button
          IconButton(
            tooltip: 'Scanner Settings',
            icon: const Icon(
              Icons.tune_rounded,
              size: 20,
              color: AppTheme.textSecondary,
            ),
            onPressed: widget.onOpenSettings,
          ),

          // Logout Button
          IconButton(
            tooltip: 'Log Out',
            icon: const Icon(
              Icons.logout_rounded,
              size: 20,
              color: Color(0xFFFF6767),
            ),
            onPressed: widget.onLogout,
          ),
        ],
      ),
    );
  }

  // ── 2. Main Body Content (State-driven) ───────────────────────────
  Widget _buildBody() {
    if (widget.state is ScannerProcessingState) {
      return _buildProcessingCard(widget.state as ScannerProcessingState);
    }

    if (widget.state is ScannerDecisionState) {
      return _buildDecisionCard(widget.state as ScannerDecisionState);
    }

    // Default: Ready Viewfinder
    return _buildReadyViewfinder();
  }

  // ── 2A. Ready Viewfinder ──────────────────────────────────────────
  Widget _buildReadyViewfinder() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Viewfinder Frame with Laser Animation
        AnimatedBuilder(
          animation: _laserAnimation,
          builder: (context, child) {
            return Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A).withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: AppTheme.accentIndigo.withValues(alpha: 0.4),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.accentIndigo.withValues(alpha: 0.1),
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Subtle Watermark QR Icon in center
                  Icon(
                    Icons.qr_code_2_rounded,
                    size: 96,
                    color: Colors.white.withValues(alpha: 0.08),
                  ),

                  // 4 High-tech Corner Brackets
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _CornerBracketPainter(
                        color: AppTheme.accentIndigo,
                        bracketLength: 28,
                        strokeWidth: 3.5,
                      ),
                    ),
                  ),

                  // Animated Scanning Laser Beam
                  Positioned(
                    top: 250 * _laserAnimation.value,
                    left: 20,
                    right: 20,
                    child: Container(
                      height: 2,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            AppTheme.accentCyan,
                            Colors.white,
                            AppTheme.accentCyan,
                            Colors.transparent,
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.accentCyan.withValues(alpha: 0.8),
                            blurRadius: 10,
                            spreadRadius: 1.5,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),

        const SizedBox(height: 24),

        // Title
        const Text(
          'READY TO SCAN',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
            color: Colors.white,
          ),
        ),

        const SizedBox(height: 6),

        // Subtitle
        const Text(
          'Aim Zebra hardware scanner or camera at badge',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),

        const SizedBox(height: 16),

        // Hardware Scanner Ready Pill
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: AppTheme.surfaceElevated,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppTheme.statusSuccess.withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.statusSuccess,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.statusSuccess,
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Hardware Barcode Engine Active',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ],
    ).animate().fadeIn(duration: 200.ms);
  }

  // ── 2B. Processing Card ───────────────────────────────────────────
  Widget _buildProcessingCard(ScannerProcessingState procState) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppTheme.accentIndigo.withValues(alpha: 0.6),
          width: 2,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 54,
            height: 54,
            child: CircularProgressIndicator(
              strokeWidth: 4,
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.accentIndigo),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'VERIFYING ADMISSION...',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Token: ${procState.tokenSnippet}',
            style: const TextStyle(
              fontSize: 13,
              fontFamily: 'monospace',
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 150.ms).scale(begin: const Offset(0.95, 0.95));
  }

  // ── 2C. Clean Decision Card ───────────────────────────────────────
  Widget _buildDecisionCard(ScannerDecisionState decState) {
    Color cardColor;
    Color accentColor;
    IconData iconData;
    String headline;

    if (decState.isSuccess) {
      accentColor = AppTheme.statusSuccess;
      cardColor = AppTheme.statusSuccessBg;
      iconData = Icons.check_circle_rounded;
      headline = decState.response.message ?? 'Checked In Successfully!';
    } else if (decState.isWarning) {
      accentColor = AppTheme.statusWarning;
      cardColor = AppTheme.statusWarningBg;
      iconData = Icons.warning_amber_rounded;
      headline = decState.response.message ?? 'Already Checked In';
    } else {
      accentColor = AppTheme.statusRejected;
      cardColor = AppTheme.statusRejectedBg;
      iconData = Icons.cancel_rounded;
      headline = decState.response.message ?? 'Access Denied';
    }

    final attendee = decState.response.attendee;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 26),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accentColor, width: 2),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.25),
            blurRadius: 24,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Hero Icon
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accentColor.withValues(alpha: 0.15),
              border: Border.all(
                color: accentColor.withValues(alpha: 0.4),
                width: 2,
              ),
            ),
            child: Icon(iconData, size: 52, color: accentColor),
          ),

          const SizedBox(height: 16),

          // Status Headline
          Text(
            headline,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
              color: accentColor,
            ),
          ),

          const SizedBox(height: 12),

          // Attendee Details (If Granted or Valid Attendee)
          if (attendee != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: accentColor.withValues(alpha: 0.3)),
              ),
              child: Column(
                children: [
                  // Attendee Name
                  Text(
                    attendee.fullName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),

                  const SizedBox(height: 6),

                  // Badge Category Pill
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: accentColor.withValues(alpha: 0.6),
                      ),
                    ),
                    child: Text(
                      attendee.badgeType.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: accentColor,
                      ),
                    ),
                  ),

                  if (attendee.company != null &&
                      attendee.company!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      attendee.company!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ] else ...[
            // Rejection / Warning Note
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Token: ${decState.request.qrToken}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: AppTheme.textMuted,
                ),
              ),
            ),
          ],

          const SizedBox(height: 18),

          // Dismiss / Next Button
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              onPressed: widget.onResetToReady,
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: const Text(
                'Ready For Next Attendee',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor:
                    decState.isSuccess ? Colors.black : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 180.ms).scale(begin: const Offset(0.92, 0.92));
  }

  // ── 3. Simple Footer ─────────────────────────────────────────────
  Widget _buildFooter(bool isCheckIn) {
    final telemetry = widget.state.telemetry;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          top: BorderSide(color: AppTheme.surfaceBorder, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Total Checked In Counter
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.statusSuccess.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppTheme.statusSuccess.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.how_to_reg_rounded,
                  size: 16,
                  color: AppTheme.statusSuccess,
                ),
                const SizedBox(width: 6),
                Text(
                  '${telemetry.acceptedCount} Checked In',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.statusSuccess,
                  ),
                ),
              ],
            ),
          ),

          const Spacer(),

          // Quick Button to Switch to Advanced Kiosk HUD
          TextButton.icon(
            onPressed: widget.onToggleMode,
            icon: const Icon(Icons.tune_rounded, size: 16, color: AppTheme.accentIndigo),
            label: const Text(
              'Advanced HUD',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.accentIndigo,
              ),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              backgroundColor: AppTheme.accentIndigo.withValues(alpha: 0.1),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom painter for the 4 stylish corner brackets on the simple scanner viewfinder.
class _CornerBracketPainter extends CustomPainter {
  final Color color;
  final double bracketLength;
  final double strokeWidth;

  const _CornerBracketPainter({
    required this.color,
    required this.bracketLength,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;
    final l = bracketLength;

    // Top-Left
    canvas.drawLine(Offset(0, l), const Offset(0, 0), paint);
    canvas.drawLine(const Offset(0, 0), Offset(l, 0), paint);

    // Top-Right
    canvas.drawLine(Offset(w - l, 0), Offset(w, 0), paint);
    canvas.drawLine(Offset(w, 0), Offset(w, l), paint);

    // Bottom-Left
    canvas.drawLine(Offset(0, h - l), Offset(0, h), paint);
    canvas.drawLine(Offset(0, h), Offset(l, h), paint);

    // Bottom-Right
    canvas.drawLine(Offset(w - l, h), Offset(w, h), paint);
    canvas.drawLine(Offset(w, h), Offset(w, h - l), paint);
  }

  @override
  bool shouldRepaint(covariant _CornerBracketPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.bracketLength != bracketLength ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
