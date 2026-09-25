import 'package:flutter/material.dart';

/// Dark, high-contrast trading theme (Material 3).
class TrTheme {
  TrTheme._();

  static const Color bg = Color(0xFF0B0F14);
  static const Color surface = Color(0xFF121821);
  static const Color surface2 = Color(0xFF1A2230);
  static const Color outline = Color(0xFF2A3444);
  static const Color textPrimary = Color(0xFFE8EDF5);
  static const Color textMuted = Color(0xFF8B97A8);
  static const Color up = Color(0xFF26C281); // green
  static const Color down = Color(0xFFF6465D); // red
  static const Color accent = Color(0xFF4C8DFF); // blue
  static const Color warn = Color(0xFFF3A712);
  static const Color live = Color(0xFFFF3B3B);

  static ThemeData dark() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        secondary: up,
        surface: surface,
        error: down,
        onPrimary: Colors.white,
        onSurface: textPrimary,
      ),
      scaffoldBackgroundColor: bg,
    );
    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: outline),
        ),
      ),
      dividerTheme: const DividerThemeData(color: outline, thickness: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface2,
        hintStyle: const TextStyle(color: textMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: accent, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: accent.withOpacity(0.18),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? accent
                : textMuted,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surface2,
        contentTextStyle: const TextStyle(color: textPrimary),
        behavior: SnackBarBehavior.floating,
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: textMuted,
        textColor: textPrimary,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? accent
              : textMuted,
        ),
      ),
    );
  }

  static Color pnlColor(double v) => v > 0 ? up : v < 0 ? down : textMuted;

  static String money(double v, {bool signed = false}) {
    final sign = signed && v > 0 ? '+' : '';
    if (v.abs() >= 100000) {
      return '$sign\$${(v / 1000).toStringAsFixed(1)}k';
    }
    final minus = v < 0 ? '-' : '';
    final fixed = v.abs().toStringAsFixed(2);
    final dot = fixed.indexOf('.');
    final whole = fixed.substring(0, dot);
    final grouped = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) grouped.write(',');
      grouped.write(whole[i]);
    }
    return '$sign$minus\$$grouped${fixed.substring(dot)}';
  }
}
