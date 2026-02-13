import 'package:flutter/material.dart';

import 'app_tokens.dart';

class AppTheme {
  AppTheme._();

  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.primary,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFFFE2CA),
      onPrimaryContainer: Color(0xFF3B1B00),
      secondary: Color(0xFFF3ECE6),
      onSecondary: AppColors.lightText,
      secondaryContainer: Color(0xFFEDE4DB),
      onSecondaryContainer: AppColors.lightText,
      tertiary: AppColors.chart3,
      onTertiary: Colors.white,
      tertiaryContainer: Color(0xFFDCE7FF),
      onTertiaryContainer: Color(0xFF112D66),
      error: Color(0xFFE25247),
      onError: Colors.white,
      errorContainer: Color(0xFFFFDAD6),
      onErrorContainer: Color(0xFF410002),
      surface: AppColors.lightSurface,
      onSurface: AppColors.lightText,
      surfaceContainerHighest: Color(0xFFF4EEEA),
      onSurfaceVariant: AppColors.lightMutedText,
      outline: Color(0xFFC8BEB4),
      outlineVariant: AppColors.lightBorder,
      shadow: Color(0x22000000),
      scrim: Color(0x66000000),
      inverseSurface: Color(0xFF27221D),
      onInverseSurface: Color(0xFFF8F2ED),
      inversePrimary: AppColors.primaryDark,
    );

    return _base(
      colorScheme: scheme,
      scaffold: AppColors.lightBackground,
      tone: const AppTone(
        success: AppColors.success,
        warning: AppColors.warning,
        chart2: AppColors.chart2,
        chart3: AppColors.chart3,
        chart4: AppColors.chart4,
        cardBorder: AppColors.lightBorder,
        mutedText: AppColors.lightMutedText,
        glassBackground: Color(0xE6FFFFFF),
      ),
    );
  }

  static ThemeData dark() {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: AppColors.primaryDark,
      onPrimary: Color(0xFF2E1500),
      primaryContainer: Color(0xFF4D2502),
      onPrimaryContainer: Color(0xFFFFDBBE),
      secondary: Color(0xFF1F1A16),
      onSecondary: AppColors.darkText,
      secondaryContainer: Color(0xFF29241F),
      onSecondaryContainer: AppColors.darkText,
      tertiary: Color(0xFF8FB6FF),
      onTertiary: Color(0xFF08255C),
      tertiaryContainer: Color(0xFF183C8C),
      onTertiaryContainer: Color(0xFFDCE7FF),
      error: Color(0xFFFF8A80),
      onError: Color(0xFF4A0A06),
      errorContainer: Color(0xFF6B1510),
      onErrorContainer: Color(0xFFFFDAD6),
      surface: AppColors.darkSurface,
      onSurface: AppColors.darkText,
      surfaceContainerHighest: Color(0xFF2A241F),
      onSurfaceVariant: AppColors.darkMutedText,
      outline: Color(0xFF5C5248),
      outlineVariant: AppColors.darkBorder,
      shadow: Color(0x66000000),
      scrim: Color(0x99000000),
      inverseSurface: Color(0xFFF8F2ED),
      onInverseSurface: Color(0xFF221D18),
      inversePrimary: AppColors.primary,
    );

    return _base(
      colorScheme: scheme,
      scaffold: AppColors.darkBackground,
      tone: const AppTone(
        success: AppColors.success,
        warning: AppColors.warning,
        chart2: AppColors.chart2,
        chart3: AppColors.chart3,
        chart4: AppColors.chart4,
        cardBorder: AppColors.darkBorder,
        mutedText: AppColors.darkMutedText,
        glassBackground: Color(0xE61E1814),
      ),
    );
  }

  static ThemeData _base({
    required ColorScheme colorScheme,
    required Color scaffold,
    required AppTone tone,
  }) {
    final text = Typography.material2021().black.apply(
      bodyColor: colorScheme.onSurface,
      displayColor: colorScheme.onSurface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      brightness: colorScheme.brightness,
      scaffoldBackgroundColor: scaffold,
      splashFactory: InkSparkle.splashFactory,
      extensions: [tone],
      textTheme: text.copyWith(
        displaySmall: text.displaySmall?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.8,
        ),
        headlineMedium: text.headlineMedium?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
        ),
        headlineSmall: text.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
        titleLarge: text.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        bodyLarge: text.bodyLarge?.copyWith(height: 1.34),
        bodyMedium: text.bodyMedium?.copyWith(height: 1.34),
        labelLarge: text.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        ),
        labelMedium: text.labelMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        thickness: 1,
        space: 1,
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: tone.cardBorder.withValues(alpha: 0.6)),
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: colorScheme.surface,
        elevation: 0,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: colorScheme.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.secondary.withValues(alpha: 0.72),
        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: tone.cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: tone.cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.4),
        ),
      ),
      chipTheme: ChipThemeData(
        side: BorderSide(color: tone.cardBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        backgroundColor: colorScheme.secondary.withValues(alpha: 0.62),
        selectedColor: colorScheme.primaryContainer,
        labelStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          side: BorderSide(color: tone.cardBorder),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: TextStyle(color: colorScheme.onInverseSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        elevation: 0,
        indicatorColor: colorScheme.primaryContainer,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
        linearTrackColor: colorScheme.surfaceContainerHighest,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        backgroundColor: colorScheme.surface,
      ),
    );
  }
}
