import 'package:flutter/material.dart';

/// Design tokens for Moneylock's Red & White visual system.
abstract final class AppColors {
  static const primary = Color(0xFFBA1A1A);
  static const primaryBright = Color(0xFFFF3B30);
  static const onPrimary = Color(0xFFFFFFFF);
  static const primaryContainer = Color(0xFFFFDAD6);
  static const onPrimaryContainer = Color(0xFF410002);
  static const primaryFixedDim = Color(0xFFFFB4AB);

  static const background = Color(0xFFF9F9FA);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceContainer = Color(0xFFF4F4F5);
  static const surfaceContainerLow = Color(0xFFF3F3F4);
  static const surfaceContainerHigh = Color(0xFFE8E8E9);
  static const surfaceContainerHighest = Color(0xFFE2E2E3);
  static const surfaceVariant = Color(0xFFE2E2E3);
  static const onSurface = Color(0xFF131313);
  static const onSurfaceVariant = Color(0xFF444933);
  static const outline = Color(0xFF747A60);
  static const outlineVariant = Color(0xFFC4C9AC);
  static const borderSubtle = Color(0xFFE4E4E7);
  static const error = Color(0xFFBA1A1A);
  static const errorContainer = Color(0xFFFFDAD6);
  static const onErrorContainer = Color(0xFF93000A);
  static const shadowBase = Color(0x0A000000);

  // Dark tokens are reserved for the chat modal.
  static const darkBackground = Color(0xFF131313);
  static const darkSurface = Color(0xFF131313);
  static const darkSurfaceContainer = Color(0xFF201F1F);
  static const darkSurfaceContainerLow = Color(0xFF1C1B1B);
  static const darkSurfaceContainerHigh = Color(0xFF2A2A2A);
  static const darkSurfaceContainerHighest = Color(0xFF353534);
  static const darkSurfaceBright = Color(0xFF3A3939);
  static const darkOnSurface = Color(0xFFE5E2E1);
  static const darkOnSurfaceVariant = Color(0xFFC4C9AC);
  static const darkPrimary = Color(0xFFFFB4AB);
  static const darkOutline = Color(0xFF8E9379);
  static const darkOutlineVariant = Color(0xFF444933);
}

abstract final class AppSpacing {
  static const unit = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 32.0;
  static const gutter = 12.0;
  static const margin = 20.0;
}

abstract final class AppRadii {
  static const md = 4.0;
  static const xl = 8.0;
  static const full = 12.0;
}

abstract final class AppShadows {
  static const card = <BoxShadow>[
    BoxShadow(
      color: AppColors.shadowBase,
      blurRadius: 8,
      offset: Offset(0, 1),
    ),
  ];

  static const glow = <BoxShadow>[
    BoxShadow(
      color: Color(0x33BA1A1A),
      blurRadius: 10,
    ),
  ];
}

abstract final class AppTextStyles {
  static const display = TextStyle(
    fontFamily: 'Inter',
    fontSize: 48,
    height: 52 / 48,
    fontWeight: FontWeight.w700,
    letterSpacing: -1.92,
  );

  static const headlineLg = TextStyle(
    fontFamily: 'Inter',
    fontSize: 32,
    height: 38 / 32,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.64,
  );

  static const headlineLgMobile = TextStyle(
    fontFamily: 'Inter',
    fontSize: 24,
    height: 28 / 24,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.24,
  );

  static const headlineMd = TextStyle(
    fontFamily: 'Inter',
    fontSize: 20,
    height: 28 / 20,
    fontWeight: FontWeight.w600,
  );

  static const bodyMd = TextStyle(
    fontFamily: 'Inter',
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w400,
  );

  static const bodyLg = TextStyle(
    fontFamily: 'Inter',
    fontSize: 18,
    height: 28 / 18,
    fontWeight: FontWeight.w400,
  );

  static const monoData = TextStyle(
    fontFamily: 'Geist',
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w500,
  );

  static const labelCaps = TextStyle(
    fontFamily: 'Geist',
    fontSize: 12,
    height: 1,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
  );
}

ThemeData buildAppTheme() {
  const colorScheme = ColorScheme.light(
    primary: AppColors.primary,
    onPrimary: AppColors.onPrimary,
    primaryContainer: AppColors.primaryContainer,
    onPrimaryContainer: AppColors.onPrimaryContainer,
    secondary: AppColors.onSurfaceVariant,
    onSecondary: AppColors.onPrimary,
    secondaryContainer: Color(0xFFE5E2E1),
    onSecondaryContainer: AppColors.onSurface,
    tertiary: Color(0xFF4F616E),
    onTertiary: AppColors.onPrimary,
    tertiaryContainer: Color(0xFFDCEFFF),
    onTertiaryContainer: Color(0xFF071E26),
    error: AppColors.error,
    onError: AppColors.onPrimary,
    errorContainer: AppColors.errorContainer,
    onErrorContainer: AppColors.onErrorContainer,
    surface: AppColors.surface,
    onSurface: AppColors.onSurface,
    surfaceContainerLowest: AppColors.surface,
    surfaceContainerLow: AppColors.surfaceContainerLow,
    surfaceContainer: AppColors.surfaceContainer,
    surfaceContainerHigh: AppColors.surfaceContainerHigh,
    surfaceContainerHighest: AppColors.surfaceContainerHighest,
    outline: AppColors.outline,
    outlineVariant: AppColors.outlineVariant,
    shadow: AppColors.shadowBase,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: colorScheme,
    fontFamily: 'Inter',
    scaffoldBackgroundColor: AppColors.background,
    canvasColor: AppColors.background,
    dividerColor: AppColors.borderSubtle,
    cardTheme: const CardThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppRadii.xl)),
        side: BorderSide(color: AppColors.borderSubtle),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceContainer,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.xl),
        borderSide: const BorderSide(color: AppColors.borderSubtle),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.xl),
        borderSide: const BorderSide(color: AppColors.borderSubtle),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.xl),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
    ),
  );
}
