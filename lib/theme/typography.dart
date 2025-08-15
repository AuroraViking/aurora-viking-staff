import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AVTypography {
  static TextTheme textTheme(Color color) {
    final base = ThemeData.dark().textTheme.apply(
      bodyColor: color,
      displayColor: color,
    );
    return base.copyWith(
      displayLarge: GoogleFonts.orbitron(textStyle: base.displayLarge)?.copyWith(letterSpacing: 0.5),
      headlineMedium: GoogleFonts.orbitron(textStyle: base.headlineMedium)?.copyWith(letterSpacing: 0.25),
      titleLarge: GoogleFonts.orbitron(textStyle: base.titleLarge),
      bodyLarge: GoogleFonts.inter(textStyle: base.bodyLarge),
      bodyMedium: GoogleFonts.inter(textStyle: base.bodyMedium),
      labelLarge: GoogleFonts.inter(textStyle: base.labelLarge),
    );
  }
} 