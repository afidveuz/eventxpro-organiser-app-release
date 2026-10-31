import 'package:flutter/material.dart';

/// A reusable widget that displays an asset background image with a smooth,
/// hardware-accelerated fade-in entrance animation.
///
/// Ensures the animation runs gracefully upon screen mount without re-triggering
/// on subsequent parent [setState] calls.
class FadeInBackgroundImage extends StatefulWidget {
  final String imagePath;
  final BoxFit fit;
  final Duration duration;
  final Duration? delay;
  final Curve curve;
  final Alignment alignment;
  final Widget? fallback;

  const FadeInBackgroundImage({
    super.key,
    this.imagePath = 'assets/images/bg.png',
    this.fit = BoxFit.cover,
    this.duration = const Duration(milliseconds: 800),
    this.delay,
    this.curve = Curves.easeOutCubic,
    this.alignment = Alignment.center,
    this.fallback,
  });

  @override
  State<FadeInBackgroundImage> createState() => _FadeInBackgroundImageState();
}

class _FadeInBackgroundImageState extends State<FadeInBackgroundImage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _opacity = CurvedAnimation(
      parent: _controller,
      curve: widget.curve,
    );

    if (widget.delay != null && widget.delay! > Duration.zero) {
      Future.delayed(widget.delay!, () {
        if (mounted) _controller.forward();
      });
    } else {
      _controller.forward();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Warm up the image cache so rendering during fade is stutter-free
    precacheImage(AssetImage(widget.imagePath), context);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: Image.asset(
        widget.imagePath,
        fit: widget.fit,
        alignment: widget.alignment,
        errorBuilder: (context, error, stackTrace) =>
            widget.fallback ?? const SizedBox.shrink(),
      ),
    );
  }
}
