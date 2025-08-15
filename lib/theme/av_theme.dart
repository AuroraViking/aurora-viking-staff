import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';
import 'colors.dart';
import 'typography.dart';

class GlowTheme extends ThemeExtension<GlowTheme> {
  final double glowBlur;
  final double glowSpread;
  final Color glowColor;

  const GlowTheme({
    this.glowBlur = 18,
    this.glowSpread = 0.5,
    this.glowColor = AVColors.tealGlowEdge,
  });

  @override
  GlowTheme copyWith({double? glowBlur, double? glowSpread, Color? glowColor}) =>
      GlowTheme(
        glowBlur: glowBlur ?? this.glowBlur,
        glowSpread: glowSpread ?? this.glowSpread,
        glowColor: glowColor ?? this.glowColor,
      );

  @override
  ThemeExtension<GlowTheme> lerp(ThemeExtension<GlowTheme>? other, double t) {
    if (other is! GlowTheme) return this;
    return GlowTheme(
      glowBlur: lerpDouble(glowBlur, other.glowBlur, t)!,
      glowSpread: lerpDouble(glowSpread, other.glowSpread, t)!,
      glowColor: Color.lerp(glowColor, other.glowColor, t)!,
    );
  }
}

ThemeData avTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AVColors.primaryTeal,
    brightness: Brightness.dark,
    primary: AVColors.primaryTeal,
    secondary: AVColors.auroraGreen,
    surface: AVColors.slate,
    background: AVColors.scaffold,
    error: AVColors.forgeRed,
    onPrimary: AVColors.obsidian,
    onSurface: AVColors.textHigh,
    onBackground: AVColors.textHigh,
  );

  final text = AVTypography.textTheme(AVColors.textHigh);

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: AVColors.scaffold,
    textTheme: text,
    extensions: const [GlowTheme()],
    visualDensity: VisualDensity.comfortable,

    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: AVColors.primaryTeal,
      selectionColor: AVColors.tealGlowMid,
      selectionHandleColor: AVColors.primaryTeal,
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ButtonStyle(
        padding: const MaterialStatePropertyAll(EdgeInsets.symmetric(horizontal: 20, vertical: 14)),
        shape: MaterialStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
        overlayColor: MaterialStateProperty.resolveWith((s) => s.contains(MaterialState.pressed) ? AVColors.tealGlowMid.withOpacity(.15) : null),
        elevation: const MaterialStatePropertyAll(0),
        backgroundColor: const MaterialStatePropertyAll(AVColors.slateElev),
        foregroundColor: const MaterialStatePropertyAll(AVColors.textHigh),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AVColors.slateElev,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AVColors.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AVColors.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AVColors.primaryTeal, width: 1.6),
      ),
      hintStyle: const TextStyle(color: AVColors.textLow),
      labelStyle: const TextStyle(color: AVColors.textLow),
    ),

    cardTheme: const CardThemeData(
      color: AVColors.slate,
      elevation: 0,
      margin: EdgeInsets.all(12),
    ),

    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AVColors.slateElev,
      contentTextStyle: TextStyle(color: AVColors.textHigh),
    ),

    popupMenuTheme: const PopupMenuThemeData(
      color: AVColors.slate,
      surfaceTintColor: AVColors.slate,
      textStyle: TextStyle(color: AVColors.textHigh),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
      elevation: 6,
    ),
  );
} 