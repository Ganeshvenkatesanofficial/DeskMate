import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// GitHub Primer Dark Default Color System Tokens
class AppTheme {
  // Backgrounds
  static const Color bgCanvas = Color(0xFF0D1117);
  static const Color bgSubtle = Color(0xFF161B22);
  static const Color bgInset = Color(0xFF010409);
  static const Color bgEmphasis = Color(0xFF21262D);
  static const Color bgOverlay = Color(0xFF1C2128);

  // Text
  static const Color fgDefault = Color(0xFFE6EDF3);
  static const Color fgMuted = Color(0xFF7D8590);
  static const Color fgSubtle = Color(0xFF6E7681);
  static const Color fgDisabled = Color(0xFF484F58);

  // Borders
  static const Color borderDefault = Color(0xFF30363D);
  static const Color borderMuted = Color(0xFF21262D);

  // Accents & Semantics
  static const Color accentFg = Color(0xFF2F81F7);
  static const Color accentEmphasis = Color(0xFF1F6FEB);
  static const Color successFg = Color(0xFF3FB950);
  static const Color successEmphasis = Color(0xFF238636);
  static const Color attentionFg = Color(0xFFD29922);
  static const Color dangerFg = Color(0xFFF85149);
  static const Color dangerEmphasis = Color(0xFFDA3633);
  static const Color dangerBg = Color(0x1AF85149); // rgba(248, 81, 73, 0.10)
  static const Color dangerBorder = Color(0x66F85149); // rgba(248, 81, 73, 0.40)


  // Standard Dark Theme (GitHub Primer Dark Default)
  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: bgCanvas,
    canvasColor: bgCanvas,
    cardColor: bgSubtle,
    dividerColor: borderDefault,
    colorScheme: const ColorScheme.dark(
      primary: accentFg,
      secondary: accentEmphasis,
      surface: bgSubtle,
      onPrimary: Colors.white,
      onSurface: fgDefault,
      error: dangerFg,
      outline: borderDefault,
    ),
    textTheme: GoogleFonts.interTextTheme(
      ThemeData.dark().textTheme.apply(
        bodyColor: fgDefault,
        displayColor: fgDefault,
      ),
    ),
    cardTheme: const CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(6)),
        side: BorderSide(color: borderDefault, width: 1),
      ),
      color: bgSubtle,
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: bgOverlay,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(6)),
        side: BorderSide(color: borderDefault, width: 1),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: const BorderSide(color: accentEmphasis, width: 1),
        ),
        backgroundColor: accentEmphasis,
        foregroundColor: Colors.white,
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        side: const BorderSide(color: borderDefault, width: 1),
        backgroundColor: bgEmphasis,
        foregroundColor: fgDefault,
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: bgInset,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      hintStyle: const TextStyle(color: fgMuted, fontSize: 13),
      labelStyle: const TextStyle(color: fgMuted, fontSize: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: borderDefault, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: borderDefault, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: accentFg, width: 1.5),
      ),
    ),
  );

  // Light Theme mapped to GitHub Primer Light for full system completeness
  static ThemeData lightTheme = darkTheme;
}
