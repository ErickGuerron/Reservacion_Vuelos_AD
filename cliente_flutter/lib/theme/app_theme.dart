import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Tokens del tema de tailwind-config.js del cliente web, traducidos 1:1.
class AppColors {
  static const primary = Color(0xFF000000);
  static const onPrimary = Color(0xFFFFFFFF);
  static const primaryContainer = Color(0xFF0E1C2F);
  static const onPrimaryContainer = Color(0xFF77849C);
  static const secondary = Color(0xFF006398);
  static const onSecondary = Color(0xFFFFFFFF);
  static const secondaryContainer = Color(0xFF5BB8FE);
  static const onSecondaryContainer = Color(0xFF00476E);
  static const secondaryFixed = Color(0xFFCCE5FF);
  static const secondaryFixedDim = Color(0xFF93CCFF);
  static const onSecondaryFixed = Color(0xFF001D31);
  static const tertiary = Color(0xFF000000);
  static const tertiaryFixed = Color(0xFFFFDDB8);
  static const tertiaryFixedDim = Color(0xFFFFB95F);
  static const onTertiaryFixed = Color(0xFF2A1700);
  static const tertiaryContainer = Color(0xFF2A1700);
  static const surface = Color(0xFFF7F9FB);
  static const surfaceBright = Color(0xFFF7F9FB);
  static const primaryFixed = Color(0xFFD6E3FE);
  static const background = Color(0xFFF7F9FB);
  static const surfaceContainerLowest = Color(0xFFFFFFFF);
  static const surfaceContainerLow = Color(0xFFF2F4F6);
  static const surfaceContainer = Color(0xFFECEEF0);
  static const surfaceContainerHigh = Color(0xFFE6E8EA);
  static const surfaceContainerHighest = Color(0xFFE0E3E5);
  static const surfaceVariant = Color(0xFFE0E3E5);
  static const onSurface = Color(0xFF191C1E);
  static const onSurfaceVariant = Color(0xFF44474C);
  static const outline = Color(0xFF75777D);
  static const outlineVariant = Color(0xFFC5C6CD);
  static const error = Color(0xFFBA1A1A);
  static const onError = Color(0xFFFFFFFF);
  static const errorContainer = Color(0xFFFFDAD6);
  static const onErrorContainer = Color(0xFF93000A);
  static const inverseSurface = Color(0xFF2D3133);
  static const inverseOnSurface = Color(0xFFEFF1F3);

  // Colores de alerta de mostrarAlerta() en cargador.js (tailwind emerald/rose/amber).
  static const successBg = Color(0xFFECFDF5);
  static const successText = Color(0xFF065F46);
  static const successBorder = Color(0xFFA7F3D0);
  static const successIcon = Color(0xFF059669);
  static const errorBg = Color(0xFFFFF1F2);
  static const errorText = Color(0xFF9F1239);
  static const errorBorder = Color(0xFFFECDD3);
  static const errorIcon = Color(0xFFE11D48);
  static const warningBg = Color(0xFFFFFBEB);
  static const warningText = Color(0xFF92400E);
  static const warningBorder = Color(0xFFFDE68A);
  static const warningIcon = Color(0xFFD97706);

  // Login y registro usan la paleta slate y el azul de marca.
  static const slate900 = Color(0xFF0F172A);
  static const slate700 = Color(0xFF334155);
  static const slate600 = Color(0xFF475569);
  static const slate500 = Color(0xFF64748B);
  static const slate400 = Color(0xFF94A3B8);
  static const slate300 = Color(0xFFCBD5E1);
  static const brandNavy = Color(0xFF0B192C);
  static const brandNavyHover = Color(0xFF132A4A);
  static const sky400 = Color(0xFF38BDF8);
  static const sky300 = Color(0xFF7DD3FC);
}

class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 40.0;
  static const marginMobile = 16.0;
  static const margin = 48.0;
}

class AppTheme {
  // Plus Jakarta Sans para texto, JetBrains Mono para telemetría (igual que el index).
  static TextStyle telemetry({double size = 12, FontWeight weight = FontWeight.w500, Color? color}) {
    return GoogleFonts.jetBrainsMono(fontSize: size, fontWeight: weight, color: color ?? AppColors.onSurfaceVariant);
  }

