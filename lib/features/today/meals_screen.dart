import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme/even_colors.dart';
import '../../core/utils/sensory_feedback.dart';
import '../../models/meal_log.dart';
import '../../services/local_storage_service.dart';
import '../meals/add_meal_chooser.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/meal_thumb.dart';

class MealsScreen extends StatelessWidget {
  final LocalStorageService storage;
  final VoidCallback onScanPressed;

  const MealsScreen({
    super.key,
    required this.storage,
    required this.onScanPressed,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final meals = storage.meals;

    final today = DateTime.now();
    final todayMeals = meals.where((m) {
      return m.timestamp.year == today.year &&
          m.timestamp.month == today.month &&
          m.timestamp.day == today.day;
    }).toList();

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // Top Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Row(
                  children: [
                    if (Navigator.of(context).canPop()) ...[
                      GestureDetector(
                        onTap: () {
                          SensoryFeedback.gentleTap();
                          Navigator.of(context).pop();
                        },
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : Colors.black.withValues(alpha: 0.05),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.12)
                                  : Colors.black.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Icon(
                            Icons.arrow_back_ios_new_rounded,
                            size: 18,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Nutrition & Satiety Log',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                              color: isDark
                                  ? EvenColors.textDarkMuted
                                  : EvenColors.textLightMuted,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Meal Diary',
                            style: Theme.of(context).textTheme.displayMedium,
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () {
                        showAddMealChooser(
                          context,
                          storage: storage,
                          onScan: onScanPressed,
                        );
                      },
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add Plate'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: EvenColors.netSage,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Summary Card
            if (todayMeals.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  child: GlassCard(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: EvenColors.netSage.withValues(
                                  alpha: 0.12,
                                ),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.hourglass_top_rounded,
                                color: EvenColors.netSage,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${todayMeals.length} Plates Logged',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: isDark
                                        ? EvenColors.textDarkPrimary
                                        : EvenColors.textLightPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${todayMeals.length} plates logged today',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? EvenColors.textDarkMuted
                                        : EvenColors.textLightMuted,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: EvenColors.netSage.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            'Today',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: EvenColors.netSage,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Meals List
            if (todayMeals.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
                  child: GlassCard(
                    padding: const EdgeInsets.symmetric(
                      vertical: 40,
                      horizontal: 24,
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: EvenColors.netSage.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.restaurant_menu_rounded,
                              size: 32,
                              color: EvenColors.primaryGreen,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No plates logged today',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? EvenColors.textDarkPrimary
                                : EvenColors.textLightPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Snap a photo of your meal to analyze protein anchors, fiber nets, and your satiety curve.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark
                                ? EvenColors.textDarkSecondary
                                : EvenColors.textLightSecondary,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: () {
                            showAddMealChooser(
                              context,
                              storage: storage,
                              onScan: onScanPressed,
                            );
                          },
                          icon: const Icon(Icons.camera_alt_rounded, size: 18),
                          label: const Text('Add First Meal'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: EvenColors.netSage,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(22),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final meal = todayMeals[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _buildMealCard(context, meal, isDark),
                    );
                  }, childCount: todayMeals.length),
                ),
              ),

            const SliverToBoxAdapter(child: SizedBox(height: 110)),
          ],
        ),
      ),
    );
  }

  Widget _buildMealCard(BuildContext context, MealLog meal, bool isDark) {
    final pillars = meal.satietyResult.pillars;
    final timeStr = DateFormat('h:mm a').format(meal.timestamp);

    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  MealThumb(
                    imagePath: meal.imagePath,
                    size: 36,
                    semanticLabel: meal.mealName,
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        meal.mealName.isNotEmpty
                            ? meal.mealName
                            : 'Plate Analysis',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? EvenColors.textDarkPrimary
                              : EvenColors.textLightPrimary,
                        ),
                      ),
                      Text(
                        timeStr,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? EvenColors.textDarkMuted
                              : EvenColors.textLightMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: EvenColors.netSage.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  meal.satietyResult.fullnessLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: EvenColors.netSage,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (pillars.anchor.isAligned)
                _buildPillarBadge(
                  label: 'Anchor (Protein)',
                  color: EvenColors.anchorTerracotta,
                  isDark: isDark,
                ),
              if (pillars.net.isAligned)
                _buildPillarBadge(
                  label: 'Net (Fiber)',
                  color: EvenColors.netSage,
                  isDark: isDark,
                ),
              if (pillars.buffer.isAligned)
                _buildPillarBadge(
                  label: 'Fat',
                  color: EvenColors.bufferAmber,
                  isDark: isDark,
                ),
            ],
          ),
          if (meal.satietyResult.components.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              meal.satietyResult.components.join(', '),
              style: TextStyle(
                fontSize: 12,
                color: isDark
                    ? EvenColors.textDarkSecondary
                    : EvenColors.textLightSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPillarBadge({
    required String label,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
