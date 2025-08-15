import 'package:flutter/material.dart';

class PulsingAuroraIcon extends StatefulWidget {
  const PulsingAuroraIcon({super.key});

  @override
  State<PulsingAuroraIcon> createState() => PulsingAuroraIconState();
}

class PulsingAuroraIconState extends State<PulsingAuroraIcon> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);

    _scale = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: const Text(
        '🌌',
        style: TextStyle(
          fontSize: 32,
          shadows: [
            Shadow(color: Colors.amber, blurRadius: 40),
            Shadow(color: Colors.orange, blurRadius: 20),
          ],
        ),
      ),
    );
  }
} 