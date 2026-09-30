import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme/even_colors.dart';
import '../../core/utils/sensory_feedback.dart';
import '../../models/meal_log.dart';
import '../../services/local_storage_service.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/meal_thumb.dart';
import '../meals/open_saved_meal.dart';
import 'insights_stats.dart';

const _insightsPageSize = 6;

class InsightsScreen extends StatefulWidget {
  final LocalStorageService storage;
  final VoidCallback? onScanPressed;

  const InsightsScreen({super.key, required this.storage, this.onScanPressed});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  InsightsRange _range = InsightsRange.week;
  InsightPillar? _selectedPillar;

  void _openMeal(MealLog meal) {
    openSavedMeal(context, storage: widget.storage, meal: meal);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.storage.mealChanges,
      builder: (context, _) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final stats = InsightsStats.fromMeals(
          widget.storage.meals,
          range: _range,
        );

        return Scaffold(
          body: SafeArea(
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
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
                                color: Colors.white.withValues(alpha: 0.08),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.12),
                                ),
                              ),
                              child: const Icon(
                                Icons.arrow_back_ios_new_rounded,
                                size: 18,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                        ],
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Satiety Trends',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: EvenColors.textDarkMuted,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Body Rhythm',
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Row(
                      children: [
                        _RangeChip(
                          id: 'chip_insights_today',
                          label: 'Today',
                          selected: _range == InsightsRange.today,
                          onTap: () => setState(() {
                            _range = InsightsRange.today;
                            _selectedPillar = null;
                          }),
                        ),
                        const SizedBox(width: 8),
                        _RangeChip(
                          id: 'chip_insights_week',
                          label: '7 days',
                          selected: _range == InsightsRange.week,
                          onTap: () => setState(() {
                            _range = InsightsRange.week;
                            _selectedPillar = null;
                          }),
                        ),
                        const SizedBox(width: 8),
                        _RangeChip(
                          id: 'chip_insights_month',
                          label: '30 days',
                          selected: _range == InsightsRange.month,
                          onTap: () => setState(() {
                            _range = InsightsRange.month;
                            _selectedPillar = null;
                          }),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    child: GlassCard(
                      padding: const EdgeInsets.all(22),
                      child: stats.isEmpty
                          ? _EmptyRange(
                              rangePhrase: stats.rangePhrase,
                              onScan: widget.onScanPressed,
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  stats.headline,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${stats.plateCountLabel}. Fully aligned on ${stats.fullMatrixCount} of ${stats.totalLogged}.',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
                if (!stats.isEmpty &&
                    (stats.dipCount > 0 || stats.steadyCount > 0))
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      child: GlassCard(
                        padding: const EdgeInsets.all(22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Held vs dipped',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${stats.steadyCount} held \u00b7 ${stats.dipCount} dipped',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            if (stats.dippedPlates.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Text(
                                'Dipped: ${stats.dippedPlates.first.mealName}',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              TextButton(
                                key: const ValueKey('btn_insights_dipped_meal'),
                                onPressed: () =>
                                    _openMeal(stats.dippedPlates.first),
                                child: const Text('Open dipped plate'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                if (!stats.isEmpty) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      child: GlassCard(
                        padding: const EdgeInsets.all(22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Average relative fullness',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 10),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  stats.avgFullness?.toStringAsFixed(1) ?? '--',
                                  style: const TextStyle(
                                    fontSize: 38,
                                    fontWeight: FontWeight.w700,
                                    color: EvenColors.textDarkPrimary,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'estimated fullness / 100',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: EvenColors.textDarkSecondary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Nutrient-based comparison. Unrated plates are excluded.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            if (stats.dipCount > 0 ||
                                stats.steadyCount > 0) ...[
                              const SizedBox(height: 8),
                              Text(
                                [
                                  if (stats.dipCount > 0)
                                    'Dip recorded on ${stats.dipCount}',
                                  if (stats.steadyCount > 0)
                                    'steady on ${stats.steadyCount}',
                                ].join(', '),
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      child: GlassCard(
                        padding: const EdgeInsets.all(22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Pillar consistency',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Tap a pillar to see which plates missed it.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 16),
                            _PillarRow(
                              pillar: InsightPillar.protein,
                              hits: stats.proteinHit,
                              total: stats.totalLogged,
                              rate: stats.proteinRate,
                              color: EvenColors.anchorTerracotta,
                              selected:
                                  _selectedPillar == InsightPillar.protein,
                              onTap: () => setState(() {
                                _selectedPillar =
                                    _selectedPillar == InsightPillar.protein
                                    ? null
                                    : InsightPillar.protein;
                              }),
                            ),
                            const SizedBox(height: 12),
                            _PillarRow(
                              pillar: InsightPillar.fiber,
                              hits: stats.fiberHit,
                              total: stats.totalLogged,
                              rate: stats.fiberRate,
                              color: EvenColors.netSage,
                              selected: _selectedPillar == InsightPillar.fiber,
                              onTap: () => setState(() {
                                _selectedPillar =
                                    _selectedPillar == InsightPillar.fiber
                                    ? null
                                    : InsightPillar.fiber;
                              }),
                            ),
                            const SizedBox(height: 12),
                            _PillarRow(
                              pillar: InsightPillar.fats,
                              hits: stats.fatsHit,
                              total: stats.totalLogged,
                              rate: stats.bufferRate,
                              color: EvenColors.bufferAmber,
                              selected: _selectedPillar == InsightPillar.fats,
                              onTap: () => setState(() {
                                _selectedPillar =
                                    _selectedPillar == InsightPillar.fats
                                    ? null
                                    : InsightPillar.fats;
                              }),
                            ),
                            const SizedBox(height: 12),
                            _PillarRow(
                              pillar: InsightPillar.spark,
                              hits: stats.sparkHit,
                              total: stats.totalLogged,
                              rate: stats.sparkRate,
                              color: EvenColors.sparkBlush,
                              selected: _selectedPillar == InsightPillar.spark,
                              onTap: () => setState(() {
                                _selectedPillar =
                                    _selectedPillar == InsightPillar.spark
                                    ? null
                                    : InsightPillar.spark;
                              }),
                            ),
                            if (_selectedPillar != null) ...[
                              const SizedBox(height: 18),
                              _MissedList(
                                pillar: _selectedPillar!,
                                missed: stats.missed(_selectedPillar!),
                                onMeal: _openMeal,
                                onScan: widget.onScanPressed,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      child: GlassCard(
                        padding: const EdgeInsets.all(22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Plates ${stats.rangePhrase}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 14),
                            _PagedMealList(
                              key: ValueKey('plates_${_range.name}'),
                              meals: stats.plates,
                              onMeal: _openMeal,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    child: Text(
                      'EvenPlate is not a medical device. These insights are for information only.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white54 : Colors.black54,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RangeChip extends StatelessWidget {
  final String id;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _RangeChip({
    required this.id,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: ValueKey(id),
      onTap: () {
        SensoryFeedback.gentleTap();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? EvenColors.primaryGreen.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? EvenColors.primaryGreen.withValues(alpha: 0.5)
                : EvenColors.darkGlassBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected
                ? EvenColors.primaryGreen
                : EvenColors.textDarkSecondary,
          ),
        ),
      ),
    );
  }
}

class _EmptyRange extends StatelessWidget {
  final String rangePhrase;
  final VoidCallback? onScan;

  const _EmptyRange({required this.rangePhrase, this.onScan});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'No plates $rangePhrase',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Log a plate to see how protein, fiber, fat, and volume held.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        if (onScan != null) ...[
          const SizedBox(height: 16),
          TextButton(
            key: const ValueKey('btn_insights_scan'),
            onPressed: onScan,
            child: const Text('Scan a plate'),
          ),
        ],
      ],
    );
  }
}

class _PillarRow extends StatelessWidget {
  final InsightPillar pillar;
  final int hits;
  final int total;
  final double rate;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _PillarRow({
    required this.pillar,
    required this.hits,
    required this.total,
    required this.rate,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: ValueKey('pillar_${pillar.name}'),
      onTap: () {
        SensoryFeedback.gentleTap();
        onTap();
      },
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  InsightsStats.labelFor(pillar),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: EvenColors.textDarkPrimary,
                  ),
                ),
                Text(
                  '$hits/$total',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: rate.clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: EvenColors.darkSurfaceElevated,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MissedList extends StatelessWidget {
  final InsightPillar pillar;
  final List<MealLog> missed;
  final ValueChanged<MealLog> onMeal;
  final VoidCallback? onScan;

  const _MissedList({
    required this.pillar,
    required this.missed,
    required this.onMeal,
    this.onScan,
  });

  @override
  Widget build(BuildContext context) {
    final name = InsightsStats.labelFor(pillar).toLowerCase();
    if (missed.isEmpty) {
      return Text(
        'Every plate in this range landed $name.',
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Missed $name',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: EvenColors.textDarkMuted,
          ),
        ),
        const SizedBox(height: 8),
        _PagedMealList(
          key: ValueKey('missed_${pillar.name}'),
          meals: missed,
          onMeal: onMeal,
          compact: true,
          moreKey: 'btn_insights_missed_show_more',
          lessKey: 'btn_insights_missed_show_less',
        ),
        if (onScan != null)
          TextButton(onPressed: onScan, child: Text('Scan with $name in mind')),
      ],
    );
  }
}

class _PagedMealList extends StatefulWidget {
  final List<MealLog> meals;
  final ValueChanged<MealLog> onMeal;
  final bool compact;
  final String moreKey;
  final String lessKey;

  const _PagedMealList({
    super.key,
    required this.meals,
    required this.onMeal,
    this.compact = false,
    this.moreKey = 'btn_insights_show_more',
    this.lessKey = 'btn_insights_show_less',
  });

  @override
  State<_PagedMealList> createState() => _PagedMealListState();
}

class _PagedMealListState extends State<_PagedMealList> {
  int _visible = _insightsPageSize;

  @override
  Widget build(BuildContext context) {
    final total = widget.meals.length;
    final shown = total < _visible ? total : _visible;
    final remaining = total - shown;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final meal in widget.meals.take(shown))
          _MealTile(
            meal: meal,
            compact: widget.compact,
            onTap: () => widget.onMeal(meal),
          ),
        if (remaining > 0)
          TextButton(
            key: ValueKey(widget.moreKey),
            onPressed: () {
              SensoryFeedback.gentleTap();
              setState(() => _visible += _insightsPageSize);
            },
            child: Text(
              remaining > _insightsPageSize
                  ? 'Show $_insightsPageSize more'
                  : 'Show $remaining more',
            ),
          )
        else if (total > _insightsPageSize)
          TextButton(
            key: ValueKey(widget.lessKey),
            onPressed: () {
              SensoryFeedback.gentleTap();
              setState(() => _visible = _insightsPageSize);
            },
            child: const Text('Show less'),
          ),
      ],
    );
  }
}

class _MealTile extends StatelessWidget {
  final MealLog meal;
  final VoidCallback onTap;
  final bool compact;

  const _MealTile({
    required this.meal,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final when = DateFormat('EEE d, H:mm').format(meal.timestamp);
    final hours = meal.satietyResult.fullnessLabel;
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 6 : 10),
      child: InkWell(
        key: ValueKey(
          compact ? 'insight_missed_${meal.id}' : 'insight_meal_${meal.id}',
        ),
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: EvenColors.darkGlassBorder),
          ),
          child: Row(
            children: [
              MealThumb(
                imagePath: meal.imagePath,
                size: 36,
                semanticLabel: meal.mealName,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      meal.mealName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$when  \u00b7  $hours',
                      style: const TextStyle(
                        fontSize: 12,
                        color: EvenColors.textDarkMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
