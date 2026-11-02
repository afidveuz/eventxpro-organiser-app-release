import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Blinking Offline Mode Button / Badge matching React Native eventxproorganiser Background.jsx:
/// - Background Color: #FF3B30 (danger red)
/// - Padding: Vertical 6, Horizontal 16
/// - Rounded corners: Radius 10
/// - Elevation / Shadow: #FF3B30 with 0.5 opacity, radius 6, offset (0, 2)
/// - Text: 'Offline Mode' (white, 14pt, FontWeight.w600)
/// - Blinking effect: Opacity looping between 1.0 and 0.2 with 600ms timing
class BlinkingOfflineButton extends StatefulWidget {
  final VoidCallback? onTap;
  final String text;
  final bool showIcon;
  final Duration duration;
  final double minOpacity;
  final EdgeInsetsGeometry? padding;
  final double fontSize;

  const BlinkingOfflineButton({
    super.key,
    this.onTap,
    this.text = 'Offline Mode',
    this.showIcon = false,
    this.duration = const Duration(milliseconds: 600),
    this.minOpacity = 0.2,
    this.padding,
    this.fontSize = 13.5,
  });

  @override
  State<BlinkingOfflineButton> createState() => _BlinkingOfflineButtonState();
}

class _BlinkingOfflineButtonState extends State<BlinkingOfflineButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacityAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    )..repeat(reverse: true);

    _opacityAnim = Tween<double>(
      begin: 1.0,
      end: widget.minOpacity,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: FadeTransition(
        opacity: _opacityAnim,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap != null
                ? () {
                    HapticFeedback.lightImpact();
                    widget.onTap!();
                  }
                : null,
            borderRadius: BorderRadius.circular(10),
            splashColor: Colors.white24,
            highlightColor: Colors.white10,
            child: Container(
              padding: widget.padding ??
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFF3B30),
                borderRadius: BorderRadius.circular(10),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x80FF3B30),
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (widget.showIcon) ...[
                    const Icon(
                      Icons.wifi_off_rounded,
                      size: 13,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 5),
                  ],
                  Text(
                    widget.text,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: widget.fontSize,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
