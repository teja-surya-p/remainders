import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const Color primary = Color(0xFFF5791A);
  static const Color primaryDark = Color(0xFFF58B3A);

  static const Color lightBackground = Color(0xFFFCFAF8);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceAlt = Color(0xFFF4EFEB);
  static const Color lightText = Color(0xFF191511);
  static const Color lightMutedText = Color(0xFF736B61);
  static const Color lightBorder = Color(0xFFE4DCD3);

  static const Color darkBackground = Color(0xFF13100D);
  static const Color darkSurface = Color(0xFF1A1612);
  static const Color darkSurfaceAlt = Color(0xFF23201C);
  static const Color darkText = Color(0xFFF6F1EC);
  static const Color darkMutedText = Color(0xFFB6ACA1);
  static const Color darkBorder = Color(0xFF2C2722);

  static const Color success = Color(0xFF1FA064);
  static const Color warning = Color(0xFFF29E1F);
  static const Color chart2 = Color(0xFF1A9C7D);
  static const Color chart3 = Color(0xFF3D7BE0);
  static const Color chart4 = Color(0xFFCF9C31);
}

@immutable
class AppTone extends ThemeExtension<AppTone> {
  final Color success;
  final Color warning;
  final Color chart2;
  final Color chart3;
  final Color chart4;
  final Color cardBorder;
  final Color mutedText;
  final Color glassBackground;

  const AppTone({
    required this.success,
    required this.warning,
    required this.chart2,
    required this.chart3,
    required this.chart4,
    required this.cardBorder,
    required this.mutedText,
    required this.glassBackground,
  });

  static AppTone of(BuildContext context) {
    final theme = Theme.of(context);
    final tone = theme.extension<AppTone>();
    if (tone != null) {
      return tone;
    }

    final isDark = theme.brightness == Brightness.dark;
    return AppTone(
      success: AppColors.success,
      warning: AppColors.warning,
      chart2: AppColors.chart2,
      chart3: AppColors.chart3,
      chart4: AppColors.chart4,
      cardBorder: isDark ? AppColors.darkBorder : AppColors.lightBorder,
      mutedText: isDark ? AppColors.darkMutedText : AppColors.lightMutedText,
      glassBackground: isDark
          ? const Color(0xE61E1814)
          : const Color(0xE6FFFFFF),
    );
  }

  @override
  ThemeExtension<AppTone> copyWith({
    Color? success,
    Color? warning,
    Color? chart2,
    Color? chart3,
    Color? chart4,
    Color? cardBorder,
    Color? mutedText,
    Color? glassBackground,
  }) {
    return AppTone(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      chart2: chart2 ?? this.chart2,
      chart3: chart3 ?? this.chart3,
      chart4: chart4 ?? this.chart4,
      cardBorder: cardBorder ?? this.cardBorder,
      mutedText: mutedText ?? this.mutedText,
      glassBackground: glassBackground ?? this.glassBackground,
    );
  }

  @override
  ThemeExtension<AppTone> lerp(
    covariant ThemeExtension<AppTone>? other,
    double t,
  ) {
    if (other is! AppTone) {
      return this;
    }
    return AppTone(
      success: Color.lerp(success, other.success, t) ?? success,
      warning: Color.lerp(warning, other.warning, t) ?? warning,
      chart2: Color.lerp(chart2, other.chart2, t) ?? chart2,
      chart3: Color.lerp(chart3, other.chart3, t) ?? chart3,
      chart4: Color.lerp(chart4, other.chart4, t) ?? chart4,
      cardBorder: Color.lerp(cardBorder, other.cardBorder, t) ?? cardBorder,
      mutedText: Color.lerp(mutedText, other.mutedText, t) ?? mutedText,
      glassBackground:
          Color.lerp(glassBackground, other.glassBackground, t) ??
          glassBackground,
    );
  }
}
