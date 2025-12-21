import 'package:flutter/material.dart';

/// Reusable logo widget for Aurora Viking Staff branding
class LogoWidget extends StatelessWidget {
  final double? height;
  final double? width;
  final Color? color;
  final BoxFit fit;

  const LogoWidget({
    super.key,
    this.height,
    this.width,
    this.color,
    this.fit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/logowhite.png',
      height: height,
      width: width,
      fit: fit,
      color: color,
      errorBuilder: (context, error, stackTrace) {
        // Debug: Print error to help diagnose
        debugPrint('Logo asset error: $error');
        // Fallback if logo not found
        return Icon(
          Icons.directions_bus,
          size: height ?? 40,
          color: color ?? Colors.white,
        );
      },
    );
  }
}

/// Small logo for app bars and headers - bigger and bolder
class LogoSmall extends StatelessWidget {
  const LogoSmall({super.key});

  @override
  Widget build(BuildContext context) {
    return const LogoWidget(height: 112, width: 112);
  }
}

/// Medium logo for cards and dialogs
class LogoMedium extends StatelessWidget {
  const LogoMedium({super.key});

  @override
  Widget build(BuildContext context) {
    return const LogoWidget(height: 64, width: 64);
  }
}

/// Large logo for login and splash screens
class LogoLarge extends StatelessWidget {
  const LogoLarge({super.key});

  @override
  Widget build(BuildContext context) {
    return const LogoWidget(height: 120, width: 120);
  }
}

/// Animated logo with breathing/pulsing effect for loading screens
class LogoBreathing extends StatefulWidget {
  final double baseSize;
  final Duration duration;
  final double minScale;
  final double maxScale;

  const LogoBreathing({
    super.key,
    this.baseSize = 120,
    this.duration = const Duration(seconds: 2),
    this.minScale = 0.85,
    this.maxScale = 1.0,
  });

  @override
  State<LogoBreathing> createState() => _LogoBreathingState();
}

class _LogoBreathingState extends State<LogoBreathing>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(
      begin: widget.minScale,
      end: widget.maxScale,
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
    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: LogoWidget(
            height: widget.baseSize,
            width: widget.baseSize,
          ),
        );
      },
    );
  }
}

