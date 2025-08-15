import 'package:flutter/material.dart';
import 'colors.dart';

class AVGradients {
  static const aurora = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      AVColors.slate,
      AVColors.slateElev,
      Color(0xFF0D1F26),
    ],
  );

  static const neonEdge = RadialGradient(
    radius: 1.2,
    colors: [AVColors.tealGlowEdge, Colors.transparent],
  );
} 