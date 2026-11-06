import 'package:flutter/material.dart';

class Brand {
  static const paper = Color(0xFFF6F1E6);
  static const card = Color(0xFFFFFDF8);
  static const ink = Color(0xFF14211D);
  static const forest = Color(0xFF0E3B32);
  static const muted = Color(0xFF5A6B63);
  static const line = Color(0xFFE3DCCB);
  static const amber = Color(0xFFF2B544);
  static const danger = Color(0xFFB4432B);
  static const mint = Color(0xFFE1EAD9);
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: Brand.forest, brightness: Brightness.light).copyWith(
      primary: Brand.forest,
      onPrimary: Brand.paper,
      surface: Brand.paper,
      onSurface: Brand.ink,
      error: Brand.danger,
    ),
    scaffoldBackgroundColor: Brand.paper,
    fontFamily: 'PlusJakartaSans',
  );
  final text = base.textTheme.apply(bodyColor: Brand.ink, displayColor: Brand.ink);
  return base.copyWith(
    textTheme: text,
    appBarTheme: const AppBarTheme(backgroundColor: Brand.paper, surfaceTintColor: Colors.transparent, elevation: 0),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Brand.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Brand.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Brand.line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Brand.forest, width: 1.8)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Brand.forest,
        foregroundColor: Brand.paper,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Brand.ink,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

