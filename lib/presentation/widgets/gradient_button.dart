import 'package:flutter/material.dart';
import '../../core/config/app_constants.dart';

class GradientButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isFade;
  final bool isRound;
  final bool sm;
  final double? width;
  final IconData? icon;

  const GradientButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.isFade = false,
    this.isRound = true,
    this.sm = false,
    this.width,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final height = sm ? 40.0 : 48.0;
    final borderRadius = BorderRadius.circular(isRound ? 50.0 : 12.0);
    final bgColor = isFade ? AppConstants.brandGrey : AppConstants.brandAccent;

    return SizedBox(
      width: width ?? double.infinity,
      height: height,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: (isLoading || onPressed == null) ? null : onPressed,
          borderRadius: borderRadius,
          child: Ink(
            decoration: BoxDecoration(
              color: (onPressed == null && !isLoading)
                  ? bgColor.withValues(alpha: 0.5)
                  : bgColor,
              borderRadius: borderRadius,
              boxShadow: isFade || onPressed == null
                  ? null
                  : [
                      BoxShadow(
                        color: AppConstants.brandAccent.withValues(alpha: 0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
            ),
            child: Center(
              child: isLoading
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'PLEASE WAIT',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: sm ? 12 : 14,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null) ...[
                          Icon(icon, color: Colors.white, size: sm ? 16 : 18),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          text.toUpperCase(),
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: sm ? 12 : 14,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.0,
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
