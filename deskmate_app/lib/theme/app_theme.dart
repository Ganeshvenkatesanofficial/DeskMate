import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Light Theme Palette
  static const lightBackground = Color(0xFFFFFFFF);
  static const lightSurface = Color(0xFFF6F8FA);
  static const lightText = Color(0xFF24292F);
  static const lightPrimaryBlue = Color(0xFF0969DA);

  // Dark Theme Palette
  static const darkBackground = Color(0xFF0D1117);
  static const darkSurface = Color(0xFF161B22);
  static const darkText = Color(0xFFC9D1D9);
  static const darkPrimaryBlue = Color(0xFF1F6FEB);

  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: lightBackground,
    colorScheme: const ColorScheme.light(
      primary: lightPrimaryBlue,
      secondary: lightPrimaryBlue,
      surface: lightBackground,
      onPrimary: Colors.white,
      onSurface: lightText,
    ),
    textTheme: GoogleFonts.interTextTheme(
      ThemeData.light().textTheme.apply(
        bodyColor: lightText,
        displayColor: lightText,
      ),
    ),
    cardTheme: const CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
      color: lightSurface,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: lightPrimaryBlue,
        foregroundColor: Colors.white,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: lightSurface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFD0D7DE)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFD0D7DE)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: lightPrimaryBlue, width: 2),
      ),
    ),
  );

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: darkBackground,
    colorScheme: const ColorScheme.dark(
      primary: darkPrimaryBlue,
      secondary: darkPrimaryBlue,
      surface: darkSurface,
      onPrimary: Colors.white,
      onSurface: darkText,
    ),
    textTheme: GoogleFonts.interTextTheme(
      ThemeData.dark().textTheme.apply(
        bodyColor: darkText,
        displayColor: darkText,
      ),
    ),
    cardTheme: const CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
      color: darkSurface,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: darkPrimaryBlue,
        foregroundColor: Colors.white,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF21262D),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF30363D)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF30363D)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: darkPrimaryBlue, width: 2),
      ),
    ),
  );
}
