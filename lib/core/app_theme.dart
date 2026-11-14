import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const Color orange = Color(0xFFE08C14);
  static const Color orangeLight = Color(0xFFF0A83A);
  static const Color orangeDeep = Color(0xFFD07E0C);
  static const Color danger = Color(0xFFD32F2F);

  static const LinearGradient barGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [
      orangeDeep,
      orange,
      orangeLight,
      orange,
      orangeDeep,
    ],
    stops: [0.0, 0.22, 0.5, 0.78, 1.0],
  );

  static const LinearGradient topBarGradient = barGradient;
  static const LinearGradient bottomBarGradient = barGradient;

  static const LinearGradient surahHeaderGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [
      Color(0xFFFFD9A0),
      Color(0xFFFFE8C8),
      Color(0xFFFFF8EE),
      Color(0xFFFFE8C8),
      Color(0xFFFFD9A0),
    ],
    stops: [0.0, 0.22, 0.5, 0.78, 1.0],
  );

  static ThemeData build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final ink = isDark ? Colors.white : const Color(0xFF1C140C);
    final muted = isDark ? Colors.white70 : Colors.black54;
    final scheme = ColorScheme.fromSeed(
      seedColor: orange,
      brightness: brightness,
      primary: orange,
    ).copyWith(
      onSurface: ink,
      onSurfaceVariant: muted,
    );

    final baseText = ThemeData(brightness: brightness).textTheme;
    final textTheme = baseText.apply(bodyColor: ink, displayColor: ink);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark ? const Color(0xFF121816) : Colors.white,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      iconTheme: IconThemeData(color: ink),
      drawerTheme: DrawerThemeData(
        backgroundColor: isDark ? const Color(0xFF1A1A1A) : null,
      ),
      listTileTheme: ListTileThemeData(
        textColor: ink,
        iconColor: ink,
        subtitleTextStyle: TextStyle(color: muted, fontSize: 14),
      ),
      inputDecorationTheme: InputDecorationTheme(
        hintStyle: TextStyle(color: muted),
        labelStyle: TextStyle(color: ink),
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: Colors.white),
        actionsIconTheme: IconThemeData(color: Colors.white),
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      sliderTheme: const SliderThemeData(
        showValueIndicator: ShowValueIndicator.never,
      ),
    );
  }
}
