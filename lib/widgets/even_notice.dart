import 'package:flutter/material.dart';
import '../core/theme/even_colors.dart';

/// Inline status card that matches [EvenSnack]: dark mint bar, white copy.
class EvenNotice extends StatelessWidget {
  final String message;
  final IconData icon;
  final Color accent;

  const EvenNotice({
    super.key,
    required this.message,
    required this.icon,
    this.accent = EvenColors.primaryGreen,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: EvenColors.darkSurfaceElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, color: accent, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: EvenColors.textDarkPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
