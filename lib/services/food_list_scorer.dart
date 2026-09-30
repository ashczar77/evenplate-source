import 'dart:async';
import 'dart:convert';
import 'dart:collection';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import '../core/errors/telemetry.dart';
import '../models/satiety_matrix.dart';
import 'food_score_cache.dart';
import 'gemini_vision_service.dart';

class FoodScoreOutcome {
  final SatietyResult result;
  final bool isFood;
  final bool settled;
  final List<String> rejected;
  final List<String> pending;
  final ScanQuota? quota;
  final String? failureMessage;
  const FoodScoreOutcome({
    required this.result,
    required this.isFood,
    required this.settled,
    this.rejected = const [],
    this.pending = const [],
    this.quota,
    this.failureMessage,
  });
}

// Cache complete assessments. Individual food scores cannot be composed.
class FoodListScorer {
  FoodListScorer._();
  static final FoodListScorer instance = FoodListScorer._();
  FoodScoreCache cache = FoodScoreCache();
  GeminiVisionService? vision;
  bool persistCache = false;
  Future<void>? _cacheInit;
  final Map<String, Future<FoodScoreOutcome>> _inflight = {};
  final LinkedHashMap<String, SatietyResult> _snapshots = LinkedHashMap();
  int _snapshotGeneration = 0;

  void configure({GeminiVisionService? vision, bool persistCache = false}) {
    this.vision = vision;
    this.persistCache = persistCache;
    if (persistCache) unawaited(_ensureCache());
  }

  @visibleForTesting
  void resetForTest({FoodScoreCache? cache, GeminiVisionService? vision}) {
    this.cache = cache ?? FoodScoreCache();
    this.vision = vision;
    persistCache = false;
    _cacheInit = null;
    _inflight.clear();
    _snapshots.clear();
    _snapshotGeneration = this.cache.generation;
  }

  Future<void> _ensureCache() async {
    if (!persistCache) return;
    await (_cacheInit ??= cache.init().catchError((Object e) {
      debugPrint('Food cache initialization failed');
    }));
  }

  Future<void> invalidateFoods(List<List<String>> selections) async {
    await _ensureCache();
    final keys = selections.map((foods) => keyFor(foods)).toList();
    for (final key in keys) {
      _snapshots.remove(key);
    }
    await cache.removeKeys(keys);
  }

  void _checkGeneration() {
    if (_snapshotGeneration == cache.generation) return;
    _snapshots.clear();
    _inflight.clear();
    _snapshotGeneration = cache.generation;
  }

  static String keyFor(List<String> foods, {SatietyResult? original}) {
    final selected =
        foods
            .map((f) => f.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase())
            .toSet()
            .toList()
          ..sort();
    return sha256
        .convert(
          utf8.encode(
            jsonEncode([
              'gemini-meal-regular-range-v2',
              original?.assessmentContext,
              selected,
            ]),
          ),
        )
        .toString();
  }

  void _remember(String key, SatietyResult result) {
    _snapshots.remove(key);
    _snapshots[key] = SatietyResult.fromJson(result.toJson());
    while (_snapshots.length > FoodScoreCache.maxEntries) {
      _snapshots.remove(_snapshots.keys.first);
    }
  }

  SatietyResult? cachedPlate({
    required String mealName,
    required List<String> foods,
    SatietyResult? original,
  }) {
    _checkGeneration();
    final key = keyFor(foods, original: original);
    final snapshot = _snapshots[key];
    if (snapshot != null) return snapshot.copyWith(mealName: mealName);
    final hit = cache.read(key);
    if (hit?.isFood != true || hit?.result?.hasModelAssessment != true) {
      return null;
    }
    return hit!.result!.copyWith(mealName: mealName);
  }

  void rememberScan(SatietyResult result) {
    _checkGeneration();
    final original = result.original;
    // Keep the original even if it predates the current assessment method.
    _remember(keyFor(original.components, original: original), original);
    _remember(keyFor(result.components, original: original), result);
    if (result.hasModelAssessment) {
      cache.writeSuccess(keyFor(result.components, original: original), result);
    }
  }

  Future<FoodScoreOutcome> score({
    required String mealName,
    required List<String> foods,
    SatietyResult? original,
  }) async {
    _checkGeneration();
    final descriptions = foods
        .map((f) => f.trim().replaceAll(RegExp(r'\s+'), ' '))
        .where((f) => f.isNotEmpty)
        .toList();
    if (descriptions.map((f) => f.toLowerCase()).toSet().length >
            kMaxFoodItems ||
        descriptions.any((f) => f.length > kMaxFoodNameLength)) {
      return FoodScoreOutcome(
        result: SatietyResult.fromFoods(
          mealName: mealName,
          components: const [],
        ),
        isFood: true,
        settled: false,
        pending: foods,
        failureMessage:
            'Use up to 40 foods, with each description at most 60 characters.',
      );
    }
    final normalized = normalizeFoodList(foods);
    final name = mealName.trim().isEmpty ? 'Plate' : mealName.trim();
    final key = keyFor(normalized, original: original);
    final pending = _inflight[key];
    if (pending != null) return pending;
    final future = _scoreOnce(name, normalized, original, key);
    _inflight[key] = future;
    try {
      return await future;
    } finally {
      if (identical(_inflight[key], future)) _inflight.remove(key);
    }
  }

