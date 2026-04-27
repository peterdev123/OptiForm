import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_typography.dart';

class AppTheme {
  static ThemeData dark() {
    return _buildThemeData(
      brightness: Brightness.dark,
      scaffoldColor: AppColors.background,
      surfaceColor: AppColors.surface,
      surfaceAltColor: AppColors.surfaceAlt,
      textPrimary: AppColors.textPrimary,
      textSecondary: AppColors.textSecondary,
      onPrimary: const Color(0xFF0C1226),
    );
  }

  static ThemeData light() {
    return _buildThemeData(
      brightness: Brightness.light,
      scaffoldColor: const Color(0xFFF4F7FF),
      surfaceColor: Colors.white,
      surfaceAltColor: const Color(0xFFE7EDFF),
      textPrimary: const Color(0xFF171C2F),
      textSecondary: const Color(0xFF5A678A),
      onPrimary: Colors.white,
    );
  }

  static ThemeData _buildThemeData({
    required Brightness brightness,
    required Color scaffoldColor,
    required Color surfaceColor,
    required Color surfaceAltColor,
    required Color textPrimary,
    required Color textSecondary,
    required Color onPrimary,
  }) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: brightness,
    ).copyWith(
      primary: AppColors.primary,
      onPrimary: onPrimary,
      secondary: AppColors.secondary,
      onSecondary: onPrimary,
      surface: surfaceColor,
      onSurface: textPrimary,
      error: const Color(0xFFFF6B6B),
      onError: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldColor,
      textTheme: AppTypography.textTheme.apply(
        bodyColor: textPrimary,
        displayColor: textPrimary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldColor,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: surfaceAltColor,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dividerColor: textSecondary.withValues(alpha: 0.2),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surfaceColor,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          side: BorderSide(color: AppColors.primary.withValues(alpha: 0.55)),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: colorScheme.onPrimary,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return colorScheme.onPrimary;
            return textPrimary;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return AppColors.primary;
            return surfaceColor;
          }),
          side: WidgetStateProperty.all(
            BorderSide(color: AppColors.primary.withValues(alpha: 0.40)),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceColor,
        hintStyle: TextStyle(color: textSecondary),
        labelStyle: TextStyle(color: textSecondary),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.25)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.8), width: 1.2),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.4)),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: colorScheme.onPrimary,
      ),
    );
  }
}
