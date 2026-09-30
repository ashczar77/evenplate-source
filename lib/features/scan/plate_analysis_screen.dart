import '../../widgets/analysis_consent_prompt.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../core/a11y/access.dart';
import '../../core/errors/telemetry.dart';
import '../../core/theme/even_colors.dart';
import '../../core/utils/sensory_feedback.dart';
import '../../models/meal_log.dart';
import '../../models/satiety_matrix.dart';
import '../../models/fullness_assessment.dart';
import '../../services/food_list_scorer.dart';
import '../../services/local_storage_service.dart';
import '../../services/meal_photo_store.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/meal_thumb.dart';
import '../../widgets/satiety_duration_clock.dart';
import '../../widgets/satiety_matrix_widget.dart';
import '../../widgets/nutrition_disclaimer.dart';
import '../../widgets/even_snack.dart';
import '../../widgets/upgrade_card.dart';
import '../../widgets/zen_bloom_overlay.dart';

class PlateAnalysisScreen extends StatefulWidget {
  final SatietyResult result;
  final String? diaryId;
  final String? imagePath;
  final Uint8List? imageBytes;
  final LocalStorageService storage;
  final MealPhotoStore? photoStore;
  final bool animateSensory;
  final bool inspectOnly;
  final MealLog? existingMeal;

  const PlateAnalysisScreen({
    super.key,
    required this.result,
    this.diaryId,
    this.imagePath,
    this.imageBytes,
    required this.storage,
    this.photoStore,
    this.animateSensory = true,
    this.inspectOnly = false,
    this.existingMeal,
  });

  @override
  State<PlateAnalysisScreen> createState() => _PlateAnalysisScreenState();
}

class _PlateAnalysisScreenState extends State<PlateAnalysisScreen> {
  bool _isSaving = false;
  bool _showZenBloom = false;
  late SatietyResult _draft;
  FullnessAssessment? _stableFullness;
  late final TextEditingController _nameController;
  late final TextEditingController _foodController;
  List<String> _plusOneFoods = const [];
  bool _needsAssessment = false;
  Timer? _settleTimer;
  int _settleGen = 0;
  bool _foodsEdited = false;
  bool _settling = false;
  late double _stableHours;
  late int _stableScore;

  @override
  void initState() {
    super.initState();
    _draft = widget.result;
    _stableFullness = _draft.fullness;
    FoodListScorer.instance.rememberScan(widget.result);
    _stableHours = widget.result.durationHours;
    _stableScore = widget.result.satietyScore;
    _nameController = TextEditingController(text: widget.result.mealName);
    _foodController = TextEditingController();
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    _nameController.dispose();
    _foodController.dispose();
    super.dispose();
  }

  void _onCompleteBloom() {
    if (!mounted) return;
    EvenSnack.show(context, 'Plate saved.', icon: Icons.check_circle_rounded);
    Navigator.of(context).pop(true);
  }

