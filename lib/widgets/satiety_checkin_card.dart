import 'package:flutter/material.dart';
import '../core/theme/even_colors.dart';
import '../core/utils/sensory_feedback.dart';
import '../features/insights/check_in_verdict.dart';
import '../features/meals/plate_blueprint_screen.dart';
import '../models/meal_log.dart';
import '../services/local_storage_service.dart';
import 'bridge_snack_sheet.dart';
import 'even_snack.dart';
import 'glass_card.dart';

/// In-App Post-Meal Energy Check-In Card
/// Prompts users to check in on their sustained satiety hours post-meal.
class SatietyCheckinCard extends StatelessWidget {
  final MealLog meal;
  final LocalStorageService storage;

  const SatietyCheckinCard({
    super.key,
    required this.meal,
    required this.storage,
  });

  void _onSteady(BuildContext context) async {
    SensoryFeedback.zenBloomPulse();
    await storage.updateMealEnergyCheckIn(meal.id, 'steady');

    if (context.mounted) {
      EvenSnack.show(
        context,
        'Logged: you stayed even.',
        icon: Icons.bolt_rounded,
        iconColor: EvenColors.bufferAmber,
      );
    }
  }

  void _onDip(BuildContext context) async {
    SensoryFeedback.gentleTap();
    await storage.updateMealEnergyCheckIn(meal.id, 'dip');
    if (!context.mounted) return;
    BridgeSnackSheet.show(context, storage, applyTo: meal);
  }

  void _onUndo() {
    SensoryFeedback.gentleTap();
    storage.resetMealCheckIn(meal.id);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: storage.mealChanges,
      builder: (context, _) {
        MealLog live = meal;
        for (final logged in storage.meals) {
          if (logged.id == meal.id) {
            live = logged;
            break;
          }
        }
        return _buildCard(context, live);
      },
    );
  }

  Widget _buildCard(BuildContext context, MealLog meal) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final checkIn = meal.energyCheckIn;

    return GlassCard(
      padding: const EdgeInsets.all(16),
      radius: 20,
      customBorder: checkIn != null
          ? (checkIn == 'steady'
                ? EvenColors.stableHorizon.withValues(alpha: 0.4)
                : EvenColors.bufferAmber.withValues(alpha: 0.4))
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color:
                      (checkIn == 'steady'
                              ? EvenColors.stableHorizon
                              : EvenColors.bufferAmber)
                          .withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  checkIn == 'steady'
                      ? Icons.bolt_rounded
                      : Icons.hourglass_bottom_rounded,
                  size: 18,
                  color: checkIn == 'steady'
                      ? EvenColors.stableHorizon
                      : EvenColors.bufferAmber,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Satiety Energy Check-in',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      meal.mealName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? EvenColors.textDarkSecondary
                            : EvenColors.textLightSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (checkIn != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color:
                        (checkIn == 'steady'
                                ? EvenColors.stableHorizon
                                : EvenColors.bufferAmber)
                            .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        checkIn == 'steady'
                            ? Icons.check_circle_rounded
                            : Icons.info_outline_rounded,
                        size: 12,
                        color: checkIn == 'steady'
                            ? EvenColors.stableHorizon
                            : EvenColors.bufferAmber,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        checkIn == 'steady' ? 'Steady' : 'Bridge Fix',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: checkIn == 'steady'
                              ? EvenColors.stableHorizon
                              : EvenColors.bufferAmber,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),

          if (checkIn == null) ...[
            const SizedBox(height: 12),
            Text(
              'How did you feel after ${meal.mealName}?',
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: isDark
                    ? EvenColors.textDarkSecondary
                    : EvenColors.textLightSecondary,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    key: ValueKey('btn_checkin_steady_${meal.id}'),
                    onPressed: () => _onSteady(context),
                    icon: const Icon(Icons.bolt_rounded, size: 16),
                    label: const Text(
                      'Steady & Focused',
                      style: TextStyle(fontSize: 12),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: EvenColors.stableHorizon,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    key: ValueKey('btn_checkin_dip_${meal.id}'),
                    onPressed: () => _onDip(context),
                    icon: const Icon(Icons.fastfood_outlined, size: 16),
                    label: const Text(
                      'Feeling a Dip',
                      style: TextStyle(fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: EvenColors.bufferAmber,
                      side: const BorderSide(color: EvenColors.bufferAmber),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 10),
            Builder(
              builder: (context) {
                final verdict = CheckInVerdict.from(meal);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      verdict.headline,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                        color: isDark
                            ? EvenColors.textDarkPrimary
                            : EvenColors.textLightPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      verdict.body,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: isDark
                            ? EvenColors.textDarkSecondary
                            : EvenColors.textLightSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      verdict.nextTip,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: isDark
                            ? EvenColors.textDarkSecondary
                            : EvenColors.textLightSecondary,
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        key: ValueKey('btn_checkin_build_${meal.id}'),
                        onPressed: () {
                          PlateBlueprintScreen.show(
                            context,
                            storage,
                            highlightPillar: verdict.gapId,
                          );
                        },
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                        ),
                        child: const Text(
                          'Build the next plate',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        key: ValueKey('btn_checkin_undo_${meal.id}'),
                        onPressed: _onUndo,
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                        ),
                        child: const Text(
                          'Undo',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
