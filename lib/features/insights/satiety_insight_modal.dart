import 'package:flutter/material.dart';
import '../../core/a11y/access.dart';
import '../../core/theme/even_colors.dart';
import 'insight_mark.dart';
import 'satiety_insight_state.dart';

class SatietyInsightModal extends StatelessWidget {
  final SatietyInsightState insightState;
  final String confirmLabel;
  final VoidCallback? onConfirm;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  const SatietyInsightModal({
    super.key,
    required this.insightState,
    this.confirmLabel = 'Got it',
    this.onConfirm,
    this.secondaryLabel,
    this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: EvenColors.darkSurfaceCard,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: EvenColors.darkGlassBorder),
          boxShadow: safeBoxShadows([
            BoxShadow(
              color: EvenColors.primaryGreen.withValues(alpha: 0.12),
              blurRadius: 28,
              spreadRadius: 2,
            ),
          ]),
        ),
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              InsightMark(type: insightState.type),
              const SizedBox(height: 28),
              Text(
                insightState.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: EvenColors.primaryGreen,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                insightState.description,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: EvenColors.textDarkSecondary,
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 28),
              if (secondaryLabel != null) ...[
                TextButton(
                  key: const ValueKey('btn_insight_secondary'),
                  onPressed: onSecondary ?? () => Navigator.pop(context),
                  child: Text(
                    secondaryLabel!,
                    style: const TextStyle(
                      color: EvenColors.textDarkSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              ElevatedButton(
                onPressed: onConfirm ?? () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: EvenColors.primaryGreen,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  confirmLabel,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
