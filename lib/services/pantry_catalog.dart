import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/fullness_assessment.dart';

import '../models/satiety_matrix.dart';

/// Pantry labels. Ratings use the sourced nutrient_profiles asset.
class PantryFood {
  final String name;
  const PantryFood({required this.name});
}

class PantryCatalog {
  PantryCatalog._();
  static const foods = <PantryFood>[
    PantryFood(name: 'Eggs'),
    PantryFood(name: 'Greek yogurt'),
    PantryFood(name: 'Chicken'),
    PantryFood(name: 'Salmon'),
    PantryFood(name: 'Tofu'),
    PantryFood(name: 'Beans'),
    PantryFood(name: 'Side salad'),
    PantryFood(name: 'Broccoli'),
    PantryFood(name: 'Oats'),
    PantryFood(name: 'Lentils'),
    PantryFood(name: 'Berries'),
    PantryFood(name: 'Avocado'),
    PantryFood(name: 'Olive oil'),
    PantryFood(name: 'Walnuts'),
    PantryFood(name: 'Almonds'),
    PantryFood(name: 'Tahini'),
    PantryFood(name: 'Cucumber'),
    PantryFood(name: 'Cherry tomatoes'),
    PantryFood(name: 'Greens'),
    PantryFood(name: 'Apple'),
    PantryFood(name: 'Slaw'),
    PantryFood(name: 'Orange juice'),
    PantryFood(name: 'Sloppy joes'),
    PantryFood(name: 'Strawberries'),
    PantryFood(name: 'Banana'),
    PantryFood(name: 'Orange'),
    PantryFood(name: 'Rice'),
    PantryFood(name: 'Pasta'),
    PantryFood(name: 'Bread'),
    PantryFood(name: 'Milk'),
  ];

  static const _aliases = <String, String>{
    'strawberry': 'strawberries',
    'strawberrys': 'strawberries',
    'blueberry': 'berries',
    'blueberries': 'berries',
    'berry': 'berries',
    'egg': 'eggs',
    'hardboiled egg': 'eggs',
    'edamame beans': 'edamame',
    'yogurt': 'greek yogurt',
    'yoghurt': 'greek yogurt',
    'greek yoghurt': 'greek yogurt',
    'chicken breast': 'chicken',
    'grilled chicken': 'chicken',
    'tomato': 'cherry tomatoes',
    'tomatoes': 'cherry tomatoes',
    'cherry tomato': 'cherry tomatoes',
    'spinach': 'greens',
    'lettuce': 'side salad',
    'salad': 'side salad',
    'oj': 'orange juice',
    'orange juice': 'orange juice',
    'sloppy joe': 'sloppy joes',
    'bananas': 'banana',
    'oranges': 'orange',
    'apples': 'apple',
    'cucumbers': 'cucumber',
    'almond': 'almonds',
    'walnut': 'walnuts',
    'lentil': 'lentils',
    'bean': 'beans',
    'oat': 'oats',
    'white rice': 'rice',
    'spaghetti': 'pasta',
    'noodles': 'pasta',
  };

  static final Map<String, PantryFood> _byKey = {
    for (final food in foods) food.name.toLowerCase(): food,
  };

  static String _stem(String key) {
    if (key.endsWith('ies') && key.length > 4) {
      return '${key.substring(0, key.length - 3)}y';
    }
    if (key.endsWith('oes') && key.length > 4) {
      return key.substring(0, key.length - 2);
    }
    if (key.endsWith('es') && key.length > 4) {
      return key.substring(0, key.length - 2);
    }
    if (key.endsWith('s') && !key.endsWith('ss') && key.length > 3) {
      return key.substring(0, key.length - 1);
    }
    return key;
  }

  static PantryFood? lookup(String name) => resolve(name);

  /// Chip names, aliases, and simple plurals. Typed names that are not
  /// chips go to Gemini, then the cache.
  static PantryFood? resolve(String name) {
    var key = name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    if (key.isEmpty) return null;

    PantryFood? hit(String candidate) {
      if (candidate.isEmpty) return null;
      final extra = _profiles[candidate];
      if (extra != null && !_byKey.containsKey(candidate)) {
        return PantryFood(name: extra.name);
      }
      final direct = _byKey[candidate];
      if (direct != null) return direct;
      final alias = _aliases[candidate];
      if (alias != null) return _byKey[alias] ?? hit(alias);
      return null;
    }

    final exact = hit(key);
    if (exact != null) return exact;
    return hit(_stem(key));
  }

  static bool covers(Iterable<String> foods) {
    final list = normalizeFoodList(foods);
    return list.isNotEmpty && list.every((food) => resolve(food) != null);
  }

  static final Map<String, FoodNutrientProfile> _profiles = {};

  static Future<void> loadProfiles() async {
    final raw =
        jsonDecode(
              await rootBundle.loadString(
                'assets/pantry/nutrient_profiles.json',
              ),
            )
            as Map;
    _profiles.clear();
    for (final entry in raw.entries) {
      final profile = FoodNutrientProfile.parse(entry.value);
      if (profile != null) {
        _profiles[entry.key.toString().toLowerCase()] = profile;
      }
    }
  }

  static SatietyResult score({
    required String mealName,
    required List<String> foods,
  }) {
    final list = normalizeFoodList(foods);
    final profiles = <FoodNutrientProfile>[];
    for (final name in list) {
      final canonical = resolve(name)?.name.toLowerCase();
      final p = _profiles[canonical];
      if (p != null) {
        profiles.add(FoodNutrientProfile.parse({...p.toJson(), 'name': name})!);
      }
    }
    return SatietyResult.fromFoods(
      mealName: mealName,
      components: list,
    ).copyWith(
      durationHours: 0,
      satietyScore: 0,
      crashRisk: 'moderate',
      foodProfiles: profiles,
      nutrientLookupComplete: true,
    );
  }
}
