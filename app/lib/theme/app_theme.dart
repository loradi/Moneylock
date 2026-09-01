import 'package:flutter/material.dart';

/// Design tokens for Moneylock's calm, private-planning visual system.
abstract final class AppColors {
  static const primary = Color(0xFF075B63);
  static const primaryBright = Color(0xFF0B737B);
  static const onPrimary = Color(0xFFFFFFFF);
  static const primaryContainer = Color(0xFFC6F3EE);
  static const onPrimaryContainer = Color(0xFF002021);
  static const primaryFixedDim = Color(0xFF8DE0C2);
  static const accent = Color(0xFF237B5D);
  static const accentContainer = Color(0xFFD6F5E3);
  static const coral = Color(0xFFCC5A45);

  static const background = Color(0xFFF6F8F7);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceContainer = Color(0xFFEFF4F2);
  static const surfaceContainerLow = Color(0xFFF2F6F4);
  static const surfaceContainerHigh = Color(0xFFE3ECE8);
  static const surfaceContainerHighest = Color(0xFFD7E4DF);
  static const surfaceVariant = Color(0xFFD7E4DF);
  static const onSurface = Color(0xFF17201F);
  static const onSurfaceVariant = Color(0xFF52615F);
  static const outline = Color(0xFF6B7A77);
  static const outlineVariant = Color(0xFFB9C8C3);
  static const borderSubtle = Color(0xFFDDE7E3);
  static const error = Color(0xFFB3261E);
  static const errorContainer = Color(0xFFF9DEDC);
  static const onErrorContainer = Color(0xFF410E0B);
  static const shadowBase = Color(0x0A000000);

  // Dark tokens are reserved for the chat modal.
  static const darkBackground = Color(0xFF082D31);
  static const darkSurface = Color(0xFF082D31);
  static const darkSurfaceContainer = Color(0xFF123A3D);
  static const darkSurfaceContainerLow = Color(0xFF0D3539);
  static const darkSurfaceContainerHigh = Color(0xFF19474B);
  static const darkSurfaceContainerHighest = Color(0xFF24565A);
  static const darkSurfaceBright = Color(0xFF2F6265);
  static const darkOnSurface = Color(0xFFE7F1EE);
  static const darkOnSurfaceVariant = Color(0xFFB8CBC5);
  static const darkPrimary = Color(0xFF8DE0C2);
  static const darkOutline = Color(0xFF8DA39D);
  static const darkOutlineVariant = Color(0xFF3E5450);
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
    BoxShadow(color: AppColors.shadowBase, blurRadius: 8, offset: Offset(0, 1)),
  ];

  static const glow = <BoxShadow>[
    BoxShadow(color: Color(0x338DE0C2), blurRadius: 10),
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
    secondary: AppColors.accent,
    onSecondary: AppColors.onPrimary,
    secondaryContainer: AppColors.accentContainer,
    onSecondaryContainer: AppColors.onSurface,
    tertiary: AppColors.coral,
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
