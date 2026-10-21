import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class ReadyScannerTarget extends StatefulWidget {
  final String statusText;
  final String adapterName;

  const ReadyScannerTarget({
    super.key,
    required this.statusText,
    required this.adapterName,
  });

  @override
  State<ReadyScannerTarget> createState() => _ReadyScannerTargetState();
}

class _ReadyScannerTargetState extends State<ReadyScannerTarget>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _glowAnimation = Tween<double>(begin: 0.25, end: 0.85).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          decoration: BoxDecoration(
            color: AppTheme.surfaceElevated.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: AppTheme.accentIndigo.withValues(alpha: _glowAnimation.value),
              width: 2.0,
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.accentIndigo.withValues(alpha: 0.15 * _glowAnimation.value),
                blurRadius: 32,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Reticle / Scanner Frame
              Stack(
                alignment: Alignment.center,
                children: [
                  // Outer Pulsing Ring
                  Container(
                    width: 170,
                    height: 170,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppTheme.accentIndigo.withValues(alpha: 0.2 * _glowAnimation.value),
                        width: 3,
                      ),
                    ),
                  ),

                  // Scanner Target Icon
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.surface,
                      border: Border.all(
                        color: AppTheme.accentIndigo.withValues(alpha: _glowAnimation.value),
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.qr_code_scanner_rounded,
                      size: 64,
                      color: AppTheme.accentIndigo,
                    ),
                  ),

                  // Red Laser Line Simulation
                  Positioned(
                    top: 25 + (_pulseController.value * 120),
                    child: Container(
                      width: 140,
                      height: 2,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            Colors.transparent,
                            Color(0xFFFF1744),
                            Color(0xFFFF1744),
                            Colors.transparent,
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFF1744).withValues(alpha: 0.8),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 28),

              // Ready status text
              Text(
                widget.statusText.toUpperCase(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.0,
                  color: AppTheme.textPrimary,
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                'Aim scanner at badge QR code. Direct hardware ingestion active.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textSecondary,
                ),
              ),

              const SizedBox(height: 18),

              // Zero TextField Indicator
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.keyboard_hide_outlined, size: 14, color: Color(0xFF38BDF8)),
                    SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Hardware Broadcast Engine Ready',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF38BDF8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
