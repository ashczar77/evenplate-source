import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/a11y/access.dart';
import '../../core/theme/even_colors.dart';
import '../../core/theme/even_fonts.dart';
import '../../core/utils/sensory_feedback.dart';
import '../../models/meal_log.dart';
import '../../services/local_storage_service.dart';
import '../../services/revenuecat_service.dart';
import '../../widgets/satiety_engine_widget.dart';
import '../../widgets/satiety_checkin_card.dart';
import '../../widgets/meal_thumb.dart';
import '../meals/add_meal_chooser.dart';
import '../meals/open_saved_meal.dart';
import '../meals/plate_blueprint_screen.dart';
import '../settings/paywall_screen.dart';
import 'today_day_status.dart';

const _mealCardRadius = 22.0;

class TodayScreen extends StatelessWidget {
  final LocalStorageService storage;
  final RevenueCatService? revenueCat;
  final VoidCallback onScanPressed;
  final VoidCallback? onInsightsPressed;
  final VoidCallback? onOpenSettings;

  const TodayScreen({
    super.key,
    required this.storage,
    this.revenueCat,
    required this.onScanPressed,
    this.onInsightsPressed,
    this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: storage.mealChanges,
      builder: (context, _) {
        final profile = storage.userProfile;
        final meals = storage.meals;
        final today = DateTime.now();

        final todayMeals = meals.where((m) {
          return m.timestamp.year == today.year &&
              m.timestamp.month == today.month &&
              m.timestamp.day == today.day;
        }).toList();

        MealLog? checkInMeal;
        for (final meal in todayMeals) {
          if (meal.isBridgeFix) continue;
          if (checkInMeal == null ||
              meal.timestamp.isBefore(checkInMeal.timestamp)) {
            checkInMeal = meal;
          }
        }

        double proteinCredit = 0;
        double fiberCredit = 0;
        double fatsCredit = 0;
        double carbsCredit = 0;

        final targetMeals = profile.targetMealsPerDay;

        for (final meal in todayMeals) {
          final pillars = meal.satietyResult.pillars;
          proteinCredit += pillars.protein.dailyCredit;
          fiberCredit += pillars.fiber.dailyCredit;
          fatsCredit += pillars.fats.dailyCredit;
          carbsCredit += pillars.carbs.dailyCredit;
        }

        final proteinProgress = (proteinCredit / targetMeals.toDouble()).clamp(
          0.0,
          1.5,
        );
        final fiberProgress = (fiberCredit / targetMeals.toDouble()).clamp(
          0.0,
          1.5,
        );
        final fatsProgress = (fatsCredit / targetMeals.toDouble()).clamp(
          0.0,
          1.5,
        );
        final carbsProgress = (carbsCredit / targetMeals.toDouble()).clamp(
          0.0,
          1.5,
        );

        final plateCount = todayMeals.where((m) => !m.isBridgeFix).length;
        final dayStatus = TodayDayStatus.from(
          plateCount: plateCount,
          targetMeals: targetMeals,
          proteinProgress: proteinProgress,
          fiberProgress: fiberProgress,
          fatsProgress: fatsProgress,
          carbsProgress: carbsProgress,
        );
        final hasPlates = plateCount > 0;

        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Scaffold(
          backgroundColor: isDark
              ? EvenColors.darkBackground
              : EvenColors.lightBackground,
          body: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // Hero Header
              SliverToBoxAdapter(
                child: ListenableBuilder(
                  listenable: storage.profileChanges,
                  builder: (context, _) => _HeroHeader(
                    photoLeft: storage.photoLeft,
                    isPro: storage.hasPro,
                    today: today,
                    onProTapped: () {
                      SensoryFeedback.gentleTap();
                      if (storage.hasPro) {
                        onOpenSettings?.call();
                        return;
                      }
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PaywallScreen(
                            storage: storage,
                            revenueCatService: revenueCat,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

              // Weekday Strip
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 4,
                  ),
                  child: _WeekdayStrip(today: today),
                ),
              ),

              // Satiety Circle Hero
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                  child: _SatietyHeroCard(
                    proteinProgress: proteinProgress,
                    fiberProgress: fiberProgress,
                    fatsProgress: fatsProgress,
                    carbsProgress: carbsProgress,
                    title: dayStatus.title,
                    subtitle: dayStatus.subtitle,
                    onInsightsTapped: onInsightsPressed,
                  ),
                ),
              ),

              // 4 Pillar Badges
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _PillarBadge(
                          icon: Icons.fitness_center_rounded,
                          label: 'Protein',
                          value: TodayDayStatus.pillarLabel(
                            proteinProgress,
                            hasPlates: hasPlates,
                          ),
                          color: EvenColors.anchorTerracotta,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _PillarBadge(
                          icon: Icons.eco_rounded,
                          label: 'Fiber',
                          value: TodayDayStatus.pillarLabel(
                            fiberProgress,
                            hasPlates: hasPlates,
                          ),
                          color: EvenColors.netSage,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _PillarBadge(
                          icon: Icons.water_drop_rounded,
                          label: 'Fat',
                          value: TodayDayStatus.pillarLabel(
                            fatsProgress,
                            hasPlates: hasPlates,
                          ),
                          color: EvenColors.bufferAmber,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _PillarBadge(
                          icon: Icons.grain_rounded,
                          label: 'Volume',
                          value: TodayDayStatus.pillarLabel(
                            carbsProgress,
                            hasPlates: hasPlates,
                          ),
                          color: EvenColors.sparkBlush,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Check-in Card
              if (checkInMeal != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    child: SatietyCheckinCard(
                      meal: checkInMeal,
                      storage: storage,
                    ),
                  ),
                ),

              // Today's Meals Section
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Today's Meals",
                        style: evenPoppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? EvenColors.textDarkPrimary
                              : EvenColors.textLightPrimary,
                          letterSpacing: -0.3,
                        ),
                      ),
                      _GradientButton(
                        label: dayStatus.addPlateLabel,
                        icon: Icons.add_rounded,
                        quiet: dayStatus.dayLogged,
                        onTap: () {
                          showAddMealChooser(
                            context,
                            storage: storage,
                            onScan: onScanPressed,
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),

              // Meals List or Empty State
              if (todayMeals.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    child: _EmptyMealsCard(
                      storage: storage,
                      onScanPressed: onScanPressed,
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _SwipeToDeleteMeal(
                          meal: todayMeals[index],
                          onOpen: () {
                            openSavedMeal(
                              context,
                              storage: storage,
                              meal: todayMeals[index],
                            );
                          },
                          onDeleted: () {
                            SensoryFeedback.gentleTap();
                            storage.deleteMeal(todayMeals[index].id);
                          },
                        ),
                      );
                    }, childCount: todayMeals.length),
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          ),
        );
      },
    );
  }
}

// Hero Header

class _HeroHeader extends StatelessWidget {
  final int photoLeft;
  final bool isPro;
  final DateTime today;
  final VoidCallback onProTapped;

