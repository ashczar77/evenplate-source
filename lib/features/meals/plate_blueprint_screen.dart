import '../../widgets/analysis_consent_prompt.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/theme/even_colors.dart';
import '../../core/utils/sensory_feedback.dart';
import '../../models/meal_log.dart';
import '../../models/satiety_matrix.dart';
import '../../services/food_list_scorer.dart';
import '../../services/food_score_cache.dart';
import '../../services/local_storage_service.dart';
import '../../widgets/even_snack.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/satiety_duration_clock.dart';

const _proteinFoods = [
  'Eggs',
  'Greek yogurt',
  'Chicken',
  'Salmon',
  'Tofu',
  'Beans',
];
const _fiberFoods = ['Side salad', 'Broccoli', 'Oats', 'Lentils', 'Berries'];
const _fatFoods = ['Avocado', 'Olive oil', 'Walnuts', 'Almonds', 'Tahini'];
const _volumeFoods = ['Cucumber', 'Cherry tomatoes', 'Greens', 'Apple', 'Slaw'];

/// Select foods, then assess the complete plate.
class PlateBlueprintScreen extends StatefulWidget {
  final LocalStorageService storage;
  final String? highlightPillar;
  final MealLog? existing;

  const PlateBlueprintScreen({
    super.key,
    required this.storage,
    this.highlightPillar,
    this.existing,
  });

  static Future<bool?> show(
    BuildContext context,
    LocalStorageService storage, {
    String? highlightPillar,
    MealLog? existing,
  }) {
    SensoryFeedback.gentleTap();
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PlateBlueprintScreen(
          storage: storage,
          highlightPillar: highlightPillar,
          existing: existing,
        ),
      ),
    );
  }

  @override
  State<PlateBlueprintScreen> createState() => _PlateBlueprintScreenState();
}

class _PlateBlueprintScreenState extends State<PlateBlueprintScreen> {
  late final TextEditingController _name;
  final _food = TextEditingController();
  final _selected = <String>{};
  SatietyResult? _committed;
  String? _scoredKey;
  Timer? _settleTimer;
  int _settleGen = 0;
  bool _saving = false;
  bool _settling = false;

