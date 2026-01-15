import 'package:flutter/material.dart';
import 'dart:math';

/// Draws a compass rose overlay with direction labels
/// This helps the AI understand which direction is which on the map
class CompassRoseOverlay extends StatelessWidget {
  final double size;
  final bool show16Directions; // 16 directions (N, NNE, NE...) or 8 (N, NE, E...)
  final Color lineColor;
  final Color labelColor;
  final double labelFontSize;
  
  const CompassRoseOverlay({
    super.key,
    this.size = 300,
    this.show16Directions = true,
    this.lineColor = Colors.white,
    this.labelColor = Colors.white,
    this.labelFontSize = 14,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _CompassRosePainter(
          show16Directions: show16Directions,
          lineColor: lineColor,
          labelColor: labelColor,
          labelFontSize: labelFontSize,
        ),
        child: Center(
          child: _buildCenterMarker(),
        ),
      ),
    );
  }

  Widget _buildCenterMarker() {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: Colors.blue,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.5),
            blurRadius: 10,
            spreadRadius: 3,
          ),
        ],
      ),
    );
  }
}

class _CompassRosePainter extends CustomPainter {
  final bool show16Directions;
  final Color lineColor;
  final Color labelColor;
  final double labelFontSize;

  // 16-point compass directions
  static const List<String> directions16 = [
    'N', 'NNE', 'NE', 'ENE',
    'E', 'ESE', 'SE', 'SSE',
    'S', 'SSW', 'SW', 'WSW',
    'W', 'WNW', 'NW', 'NNW',
  ];

  // 8-point compass directions
  static const List<String> directions8 = [
    'N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW',
  ];

  _CompassRosePainter({
    required this.show16Directions,
    required this.lineColor,
    required this.labelColor,
    required this.labelFontSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 - 30; // Leave room for labels
    final innerRadius = 25.0; // Circle around center dot

    final directions = show16Directions ? directions16 : directions8;
    final angleStep = 360 / directions.length;

    // Draw inner circle around user location
    final circlePaint = Paint()
      ..color = lineColor.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    
    canvas.drawCircle(center, innerRadius, circlePaint);

    // Draw each direction line and label
    for (int i = 0; i < directions.length; i++) {
      final direction = directions[i];
      // Angle: 0° = North (up), clockwise
      final angleDeg = i * angleStep;
      final angleRad = (angleDeg - 90) * pi / 180; // -90 to start from top

      // Determine if this is a primary direction (N, E, S, W)
      final isPrimary = ['N', 'E', 'S', 'W'].contains(direction);
      // Secondary: NE, SE, SW, NW
      final isSecondary = ['NE', 'SE', 'SW', 'NW'].contains(direction);

      // Line thickness and style based on importance
      final linePaint = Paint()
        ..color = lineColor.withOpacity(isPrimary ? 0.9 : isSecondary ? 0.7 : 0.5)
        ..strokeWidth = isPrimary ? 3 : isSecondary ? 2 : 1
        ..style = PaintingStyle.stroke;

      // Calculate line endpoints
      final startX = center.dx + innerRadius * cos(angleRad);
      final startY = center.dy + innerRadius * sin(angleRad);
      final endX = center.dx + radius * cos(angleRad);
      final endY = center.dy + radius * sin(angleRad);

      // Draw line
      canvas.drawLine(
        Offset(startX, startY),
        Offset(endX, endY),
        linePaint,
      );

      // Draw label
      final labelRadius = radius + 15;
      final labelX = center.dx + labelRadius * cos(angleRad);
      final labelY = center.dy + labelRadius * sin(angleRad);

      final textPainter = TextPainter(
        text: TextSpan(
          text: direction,
          style: TextStyle(
            color: labelColor.withOpacity(isPrimary ? 1.0 : 0.8),
            fontSize: isPrimary ? labelFontSize + 2 : labelFontSize,
            fontWeight: isPrimary ? FontWeight.bold : FontWeight.normal,
            shadows: [
              Shadow(
                color: Colors.black,
                blurRadius: 4,
                offset: const Offset(1, 1),
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      );

      textPainter.layout();
      
      // Center the text on the label position
      final textOffset = Offset(
        labelX - textPainter.width / 2,
        labelY - textPainter.height / 2,
      );

      textPainter.paint(canvas, textOffset);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
