import 'package:flutter/material.dart';

/// EvenPlate: Dark Mint Aesthetic (Phase 4 Redesign)
/// Inspired by premium 2026 health dashboards.
/// Deep greenish-black backgrounds, elevated dark gray surfaces, and vibrant mint accents.
class EvenColors {
  EvenColors._();

  // Backgrounds & Surfaces
  static const Color darkBackground = Color(0xFF191C1B); // Deep greenish-black
  static const Color darkSurface = Color(0xFF242725); // Elevated dark gray
  static const Color darkSurfaceElevated = Color(
    0xFF2D302E,
  ); // Higher elevation
  static const Color darkSurfaceCard = Color(0xFF242725);

  // Since we are locking to Dark Mode, these light variants are largely unused,
  // but we keep them to prevent compilation errors if referenced.
  static const Color lightBackground = Color(0xFF191C1B);
  static const Color lightSurface = Color(0xFF242725);
  static const Color lightSurfaceElevated = Color(0xFF2D302E);
  static const Color lightSurfaceCard = Color(0xFF242725);

  // Primary Accents
  static const Color primaryGreen = Color(0xFF73D197); // Vibrant Mint Green
  static const Color primaryGreenLight = Color(0xFF90E8B2);
  static const Color primaryCharcoal = Color(0xFF131514);

  // Satiety Matrix Core Pillars (Harmonized to Mint/Sage spectrum)
  static const Color anchorTerracotta = Color(0xFF73D197); // Mint
  static const Color anchorTerracottaLight = Color(0xFF90E8B2);
  static const Color anchorGlow = Color(0x3373D197);

  static const Color netSage = Color(0xFF5A8D6E); // Muted Sage
  static const Color netSageLight = Color(0xFF74AF8C);
  static const Color netGlow = Color(0x335A8D6E);

  static const Color bufferAmber = Color(0xFFA1A5A3); // Neutral Light Gray
  static const Color bufferAmberLight = Color(0xFFC4C8C6);
  static const Color bufferGlow = Color(0x33A1A5A3);

  static const Color sparkBlush = Color(0xFFD4E8DC); // Very pale mint/white
  static const Color sparkBlushLight = Color(0xFFFFFFFF);
  static const Color sparkGlow = Color(0x33D4E8DC);

  // Card Borders & Glassmorphic Fills
  static const Color darkGlassBorder = Color(
    0x1AFFFFFF,
  ); // 10% white for crisp subtle border
  static const Color darkGlassBorderAccent = Color(0x4473D197);
  static const Color darkGlassFill = Color(0xFF242725); // Match surface

  static const Color lightGlassBorder = darkGlassBorder;
  static const Color lightGlassBorderAccent = darkGlassBorderAccent;
  static const Color lightGlassFill = darkGlassFill;

  // Typography Tokens
  static const Color textDarkPrimary = Color(0xFFFFFFFF); // Crisp White
  static const Color textDarkSecondary = Color(0xFF9CA39F); // Sage-gray
  static const Color textDarkMuted = Color(0xFF6A706C);

  static const Color textLightPrimary = textDarkPrimary;
  static const Color textLightSecondary = textDarkSecondary;
  static const Color textLightMuted = textDarkMuted;

  // Gradients (Mint/Dark)
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF242725), Color(0xFF191C1B)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient greenGradient = LinearGradient(
    colors: [Color(0xFF90E8B2), Color(0xFF73D197)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient accentGradient = LinearGradient(
    colors: [Color(0xFF73D197), Color(0xFF5A8D6E)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const LinearGradient heroGradient = LinearGradient(
    colors: [Color(0xFF2D302E), Color(0xFF242725)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // Status & Satiety Indicators
  static const Color stableHorizon = Color(0xFF73D197); // Mint
  static const Color crashWarning = Color(
    0xFFFF8B8B,
  ); // Soft red for actual errors
  static const Color moderateCurve = Color(0xFF5A8D6E); // Muted sage
}
