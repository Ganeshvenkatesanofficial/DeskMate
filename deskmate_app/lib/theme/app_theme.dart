import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Display a dialog with the signature DeskMate frosted-glass blurred backdrop (matches Reasoning modal)
Future<T?> showBlurredDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final effectiveBarrierColor =
      barrierColor ??
      (isDark ? const Color(0x66010409) : const Color(0x401F2328));
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: effectiveBarrierColor,
    builder: (ctx) => BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 4.5, sigmaY: 4.5),
      child: builder(ctx),
    ),
  );
}

/// GitHub Primer Design System Tokens & DeskMate Purple Theme
class AppTheme {
  // --- DESKMATE SIGNATURE PURPLE ACCENT TOKENS ---
  static const Color purplePrimary = Color(0xFF6A35F5);
  static const Color purpleMid = Color(0xFF7C49F6);
  static const Color purpleLight = Color(0xFF8E67F6);
  static const Color purpleHover = Color(0xFF7C49F6);
  static const Color purpleActive = Color(0xFF5B24E8);
  static const Color purpleHighlight = Color(0xFFA78BFA);
  static const Color purpleMuted = Color(0x1F6A35F5);
  static const Color purpleBorder = Color(0x4D6A35F5);
  static const Color purpleFocusRing = Color(0x4D6A35F5);

  static const LinearGradient purpleGradient = LinearGradient(
    colors: [Color(0xFF6A35F5), Color(0xFF7C49F6), Color(0xFF8E67F6)],
    stops: [0.0, 0.5, 1.0],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  // Meeting / domain semantic colors
  static const Color emerald = Color(0xFF10B981);
  static const Color emeraldLight = Color(0xFF34D399);
  static const Color amber = Color(0xFFF59E0B);
  static const Color amberLight = Color(0xFFFBBF24);
  static const Color recordingRed = Color(0xFFDC2626);
  static const Color recordingRedLight = Color(0xFFF87171);
  static const Color teal = Color(0xFF0D9488);

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

  static const Color lightAccentFg = purplePrimary;
  static const Color lightAccentEmphasis = purplePrimary;
  static const Color lightAccentHover = purpleHover;
  static const Color lightSuccessFg = Color(0xFF1A7F37);
  static const Color lightSuccessEmphasis = Color(0xFF1F883D);
  static const Color lightAttentionFg = Color(0xFF9A6700);
  static const Color lightDangerFg = Color(0xFFD1242F);
  static const Color lightDangerBg = Color(0x14D1242F);
  static const Color lightDangerBorder = Color(0x4DD1242F);

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

  static const Color darkAccentFg = purpleLight;
  static const Color darkAccentEmphasis = purplePrimary;
  static const Color darkAccentHover = purpleLight;
  static const Color darkSuccessFg = Color(0xFF3FB950);
  static const Color darkSuccessEmphasis = Color(0xFF238636);
  static const Color darkAttentionFg = Color(0xFFD29922);
  static const Color darkDangerFg = Color(0xFFF85149);
  static const Color darkDangerBg = Color(0x1AF85149);
  static const Color darkDangerBorder = Color(0x66F85149);

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
        enabledMouseCursor: SystemMouseCursors.click,
        disabledMouseCursor: SystemMouseCursors.basic,
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
        enabledMouseCursor: SystemMouseCursors.click,
        disabledMouseCursor: SystemMouseCursors.basic,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        side: const BorderSide(color: lightBorderDefault, width: 1),
        backgroundColor: lightBgSubtle,
        foregroundColor: lightFgDefault,
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        enabledMouseCursor: SystemMouseCursors.click,
        disabledMouseCursor: SystemMouseCursors.basic,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        enabledMouseCursor: SystemMouseCursors.click,
        disabledMouseCursor: SystemMouseCursors.basic,
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
        enabledMouseCursor: SystemMouseCursors.click,
        disabledMouseCursor: SystemMouseCursors.basic,
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
        enabledMouseCursor: SystemMouseCursors.click,
        disabledMouseCursor: SystemMouseCursors.basic,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        side: const BorderSide(color: darkBorderDefault, width: 1),
        backgroundColor: darkBgEmphasis,
        foregroundColor: darkFgDefault,
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        enabledMouseCursor: SystemMouseCursors.click,
        disabledMouseCursor: SystemMouseCursors.basic,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        enabledMouseCursor: SystemMouseCursors.click,
        disabledMouseCursor: SystemMouseCursors.basic,
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
        borderSide: const BorderSide(color: purpleLight, width: 1.5),
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
  Color get accentHover => isDark ? AppTheme.purpleLight : AppTheme.purpleHover;
  Color get accentActive => AppTheme.purpleActive;
  Color get accentHighlight => AppTheme.purpleHighlight;
  Color get accentMuted =>
      isDark ? const Color(0x336A35F5) : const Color(0x1F6A35F5);
  Color get accentBorder =>
      isDark ? const Color(0x668E67F6) : const Color(0x4D6A35F5);
  Color get accentFocus =>
      isDark ? const Color(0x668E67F6) : const Color(0x4D6A35F5);
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

  // Panel / code block backgrounds (replaces hardcoded 0xFF161B22 / 0xFFF6F8FA)
  Color get bgPanel =>
      isDark ? const Color(0xFF161B22) : const Color(0xFFF6F8FA);
  Color get bgCode =>
      isDark ? const Color(0xFF0D1117) : const Color(0xFFF6F8FA);

  // Success text on dark/light (replaces hardcoded 0xFF7EE787 / 0xFF1A7F37 ternaries)
  Color get successText =>
      isDark ? const Color(0xFF7EE787) : const Color(0xFF1A7F37);

  // Status pill convenience
  Color get statusOk => const Color(0xFF2DA44E);
  Color get statusBad =>
      isDark ? AppTheme.darkDangerFg : AppTheme.lightDangerFg;
}
