import 'package:flutter/material.dart';
import '../../presentation/providers/theme_provider.dart';

class AppTheme {
  static ThemeData buildTheme(CustomThemeState themeState, {required bool isDark}) {
    final primaryColor = themeState.primaryColor;
    final fontFamily = themeState.fontFamily;

    // Determine colors based on dark mode vs light mode and pure black settings
    final Color scaffoldBg;
    final Color surfaceColor;
    final Color cardBorderColor;

    if (isDark) {
      if (themeState.isPureBlack) {
        scaffoldBg = const Color(0xFF000000);
        surfaceColor = const Color(0xFF121212);
        cardBorderColor = const Color(0xFF222222);
      } else {
        scaffoldBg = const Color(0xFF0F172A); // Slate 900
        surfaceColor = const Color(0xFF1E293B); // Slate 800
        cardBorderColor = const Color(0xFF334155).withOpacity(0.3);
      }
    } else {
      scaffoldBg = const Color(0xFFF9FAFB);
      surfaceColor = Colors.white;
      cardBorderColor = Colors.grey.shade200;
    }

    final ColorScheme colorScheme = ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: isDark ? Brightness.dark : Brightness.light,
      primary: primaryColor,
      secondary: const Color(0xFFEC4899), // Vibrant Pink
      background: scaffoldBg,
      surface: surfaceColor,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBg,
      fontFamily: fontFamily,
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: cardBorderColor),
        ),
        color: surfaceColor,
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        backgroundColor: Colors.transparent,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: isDark ? Colors.white : const Color(0xFF1F2937),
          fontSize: 20,
          fontWeight: FontWeight.bold,
          fontFamily: fontFamily,
        ),
        iconTheme: IconThemeData(color: isDark ? Colors.white : const Color(0xFF1F2937)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? surfaceColor : Colors.grey.shade100,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primaryColor, width: 1.5),
        ),
      ),
    );
  }
}
