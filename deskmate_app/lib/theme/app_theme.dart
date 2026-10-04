import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// GitHub Primer Design System Tokens (Dark Default & Light Default with DeskMate Purple Accent)
class AppTheme {
  // --- PURPLE BRAND ACCENT TOKENS ---
  static const Color purplePrimary = Color(0xFF6A35F5);
  static const Color purpleMid = Color(0xFF7C49F6);
  static const Color purpleLight = Color(0xFF8E67F6);
  static const Color purpleHover = Color(0xFF8E67F6);
  static const Color purpleActive = Color(0xFF5B24E8);
  static const Color purpleHighlight = Color(0xFFA78BFA);
  static const Color purpleMuted = Color(
    0x266A35F5,
  ); // rgba(106, 53, 245, 0.15)
  static const Color purpleBorder = Color(
    0x666A35F5,
  ); // rgba(106, 53, 245, 0.40)
  static const Color purpleFocusRing = Color(
    0x4D6A35F5,
  ); // rgba(106, 53, 245, 0.30)

  static const LinearGradient purpleGradient = LinearGradient(
    colors: [Color(0xFF6A35F5), Color(0xFF7C49F6), Color(0xFF8E67F6)],
    stops: [0.0, 0.5, 1.0],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  // --- GITHUB PRIMER LIGHT DEFAULT TOKENS ---
  static const Color lightBgCanvas = Color(0xFFFFFFFF);
  static const Color lightBgSubtle = Color(0xFFF6F8FA);
  static const Color lightBgInset = Color(0xFFEAEEF2);
  static const Color lightBgEmphasis = Color(0xFFD0D7DE);
  static const Color lightBgOverlay = Color(0xFFFFFFFF);

  static const Color lightFgDefault = Color(0xFF1F2328);
  static const Color lightFgMuted = Color(0xFF656D76);
  static const Color lightFgSubtle = Color(0xFF6E7781);
  static const Color lightFgDisabled = Color(0xFF8C959F);

  static const Color lightBorderDefault = Color(0xFFD0D7DE);
  static const Color lightBorderMuted = Color(0xFF8C959F);

  static const Color lightAccentFg = Color(0xFF6A35F5);
  static const Color lightAccentEmphasis = Color(0xFF6A35F5);
  static const Color lightAccentHover = Color(0xFF5B24E8);
  static const Color lightSuccessFg = Color(0xFF1A7F37);
  static const Color lightSuccessEmphasis = Color(0xFF1F883D);
  static const Color lightAttentionFg = Color(0xFF9A6700);
  static const Color lightDangerFg = Color(0xFFD1242F);
  static const Color lightDangerBg = Color(
    0x14D1242F,
  ); // rgba(209, 36, 47, 0.08)
  static const Color lightDangerBorder = Color(
    0x4DD1242F,
  ); // rgba(209, 36, 47, 0.30)

  // --- GITHUB PRIMER DARK DEFAULT TOKENS ---
  static const Color darkBgCanvas = Color(0xFF0D1117);
  static const Color darkBgSubtle = Color(0xFF161B22);
  static const Color darkBgInset = Color(0xFF010409);
  static const Color darkBgEmphasis = Color(0xFF21262D);
  static const Color darkBgOverlay = Color(0xFF161B22);

  static const Color darkFgDefault = Color(0xFFE6EDF3);
  static const Color darkFgMuted = Color(0xFF8B949E);
  static const Color darkFgSubtle = Color(0xFF6E7681);
  static const Color darkFgDisabled = Color(0xFF484F58);

  static const Color darkBorderDefault = Color(0xFF30363D);
  static const Color darkBorderMuted = Color(0xFF21262D);
  static const Color darkBorderStrong = Color(0xFF484F58);

  static const Color darkAccentFg = Color(0xFF8E67F6);
  static const Color darkAccentEmphasis = Color(0xFF6A35F5);
  static const Color darkAccentHover = Color(0xFF8E67F6);
  static const Color darkSuccessFg = Color(0xFF3FB950);
  static const Color darkSuccessEmphasis = Color(0xFF238636);
  static const Color darkAttentionFg = Color(0xFFD29922);
  static const Color darkDangerFg = Color(0xFFF85149);
  static const Color darkDangerBg = Color(
    0x1AF85149,
  ); // rgba(248, 81, 73, 0.10)
  static const Color darkDangerBorder = Color(
    0x66F85149,
  ); // rgba(248, 81, 73, 0.40)

  // --- GITHUB PRIMER LIGHT THEME ---
  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: lightBgCanvas,
    canvasColor: lightBgCanvas,
    cardColor: lightBgSubtle,
    dividerColor: lightBorderDefault,
    colorScheme: const ColorScheme.light(
      primary: purplePrimary,
      secondary: purpleMid,
      surface: lightBgSubtle,
      onPrimary: Colors.white,
      onSurface: lightFgDefault,
      error: lightDangerFg,
      outline: lightBorderDefault,
    ),
    textTheme: GoogleFonts.interTextTheme(
      ThemeData.light().textTheme.apply(
        bodyColor: lightFgDefault,
        displayColor: lightFgDefault,
      ),
    ),
    cardTheme: const CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(6)),
        side: BorderSide(color: lightBorderDefault, width: 1),
      ),
      color: lightBgSubtle,
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: lightBgOverlay,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(6)),
        side: BorderSide(color: lightBorderDefault, width: 1),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        backgroundColor: purplePrimary,
        foregroundColor: Colors.white,
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        side: const BorderSide(color: lightBorderDefault, width: 1),
        backgroundColor: lightBgSubtle,
        foregroundColor: lightFgDefault,
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: lightBgCanvas,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      hintStyle: const TextStyle(color: lightFgMuted, fontSize: 13),
      labelStyle: const TextStyle(color: lightFgMuted, fontSize: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: lightBorderDefault, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: lightBorderDefault, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: purplePrimary, width: 1.5),
      ),
    ),
  );

  // --- GITHUB PRIMER DARK THEME ---
  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: darkBgCanvas,
    canvasColor: darkBgCanvas,
    cardColor: darkBgSubtle,
    dividerColor: darkBorderDefault,
    colorScheme: const ColorScheme.dark(
      primary: purplePrimary,
      secondary: purpleLight,
      surface: darkBgSubtle,
      onPrimary: Colors.white,
      onSurface: darkFgDefault,
      error: darkDangerFg,
      outline: darkBorderDefault,
    ),
    textTheme: GoogleFonts.interTextTheme(
      ThemeData.dark().textTheme.apply(
        bodyColor: darkFgDefault,
        displayColor: darkFgDefault,
      ),
    ),
    cardTheme: const CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(6)),
        side: BorderSide(color: darkBorderDefault, width: 1),
      ),
      color: darkBgSubtle,
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: darkBgOverlay,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(6)),
        side: BorderSide(color: darkBorderDefault, width: 1),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        backgroundColor: purplePrimary,
        foregroundColor: Colors.white,
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        side: const BorderSide(color: darkBorderDefault, width: 1),
        backgroundColor: darkBgEmphasis,
        foregroundColor: darkFgDefault,
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: darkBgCanvas,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      hintStyle: const TextStyle(color: darkFgMuted, fontSize: 13),
      labelStyle: const TextStyle(color: darkFgMuted, fontSize: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: darkBorderDefault, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: darkBorderDefault, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: purplePrimary, width: 1.5),
      ),
    ),
  );
}

