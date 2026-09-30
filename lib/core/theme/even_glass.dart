import 'package:flutter/material.dart';
import '../a11y/access.dart';
import 'even_colors.dart';

/// EvenPlate: Premium Dark Glassmorphism Visual Tokens
class EvenGlass {
  EvenGlass._();

  static const double defaultBlur = 20.0;
  static const double defaultRadius = 16.0;

  /// Dark premium glass card decoration
  static BoxDecoration boxDecoration({
    required bool isDark,
    double radius = defaultRadius,
    Color? customFill,
    Color? customBorder,
    List<BoxShadow>? shadows,
    bool accentBorder = false,
  }) {
    return BoxDecoration(
      color:
          customFill ??
          (isDark ? EvenColors.darkSurfaceCard : EvenColors.lightSurface),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color:
            customBorder ??
            (accentBorder
                ? EvenColors.darkGlassBorderAccent
                : isDark
                ? EvenColors.darkGlassBorder
                : EvenColors.lightGlassBorder),
        width: 1.0,
      ),
      boxShadow: safeBoxShadows(
        shadows ??
            [
              BoxShadow(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.45)
                    : Colors.black.withValues(alpha: 0.06),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
              if (isDark && accentBorder)
                BoxShadow(
                  color: EvenColors.primaryGreen.withValues(alpha: 0.15),
                  blurRadius: 24,
                  offset: const Offset(0, 4),
                ),
            ],
      ),
    );
  }

  /// Rounded card. Fill is opaque, so a live BackdropFilter would be wasted
  /// GPU work and has aborted the iOS Simulator Metal host.
  static Widget frostedCard({
    required BuildContext context,
    required Widget child,
    EdgeInsetsGeometry? padding,
    double radius = defaultRadius,
    double blur = defaultBlur,
    Color? customFill,
    Color? customBorder,
    bool accentBorder = false,
    VoidCallback? onTap,
  }) {
    assert(blur >= 0);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardContent = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        padding: padding ?? const EdgeInsets.all(20),
        decoration: boxDecoration(
          isDark: isDark,
          radius: radius,
          customFill: customFill,
          customBorder: customBorder,
          accentBorder: accentBorder,
        ),
        child: Material(color: Colors.transparent, child: child),
      ),
    );

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: onTap,
          child: cardContent,
        ),
      );
    }

    return cardContent;
  }

  /// Gradient CTA button
  static Widget gradientButton({
    required String label,
    required VoidCallback onTap,
    IconData? icon,
    double borderRadius = 20,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        decoration: BoxDecoration(
          gradient: EvenColors.primaryGradient,
          borderRadius: BorderRadius.circular(borderRadius),
          boxShadow: safeBoxShadows([
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ]),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, color: Colors.white, size: 16),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
