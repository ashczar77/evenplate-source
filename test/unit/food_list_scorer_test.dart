import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:evenplate/core/errors/telemetry.dart';
import 'package:evenplate/core/security/hive_key_store.dart';
import 'package:evenplate/models/satiety_matrix.dart';
import 'package:evenplate/services/food_list_scorer.dart';
import 'package:evenplate/services/food_score_cache.dart';
import 'package:evenplate/services/gemini_vision_service.dart';

SatietyResult meal(
  List<String> foods, {
  int score = 61,
  String id = 'scan-a',
}) => SatietyResult.fromFoods(mealName: 'Plate', components: foods).copyWith(
  assessmentMethod: SatietyResult.modelMethod,
  assessmentId: id,
  satietyScore: score,
  assessmentNote: 'Ordinary portions assumed.',
);
http.Response response(
  List<String> foods, {
  int score = 61,
  List<String> rejected = const [],
  String issue = 'none',
}) => http.Response(
  jsonEncode({
    ...meal(foods, score: score).toJson(),
    'rejected': rejected,
    'captureIssue': issue,
  }),
  200,
);

class TestKeys implements HiveKeyStore {
  @override
  Future<List<int>> loadOrCreateKey() async => List.generate(32, (i) => i);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final scorer = FoodListScorer.instance;
  setUp(() {
    scorer.resetForTest();
    Telemetry.resetForTest();
  });
  test(
    'targeted invalidation removes snacks but preserves other assessments',
    () async {
      scorer.cache.writeSuccess(
        FoodListScorer.keyFor(['Almonds']),
        meal(['Almonds']),
      );
      scorer.cache.writeSuccess(
        FoodListScorer.keyFor(['Rice']),
        meal(['Rice']),
      );
      await scorer.invalidateFoods([
        ['Almonds'],
      ]);
      expect(scorer.cachedPlate(mealName: 'Snack', foods: ['Almonds']), isNull);
      expect(scorer.cachedPlate(mealName: 'Plate', foods: ['Rice']), isNotNull);
    },
  );
  test(
    'first entire pantry composition is one assessment, not per-food calls',
    () async {
      var calls = 0;
      scorer.resetForTest(
        vision: GeminiVisionService(
          null,
          MockClient((req) async {
            calls++;
            final foods = List<String>.from(jsonDecode(req.body)['foods']);
            expect(foods, ['Eggs', 'Side salad', 'Avocado']);
            return response(foods, score: 78);
          }),
        ),
      );
      final result = await scorer.score(
        mealName: 'Lunch',
        foods: ['Eggs', 'Side salad', 'Avocado'],
      );
      expect(calls, 1);
      expect(result.settled, isTrue);
      expect(result.result.satietyScore, 78);
      expect(result.result.fullness!.label, '78 / 100');
      expect(result.result.durationHours, 0);
      await scorer.score(
        mealName: 'Dinner',
        foods: ['Avocado', 'Eggs', 'Side salad'],
      );
      expect(calls, 1);
    },
  );
  test(
    'original scan restores exactly and complete edits carry original context without image',
    () async {
      final original = meal(['Sushi platter'], score: 67);
      var calls = 0;
      scorer.resetForTest(
        vision: GeminiVisionService(
          null,
          MockClient((req) async {
            calls++;
            final body = jsonDecode(req.body);
            expect(body['foods'], ['Sushi platter', 'Edamame']);
            expect(body['originalAnalysis']['satietyScore'], 67);
            expect(body.containsKey('imageBase64'), isFalse);
            return response(['Sushi platter', 'Edamame'], score: 72);
          }),
        ),
      );
      scorer.rememberScan(original);
      final edited = await scorer.score(
        mealName: 'Sushi',
        foods: ['Sushi platter', 'Edamame'],
        original: original,
      );
      final reverted = await scorer.score(
        mealName: 'Sushi',
        foods: ['Sushi platter'],
        original: original,
      );
      expect(reverted.result.satietyScore, 67);
      expect(edited.result.satietyScore, 72);
      expect(calls, 1);
      expect(edited.result.original.satietyScore, 67);
      await scorer.score(
        mealName: 'Sushi',
        foods: ['Edamame', 'Sushi platter'],
        original: original,
      );
      expect(calls, 1);
    },
  );
  test(
    'same foods from different photos and different quantities do not alias',
    () {
      final original = meal(['Rice'], id: 'one');
      scorer.rememberScan(original);
      expect(
        scorer.cachedPlate(
          mealName: 'Plate',
          foods: ['Rice'],
          original: meal(['Rice'], id: 'two'),
        ),
        isNull,
      );
      expect(
        FoodListScorer.keyFor(['1 egg']),
        isNot(FoodListScorer.keyFor(['2 eggs'])),
      );
      expect(
        FoodListScorer.keyFor(['a|b']),
        isNot(FoodListScorer.keyFor(['a', 'b'])),
      );
    },
  );
  test(
    'identical in-flight states coalesce, different combinations do not',
    () async {
      var calls = 0;
      scorer.resetForTest(
        vision: GeminiVisionService(
          null,
          MockClient((req) async {
            calls++;
            await Future<void>.delayed(const Duration(milliseconds: 10));
            return response(List<String>.from(jsonDecode(req.body)['foods']));
          }),
        ),
      );
      final results = await Future.wait([
        scorer.score(mealName: 'Plate', foods: ['cake', 'Eggs']),
        scorer.score(mealName: 'Plate', foods: ['Eggs', 'cake']),
        scorer.score(mealName: 'Plate', foods: ['cake', 'Side salad']),
      ]);
      expect(calls, 2);
      expect(results.every((r) => r.settled), isTrue);
    },
  );
  test(
    'failed assessment keeps all foods pending and is retried rather than cached',
    () async {
      var calls = 0;
      scorer.resetForTest(
        vision: GeminiVisionService(
          null,
          MockClient((req) async {
            calls++;
            return http.Response(
              '{"error":"Temporary outage","code":"GEMINI_TRANSIENT"}',
              503,
            );
          }),
        ),
      );
      for (var i = 0; i < 2; i++) {
        final result = await scorer.score(
          mealName: 'Plate',
          foods: ['cake', 'Eggs'],
        );
        expect(result.settled, isFalse);
        expect(result.pending, ['cake', 'Eggs']);
        expect(result.result.fullness, isNull);
        expect(result.failureMessage, 'Temporary outage');
      }
      expect(calls, 2);
    },
  );
  test(
    'partial rejection is cached only under the accepted composition',
    () async {
      var calls = 0;
      scorer.resetForTest(
        vision: GeminiVisionService(
          null,
          MockClient((req) async {
            calls++;
            return response(['grapes'], rejected: ['asdf']);
          }),
        ),
      );
      final result = await scorer.score(
        mealName: 'Snack',
        foods: ['grapes', 'asdf'],
      );
      expect(result.rejected, ['asdf']);
      expect(result.result.components, ['grapes']);
      expect(
        scorer.cachedPlate(mealName: 'Plate', foods: ['grapes', 'asdf']),
        isNull,
      );
      final accepted = await scorer.score(mealName: 'Snack', foods: ['grapes']);
      expect(accepted.result.components, ['grapes']);
      expect(calls, 1);
    },
  );
  test('non-food result is refused and negative cached', () async {
    var calls = 0;
    scorer.resetForTest(
      vision: GeminiVisionService(
        null,
        MockClient((req) async {
          calls++;
          return response([], score: 0, rejected: ['chair'], issue: 'not_food');
        }),
      ),
    );
    for (var i = 0; i < 2; i++) {
      final result = await scorer.score(mealName: 'Plate', foods: ['chair']);
      expect(result.isFood, isFalse);
      expect(result.rejected, ['chair']);
    }
    expect(calls, 1);
  });
  test('legacy result cannot silently satisfy a new assessment', () async {
    final cache = FoodScoreCache();
    cache.writeSuccess(
      FoodListScorer.keyFor(['Eggs']),
      SatietyResult.fromFoods(mealName: 'Plate', components: ['Eggs']),
    );
    var calls = 0;
    scorer.resetForTest(
      cache: cache,
      vision: GeminiVisionService(
        null,
        MockClient((req) async {
          calls++;
          return response(['Eggs']);
        }),
      ),
    );
    expect(
      (await scorer.score(mealName: 'Plate', foods: ['Eggs'])).settled,
      isTrue,
    );
    expect(calls, 1);
  });
  test(
    'without vision a novel plate is unavailable, without fabricated numbers',
    () async {
      final result = await scorer.score(mealName: 'Plate', foods: ['Pad thai']);
      expect(result.settled, isFalse);
      expect(result.result.fullness, isNull);
    },
  );
  test(
    'sign-out during work cannot cache or apply the previous account result',
    () async {
      final pending = Completer<http.Response>();
      scorer.resetForTest(
        vision: GeminiVisionService(null, MockClient((req) => pending.future)),
      );
      final future = scorer.score(mealName: 'Plate', foods: ['Cake']);
      await Future<void>.delayed(Duration.zero);
      await scorer.cache.clear();
      pending.complete(response(['Cake']));
      final result = await future;
      expect(result.settled, isFalse);
      expect(result.failureMessage, contains('Account changed'));
      expect(scorer.cachedPlate(mealName: 'Plate', foods: ['Cake']), isNull);
    },
  );
  test(
    'hourly limit provides quota feedback without an outage alert',
    () async {
      final seen = <TelemetryEvent>[];
      Telemetry.debugSink(seen.add);
      scorer.resetForTest(
        vision: GeminiVisionService(
          null,
          MockClient(
            (req) async => http.Response(
              jsonEncode({
                'error': 'Too many meal assessments this hour.',
                'code': 'FOODS_RATE_LIMITED',
                'quota': {
                  'textRemaining': 7,
                  'textPurchased': 0,
                  'isPro': false,
                },
              }),
              429,
            ),
          ),
        ),
      );
      final result = await scorer.score(mealName: 'Plate', foods: ['cake']);
      expect(result.settled, isFalse);
      expect(result.failureMessage, contains('this hour'));
      expect(result.quota?.textLeft, 7);
      expect(seen, isEmpty);
    },
  );
  test(
    'encrypted completed assessments survive restart with original snapshot',
    () async {
      final dir = await Directory.systemTemp.createTemp('meal-cache-');
      Hive.init(dir.path);
      final cache = FoodScoreCache();
      await cache.init(keyStore: TestKeys());
      final original = meal(['Sushi'], score: 63);
      final edited = meal(['Sushi', 'Tofu'], score: 70).copyWith(
        originalAnalysis: {
          ...original.assessmentContext,
          'assessmentMethod': original.assessmentMethod,
        },
      );
      cache.writeSuccess(
        FoodListScorer.keyFor(edited.components, original: original),
        edited,
      );
      await Hive.close();
      final restored = FoodScoreCache();
      await restored.init(keyStore: TestKeys());
      scorer.resetForTest(cache: restored);
      final result = await scorer.score(
        mealName: 'Dinner',
        foods: ['Tofu', 'Sushi'],
        original: original,
      );
      expect(result.settled, isTrue);
      expect(result.result.satietyScore, 70);
      expect(result.result.original.satietyScore, 63);
      await Hive.close();
      await dir.delete(recursive: true);
    },
  );
  test(
    'more than twenty foods are evaluated completely and oversized input never charges',
    () async {
      var calls = 0;
      scorer.resetForTest(
        vision: GeminiVisionService(
          null,
          MockClient((req) async {
            calls++;
            final foods = List<String>.from(jsonDecode(req.body)['foods']);
            expect(foods, hasLength(25));
            return response(foods);
          }),
        ),
      );
      final foods = List.generate(25, (i) => 'Food dish $i');
      final accepted = await scorer.score(mealName: 'Plate', foods: foods);
      expect(accepted.settled, isTrue);
      expect(accepted.result.components, hasLength(25));
      for (final oversized in [
        List.generate(41, (i) => 'Food dish $i'),
        ['x' * 61],
      ]) {
        final rejected = await scorer.score(
          mealName: 'Plate',
          foods: oversized,
        );
        expect(rejected.settled, isFalse);
        expect(rejected.failureMessage, contains('40 foods'));
      }
      expect(calls, 1);
    },
  );
}