  bool get _editing => widget.existing != null;
  bool get _ready =>
      _committed != null &&
      _scoredKey == FoodScoreCache.keyFor(_selected) &&
      _selected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name = TextEditingController(text: existing?.mealName ?? '');
    if (existing != null) {
      _selected.addAll(existing.satietyResult.components);
      if (_selected.isEmpty) {
        _selected.addAll(existing.satietyResult.detectedFoods);
      }
      _committed = existing.satietyResult;
      _scoredKey = FoodScoreCache.keyFor(_selected);
      FoodListScorer.instance.rememberScan(existing.satietyResult);
    } else {
      final highlight = widget.highlightPillar;
      if (highlight == 'protein') _selected.add('Eggs');
      if (highlight == 'fiber') _selected.add('Side salad');
      if (highlight == 'fat') _selected.add('Walnuts');
      if (highlight == 'volume') _selected.add('Cucumber');
      if (_selected.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _onFoodsChanged();
        });
      }
    }
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    _name.dispose();
    _food.dispose();
    super.dispose();
  }

  String get _mealName {
    return _name.text.trim().isEmpty ? 'Plate' : _name.text.trim();
  }

  bool _alreadyHas(String food) {
    final key = food.toLowerCase();
    return _selected.any((item) => item.toLowerCase() == key);
  }

  void _onFoodsChanged() {
    _settleGen++;
    _scoredKey = null;
    _settleTimer?.cancel();
    if (_selected.isEmpty) {
      _committed = null;
      _scoredKey = null;
      _settling = false;
      setState(() {});
      return;
    }
    final cached = FoodListScorer.instance.cachedPlate(
      mealName: _mealName,
      foods: _selected.toList(),
      original: widget.existing?.satietyResult.original,
    );
    if (cached != null) {
      final foods = _selected.toList();
      _committed = cached;
      _scoredKey = FoodScoreCache.keyFor(foods);
      _settling = false;
      setState(() {});
      return;
    }
    setState(() => _settling = false);
  }

  Future<void> _settle() async {
    if (_saving) return;
    final gen = ++_settleGen;
    final cached = FoodListScorer.instance.cachedPlate(
      mealName: _mealName,
      foods: _selected.toList(),
      original: widget.existing?.satietyResult.original,
    );
    if (cached == null &&
        !await AnalysisConsentPrompt.ensure(context, widget.storage)) {
      if (mounted) setState(() => _settling = false);
      return;
    }
    if (!mounted || gen != _settleGen) return;
    final foods = _selected.toList();
    setState(() => _settling = true);
    final outcome = await FoodListScorer.instance.score(
      mealName: _mealName,
      foods: foods,
      original: widget.existing?.satietyResult.original,
    );
    if (!mounted || gen != _settleGen) return;
    _applyOutcome(outcome);
  }

  void _applyOutcome(FoodScoreOutcome outcome) {
    unawaited(widget.storage.applyFoodsQuota(outcome.quota));
    final rejected = {for (final item in outcome.rejected) item.toLowerCase()};
    var removed = false;
    if (rejected.isNotEmpty) {
      _selected.removeWhere((item) {
        final drop = rejected.contains(item.toLowerCase());
        if (drop) removed = true;
        return drop;
      });
    }
    if (!outcome.isFood && _selected.isEmpty) {
      _committed = null;
      _scoredKey = null;
      _settling = false;
      setState(() {});
      if (removed) _showNotFood();
      return;
    }
    _settling = false;
    if (outcome.settled && outcome.isFood && outcome.pending.isEmpty) {
      _committed = outcome.result;
      _scoredKey = FoodScoreCache.keyFor(_selected);
    }
    setState(() {});
    if (removed) _showNotFood();
    if (outcome.pending.isNotEmpty && mounted) {
      EvenSnack.show(
        context,
        outcome.failureMessage ??
            'Could not score ${outcome.pending.first}. Check your connection and try again.',
      );
    }
  }

  void _showNotFood() {
    EvenSnack.show(context, 'That does not look like food.');
  }

  void _toggle(String food) {
    if (_saving) return;
    SensoryFeedback.gentleTap();
    if (_selected.contains(food)) {
      _selected.remove(food);
    } else {
      if (_selected.length >= kMaxFoodItems) {
        EvenSnack.show(context, 'Use up to 40 foods per plate.');
        return;
      }
      _selected.add(food);
    }
    _onFoodsChanged();
  }

  void _addTypedFood() {
    if (_saving) return;
    final added = _food.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (added.isEmpty) return;
    if (_alreadyHas(added)) {
      _food.clear();
      return;
    }
    if (added.length > kMaxFoodNameLength ||
        _selected.length >= kMaxFoodItems) {
      EvenSnack.show(
        context,
        'Use up to 40 foods, with each description at most 60 characters.',
      );
      return;
    }
    if (normalizeFoodList([added]).isEmpty) {
      _showNotFood();
      return;
    }
    SensoryFeedback.gentleTap();
    _food.clear();
    _selected.add(added);
    _onFoodsChanged();
  }

  Future<void> _save() async {
    if (!_ready || _saving || _settling) return;
    setState(() => _saving = true);
    ++_settleGen;
    _settleTimer?.cancel();
    await SensoryFeedback.zenBloomPulse();
    final result = _committed!.copyWith(
      mealName: _mealName,
      components: _selected.toList(),
    );
    final existing = widget.existing;
    if (existing != null) {
      await widget.storage.updateMealLog(
        existing.copyWith(mealName: result.mealName, satietyResult: result),
      );
    } else {
      await widget.storage.addMealLog(
        MealLog(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          mealName: result.mealName,
          timestamp: DateTime.now(),
          satietyResult: result,
        ),
      );
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final classified = SatietyResult.fromFoods(
      mealName: _mealName,
      components: _selected.toList(),
    );
    final ready = _ready;
    final shown = _committed ?? classified.withoutForecast();
    final clockMode = _selected.isEmpty
        ? SatietyClockMode.empty
        : (_settling
              ? SatietyClockMode.scoring
              : (ready
                    ? SatietyClockMode.ready
                    : SatietyClockMode.unavailable));
    final combo = _selected.isEmpty
        ? 'Add food. An empty plate does not last.'
        : (ready
              ? _committed!.pillars.comboLine
              : classified.pillars.comboLine);
    final highlight = widget.highlightPillar;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _editing ? 'Edit plate' : 'Build a plate',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          children: [
            Text(
              'Protein, fiber, and fat is the combo. Volume is the bonus. No calorie counting.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('blueprint_meal_name'),
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Meal name',
                hintText: 'Plate',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            SatietyDurationClock(
              fullnessEstimate: ready ? shown.fullnessEstimate : null,
              assessment: shown.fullness,
              pendingChanges: !ready && _selected.isNotEmpty,
              scoring: _settling,
              onAssess: !ready && _selected.isNotEmpty && !_saving
                  ? _settle
                  : null,
              durationHours: shown.durationHours,
              crashRisk: shown.crashRisk,
              satietyScore: shown.satietyScore,
              mode: clockMode,
            ),
            const SizedBox(height: 12),
            Text(
              combo,
              key: const ValueKey('blueprint_combo_line'),
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? EvenColors.textDarkPrimary
                    : EvenColors.textLightPrimary,
              ),
            ),
            const SizedBox(height: 20),
            _ChipGroup(
              title: 'Protein',
              hint: highlight == 'protein' ? 'Start here' : null,
              color: EvenColors.anchorTerracotta,
              foods: _proteinFoods,
              selected: _selected,
              onToggle: _toggle,
            ),
            const SizedBox(height: 16),
            _ChipGroup(
              title: 'Fiber',
              hint: highlight == 'fiber' ? 'Start here' : null,
              color: EvenColors.netSage,
              foods: _fiberFoods,
              selected: _selected,
              onToggle: _toggle,
            ),
            const SizedBox(height: 16),
            _ChipGroup(
              title: 'Fat',
              hint: highlight == 'fat' ? 'Start here' : null,
              color: EvenColors.bufferAmber,
              foods: _fatFoods,
              selected: _selected,
              onToggle: _toggle,
            ),
            const SizedBox(height: 16),
            _ChipGroup(
              title: 'Volume',
              hint: highlight == 'volume' ? 'Start here' : null,
              color: EvenColors.sparkBlush,
              foods: _volumeFoods,
              selected: _selected,
              onToggle: _toggle,
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('blueprint_add_food'),
              controller: _food,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'Add a food',
                hintText: 'Sloppy joes, olive oil, chicken',
                suffixIcon: IconButton(
                  key: const ValueKey('btn_blueprint_add_food'),
                  tooltip: 'Add food',
                  icon: const Icon(Icons.add_rounded),
                  onPressed: _addTypedFood,
                ),
              ),
              onSubmitted: (_) => _addTypedFood(),
            ),
            if (_selected
                .where(
                  (food) =>
                      !_proteinFoods.contains(food) &&
                      !_fiberFoods.contains(food) &&
                      !_fatFoods.contains(food) &&
                      !_volumeFoods.contains(food),
                )
                .isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final food in _selected)
                    if (!_proteinFoods.contains(food) &&
                        !_fiberFoods.contains(food) &&
                        !_fatFoods.contains(food) &&
                        !_volumeFoods.contains(food))
                      InputChip(
                        key: ValueKey('blueprint_custom_${food.toLowerCase()}'),
                        label: Text(food),
                        onDeleted: _saving
                            ? null
                            : () {
                                _selected.remove(food);
                                _onFoodsChanged();
                              },
                      ),
                ],
              ),
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              key: const ValueKey('btn_save_blueprint'),
              onPressed: !ready || _saving || _settling ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: EvenColors.netSage,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                elevation: 0,
              ),
              child: Text(
                _editing ? 'Update this plate' : 'Save this plate',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChipGroup extends StatelessWidget {
  final String title;
  final String? hint;
  final Color color;
  final List<String> foods;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  const _ChipGroup({
    required this.title,
    required this.color,
    required this.foods,
    required this.selected,
    required this.onToggle,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              if (hint != null) ...[
                const SizedBox(width: 8),
                Text(
                  hint!,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final food in foods)
                FilterChip(
                  key: ValueKey('blueprint_chip_${food.toLowerCase()}'),
                  label: Text(food),
                  selected: selected.contains(food),
                  onSelected: (_) => onToggle(food),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
