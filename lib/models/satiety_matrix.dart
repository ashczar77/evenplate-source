import '../core/json/json_map.dart';
import 'fullness_assessment.dart';
import 'fullness_estimate.dart';

const double kMinDurationHours = 0.5;
const double kMaxDurationHours = 12.0;
const int kMaxFoodItems = 40;
const int kMaxFoodNameLength = 60;

const _genericFoodLabels = {
  'protein',
  'fiber',
  'fibre',
  'lipids',
  'volume',
  'plants',
  'plant',
  'healthy lipids',
  'fats',
  'crunch',
  'spark',
  'anchor',
  'net',
  'buffer',
};

const _qualities = {'high', 'medium', 'low'};
const _crashRisks = {'low', 'moderate', 'high'};
const _captureIssues = {'not_food', 'too_dark', 'blurry'};

String _asQuality(Object? raw) {
  if (raw is! String) return 'medium';
  final value = raw.trim().toLowerCase();
  return _qualities.contains(value) ? value : 'medium';
}

String _asCrashRisk(Object? raw) {
  if (raw is! String) return 'moderate';
  var value = raw.trim().toLowerCase();
  if (value == 'medium') value = 'moderate';
  return _crashRisks.contains(value) ? value : 'moderate';
}

String? _asCaptureIssue(Object? raw) {
  if (raw is! String) return null;
  final value = raw.trim().toLowerCase();
  if (value.isEmpty || value == 'none') return null;
  return _captureIssues.contains(value) ? value : null;
}

double _asDurationHours(Object? raw) {
  final parsed = raw is num
      ? raw.toDouble()
      : double.tryParse(raw?.toString() ?? '') ?? 3.5;
  if (parsed == 0) return 0;
  return parsed.clamp(kMinDurationHours, kMaxDurationHours);
}

bool _blobHits(String blob, List<String> needles) {
  for (final needle in needles) {
    if (needle.contains(' ')) {
      if (blob.contains(needle)) return true;
      continue;
    }
    if (needle.length <= 4) {
      if (RegExp(
        '(^|[^a-z])${RegExp.escape(needle)}([^a-z]|\$)',
      ).hasMatch(blob)) {
        return true;
      }
      continue;
    }
    if (blob.contains(needle)) return true;
  }
  return false;
}

/// True when the local word list can place this name on a pillar.
bool foodRecognizedLocally(String food) {
  final result = SatietyResult.fromFoods(mealName: 'Food', components: [food]);
  final pillars = result.pillars;
  return pillars.anchor.detected ||
      pillars.net.detected ||
      pillars.buffer.detected ||
      pillars.spark.detected;
}

bool foodsRecognizedLocally(Iterable<String> foods) {
  final list = normalizeFoodList(foods);
  return list.isNotEmpty && list.every(foodRecognizedLocally);
}

List<String> normalizeFoodList(Iterable<String> raw) {
  final seen = <String>{};
  final out = <String>[];
  for (final entry in raw) {
    var text = entry.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (text.isEmpty) continue;
    if (text.length > kMaxFoodNameLength) {
      text = text.substring(0, kMaxFoodNameLength).trimRight();
    }
    final key = text.toLowerCase();
    if (_genericFoodLabels.contains(key)) continue;
    if (!seen.add(key)) continue;
    out.add(text);
    if (out.length >= kMaxFoodItems) break;
  }
  return out;
}

PillarDetail _pillarFromFoods(
  List<String> foods,
  List<String> strongNeedles, {
  List<String> weakNeedles = const [],
}) {
  final strong = <String>[];
  final weak = <String>[];
  for (final food in foods) {
    final blob = food.toLowerCase();
    if (_blobHits(blob, strongNeedles)) {
      strong.add(food);
    } else if (weakNeedles.isNotEmpty && _blobHits(blob, weakNeedles)) {
      weak.add(food);
    }
  }
  final items = [...strong, ...weak];
  if (items.isEmpty) {
    return const PillarDetail(detected: false, items: [], quality: 'low');
  }
  final quality = strong.isNotEmpty ? 'high' : 'low';
  return PillarDetail(detected: true, items: items, quality: quality);
}