  Future<FoodScoreOutcome> _scoreOnce(
    String name,
    List<String> foods,
    SatietyResult? original,
    String key,
  ) async {
    final local = SatietyResult.fromFoods(mealName: name, components: foods);
    if (foods.isEmpty) {
      return FoodScoreOutcome(result: local, isFood: false, settled: true);
    }
    final generation = cache.generation;
    await _ensureCache();
    if (generation != cache.generation) {
      return FoodScoreOutcome(
        result: local,
        isFood: true,
        settled: false,
        pending: foods,
        failureMessage: 'Account changed. Please try again.',
      );
    }
    final hit = cachedPlate(mealName: name, foods: foods, original: original);
    if (hit != null) {
      Telemetry.assessmentBreadcrumb('cache_hit', {'food_count': foods.length});
      return FoodScoreOutcome(result: hit, isFood: true, settled: true);
    }
    if (cache.read(key)?.isFood == false) {
      return FoodScoreOutcome(
        result: local,
        isFood: false,
        settled: true,
        rejected: foods,
      );
    }
    final remote = vision;
    if (remote == null) {
      return FoodScoreOutcome(
        result: local,
        isFood: true,
        settled: false,
        pending: foods,
        failureMessage:
            'Connect to assess this plate. Previously assessed plates still work.',
      );
    }
    try {
      final timer = Stopwatch()..start();
      final analysis = await remote.analyzeFoods(
        mealName: _remoteMealName(name),
        foods: foods,
        original: original,
      );
      Telemetry.assessmentBreadcrumb('remote_completed', {
        'food_count': foods.length,
        'latency_ms': timer.elapsedMilliseconds,
      });
      if (generation != cache.generation) {
        throw const PlateAnalysisException(
          'Account changed. Please try again.',
          code: 'ACCOUNT_CHANGED',
        );
      }
      if (analysis.result.captureIssue == 'not_food') {
        cache.writeNotFood(key);
        return FoodScoreOutcome(
          result: local.copyWith(captureIssue: 'not_food'),
          isFood: false,
          settled: true,
          rejected: analysis.rejected.isEmpty ? foods : analysis.rejected,
          quota: analysis.quota,
        );
      }
      if (!analysis.result.hasModelAssessment) {
        throw const PlateAnalysisException(
          'Meal assessment returned an incomplete response. Please try again.',
          code: 'GEMINI_MALFORMED',
        );
      }
      final rejected = analysis.rejected.map((f) => f.toLowerCase()).toSet();
      final kept = foods
          .where((f) => !rejected.contains(f.toLowerCase()))
          .toList();
      if (FoodScoreCache.keyFor(kept) !=
          FoodScoreCache.keyFor(analysis.result.components)) {
        throw PlateAnalysisException(
          'The complete plate could not be assessed. Please try again.',
          code: 'GEMINI_MALFORMED',
          quota: analysis.quota,
        );
      }
      final result = analysis.result.copyWith(
        mealName: name,
        components: kept,
        originalAnalysis: original == null
            ? null
            : {
                ...original.assessmentContext,
                'assessmentMethod': original.assessmentMethod,
              },
      );
      if (analysis.rejected.isEmpty) {
        cache.writeSuccess(key, result);
        _remember(key, result);
      } else {
        final keptKey = keyFor(kept, original: original);
        cache.writeSuccess(keptKey, result);
        _remember(keptKey, result);
      }
      return FoodScoreOutcome(
        result: result,
        isFood: kept.isNotEmpty,
        settled: true,
        rejected: analysis.rejected,
        quota: analysis.quota,
      );
    } on ScanQuotaExceededException catch (e) {
      return FoodScoreOutcome(
        result: local,
        isFood: true,
        settled: false,
        pending: foods,
        quota: e.quota,
        failureMessage:
            'This week\'s meal assessments are used. Previously assessed plates still work.',
      );
    } catch (e, st) {
      if (e is PlateAnalysisException && e.alert) {
        Telemetry.report(
          name: e.telemetryNameFor('foods'),
          error: e,
          stack: st,
          tags: {
            'source': 'app',
            if (e.code != null) 'code': e.code!,
            if (e.statusCode != null) 'http_status': '${e.statusCode}',
          },
        );
      } else if (e is! PlateAnalysisException) {
        Telemetry.report(name: 'foods.unknown', error: e, stack: st);
      }
      return FoodScoreOutcome(
        result: local,
        isFood: true,
        settled: false,
        pending: foods,
        failureMessage: e is PlateAnalysisException
            ? e.message
            : 'Meal assessment failed. Check your connection and try again.',
        quota: e is PlateAnalysisException ? e.quota : null,
      );
    }
  }

  static String _remoteMealName(String name) {
    final key = name.trim().toLowerCase();
    return ['test', 'hello', 'asdf'].contains(key) ? 'Plate' : name;
  }
}
