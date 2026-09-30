import 'package:flutter/material.dart';
import '../core/theme/even_colors.dart';

/// One look for every short status line: dark mint bar, white copy.
class EvenSnack {
  EvenSnack._();

  static void show(
    BuildContext context,
    String message, {
    IconData? icon,
    Color iconColor = EvenColors.primaryGreen,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: iconColor, size: 18),
              const SizedBox(width: 10),
            ],
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}
