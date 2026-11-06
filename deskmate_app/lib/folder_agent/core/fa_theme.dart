import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Folder Agent design tokens.
///
/// The visual language follows the FilDOS design system (MIT, (c) Fahim
/// Ahmed): a black-and-white Ink / Mist / Cloud foundation where six "scoop"
/// accents carry all colour — always as an accent (dot, chip, corner, tag),
/// never as a large fill or body text. AI highlights use Mint. Branding is
/// DeskMate's own (see `widgets/logo.dart`).
abstract final class Scoop {
  static const strawberry = Color(0xFFF26D6D);
  static const bubblegum = Color(0xFFF286B4);
  static const mango = Color(0xFFF9A85C);
  static const blueberry = Color(0xFF6E9BEE);
  static const mint = Color(0xFF4FC9B8);
  static const grape = Color(0xFFA585E0);

  static const all = [strawberry, bubblegum, mango, blueberry, mint, grape];
  static const names = ['Strawberry', 'Bubblegum', 'Mango', 'Blueberry', 'Mint', 'Grape'];

  static Color parse(String? hex, [Color fallback = blueberry]) {
    if (hex == null) return fallback;
    final h = hex.replaceFirst('#', '');
    final v = int.tryParse(h.length == 6 ? 'FF$h' : h, radix: 16);
    return v == null ? fallback : Color(v);
  }

  static String hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

@immutable
class FaColors extends ThemeExtension<FaColors> {
  final Brightness brightness;
  final Color background;
  final Color foreground;
  final Color card;
  final Color popover;
  final Color primary;
  final Color primaryForeground;
  final Color muted;
  final Color mutedForeground;
  final Color accent;
  final Color border;
  final Color destructive;
  final Color success;
  final Color sidebar;
  final Color selection;
  final Color overlay;

  const FaColors({
    required this.brightness,
    required this.background,
    required this.foreground,
    required this.card,
    required this.popover,
    required this.primary,
    required this.primaryForeground,
    required this.muted,
    required this.mutedForeground,
    required this.accent,
    required this.border,
    required this.destructive,
    required this.success,
    required this.sidebar,
    required this.selection,
    required this.overlay,
  });

  bool get isDark => brightness == Brightness.dark;

  static const light = FaColors(
    brightness: Brightness.light,
    background: Color(0xFFFFFFFF),
    foreground: Color(0xFF0F1117),
    card: Color(0xFFFFFFFF),
    popover: Color(0xFFFFFFFF),
    primary: Color(0xFF0F1117),
    primaryForeground: Color(0xFFFFFFFF),
    muted: Color(0xFFF5F5F7),
    mutedForeground: Color(0xFF8A8F9C),
    accent: Color(0xFFF5F5F7),
    border: Color(0xFFE7E7EA),
    destructive: Color(0xFFDC2626),
    success: Color(0xFF16A34A),
    sidebar: Color(0xFFFFFFFF),
    selection: Color(0x260F1117),
    overlay: Color(0x330F1117),
  );

  static const dark = FaColors(
    brightness: Brightness.dark,
    background: Color(0xFF0F1117),
    foreground: Color(0xFFEEF2FB),
    card: Color(0xFF16181F),
    popover: Color(0xFF16181F),
    primary: Color(0xFFEEF2FB),
    primaryForeground: Color(0xFF0F1117),
    muted: Color(0xFF1D2029),
    mutedForeground: Color(0xFF8A8F9C),
    accent: Color(0xFF1D2029),
    border: Color(0xFF262932),
    destructive: Color(0xFFF87171),
    success: Color(0xFF4ADE80),
    sidebar: Color(0xFF0F1117),
    selection: Color(0x26EEF2FB),
    overlay: Color(0x99000000),
  );

  @override
  FaColors copyWith() => this;

  @override
  FaColors lerp(ThemeExtension<FaColors>? other, double t) => t < 0.5 ? this : (other as FaColors? ?? this);
}

/// Text styles: Inter for UI, Space Mono for paths, sizes and other technical text.
abstract final class FaText {
  static TextStyle sans({
    double size = 13,
    FontWeight weight = FontWeight.w400,
    Color? color,
    double? height,
    double letterSpacing = 0,
  }) => GoogleFonts.inter(
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: height,
    letterSpacing: letterSpacing,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  static TextStyle mono({double size = 11, FontWeight weight = FontWeight.w400, Color? color, double? height}) =>
      GoogleFonts.spaceMono(fontSize: size, fontWeight: weight, color: color, height: height);

  /// Uppercase section label ("QUICK ACCESS").
  static TextStyle label(FaColors c) =>
      GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w600, color: c.mutedForeground, letterSpacing: 0.9);
}

abstract final class FaMotion {
  static const snappy = Cubic(0.23, 1, 0.32, 1);
  static const fluid = Cubic(0.77, 0, 0.175, 1);
  static const fast = Duration(milliseconds: 140);
  static const medium = Duration(milliseconds: 240);
}

abstract final class FaRadius {
  static const sm = 6.0;
  static const md = 8.0;
  static const lg = 10.0;
  static const xl = 14.0;
}

extension FaContext on BuildContext {
  FaColors get fa =>
      Theme.of(this).extension<FaColors>() ??
      (Theme.of(this).brightness == Brightness.dark ? FaColors.dark : FaColors.light);
}

/// Wraps the Folder Agent subtree in a theme carrying [FaColors].
ThemeData faThemeData(ThemeData base, Brightness brightness) {
  final c = brightness == Brightness.dark ? FaColors.dark : FaColors.light;
  return base.copyWith(
    brightness: brightness,
    scaffoldBackgroundColor: c.background,
    canvasColor: c.background,
    dividerColor: c.border,
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: c.foreground,
      selectionColor: Scoop.mint.withValues(alpha: 0.30),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: c.isDark ? const Color(0xFF262932) : const Color(0xFF0F1117),
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: FaText.sans(size: 11.5, color: Colors.white),
      waitDuration: const Duration(milliseconds: 450),
    ),
    // Neutral fields: DeskMate's app theme focuses inputs in purple; Folder
    // Agent fields are borderless unless they draw their own (FaTextField).
    inputDecorationTheme: const InputDecorationTheme(
      filled: false,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
      errorBorder: InputBorder.none,
      focusedErrorBorder: InputBorder.none,
    ),
    colorScheme: base.colorScheme.copyWith(
      brightness: brightness,
      primary: c.foreground,
      onPrimary: c.background,
      secondary: Scoop.mint,
      surface: c.card,
      onSurface: c.foreground,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(c.mutedForeground.withValues(alpha: 0.35)),
      radius: const Radius.circular(8),
      thickness: const WidgetStatePropertyAll(6),
    ),
    extensions: [c],
  );
}
