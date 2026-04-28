import 'package:flutter/material.dart';

class AppTheme {
  // --- PALETA OSCURA (SLATE) ---
  static const Color darkBgBase = Color(0xFF020617); // slate-950
  static const Color darkBgCard = Color(0xFF0F172A); // slate-900
  static const Color darkBgCardHighlight = Color(0xFF1E293B); // slate-800
  static const Color darkBorder = Color(0xFF1E293B); // slate-800
  static const Color darkBorderHover = Color(0xFF334155); // slate-700
  static const Color darkTextMain = Color(0xFFF8FAFC); // slate-50
  static const Color darkTextMuted = Color(0xFF94A3B8); // slate-400

  // --- PALETA CLARA ---
  static const Color lightBgBase = Color(0xFFF1F5F9); // slate-100
  static const Color lightBgCard = Colors.white;
  static const Color lightBorder = Color(0xFFE2E8F0); // slate-200
  static const Color lightTextMain = Color(0xFF0F172A); // slate-900
  static const Color lightTextMuted = Color(0xFF64748B); // slate-500

  // --- COLORES DE ACENTO (Comunes) ---
  static const Color primaryBlue = Color(0xFF3B82F6); // blue-500
  static const Color successGreen = Color(0xFF10B981); // emerald-500
  static const Color warningAmber = Color(0xFFF59E0B); // amber-500
  static const Color errorRed = Color(0xFFF43F5E); // rose-500

  // --- ALIAS DE COMPATIBILIDAD (Para pantallas que no usan Theme.of(context) aún) ---
  static const Color textMain = darkTextMain;
  static const Color textMuted = darkTextMuted;
  static const Color bgCard = darkBgCard;
  static const Color bgCardHighlight = darkBgCardHighlight;
  static const Color border = darkBorder;
  static const Color borderHover = darkBorderHover;
  static const Color borderColor = darkBorder;

  // --- DECORACIONES Y ESTILOS ---
  static final cardDecoration =
      (BuildContext context) => BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      );

  static const monoStyle = TextStyle(fontFamily: 'monospace');

  // --- TEMAS ---
  static final ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    primaryColor: primaryBlue,
    scaffoldBackgroundColor: darkBgBase,
    useMaterial3: true,
    dividerColor: darkBorder,
    cardColor: darkBgCard,
    colorScheme: const ColorScheme.dark(
      primary: primaryBlue,
      onPrimary: Colors.white,
      secondary: primaryBlue,
      onSecondary: Colors.white,
      error: errorRed,
      onError: Colors.white,
      surface: darkBgCard,
      onSurface: darkTextMain,
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        color: darkTextMain,
        fontWeight: FontWeight.bold,
        letterSpacing: -0.5,
      ),
      headlineMedium: TextStyle(
        color: darkTextMain,
        fontWeight: FontWeight.bold,
        letterSpacing: -0.3,
      ),
      titleLarge: TextStyle(color: darkTextMain, letterSpacing: -0.2),
      bodyLarge: TextStyle(color: darkTextMain),
      bodyMedium: TextStyle(color: darkTextMuted),
      labelLarge: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      },
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: darkBgCardHighlight,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: darkBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primaryBlue, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: errorRed, width: 1),
      ),
      labelStyle: const TextStyle(color: darkTextMuted),
      prefixIconColor: darkTextMuted,
      suffixIconColor: darkTextMuted,
    ),
    elevatedButtonTheme: _elevatedButtonTheme,
    outlinedButtonTheme: _outlinedButtonTheme(isDark: true),
    textButtonTheme: _textButtonTheme,
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: darkBgCard,
    ),
  );

  static final ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    primaryColor: primaryBlue,
    scaffoldBackgroundColor: lightBgBase,
    useMaterial3: true,
    dividerColor: lightBorder,
    cardColor: lightBgCard,
    colorScheme: const ColorScheme.light(
      primary: primaryBlue,
      onPrimary: Colors.white,
      secondary: primaryBlue,
      onSecondary: Colors.white,
      error: errorRed,
      onError: Colors.white,
      surface: lightBgCard,
      onSurface: lightTextMain,
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        color: lightTextMain,
        fontWeight: FontWeight.bold,
      ),
      headlineMedium: TextStyle(
        color: lightTextMain,
        fontWeight: FontWeight.bold,
      ),
      titleLarge: TextStyle(color: lightTextMain),
      bodyLarge: TextStyle(color: lightTextMain),
      bodyMedium: TextStyle(color: lightTextMuted),
      labelLarge: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: lightBgCard,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: lightBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primaryBlue, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: errorRed, width: 1),
      ),
      labelStyle: const TextStyle(color: lightTextMuted),
      prefixIconColor: lightTextMuted,
      suffixIconColor: lightTextMuted,
    ),
    elevatedButtonTheme: _elevatedButtonTheme,
    outlinedButtonTheme: _outlinedButtonTheme(isDark: false),
    textButtonTheme: _textButtonTheme,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      },
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: lightBgCard,
    ),
  );

  // --- ESTILOS DE BOTONES COMPARTIDOS ---
  static final _elevatedButtonTheme = ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: primaryBlue,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      elevation: 2,
    ),
  );

  static _outlinedButtonTheme({required bool isDark}) =>
      OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: isDark ? darkTextMain : lightTextMain,
          side: BorderSide(color: isDark ? darkBorderHover : lightBorder),
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      );

  static final _textButtonTheme = TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: primaryBlue,
      textStyle: const TextStyle(fontWeight: FontWeight.bold),
    ),
  );
}
