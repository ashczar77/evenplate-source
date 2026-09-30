import 'dart:math';

class FoodNutrientProfile {
  final String name;
  final int fdcId;
  final String description;
  final double kcal;
  final double proteinG;
  final double fiberG;
  final double fatG;
  final double portionG;
  final bool liquid;

  const FoodNutrientProfile({
    required this.name,
    required this.fdcId,
    required this.description,
    required this.kcal,
    required this.proteinG,
    required this.fiberG,
    required this.fatG,
    this.portionG = 100,
    this.liquid = false,
  });

  static FoodNutrientProfile? parse(Object? value) {
    if (value is! Map) return null;
    double? number(String key) {
      final v = value[key];
      return v is num && v.isFinite && v >= 0 ? v.toDouble() : null;
    }

    final kcal = number('kcal'),
        protein = number('proteinG'),
        fiber = number('fiberG'),
        fat = number('fatG'),
        grams = number('portionG');
    final id = value['fdcId'];
    if (id is! int ||
        id <= 0 ||
        kcal == null ||
        protein == null ||
        fiber == null ||
        fat == null ||
        grams == null ||
        grams <= 0 ||
        grams > 10000 ||
        kcal > 1000 ||
        protein > 100 ||
        fiber > 100 ||
        fat > 100) {
      return null;
    }
    if (value['name'] is! String ||
        value['description'] is! String ||
        (value['name'] as String).trim().isEmpty ||
        (value['description'] as String).trim().isEmpty) {
      return null;
    }
    return FoodNutrientProfile(
      name: value['name'],
      fdcId: id,
      description: value['description'],
      kcal: kcal,
      proteinG: protein,
      fiberG: fiber,
      fatG: fat,
      portionG: grams,
      liquid: value['liquid'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'fdcId': fdcId,
    'description': description,
    'kcal': kcal,
    'proteinG': proteinG,
    'fiberG': fiberG,
    'fatG': fatG,
    'portionG': portionG,
    'liquid': liquid,
  };
}

class FullnessAssessment {
  final double value;
  final List<FoodNutrientProfile> profiles;
  final bool modelEstimated;
  final String note;
  String get label => modelEstimated
      ? "${value.round()} / 100"
      : "${value.toStringAsFixed(1)} / 5";
  const FullnessAssessment(this.value, this.profiles)
    : modelEstimated = false,
      note = "";
  const FullnessAssessment.model(this.value, this.note)
    : modelEstimated = true,
      profiles = const [];

  // NutritionData Fullness Factor, published coefficients and input limits.
  // US7620531B1, preferred FF equation. Inputs are nutrients per 100 g.
  static double calculate({
    required double kcal,
    required double proteinG,
    required double fiberG,
    required double fatG,
  }) {
    final values = [kcal, proteinG, fiberG, fatG];
    if (values.any((v) => !v.isFinite || v < 0)) {
      throw ArgumentError('Invalid nutrient data');
    }
    final ff =
        37 / 60 +
        (2500 / 60) * pow(max(30, kcal), -0.7) +
        (3 / 60) * min(30, proteinG) +
        pow(min(12, fiberG), 3) / 1620 -
        pow(min(50, fatG), 3) / 138000;
    return ff.clamp(0.5, 5.0).toDouble();
  }

  static FullnessAssessment? forFoods(
    List<String> foods,
    List<FoodNutrientProfile> profiles,
  ) {
    if (foods.isEmpty) return null;
    final mapped = {for (final p in profiles) p.name.trim().toLowerCase(): p};
    final selected = <FoodNutrientProfile>[];
    for (final food in foods) {
      final p = mapped[food.trim().toLowerCase()];
      if (p == null || p.liquid || p.kcal <= 0) return null;
      selected.add(p);
    }
    var weight = 0.0, kcal = 0.0, protein = 0.0, fiber = 0.0, fat = 0.0;
    for (final p in selected) {
      weight += p.portionG;
      kcal += p.kcal * p.portionG / 100;
      protein += p.proteinG * p.portionG / 100;
      fiber += p.fiberG * p.portionG / 100;
      fat += p.fatG * p.portionG / 100;
    }
    return FullnessAssessment(
      calculate(
        kcal: kcal * 100 / weight,
        proteinG: protein * 100 / weight,
        fiberG: fiber * 100 / weight,
        fatG: fat * 100 / weight,
      ),
      selected,
    );
  }
}
