import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Gemini-seeded hours for pantry chips. Loaded from
/// assets/pantry/gemini_chip_scores.json at boot. A miss falls back to
/// the USDA formula in PantryCatalog.
class ChipScoreStore {
  ChipScoreStore._();

  static const assetPath = 'assets/pantry/gemini_chip_scores.json';

  static final Map<String, double> _hours = {};
  static bool _assetTried = false;

  static void replaceAll(Map<String, double> hours) {
    _hours
      ..clear()
      ..addAll({
        for (final entry in hours.entries)
          if (entry.key.trim().isNotEmpty && entry.value > 0)
            entry.key.trim().toLowerCase(): entry.value,
      });
  }

  static void resetForTest() {
    _hours.clear();
    _assetTried = false;
  }

  static Future<void> loadAsset() async {
    if (_assetTried) return;
    _assetTried = true;
    try {
      final raw = await rootBundle.loadString(assetPath);
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        loadFromJson(decoded);
      }
    } catch (e) {
      debugPrint('Chip score store load failed: $e');
    }
  }

  static void loadFromJson(Map<String, dynamic> json) {
    final raw = json['hours'];
    if (raw is! Map) return;
    final next = <String, double>{};
    raw.forEach((key, value) {
      if (key is! String) return;
      if (value is num && value > 0) {
        next[key] = value.toDouble();
      }
    });
    replaceAll(next);
  }

  static double? hoursFor(String name) {
    final key = name.trim().toLowerCase();
    if (key.isEmpty) return null;
    return _hours[key];
  }

  static bool covers(Iterable<String> foods) {
    final list = foods
        .map((food) => food.trim())
        .where((food) => food.isNotEmpty)
        .toList();
    return list.isNotEmpty && list.every((food) => hoursFor(food) != null);
  }
}