  static TextStyle headlineXl({Color? color}) =>
      GoogleFonts.plusJakartaSans(fontSize: 44, height: 52 / 44, fontWeight: FontWeight.w800, color: color ?? AppColors.onSurface, letterSpacing: -0.5);
  static TextStyle headlineLg({Color? color}) =>
      GoogleFonts.plusJakartaSans(fontSize: 32, height: 40 / 32, fontWeight: FontWeight.w700, color: color ?? AppColors.onSurface, letterSpacing: -0.3);
  static TextStyle headlineMd({Color? color}) =>
      GoogleFonts.plusJakartaSans(fontSize: 24, height: 32 / 24, fontWeight: FontWeight.w700, color: color ?? AppColors.onSurface);
  static TextStyle headlineSm({Color? color}) =>
      GoogleFonts.plusJakartaSans(fontSize: 20, height: 28 / 20, fontWeight: FontWeight.w600, color: color ?? AppColors.onSurface);
  static TextStyle bodyLg({Color? color}) =>
      GoogleFonts.plusJakartaSans(fontSize: 18, height: 28 / 18, color: color ?? AppColors.onSurface);
  static TextStyle bodyMd({Color? color}) =>
      GoogleFonts.plusJakartaSans(fontSize: 16, height: 24 / 16, color: color ?? AppColors.onSurface);
  static TextStyle bodySm({Color? color}) =>
      GoogleFonts.plusJakartaSans(fontSize: 14, height: 20 / 14, color: color ?? AppColors.onSurface);
  static TextStyle labelLg({Color? color}) =>
      GoogleFonts.plusJakartaSans(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600, color: color ?? AppColors.onSurface);
  static TextStyle labelMd({Color? color}) =>
      GoogleFonts.plusJakartaSans(fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w600, color: color ?? AppColors.onSurface);
  static TextStyle labelSm({Color? color}) =>
      GoogleFonts.plusJakartaSans(fontSize: 11, height: 14 / 11, fontWeight: FontWeight.w500, color: color ?? AppColors.onSurface);

  // Esquema explícito con los tokens de la paleta. Antes se generaba desde una semilla negra y Material
  // producía terciarios y tonales rosados que no pertenecen a la identidad de la app.
  static ColorScheme get _esquema => const ColorScheme.light(
        primary: AppColors.primary,
        onPrimary: AppColors.onPrimary,
        primaryContainer: AppColors.primaryContainer,
        onPrimaryContainer: AppColors.onPrimaryContainer,
        secondary: AppColors.secondary,
        onSecondary: AppColors.onSecondary,
        secondaryContainer: AppColors.secondaryFixed,
        onSecondaryContainer: AppColors.onSecondaryFixed,
        tertiary: AppColors.secondary,
        onTertiary: AppColors.onSecondary,
        tertiaryContainer: AppColors.secondaryFixed,
        onTertiaryContainer: AppColors.onSecondaryFixed,
        error: AppColors.error,
        onError: AppColors.onError,
        errorContainer: AppColors.errorContainer,
        onErrorContainer: AppColors.onErrorContainer,
        surface: AppColors.surface,
        onSurface: AppColors.onSurface,
        onSurfaceVariant: AppColors.onSurfaceVariant,
        surfaceTint: Colors.transparent,
        surfaceContainerLowest: AppColors.surfaceContainerLowest,
        surfaceContainerLow: AppColors.surfaceContainerLow,
        surfaceContainer: AppColors.surfaceContainer,
        surfaceContainerHigh: AppColors.surfaceContainerHigh,
        surfaceContainerHighest: AppColors.surfaceContainerHighest,
        outline: AppColors.outline,
        outlineVariant: AppColors.outlineVariant,
        inverseSurface: AppColors.inverseSurface,
        onInverseSurface: AppColors.inverseOnSurface,
      );

  static ThemeData light() {
    final base = ThemeData(useMaterial3: true, colorScheme: _esquema);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceContainerLow,
        border: InputBorder.none,
        labelStyle: bodySm(color: AppColors.onSurfaceVariant),
        floatingLabelStyle: labelMd(color: AppColors.onSurfaceVariant),
        hintStyle: bodySm(color: AppColors.outline),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titleTextStyle: headlineSm(),
      ),
    );
  }
}
