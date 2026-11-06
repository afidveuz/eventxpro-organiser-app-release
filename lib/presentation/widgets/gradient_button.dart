import 'package:flutter/material.dart';
import '../../core/config/app_constants.dart';
import '../../core/theme/app_theme.dart';

class GradientButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isFade;
  final bool isRound;
  final bool sm;
  final double? width;
  final IconData? icon;
  final Gradient? gradient;
  final Color? color;
  final Color? shadowColor;

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
    this.gradient,
    this.color,
    this.shadowColor,
  });

  @override
  Widget build(BuildContext context) {
    final height = sm ? 40.0 : 48.0;
    final borderRadius = BorderRadius.circular(isRound ? 50.0 : 12.0);
    final isDisabled = onPressed == null && !isLoading;

    final resolvedGradient = gradient ??
        (color != null
            ? (color == AppTheme.accentIndigo
                ? AppTheme.indigoGradient
                : LinearGradient(colors: [color!, color!]))
            : null);

    final effectiveGradient = isFade
        ? null
        : (isDisabled
            ? (resolvedGradient is LinearGradient
                ? LinearGradient(
                    colors: resolvedGradient.colors
                        .map((c) => c.withValues(alpha: 0.5))
                        .toList(),
                    begin: resolvedGradient.begin,
                    end: resolvedGradient.end,
                  )
                : LinearGradient(
                    colors: [
                      AppTheme.brandGradientStart.withValues(alpha: 0.5),
                      AppTheme.brandGradientEnd.withValues(alpha: 0.5),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ))
            : (resolvedGradient ?? AppTheme.brandGradient));

    final effectiveShadowColor = shadowColor ??
        (resolvedGradient is LinearGradient && resolvedGradient.colors.isNotEmpty
            ? resolvedGradient.colors.first.withValues(alpha: 0.35)
            : (color != null
                ? color!.withValues(alpha: 0.35)
                : AppTheme.brandGradientStart.withValues(alpha: 0.35)));

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
              color: isFade
                  ? (isDisabled
                      ? AppConstants.brandGrey.withValues(alpha: 0.5)
                      : AppConstants.brandGrey)
                  : (effectiveGradient == null ? AppConstants.brandAccent : null),
              gradient: effectiveGradient,
              borderRadius: borderRadius,
              boxShadow: isFade || isDisabled
                  ? null
                  : [
                      BoxShadow(
                        color: effectiveShadowColor,
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