  Future<void> _save() async {
    if (_isSaving) return;
    if (_draft.components.isEmpty) {
      EvenSnack.show(context, 'Add a food before saving.');
      return;
    }
    setState(() => _isSaving = true);
    _settleTimer?.cancel();
    if (_foodsEdited && _needsAssessment) {
      if (!await _settleFoods()) {
        if (mounted) {
          setState(() => _isSaving = false);
          EvenSnack.show(context, 'Assess the edited plate before saving.');
        }
        return;
      }
    }
    if (!mounted) return;
    await SensoryFeedback.zenBloomPulse();

    final existing = widget.existingMeal;
    try {
      if (existing != null) {
        await widget.storage.updateMealLog(
          existing.copyWith(mealName: _draft.mealName, satietyResult: _draft),
        );
      } else {
        final id = (widget.diaryId != null && widget.diaryId!.isNotEmpty)
            ? widget.diaryId!
            : DateTime.now().millisecondsSinceEpoch.toString();
        String? persisted;
        try {
          persisted = await (widget.photoStore ?? MealPhotoStore()).persist(
            mealId: id,
            ownerId: widget.storage.userProfile.id,
            sourcePath: widget.imagePath,
            bytes: widget.imageBytes,
          );
        } catch (e) {
          debugPrint('Meal photo persist failed: $e');
          Telemetry.report(
            name: 'meal_photo.persist_failed',
            alert: false,
            error: e,
          );
        }
        persisted ??= MealPhotoStore.isReadable(widget.imagePath)
            ? widget.imagePath
            : null;
        await widget.storage.addMealLog(
          MealLog(
            id: id,
            mealName: _draft.mealName,
            timestamp: DateTime.now(),
            imagePath: persisted,
            satietyResult: _draft,
          ),
        );
      }
    } catch (e, st) {
      Telemetry.report(name: 'meal_save.failed', error: e, stack: st);
      if (!mounted) return;
      setState(() => _isSaving = false);
      EvenSnack.show(context, 'Could not save this meal. Try again.');
      return;
    }

    if (mounted) {
      setState(() => _showZenBloom = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasImageBytes = widget.imageBytes?.isNotEmpty == true;
    final hasLocalImage =
        hasImageBytes || MealPhotoStore.isReadable(widget.imagePath);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _draft.mealName,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
      body: Stack(
        children: [
          SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                20,
                12,
                20,
                12 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (hasLocalImage)
                    Container(
                      height: 180,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: safeBoxShadows([
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ]),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: hasImageBytes
                          ? Image.memory(
                              widget.imageBytes!,
                              fit: BoxFit.cover,
                              semanticLabel: _draft.mealName,
                            )
                          : MealPhotoImage(
                              imagePath: widget.imagePath,
                              fit: BoxFit.cover,
                              semanticLabel: _draft.mealName,
                              fallback: const SizedBox.expand(),
                            ),
                    ),

                  SatietyDurationClock(
                    fullnessEstimate: _needsAssessment
                        ? null
                        : _draft.fullnessEstimate,
                    assessment: _needsAssessment
                        ? _stableFullness
                        : _draft.fullness,
                    pendingChanges: _needsAssessment,
                    onAssess: _needsAssessment && _draft.components.isNotEmpty
                        ? _settleFoods
                        : null,
                    durationHours: _settling
                        ? _stableHours
                        : _draft.durationHours,
                    crashRisk: _draft.crashRisk,
                    satietyScore: _settling
                        ? _stableScore
                        : _draft.satietyScore,
                    scoring: _settling,
                    mode: _draft.components.isEmpty
                        ? SatietyClockMode.empty
                        : SatietyClockMode.ready,
                  ),

                  const SizedBox(height: 12),
                  Text(
                    _draft.pillars.comboLine,
                    key: const ValueKey('analysis_combo_line'),
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? EvenColors.textDarkPrimary
                          : EvenColors.textLightPrimary,
                    ),
                  ),

                  if (!widget.inspectOnly) ...[
                    const SizedBox(height: 16),
                    UpgradeCard(
                      upgrade: _draft.hybridUpgrade.forDietaryPreference(
                        widget.storage.userProfile.dietaryPreference,
                      ),
                      instantAddApplied: _plusOneFoods.isNotEmpty,
                      onInstantAddChanged: _onPlusOneToggled,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      key: const ValueKey('btn_save_diary'),
                      onPressed: _isSaving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: EvenColors.netSage,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        elevation: 0,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.check_circle_outline_rounded,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            widget.existingMeal != null
                                ? 'Update this plate'
                                : 'Save this plate',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),
                  _buildFoodsCard(context, isDark),

                  const SizedBox(height: 16),
                  GlassCard(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: ExpansionTile(
                      key: const ValueKey('btn_how_scored'),
                      initiallyExpanded: widget.inspectOnly,
                      tilePadding: const EdgeInsets.symmetric(horizontal: 8),
                      childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                      title: const Text('How we scored this'),
                      children: [
                        SatietyMatrixWidget(
                          pillars: _draft.pillars,
                          animateOnMount: widget.animateSensory,
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),
                  const NutritionDisclaimer(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),

          if (_showZenBloom)
            ZenBloomOverlay(
              mealName: _draft.mealName,
              durationHours: _draft.durationHours,
              pillarsAligned: _draft.pillars.completedCount,
              animate: widget.animateSensory,
              onComplete: _onCompleteBloom,
            ),
        ],
      ),
    );
  }

  Widget _buildFoodsCard(BuildContext context, bool isDark) {
    final foods = _draft.components;
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('On this plate', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            widget.inspectOnly
                ? 'Foods named on this plate.'
                : 'Remove a miss or add what was skipped. The fullness rating updates with your foods.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          if (!widget.inspectOnly) ...[
            TextField(
              key: const ValueKey('edit_meal_name'),
              controller: _nameController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Meal name'),
              onChanged: (value) {
                final name = value.trim().isEmpty
                    ? _draft.mealName
                    : value.trim();
                setState(() => _draft = _draft.copyWith(mealName: name));
              },
            ),
            const SizedBox(height: 12),
          ],
          if (foods.isEmpty)
            Text(
              widget.inspectOnly
                  ? 'No foods listed on this plate.'
                  : 'Nothing listed yet. Add the foods you can see.',
              style: Theme.of(context).textTheme.bodyMedium,
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final food in foods)
                  InputChip(
                    key: ValueKey('food_chip_${food.toLowerCase()}'),
                    label: Text(food),
                    onDeleted: widget.inspectOnly
                        ? null
                        : () => _removeFood(food),
                    deleteButtonTooltipMessage: 'Remove $food',
                    backgroundColor: isDark
                        ? EvenColors.darkSurfaceElevated
                        : EvenColors.lightSurfaceElevated,
                  ),
              ],
            ),
          if (!widget.inspectOnly) ...[
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('add_detected_food'),
              controller: _foodController,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'Add a food or drink',
                hintText: 'Beer, side salad, pizza',
                suffixIcon: IconButton(
                  key: const ValueKey('btn_add_food'),
                  tooltip: 'Add food',
                  icon: const Icon(Icons.add_rounded),
                  onPressed: _submitFood,
                ),
              ),
              onSubmitted: (_) => _submitFood(),
            ),
          ],
        ],
      ),
    );
  }

  void _queueSettle() {
    _settleGen++;
    _foodsEdited = true;
    _settleTimer?.cancel();
    if (_draft.components.isEmpty) {
      setState(() {
        _settling = false;
        _needsAssessment = false;
      });
      return;
    }
    final scored = FoodListScorer.instance.cachedPlate(
      mealName: _draft.mealName,
      foods: _draft.components,
      original: widget.result.original,
    );
    if (scored != null) {
      setState(() {
        _draft = scored.copyWith(hybridUpgrade: _draft.hybridUpgrade);
        _stableFullness = _draft.fullness;
        _stableHours = _draft.durationHours;
        _stableScore = _draft.satietyScore;
        _settling = false;
        _needsAssessment = false;
      });
      return;
    }
    setState(() {
      _settling = false;
      _needsAssessment = true;
    });
  }

  Future<bool> _settleFoods() async {
    final gen = ++_settleGen;
    final cached = FoodListScorer.instance.cachedPlate(
      mealName: _draft.mealName,
      foods: _draft.components,
      original: widget.result.original,
    );
    if (cached == null &&
        !await AnalysisConsentPrompt.ensure(context, widget.storage)) {
      if (mounted) setState(() => _settling = false);
      return false;
    }
    if (!mounted || gen != _settleGen) return false;
    final foods = _draft.components;
    setState(() => _settling = true);
    final outcome = await FoodListScorer.instance.score(
      mealName: _draft.mealName,
      foods: foods,
      original: widget.result.original,
    );
    if (!mounted || gen != _settleGen) return false;
    _settling = false;
    _applyScoreOutcome(outcome);
    return outcome.settled && outcome.isFood && _draft.components.isNotEmpty;
  }

  void _applyScoreOutcome(FoodScoreOutcome outcome) {
    unawaited(widget.storage.applyFoodsQuota(outcome.quota));
    final rejected = {for (final item in outcome.rejected) item.toLowerCase()};
    var nextFoods = _draft.components
        .where((food) => !rejected.contains(food.toLowerCase()))
        .toList();
    final removed = nextFoods.length != _draft.components.length;
    if (!outcome.isFood && nextFoods.isEmpty) {
      nextFoods = const [];
    }
    if (outcome.settled && outcome.isFood && outcome.pending.isEmpty) {
      _needsAssessment = false;
      _draft = outcome.result.copyWith(
        mealName: _draft.mealName,
        components: nextFoods.isEmpty ? outcome.result.components : nextFoods,
        hybridUpgrade: _draft.hybridUpgrade,
      );
      _stableFullness = _draft.fullness;
      _stableHours = _draft.durationHours;
      _stableScore = _draft.satietyScore;
    } else {
      _draft = _draft
          .withFoods(nextFoods)
          .copyWith(durationHours: _stableHours, satietyScore: _stableScore);
    }
    _plusOneFoods = _plusOneFoods
        .where((item) => !rejected.contains(item.toLowerCase()))
        .toList();
    setState(() {});
    if (outcome.pending.isNotEmpty) {
      EvenSnack.show(
        context,
        outcome.failureMessage ?? 'Food lookup failed. Please try again.',
      );
    }
    if (removed) {
      EvenSnack.show(context, 'That does not look like food.');
    }
  }

  void _onPlusOneToggled(bool applied) {
    if (_isSaving) return;
    if (applied) {
      final extras = _draft
          .copyWith(
            hybridUpgrade: _draft.hybridUpgrade.forDietaryPreference(
              widget.storage.userProfile.dietaryPreference,
            ),
          )
          .suggestedPlusOneFoods;
      if (_draft.components.length +
              extras
                  .where(
                    (f) => !_draft.components.any(
                      (existing) => existing.toLowerCase() == f.toLowerCase(),
                    ),
                  )
                  .length >
          kMaxFoodItems) {
        EvenSnack.show(context, 'Use up to 40 foods per plate.');
        return;
      }
      if (extras.isEmpty) {
        EvenSnack.show(context, 'Add this suggestion using Add a food.');
        return;
      }
      setState(() {
        final existing = _draft.components.map((f) => f.toLowerCase()).toSet();
        _plusOneFoods = extras
            .where((f) => !existing.contains(f.toLowerCase()))
            .toList();
        _draft = _draft
            .withFoods([..._draft.components, ..._plusOneFoods])
            .copyWith(durationHours: _stableHours, satietyScore: _stableScore);
      });
      SensoryFeedback.zenBloomPulse();
      _queueSettle();
      return;
    }
    final skip = _plusOneFoods.map((f) => f.toLowerCase()).toSet();
    final remaining = _draft.components
        .where((f) => !skip.contains(f.toLowerCase()))
        .toList();
    _settleTimer?.cancel();
    _settleGen++;
    setState(() {
      _draft = _draft.withFoods(remaining);
      _plusOneFoods = const [];
      _settling = false;
    });
    _queueSettle();
  }

  void _removeFood(String food) {
    if (_isSaving) return;
    final next = _draft.components
        .where((item) => item.toLowerCase() != food.toLowerCase())
        .toList();
    setState(() {
      _draft = _draft
          .withFoods(next)
          .copyWith(durationHours: _stableHours, satietyScore: _stableScore);
      _plusOneFoods = _plusOneFoods
          .where((item) => item.toLowerCase() != food.toLowerCase())
          .toList();
    });
    _queueSettle();
  }

  void _submitFood() {
    if (_isSaving) return;
    final added = _foodController.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (added.isEmpty) return;
    if (_draft.components.any((f) => f.toLowerCase() == added.toLowerCase())) {
      _foodController.clear();
      return;
    }
    if (added.length > kMaxFoodNameLength ||
        _draft.components.length >= kMaxFoodItems) {
      EvenSnack.show(
        context,
        'Use up to 40 foods, with each description at most 60 characters.',
      );
      return;
    }
    if (normalizeFoodList([added]).isEmpty) {
      EvenSnack.show(context, 'That does not look like food.');
      return;
    }
    final next = [..._draft.components, added];
    _foodController.clear();
    setState(
      () => _draft = _draft
          .withFoods(next)
          .copyWith(durationHours: _stableHours, satietyScore: _stableScore),
    );
    _queueSettle();
  }
}
