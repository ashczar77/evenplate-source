import 'package:flutter/material.dart';
import '../core/legal/legal_copy.dart';
import '../core/theme/even_colors.dart';

class NutritionDisclaimer extends StatelessWidget {
  const NutritionDisclaimer({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Text(
      LegalCopy.shortDisclaimer,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 11,
        height: 1.4,
        color: isDark ? EvenColors.textDarkMuted : EvenColors.textLightMuted,
      ),
    );
  }
}
