import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../core/json/json_map.dart';
import '../core/security/hive_key_store.dart';
import '../models/satiety_matrix.dart';

class FoodScoreCacheEntry {
  final bool isFood;
  final SatietyResult? result;
  final DateTime cachedAt;
  final DateTime lastAccess;

  const FoodScoreCacheEntry({
    required this.isFood,
    required this.cachedAt,
    required this.lastAccess,
    this.result,
  });
}

/// Memory LRU plus an encrypted Hive box. Success lives 30 days, not-food
/// lives 24 hours, and 5xx responses are never written.
class FoodScoreCache {
  static const boxName = 'evenplate_food_scores_aes';
  static const maxEntries = 500;
  static const successTtl = Duration(days: 30);
  static const notFoodTtl = Duration(hours: 24);

  final LinkedHashMap<String, FoodScoreCacheEntry> _memory =
      LinkedHashMap<String, FoodScoreCacheEntry>();
  Box<String>? _box;
  int generation = 0;

  Future<void> clear() async {
    generation++;
    _memory.clear();
    await _box?.clear();
  }

  Future<void> removeKeys(Iterable<String> keys) async {
    for (final key in keys) {
      _memory.remove(key);
    }
    await _box?.deleteAll(keys);
  }

  int get length => _memory.length;

  static String keyFor(Iterable<String> foods) {
    final keys =
        foods
            .map((food) => food.trim().toLowerCase())
            .where((food) => food.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return keys.join('|');
  }

  Future<void> init({HiveKeyStore? keyStore}) async {
    final cipher = HiveAesCipher(
      await (keyStore ?? SecureHiveKeyStore()).loadOrCreateKey(),
    );
    if (Hive.isBoxOpen(boxName)) {
      await Hive.box<String>(boxName).close();
    }
    _box = await Hive.openBox<String>(boxName, encryptionCipher: cipher);
    if (_box!.get('_schema_version') != '7') {
      await _box!.clear();
      await _box!.put('_schema_version', '7');
    }
    _loadFromBox();
  }

  FoodScoreCacheEntry? read(String key) {
    if (key.isEmpty) return null;
    final memory = _memory.remove(key);
    if (memory != null) {
      if (_expired(memory)) {
        _forget(key);
        return null;
      }
      final touched = FoodScoreCacheEntry(
        isFood: memory.isFood,
        result: memory.result,
        cachedAt: memory.cachedAt,
        lastAccess: DateTime.now().toUtc(),
      );
      _memory[key] = touched;
      _persist(key, touched);
      return touched;
    }

    final raw = _box?.get(key);
    if (raw == null) return null;
    final parsed = _decode(raw);
    if (parsed == null || _expired(parsed)) {
      _forget(key);
      return null;
    }
    final touched = FoodScoreCacheEntry(
      isFood: parsed.isFood,
      result: parsed.result,
      cachedAt: parsed.cachedAt,
      lastAccess: DateTime.now().toUtc(),
    );
    _memory[key] = touched;
    _persist(key, touched);
    return touched;
  }

  void writeSuccess(String key, SatietyResult result) {
    if (key.isEmpty) return;
    final now = DateTime.now().toUtc();
    _put(
      key,
      FoodScoreCacheEntry(
        isFood: true,
        result: result,
        cachedAt: now,
        lastAccess: now,
      ),
    );
  }

  void writeNotFood(String key) {
    if (key.isEmpty) return;
    final now = DateTime.now().toUtc();
    _put(
      key,
      FoodScoreCacheEntry(isFood: false, cachedAt: now, lastAccess: now),
    );
  }

  @visibleForTesting
  void seed(String key, FoodScoreCacheEntry entry) {
    _put(key, entry);
  }

  void _put(String key, FoodScoreCacheEntry entry) {
    _memory.remove(key);
    _memory[key] = entry;
    _persist(key, entry);
    _evict();
  }

  void _loadFromBox() {
    final box = _box;
    if (box == null) return;
    final loaded = <MapEntry<String, FoodScoreCacheEntry>>[];
    for (final key in box.keys) {
      if (key is! String || key == '_schema_version') continue;
      final parsed = _decode(box.get(key));
      if (parsed == null || _expired(parsed)) {
        box.delete(key);
        continue;
      }
      loaded.add(MapEntry(key, parsed));
    }
    loaded.sort((a, b) => a.value.lastAccess.compareTo(b.value.lastAccess));
    for (final entry in loaded) {
      _memory[entry.key] = entry.value;
    }
    _evict();
  }

  void _evict() {
    while (_memory.length > maxEntries) {
      final oldest = _memory.keys.first;
      _forget(oldest);
    }
  }

  void _forget(String key) {
    _memory.remove(key);
    _box?.delete(key);
  }

  void _persist(String key, FoodScoreCacheEntry entry) {
    final box = _box;
    if (box == null) return;
    box.put(key, jsonEncode(_encode(entry)));
  }

  bool _expired(FoodScoreCacheEntry entry) {
    final ttl = entry.isFood ? successTtl : notFoodTtl;
    return DateTime.now().toUtc().difference(entry.cachedAt) >= ttl;
  }

  Map<String, dynamic> _encode(FoodScoreCacheEntry entry) {
    return {
      'isFood': entry.isFood,
      'cachedAt': entry.cachedAt.toIso8601String(),
      'lastAccess': entry.lastAccess.toIso8601String(),
      if (entry.result != null) 'result': entry.result!.toJson(),
    };
  }

  FoodScoreCacheEntry? _decode(String? raw) {
    if (raw == null) return null;
    try {
      final map = asStringKeyedMap(jsonDecode(raw));
      if (map == null) return null;
      final cachedAt = DateTime.tryParse('${map['cachedAt']}')?.toUtc();
      final lastAccess = DateTime.tryParse('${map['lastAccess']}')?.toUtc();
      if (cachedAt == null || lastAccess == null) return null;
      final isFood = map['isFood'] == true;
      SatietyResult? result;
      if (isFood) {
        final resultMap = asStringKeyedMap(map['result']);
        if (resultMap == null) return null;
        result = SatietyResult.fromJson(resultMap);
      }
      return FoodScoreCacheEntry(
        isFood: isFood,
        result: result,
        cachedAt: cachedAt,
        lastAccess: lastAccess,
      );
    } catch (e) {
      debugPrint('Food score cache decode failed: $e');
      return null;
    }
  }
}