  const _HeroHeader({
    required this.photoLeft,
    required this.isPro,
    required this.today,
    required this.onProTapped,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 16,
        left: 20,
        right: 20,
        bottom: 20,
      ),
      decoration: BoxDecoration(
        color: isDark ? EvenColors.darkBackground : EvenColors.lightBackground,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat('EEEE, MMM d').format(today).toUpperCase(),
                  style: evenPoppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? EvenColors.netSageLight
                        : EvenColors.primaryGreen,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Daily\nHarmony',
                  style: evenPoppins(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: isDark
                        ? EvenColors.textDarkPrimary
                        : EvenColors.textLightPrimary,
                    letterSpacing: -1.0,
                    height: 1.05,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onProTapped,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                gradient: isPro
                    ? const LinearGradient(
                        colors: [Color(0xFFFFB547), Color(0xFFFF6B6B)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: isPro
                    ? null
                    : (isDark
                          ? EvenColors.darkSurfaceElevated
                          : EvenColors.lightSurface),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isPro
                      ? Colors.transparent
                      : EvenColors.darkGlassBorder,
                  width: 1,
                ),
                boxShadow: isPro
                    ? safeBoxShadows([
                        BoxShadow(
                          color: EvenColors.bufferAmber.withValues(alpha: 0.4),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ])
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isPro ? Icons.star_rounded : Icons.camera_alt_outlined,
                    size: 14,
                    color: isPro
                        ? Colors.white
                        : (isDark
                              ? EvenColors.netSageLight
                              : EvenColors.primaryGreen),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$photoLeft left',
                    style: evenPoppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isPro
                          ? Colors.white
                          : (isDark
                                ? EvenColors.netSageLight
                                : EvenColors.primaryGreen),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Weekday Strip

class _WeekdayStrip extends StatelessWidget {
  final DateTime today;

  const _WeekdayStrip({required this.today});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
    final weekdays = List.generate(
      7,
      (i) => startOfWeek.add(Duration(days: i)),
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: weekdays.map((date) {
        final isToday =
            date.year == today.year &&
            date.month == today.month &&
            date.day == today.day;
        final dayName = DateFormat('E').format(date).substring(0, 1);
        final dayNumber = date.day.toString();

        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 42,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            gradient: isToday
                ? const LinearGradient(
                    colors: [
                      EvenColors.primaryGreenLight,
                      EvenColors.primaryGreen,
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  )
                : null,
            color: isToday ? null : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: isToday
                ? null
                : Border.all(color: Colors.transparent, width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                dayName,
                style: evenPoppins(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: isToday
                      ? Colors.white.withValues(alpha: 0.8)
                      : EvenColors.textDarkMuted,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                dayNumber,
                style: evenPoppins(
                  fontSize: 13,
                  fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                  color: isToday
                      ? Colors.white
                      : (isDark
                            ? EvenColors.textDarkPrimary
                            : EvenColors.textLightPrimary),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// Satiety Hero Card

class _SatietyHeroCard extends StatelessWidget {
  final double proteinProgress;
  final double fiberProgress;
  final double fatsProgress;
  final double carbsProgress;
  final String title;
  final String subtitle;
  final VoidCallback? onInsightsTapped;

  const _SatietyHeroCard({
    required this.proteinProgress,
    required this.fiberProgress,
    required this.fatsProgress,
    required this.carbsProgress,
    required this.title,
    required this.subtitle,
    this.onInsightsTapped,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark
              ? EvenColors.darkSurfaceCard
              : EvenColors.lightSurfaceCard,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: isDark
                ? EvenColors.darkGlassBorder
                : EvenColors.lightGlassBorder,
            width: 1,
          ),
          boxShadow: safeBoxShadows([
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ]),
        ),
        child: Column(
          children: [
            Center(
              child: Column(
                children: [
                  SatietyEngineWidget(
                    proteinProgress: proteinProgress,
                    fiberProgress: fiberProgress,
                    fatsProgress: fatsProgress,
                    carbsProgress: carbsProgress,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: evenPoppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      color: isDark
                          ? EvenColors.textDarkPrimary
                          : EvenColors.textLightPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: evenPoppins(
                      fontSize: 13,
                      color: isDark
                          ? EvenColors.textDarkSecondary
                          : EvenColors.textLightSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (onInsightsTapped != null) ...[
              const SizedBox(height: 16),
              GestureDetector(
                key: const ValueKey('btn_view_full_insights'),
                onTap: onInsightsTapped,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: EvenColors.primaryGreen.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: EvenColors.primaryGreen.withValues(alpha: 0.25),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.insights_rounded,
                        size: 15,
                        color: isDark
                            ? EvenColors.netSageLight
                            : EvenColors.primaryGreen,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        'View Full Insights',
                        style: evenPoppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? EvenColors.netSageLight
                              : EvenColors.primaryGreen,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// Pillar Badge

class _PillarBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _PillarBadge({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: isDark
            ? EvenColors.darkSurfaceCard
            : EvenColors.lightSurfaceCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.18), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 14),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: evenPoppins(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: evenPoppins(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? EvenColors.textDarkMuted
                  : EvenColors.textLightMuted,
            ),
          ),
        ],
      ),
    );
  }
}

// Gradient CTA Button

class _GradientButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool quiet;

  const _GradientButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.quiet = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = quiet
        ? (isDark
              ? EvenColors.textDarkSecondary
              : EvenColors.textLightSecondary)
        : Colors.white;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          gradient: quiet
              ? null
              : const LinearGradient(
                  colors: [
                    EvenColors.primaryGreenLight,
                    EvenColors.primaryGreen,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          color: quiet
              ? (isDark
                    ? EvenColors.darkSurfaceElevated
                    : EvenColors.lightSurface)
              : null,
          borderRadius: BorderRadius.circular(20),
          border: quiet
              ? Border.all(
                  color: isDark
                      ? EvenColors.darkGlassBorder
                      : EvenColors.lightGlassBorder,
                )
              : null,
          boxShadow: quiet
              ? const []
              : safeBoxShadows([
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: fg),
            const SizedBox(width: 6),
            Text(
              label,
              style: evenPoppins(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Empty Meals Card

class _EmptyMealsCard extends StatelessWidget {
  final LocalStorageService storage;
  final VoidCallback onScanPressed;

  const _EmptyMealsCard({required this.storage, required this.onScanPressed});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      decoration: BoxDecoration(
        color: isDark
            ? EvenColors.darkSurfaceCard
            : EvenColors.lightSurfaceCard,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark
              ? EvenColors.darkGlassBorder
              : EvenColors.lightGlassBorder,
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1A1F3C), Color(0xFF111427)],
              ),
              shape: BoxShape.circle,
              border: Border.all(
                color: EvenColors.darkGlassBorderAccent,
                width: 1.5,
              ),
            ),
            child: const Center(
              child: Icon(
                Icons.restaurant_menu_rounded,
                color: EvenColors.primaryGreen,
                size: 28,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No plates yet',
            style: evenPoppins(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: EvenColors.textDarkPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Build the combo before you eat, or scan what is in front of you.',
            textAlign: TextAlign.center,
            style: evenPoppins(
              fontSize: 13,
              color: EvenColors.textDarkSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              key: const ValueKey('btn_build_plate_empty'),
              onPressed: () {
                PlateBlueprintScreen.show(context, storage);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: EvenColors.primaryGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Build a plate',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              key: const ValueKey('btn_scan_empty'),
              onPressed: onScanPressed,
              style: OutlinedButton.styleFrom(
                foregroundColor: EvenColors.netSageLight,
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: const BorderSide(color: EvenColors.netSageLight),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
              ),
              child: const Text(
                'Scan a plate',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Meal Card

class _SwipeToDeleteMeal extends StatelessWidget {
  final MealLog meal;
  final VoidCallback onDeleted;
  final VoidCallback onOpen;

  const _SwipeToDeleteMeal({
    required this.meal,
    required this.onDeleted,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(_mealCardRadius),
      child: Stack(
        children: [
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0xE8D96B6B),
              child: Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: EdgeInsets.only(right: 24),
                  child: Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
            ),
          ),
          Dismissible(
            key: Key(meal.id),
            direction: DismissDirection.endToStart,
            onDismissed: (_) => onDeleted(),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                key: ValueKey('meal_card_${meal.id}'),
                onTap: onOpen,
                child: _MealCard(meal: meal),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MealCard extends StatelessWidget {
  final MealLog meal;

  const _MealCard({required this.meal});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pillars = meal.satietyResult.pillars;
    final timeStr = DateFormat('h:mm a').format(meal.timestamp);

    return Container(
      padding: const EdgeInsets.all(16),
      color: isDark ? EvenColors.darkSurfaceCard : EvenColors.lightSurfaceCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MealThumb(
                imagePath: meal.imagePath,
                semanticLabel: meal.mealName,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      meal.mealName.isNotEmpty
                          ? meal.mealName
                          : 'Plate Analysis',
                      style: evenPoppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: EvenColors.textDarkPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      timeStr,
                      style: evenPoppins(
                        fontSize: 11,
                        color: isDark
                            ? EvenColors.textDarkMuted
                            : EvenColors.textLightMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00E5A0), Color(0xFF00B47D)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: safeBoxShadows([
                    BoxShadow(
                      color: EvenColors.netSage.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]),
                ),
                child: Text(
                  meal.satietyResult.fullnessLabel,
                  style: evenPoppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          if (pillars.anchor.isAligned ||
              pillars.net.isAligned ||
              pillars.buffer.isAligned) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (pillars.anchor.isAligned)
                  _PillarTag(
                    label: 'Protein',
                    color: EvenColors.anchorTerracotta,
                  ),
                if (pillars.net.isAligned)
                  _PillarTag(label: 'Fiber', color: EvenColors.netSage),
                if (pillars.buffer.isAligned)
                  _PillarTag(label: 'Fat', color: EvenColors.bufferAmber),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PillarTag extends StatelessWidget {
  final String label;
  final Color color;

  const _PillarTag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1),
      ),
      child: Text(
        label,
        style: evenPoppins(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
