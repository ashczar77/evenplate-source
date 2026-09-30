import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'even_colors.dart';

/// EvenPlate: Premium Dark-First Theme
///
/// Platform fonts on purpose. GoogleFonts.inter sets fontFamily to a face
/// that is not bundled, so the first frames can paint with zero glyphs
/// (dark screen, no error) until the network fetch finishes, or never.
class EvenTheme {
  EvenTheme._();

  static const _fallback = ['Helvetica Neue', 'Arial', 'sans-serif'];

  static TextStyle _style({
    required double fontSize,
    required FontWeight fontWeight,
    required Color color,
    double? letterSpacing,
    double? height,
  }) {
    return TextStyle(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
      fontFamilyFallback: _fallback,
    );
  }

  static SnackBarThemeData get _snackBarTheme {
    return SnackBarThemeData(
      backgroundColor: EvenColors.darkSurfaceElevated,
      contentTextStyle: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: EvenColors.textDarkPrimary,
      ),
      actionTextColor: EvenColors.primaryGreen,
      disabledActionTextColor: EvenColors.textDarkMuted,
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      insetPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: EvenColors.darkBackground,
      colorScheme: const ColorScheme.dark(
        primary: EvenColors.primaryGreenLight,
        secondary: EvenColors.netSageLight,
        tertiary: EvenColors.bufferAmber,
        surface: EvenColors.darkSurface,
        onSurface: EvenColors.textDarkPrimary,
      ),
      snackBarTheme: _snackBarTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        iconTheme: IconThemeData(color: EvenColors.textDarkPrimary),
      ),
      textTheme: TextTheme(
        displayLarge: _style(
          fontSize: 34,
          fontWeight: FontWeight.w800,
          color: EvenColors.textDarkPrimary,
          letterSpacing: -1.0,
        ),
        displayMedium: _style(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: EvenColors.textDarkPrimary,
          letterSpacing: -0.8,
        ),
        titleLarge: _style(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: EvenColors.textDarkPrimary,
          letterSpacing: -0.3,
        ),
        titleMedium: _style(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: EvenColors.textDarkPrimary,
          letterSpacing: -0.1,
        ),
        bodyLarge: _style(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          color: EvenColors.textDarkSecondary,
          height: 1.55,
        ),
        bodyMedium: _style(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: EvenColors.textDarkSecondary,
          height: 1.5,
        ),
        labelSmall: _style(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: EvenColors.textDarkMuted,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: EvenColors.lightBackground,
      colorScheme: const ColorScheme.light(
        primary: EvenColors.primaryCharcoal,
        secondary: EvenColors.primaryGreen,
        tertiary: EvenColors.bufferAmber,
        surface: EvenColors.lightSurface,
        onSurface: EvenColors.textLightPrimary,
      ),
      snackBarTheme: _snackBarTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        iconTheme: IconThemeData(color: EvenColors.textLightPrimary),
      ),
      textTheme: TextTheme(
        displayLarge: _style(
          fontSize: 34,
          fontWeight: FontWeight.w800,
          color: EvenColors.textLightPrimary,
          letterSpacing: -1.0,
        ),
        displayMedium: _style(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: EvenColors.textLightPrimary,
          letterSpacing: -0.8,
        ),
        titleLarge: _style(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: EvenColors.textLightPrimary,
          letterSpacing: -0.3,
        ),
        titleMedium: _style(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: EvenColors.textLightPrimary,
          letterSpacing: -0.1,
        ),
        bodyLarge: _style(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          color: EvenColors.textLightSecondary,
          height: 1.55,
        ),
        bodyMedium: _style(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: EvenColors.textLightSecondary,
          height: 1.5,
        ),
        labelSmall: _style(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: EvenColors.textLightMuted,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}