/// Extension on ThemeData to easily access GitHub Primer semantic color tokens
extension GitHubPrimerTheme on ThemeData {
  bool get isDark => brightness == Brightness.dark;

  Color get bgCanvas => isDark ? AppTheme.darkBgCanvas : AppTheme.lightBgCanvas;
  Color get bgSubtle => isDark ? AppTheme.darkBgSubtle : AppTheme.lightBgSubtle;
  Color get bgInset => isDark ? AppTheme.darkBgInset : AppTheme.lightBgInset;
  Color get bgEmphasis =>
      isDark ? AppTheme.darkBgEmphasis : AppTheme.lightBgEmphasis;
  Color get bgOverlay =>
      isDark ? AppTheme.darkBgOverlay : AppTheme.lightBgOverlay;

  Color get fgDefault =>
      isDark ? AppTheme.darkFgDefault : AppTheme.lightFgDefault;
  Color get fgMuted => isDark ? AppTheme.darkFgMuted : AppTheme.lightFgMuted;
  Color get fgSubtle => isDark ? AppTheme.darkFgSubtle : AppTheme.lightFgSubtle;
  Color get fgDisabled =>
      isDark ? AppTheme.darkFgDisabled : AppTheme.lightFgDisabled;

  Color get borderDefault =>
      isDark ? AppTheme.darkBorderDefault : AppTheme.lightBorderDefault;
  Color get borderMuted =>
      isDark ? AppTheme.darkBorderMuted : AppTheme.lightBorderMuted;
  Color get borderStrong =>
      isDark ? AppTheme.darkBorderStrong : AppTheme.lightBorderMuted;

  Color get accentFg => isDark ? AppTheme.purpleLight : AppTheme.purplePrimary;
  Color get accentEmphasis => AppTheme.purplePrimary;
  Color get accentHover => AppTheme.purpleHover;
  Color get accentActive => AppTheme.purpleActive;
  Color get accentHighlight => AppTheme.purpleHighlight;
  Color get accentMuted => AppTheme.purpleMuted;
  Color get accentBorder => AppTheme.purpleBorder;
  Color get accentFocus => AppTheme.purpleFocusRing;
  LinearGradient get accentGradient => AppTheme.purpleGradient;

  Color get successFg =>
      isDark ? AppTheme.darkSuccessFg : AppTheme.lightSuccessFg;
  Color get successEmphasis =>
      isDark ? AppTheme.darkSuccessEmphasis : AppTheme.lightSuccessEmphasis;
  Color get attentionFg =>
      isDark ? AppTheme.darkAttentionFg : AppTheme.lightAttentionFg;
  Color get dangerFg => isDark ? AppTheme.darkDangerFg : AppTheme.lightDangerFg;
  Color get dangerBg => isDark ? AppTheme.darkDangerBg : AppTheme.lightDangerBg;
  Color get dangerBorder =>
      isDark ? AppTheme.darkDangerBorder : AppTheme.lightDangerBorder;
}
