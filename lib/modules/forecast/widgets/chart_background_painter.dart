import 'package:flutter/material.dart';

class ChartBackgroundPainter extends CustomPainter {
  final double chartHeight;
  final double minY;
  final double maxY;
  final Animation<double> pulseAnimation;
  final double maxBz;

  ChartBackgroundPainter({
    required this.chartHeight,
    required this.minY,
    required this.maxY,
    required this.pulseAnimation,
    required this.maxBz,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final zeroY = _calculateZeroY(size.height);

    // Create gradient for negative area with neon teal glow
    final negativeGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        const Color(0xFF4ECDC4).withOpacity(0.3 + (pulseAnimation.value * 0.2)), // Neon teal
        const Color(0xFF4ECDC4).withOpacity(0.1 + (pulseAnimation.value * 0.1)), // Faded teal
        Colors.transparent,
      ],
      stops: const [0.0, 0.5, 1.0],
    );
    final negativeRect = Rect.fromLTWH(0, zeroY, size.width, size.height - zeroY);
    final negativePaint = Paint()
      ..shader = negativeGradient.createShader(negativeRect);

    // Draw the negative area gradient
    canvas.drawRect(negativeRect, negativePaint);

    // Add neon glow effect for negative area
    final glowPaint = Paint()
      ..color = const Color(0xFF4ECDC4).withOpacity(0.2 + (pulseAnimation.value * 0.3))
      ..maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        15 + (pulseAnimation.value * 10),
      );
    canvas.drawRect(negativeRect, glowPaint);

    // Add additional glow for high Bz values
    if (maxBz.abs() > 1) {
      final intensity = (maxBz.abs() - 1) / 10; // Scale intensity based on Bz
      final extraGlowPaint = Paint()
        ..color = const Color(0xFF4ECDC4).withOpacity(0.1 * intensity * pulseAnimation.value)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          30 + (pulseAnimation.value * 20),
        );
      canvas.drawRect(negativeRect, extraGlowPaint);
    }
  }

  double _calculateZeroY(double height) {
    // If minY and maxY are equal, center the line
    if (minY == maxY) return height / 2;
    
    // Calculate the total range of values
    final totalRange = maxY - minY;
    
    // Calculate how far zero is from the minimum value
    final zeroOffset = 0 - minY;
    
    // Calculate the proportion of the height where zero should be
    final zeroProportion = zeroOffset / totalRange;
    
    // Convert proportion to actual height
    return height * (1 - zeroProportion);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    if (oldDelegate is ChartBackgroundPainter) {
      return oldDelegate.pulseAnimation != pulseAnimation ||
             oldDelegate.maxBz != maxBz;
    }
    return true;
  }
} 