/// Represents the detection state of a single Satiety Matrix pillar
class PillarDetail {
  final bool detected;
  final List<String> items;
  final String quality; // 'high', 'medium', 'low'

  const PillarDetail({
    required this.detected,
    required this.items,
    this.quality = 'medium',
  });

  factory PillarDetail.fromJson(Map<String, dynamic> json) {
    final rawDetected = json['detected'];
    final isDetected = rawDetected is bool
        ? rawDetected
        : (rawDetected?.toString().toLowerCase() == 'true');

    return PillarDetail(
      detected: isDetected,
      items:
          (json['items'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      quality: _asQuality(json['quality']),
    );
  }

  PillarDetail copyWith({
    bool? detected,
    List<String>? items,
    String? quality,
  }) {
    return PillarDetail(
      detected: detected ?? this.detected,
      items: items ?? this.items,
      quality: quality ?? this.quality,
    );
  }

  Map<String, dynamic> toJson() => {
    'detected': detected,
    'items': items,
    'quality': quality,
  };

  /// Presence is not a win. Chips can be detected as Spark and still be low.
  bool get isAligned => detected && quality != 'low';

  /// Share of one daily meal this pillar is worth. High is a full hit,
  /// medium is half, low or missing is none.
  double get dailyCredit {
    if (!isAligned) return 0;
    return quality == 'high' ? 1.0 : 0.5;
  }
}

/// The 4-Element Satiety Matrix Architecture
class SatietyPillars {
  final PillarDetail anchor; // Protein
  final PillarDetail net; // Fiber & Plants
  final PillarDetail buffer; // Healthy Lipids & Smart Carbs
  final PillarDetail spark; // Sensory Volume & Micronutrients

  const SatietyPillars({
    required this.anchor,
    required this.net,
    required this.buffer,
    required this.spark,
  });

  // Real Nutritional Pillar Accessors
  PillarDetail get protein => anchor;
  PillarDetail get fiber => net;
  PillarDetail get fats => buffer;
  PillarDetail get carbs => spark;

  int get completedCount {
    int count = 0;
    if (anchor.isAligned) count++;
    if (net.isAligned) count++;
    if (buffer.isAligned) count++;
    if (spark.isAligned) count++;
    return count;
  }

  bool get isFullMatrix => completedCount >= 3;

  /// Protein, fiber, and fat. Volume is the bonus, not the combo.
  bool get hccComplete => anchor.isAligned && net.isAligned && buffer.isAligned;

  /// First gap in combo order: protein, fiber, fat, then volume.
  String? get firstGapId {
    if (!anchor.isAligned) return 'protein';
    if (!net.isAligned) return 'fiber';
    if (!buffer.isAligned) return 'fat';
    if (!spark.isAligned) return 'volume';
    return null;
  }

  String get comboLine {
    switch (firstGapId) {
      case 'protein':
        return 'Consider a protein food.';
      case 'fiber':
        return 'Consider a fiber-rich food.';
      case 'fat':
        return 'Consider nuts, seeds, or avocado.';
      case 'volume':
        return 'Combo is on the plate. Add volume so it feels finished.';
      default:
        return 'Protein, fiber, and fat are on this plate.';
    }
  }

  SatietyPillars copyWith({
    PillarDetail? anchor,
    PillarDetail? net,
    PillarDetail? buffer,
    PillarDetail? spark,
  }) {
    return SatietyPillars(
      anchor: anchor ?? this.anchor,
      net: net ?? this.net,
      buffer: buffer ?? this.buffer,
      spark: spark ?? this.spark,
    );
  }

  factory SatietyPillars.fromJson(Map<String, dynamic> json) {
    return SatietyPillars(
      anchor: PillarDetail.fromJson(
        asStringKeyedMap(json['anchor']) ?? const {},
      ),
      net: PillarDetail.fromJson(asStringKeyedMap(json['net']) ?? const {}),
      buffer: PillarDetail.fromJson(
        asStringKeyedMap(json['buffer']) ?? const {},
      ),
      spark: PillarDetail.fromJson(asStringKeyedMap(json['spark']) ?? const {}),
    );
  }

  Map<String, dynamic> toJson() => {
    'anchor': anchor.toJson(),
    'net': net.toJson(),
    'buffer': buffer.toJson(),
    'spark': spark.toJson(),
  };
}

/// 3-Tier Hybrid EvenUpgrade Coaching Recommendation
class HybridUpgrade {
  final String instantAdd;
  final String smartSwap;
  final String digestiveCatalyst;
  final String instantAddFood;

  const HybridUpgrade({
    required this.instantAdd,
    required this.smartSwap,
    required this.digestiveCatalyst,
    this.instantAddFood = '',
  });

  factory HybridUpgrade.fromJson(Map<String, dynamic> json) {
    return HybridUpgrade(
      instantAddFood: json['instantAddFood'] is String
          ? json['instantAddFood']
          : '',
      instantAdd: json['instantAdd'] is String
          ? json['instantAdd'] as String
          : 'Add a handful of seeds or nuts to bolster your lipid buffer.',
      smartSwap: json['smartSwap'] is String
          ? json['smartSwap'] as String
          : 'Next time, consider whole-grain or sprouted options for sustained fiber release.',
      digestiveCatalyst: json['digestiveCatalyst'] is String
          ? json['digestiveCatalyst'] as String
          : 'Sip a glass of room-temperature water or herbal tea before eating.',
    );
  }

  HybridUpgrade forDietaryPreference(String preference) {
    final p = preference.toLowerCase();
    final vegan = p.contains('vegan') || p.contains('100% plant');
    final vegetarian = vegan || p.contains('vegetarian');
    final sensitive = p.contains('sensitive');
    String safe(String advice) {
      if (sensitive) {
        return 'Choose an ingredient you tolerate. Check labels and your personal allergy plan.';
      }
      final blocked = <String>[
        if (vegetarian) ...[
          'meat',
          'chicken',
          'beef',
          'pork',
          'fish',
          'salmon',
          'tuna',
          'shrimp',
          'turkey',
          'bacon',
        ],
        if (vegan) ...[
          'egg',
          'yogurt',
          'yoghurt',
          'cheese',
          'milk',
          'dairy',
          'butter',
          'honey',
        ],
        if (p.contains('low-carb')) ...[
          'rice',
          'bread',
          'oats',
          'potato',
          'pasta',
        ],
      ];
      if (blocked.any((word) => advice.toLowerCase().contains(word))) {
        return vegan
            ? 'Try tofu with leafy vegetables, checking labels for your dietary needs.'
            : 'Try leafy vegetables with a protein that fits your dietary needs.';
      }
      return advice;
    }

    return HybridUpgrade(
      instantAdd: safe(instantAdd),
      instantAddFood: safe(instantAdd) == instantAdd ? instantAddFood : '',
      smartSwap: safe(smartSwap),
      digestiveCatalyst: digestiveCatalyst,
    );
  }

  Map<String, dynamic> toJson() => {
    'instantAdd': instantAdd,
    if (instantAddFood.isNotEmpty) 'instantAddFood': instantAddFood,
    'smartSwap': smartSwap,
    'digestiveCatalyst': digestiveCatalyst,
  };
}

/// Complete Satiety Analysis Result
class SatietyResult {
  final FullnessEstimate? fullnessEstimate;
  final String mealName;
  final List<String> components;
  final List<FoodNutrientProfile> foodProfiles;
  final bool nutrientLookupComplete;
  static const modelMethod = 'gemini-meal-v1';
  final String? assessmentMethod;
  final String assessmentId;
  final String assessmentModel;
  final String assessmentNote;
  final Map<String, dynamic>? originalAnalysis;
  bool get hasModelAssessment => assessmentMethod == modelMethod;
  FullnessAssessment? get fullness => components.isEmpty
      ? null
      : hasModelAssessment
      ? FullnessAssessment.model(satietyScore.toDouble(), assessmentNote)
      : FullnessAssessment.forFoods(components, foodProfiles);
  Map<String, dynamic> get assessmentContext => {
    'assessmentId': assessmentId,
    'assessmentModel': assessmentModel,
    'mealName': mealName,
    'components': components,
    'pillars': pillars.toJson(),
    'satietyScore': satietyScore,
    'durationHours': 0.5,
    'crashRisk': 'moderate',
    'captureIssue': captureIssue ?? 'none',
    'hybridUpgrade': hybridUpgrade.toJson(),
    'assessmentNote': assessmentNote,
    if (fullnessEstimate != null)
      'fullnessEstimate': fullnessEstimate!.toJson(),
  };
  SatietyResult get original => originalAnalysis == null
      ? this
      : SatietyResult.fromJson(originalAnalysis!);
  String get fullnessLabel =>
      fullness == null ? 'Rating unavailable' : fullness!.label;
  final SatietyPillars pillars;
  final int satietyScore; // 0 - 100
  final double durationHours; // e.g. 4.5 hrs
  final String crashRisk; // 'low', 'moderate', 'high'
  final HybridUpgrade hybridUpgrade;

  /// Photo-level issue from the vision model: not_food, too_dark, blurry.
  /// Score sentinels (-1/-2/-3) cannot carry this: fromJson clamps scores.
  final String? captureIssue;

  const SatietyResult({
    required this.mealName,
    required this.components,
    required this.pillars,
    required this.satietyScore,
    required this.durationHours,
    required this.crashRisk,
    required this.hybridUpgrade,
    this.captureIssue,
    this.foodProfiles = const [],
    this.nutrientLookupComplete = false,
    this.assessmentMethod,
    this.assessmentId = "",
    this.assessmentModel = "",
    this.assessmentNote = "",
    this.originalAnalysis,
    this.fullnessEstimate,
  });

  SatietyResult copyWith({
    String? mealName,
    List<String>? components,
    SatietyPillars? pillars,
    int? satietyScore,
    double? durationHours,
    String? crashRisk,
    HybridUpgrade? hybridUpgrade,
    String? captureIssue,
    List<FoodNutrientProfile>? foodProfiles,
    bool? nutrientLookupComplete,
    String? assessmentMethod,
    String? assessmentId,
    String? assessmentModel,
    String? assessmentNote,
    Map<String, dynamic>? originalAnalysis,
    FullnessEstimate? fullnessEstimate,
  }) {
    return SatietyResult(
      assessmentMethod: assessmentMethod ?? this.assessmentMethod,
      assessmentId: assessmentId ?? this.assessmentId,
      assessmentModel: assessmentModel ?? this.assessmentModel,
      assessmentNote: assessmentNote ?? this.assessmentNote,
      originalAnalysis: originalAnalysis ?? this.originalAnalysis,
      fullnessEstimate: fullnessEstimate ?? this.fullnessEstimate,
      mealName: mealName ?? this.mealName,
      components: components ?? this.components,
      pillars: pillars ?? this.pillars,
      satietyScore: satietyScore ?? this.satietyScore,
      durationHours: durationHours ?? this.durationHours,
      crashRisk: crashRisk ?? this.crashRisk,
      hybridUpgrade: hybridUpgrade ?? this.hybridUpgrade,
      captureIssue: captureIssue ?? this.captureIssue,
      foodProfiles: foodProfiles ?? this.foodProfiles,
      nutrientLookupComplete:
          nutrientLookupComplete ?? this.nutrientLookupComplete,
    );
  }

  /// Foods the model named, minus generic labels like "Fiber".
  List<String> get detectedFoods => normalizeFoodList([
    ...components,
    ...pillars.anchor.items,
    ...pillars.net.items,
    ...pillars.buffer.items,
    ...pillars.spark.items,
  ]);

  /// Pillars can update before a forecast exists. Hours stay unset.
  SatietyResult withoutForecast() {
    return copyWith(durationHours: 0, satietyScore: 0);
  }

  /// Rebuild pillars and the forecast from the foods the user kept or added.
  SatietyResult withFoods(List<String> foods) {
    return SatietyResult.fromFoods(
      mealName: mealName,
      components: foods,
      hybridUpgrade: hybridUpgrade,
      captureIssue: captureIssue,
    ).copyWith(foodProfiles: foodProfiles);
  }

  /// Foods implied by the 30-second Plus-One, or a pantry hit for the weakest pillar.
  List<String> get suggestedPlusOneFoods {
    if (hybridUpgrade.instantAddFood.trim().isNotEmpty) {
      return [hybridUpgrade.instantAddFood.trim()];
    }
    final advice = hybridUpgrade.instantAdd.toLowerCase();
    final found = <String>[];
    void consider(String needle, String food) {
      if (!advice.contains(needle)) return;
      final key = food.toLowerCase();
      if (found.any((item) => item.toLowerCase() == key)) return;
      found.add(food);
    }

    consider('edamame', 'Edamame');
    consider('walnut', 'Walnuts');
    consider('almond', 'Almonds');
    consider('chia', 'Chia seeds');
    consider('hemp', 'Hemp hearts');
    consider('pumpkin seed', 'Pumpkin seeds');
    consider('hardboil', 'Hardboiled egg');
    consider('yogurt', 'Greek yogurt');
    consider('avocado', 'Avocado');
    consider('hummus', 'Hummus');
    consider('side salad', 'Side salad');
    consider('tomato', 'Cherry tomatoes');
    consider('berr', 'Berries');
    consider('spinach', 'Spinach');
    if (advice.contains('egg') &&
        !found.any((item) => item.toLowerCase().contains('egg'))) {
      found.add('Hardboiled egg');
    }
    if (RegExp(r'\bor\b').hasMatch(advice) && found.length > 1) return const [];
    return found.take(2).toList();
  }

  /// Classify a food list into pillars, then score it. Used when the user
  /// edits what was on the plate.
  factory SatietyResult.fromFoods({
    required String mealName,
    required List<String> components,
    HybridUpgrade? hybridUpgrade,
    String? captureIssue,
  }) {
    final foods = normalizeFoodList(components);
    if (foods.isEmpty) {
      const silent = PillarDetail(detected: false, items: [], quality: 'low');
      return SatietyResult(
        mealName: mealName.trim().isEmpty ? 'Plate' : mealName.trim(),
        components: const [],
        pillars: SatietyPillars(
          anchor: silent,
          net: silent,
          buffer: silent,
          spark: silent,
        ),
        satietyScore: 0,
        durationHours: 0,
        crashRisk: 'low',
        hybridUpgrade: hybridUpgrade ?? HybridUpgrade.fromJson(const {}),
        captureIssue: captureIssue,
      );
    }
    final pillars = SatietyPillars(
      anchor: _pillarFromFoods(foods, const [
        'burger',
        'patties',
        'patty',
        'steak',
        'chicken',
        'beef',
        'pork',
        'meat',
        'meatball',
        'fish',
        'salmon',
        'tuna',
        'sardine',
        'mackerel',
        'egg',
        'eggs',
        'tofu',
        'tempeh',
        'lentil',
        'chickpea',
        'yogurt',
        'turkey',
        'shrimp',
        'prawn',
        'bacon',
        'sausage',
        'lamb',
        'duck',
        'ham',
        'protein',
        'cottage',
        'beans',
      ]),
      net: _pillarFromFoods(foods, const [
        'salad',
        'lettuce',
        'broccoli',
        'spinach',
        'kale',
        'vegetable',
        'veggies',
        'quinoa',
        'oatmeal',
        'oats',
        'oat',
        'bean',
        'beans',
        'lentil',
        'chickpea',
        'slaw',
        'cabbage',
        'apple',
        'berries',
        'berry',
        'avocado',
        'brown rice',
        'whole grain',
        'fruit',
        'greens',
        'cucumber',
        'tomato',
        'carrot',
        'arugula',
        'hummus',
      ]),
      buffer: _pillarFromFoods(
        foods,
        const [
          'avocado',
          'olive oil',
          'olives',
          'walnut',
          'almond',
          'chia',
          'flax',
          'tahini',
          'pistachio',
          'salmon',
          'mackerel',
          'sardine',
          'seeds',
          'peanut',
          'cashew',
          'guacamole',
          'sesame',
        ],
        weakNeedles: const [
          'cheese sauce',
          'melted cheese',
          'cream sauce',
          'gravy',
          'mayo',
          'mayonnaise',
          'ranch',
          'margarine',
          'aioli',
          'cheese',
          'cream',
        ],
      ),
      spark: _pillarFromFoods(
        foods,
        const [
          'salad',
          'cucumber',
          'tomato',
          'celery',
          'greens',
          'lettuce',
          'slaw',
          'pickle',
          'berries',
          'apple',
          'watermelon',
          'radish',
          'fruit',
          'orange',
          'melon',
          'spinach',
          'kale',
        ],
        weakNeedles: const [
          'chips',
          'fries',
          'crisps',
          'french fry',
          'tater tots',
          'crackers',
          'pretzels',
        ],
      ),
    );

    return SatietyResult(
      mealName: mealName.trim().isEmpty ? 'Mindful Plate' : mealName.trim(),
      components: foods,
      pillars: pillars,
      satietyScore: 0,
      durationHours: 0,
      crashRisk: 'moderate',
      hybridUpgrade: hybridUpgrade ?? HybridUpgrade.fromJson(const {}),
      captureIssue: captureIssue,
    ).rebalanced();
  }

  /// Presence is not quality. Cheese sauce is not a Buffer. Chips are not Spark.
  SatietyResult rebalanced() {
    if (captureIssue != null) return this;
    final blob = [
      mealName,
      ...components,
      ...pillars.anchor.items,
      ...pillars.net.items,
      ...pillars.buffer.items,
      ...pillars.spark.items,
    ].join(' ').toLowerCase();

    bool has(List<String> needles) => needles.any((n) => blob.contains(n));

    String worse(String current, String cap) {
      const order = ['low', 'medium', 'high'];
      int idx(String value) {
        final i = order.indexOf(value);
        return i < 0 ? 1 : i;
      }

      final a = idx(current);
      final b = idx(cap);
      return order[a < b ? a : b];
    }

    final friedOrRefined = has(const [
      'chips',
      'fries',
      'fried',
      'crisps',
      'french fry',
      'donut',
      'doughnut',
      'pastry',
      'soda',
      'milkshake',
      'candy',
      'beer',
      'wine',
      'cocktail',
    ]);

    var buffer = pillars.buffer;
    final strongBuffer = has(const [
      'avocado',
      'olive oil',
      'olives',
      'walnut',
      'almond',
      'chia',
      'flax',
      'tahini',
      'pistachio',
      'salmon',
      'mackerel',
      'sardine',
      'seeds',
    ]);
    final weakBufferHit =
        buffer.detected &&
        has(const [
          'cheese sauce',
          'melted cheese',
          'cream sauce',
          'gravy',
          'mayo',
          'mayonnaise',
          'ranch',
          'margarine',
          'aioli',
        ]) &&
        !strongBuffer;
    if (weakBufferHit) {
      buffer = buffer.copyWith(quality: worse(buffer.quality, 'low'));
    }

    var net = pillars.net;
    final strongNet = has(const [
      'salad',
      'lettuce',
      'broccoli',
      'lentil',
      'chickpea',
      'kale',
      'spinach',
      'slaw',
      'beans',
      'quinoa',
      'oat',
      'vegetable',
    ]);
    final genericNet =
        net.items.isNotEmpty &&
        net.items.every((item) {
          final label = item.trim().toLowerCase();
          return label == 'fiber' ||
              label == 'fibre' ||
              label == 'plants' ||
              label == 'plant';
        });
    if (net.detected && genericNet && !strongNet) {
      net = net.copyWith(quality: worse(net.quality, 'low'));
    }
    if (net.detected &&
        has(const [
          'bun',
          'wrap',
          'tortilla',
          'white rice',
          'pasta',
          'bagel',
          'white bread',
        ]) &&
        !strongNet) {
      net = net.copyWith(quality: worse(net.quality, 'medium'));
    }
    if (friedOrRefined && net.detected) {
      net = net.copyWith(quality: worse(net.quality, 'medium'));
    }

    var spark = pillars.spark;
    final strongSpark = has(const [
      'salad',
      'cucumber',
      'tomato',
      'celery',
      'greens',
      'lettuce',
      'slaw',
      'pickle',
      'berries',
      'apple',
      'watermelon',
      'radish',
    ]);
    final weakSparkHit =
        spark.detected &&
        has(const ['chips', 'fries', 'crisps', 'french fry', 'tater tots']) &&
        !strongSpark;
    if (weakSparkHit) {
      spark = spark.copyWith(quality: worse(spark.quality, 'low'));
    }

    return copyWith(
      pillars: pillars.copyWith(buffer: buffer, net: net, spark: spark),
      durationHours: 0,
      satietyScore: hasModelAssessment ? satietyScore : 0,
      crashRisk: 'moderate',
    );
  }

  /// A diary entry typed by the user, with no vision model involved.
  factory SatietyResult.manual({
    required String mealName,
    required SatietyPillars pillars,
    double? durationHours,
    String? crashRisk,
  }) {
    return SatietyResult(
      mealName: mealName,
      components: mealName.isEmpty ? const [] : [mealName],
      pillars: pillars,
      satietyScore: 0,
      durationHours: 0,
      crashRisk: 'moderate',
      hybridUpgrade: HybridUpgrade.fromJson(const {}),
    );
  }

  factory SatietyResult.fromJson(Map<String, dynamic> json) {
    final rawScore = json['satietyScore'];
    final int parsedScore = rawScore is num
        ? rawScore.round()
        : int.tryParse(rawScore?.toString() ?? '') ?? 75;

    return SatietyResult(
      assessmentModel: json['assessmentModel'] is String
          ? json['assessmentModel']
          : '',
      assessmentId: json['assessmentId'] is String ? json['assessmentId'] : '',
      assessmentMethod: json['assessmentMethod'] is String
          ? json['assessmentMethod']
          : null,
      assessmentNote: json['assessmentNote'] is String
          ? json['assessmentNote']
          : '',
      originalAnalysis: asStringKeyedMap(json['originalAnalysis']),
      fullnessEstimate:
          json['assessmentMethod'] == modelMethod &&
              (json['captureIssue'] == null || json['captureIssue'] == 'none')
          ? FullnessEstimate.parse(json['fullnessEstimate'])
          : null,
      nutrientLookupComplete: json['nutrientLookupComplete'] == true,
      foodProfiles: (json['foodProfiles'] is List
          ? (json['foodProfiles'] as List)
                .map(FoodNutrientProfile.parse)
                .whereType<FoodNutrientProfile>()
                .toList()
          : const []),
      mealName: json['mealName'] is String
          ? json['mealName'] as String
          : 'Mindful Plate',
      components:
          (json['components'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      pillars: SatietyPillars.fromJson(
        asStringKeyedMap(json['pillars']) ?? const {},
      ),
      satietyScore: parsedScore.clamp(0, 100),
      durationHours: _asDurationHours(json['durationHours']),
      crashRisk: _asCrashRisk(json['crashRisk']),
      hybridUpgrade: HybridUpgrade.fromJson(
        asStringKeyedMap(json['hybridUpgrade']) ?? const {},
      ),
      captureIssue: _asCaptureIssue(json['captureIssue']),
    );
  }

  Map<String, dynamic> toJson() => {
    'assessmentId': assessmentId,
    'assessmentModel': assessmentModel,
    if (assessmentMethod != null) 'assessmentMethod': assessmentMethod,
    'assessmentNote': assessmentNote,
    if (fullnessEstimate != null)
      'fullnessEstimate': fullnessEstimate!.toJson(),
    if (originalAnalysis != null) 'originalAnalysis': originalAnalysis,
    'nutrientLookupComplete': nutrientLookupComplete,
    'foodProfiles': foodProfiles.map((p) => p.toJson()).toList(),
    'mealName': mealName,
    'components': components,
    'pillars': pillars.toJson(),
    'satietyScore': satietyScore,
    'durationHours': durationHours,
    'crashRisk': crashRisk,
    'hybridUpgrade': hybridUpgrade.toJson(),
    if (captureIssue != null) 'captureIssue': captureIssue,
  };
}
