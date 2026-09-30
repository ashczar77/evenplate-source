import 'package:flutter_test/flutter_test.dart';
import 'package:evenplate/features/insights/satiety_insight_state.dart';
import 'package:evenplate/models/meal_log.dart';
import 'package:evenplate/models/satiety_matrix.dart';

SatietyResult _result({
  int score = 80,
  double hours = 4,
  String risk = 'low',
  String? captureIssue,
  bool anchor = true,
  bool net = true,
  bool buffer = true,
}) {
  return SatietyResult(
    mealName: 'Test plate',
    components: const ['item'],
    pillars: SatietyPillars(
      anchor: PillarDetail(
        detected: anchor,
        items: anchor ? const ['protein'] : const [],
        quality: 'high',
      ),
      net: PillarDetail(
        detected: net,
        items: net ? const ['fiber'] : const [],
        quality: 'high',
      ),
      buffer: PillarDetail(
        detected: buffer,
        items: buffer ? const ['fat'] : const [],
        quality: 'high',
      ),
      spark: const PillarDetail(
        detected: true,
        items: ['crunch'],
        quality: 'medium',
      ),
    ),
    satietyScore: score,
    durationHours: hours,
    crashRisk: risk,
    hybridUpgrade: const HybridUpgrade(
      instantAdd: 'Add seeds.',
      smartSwap: 'Keep it.',
      digestiveCatalyst: 'Sip water.',
    ),
    captureIssue: captureIssue,
  );
}

void main() {
  group('SatietyInsightState.fromResult', () {
    test('Uses captureIssue instead of clamped score sentinels', () {
      expect(
        SatietyInsightState.fromResult(_result(captureIssue: 'not_food')).type,
        InsightStateType.notFood,
      );
      expect(
        SatietyInsightState.fromResult(_result(captureIssue: 'not_food')).title,
        "Oops, doesn't look like food",
      );
      expect(
        SatietyInsightState.fromResult(_result(captureIssue: 'too_dark')).type,
        InsightStateType.tooDark,
      );
      expect(
        SatietyInsightState.fromResult(_result(captureIssue: 'blurry')).type,
        InsightStateType.blurry,
      );
    });

    test('A clamped -1 score does not pretend the photo was not food', () {
      final parsed = SatietyResult.fromJson({
        'satietyScore': -1,
        'pillars': {
          'anchor': {
            'detected': true,
            'items': ['Eggs'],
          },
          'net': {
            'detected': true,
            'items': ['Greens'],
          },
          'buffer': {
            'detected': true,
            'items': ['Avocado'],
          },
        },
      });
      expect(parsed.satietyScore, 0);
      expect(
        SatietyInsightState.fromResult(parsed).type,
        InsightStateType.satietyLock,
      );
    });

    test('Keto wins over missing net when protein and fat are present', () {
      expect(
        SatietyInsightState.fromResult(
          _result(anchor: true, buffer: true, net: false),
        ).type,
        InsightStateType.keto,
      );
    });

    test('Legacy crash predictions do not imply a sugar spike', () {
      expect(
        SatietyInsightState.fromResult(
          _result(risk: 'high', anchor: false, net: false, buffer: true),
        ).type,
        InsightStateType.missingAnchor,
      );
    });

    test('Legacy hours do not imply overload', () {
      expect(
        SatietyInsightState.fromResult(_result(hours: 10)).type,
        InsightStateType.satietyLock,
      );
      expect(
        SatietyInsightState.fromResult(_result(hours: 8)).type,
        InsightStateType.satietyLock,
      );
    });
  });

  group('SatietyInsightState.fromToday', () {
    MealLog meal({
      required String id,
      required SatietyResult result,
      DateTime? when,
    }) {
      return MealLog(
        id: id,
        mealName: result.mealName,
        timestamp: when ?? DateTime(2026, 9, 14, 12),
        satietyResult: result,
      );
    }

    test('An empty day is the only fumes state', () {
      expect(
        SatietyInsightState.fromToday(
          const [],
          now: DateTime(2026, 9, 14),
        ).type,
        InsightStateType.emptyEngine,
      );
    });

    test('A logged plate is not treated as an empty engine', () {
      final burger = SatietyResult.fromFoods(
        mealName: 'Burger',
        components: const ['Burger'],
      );
      expect(
        SatietyInsightState.fromToday([
          meal(id: '1', result: burger),
        ], now: DateTime(2026, 9, 14)).type,
        isNot(InsightStateType.emptyEngine),
      );
    });

    test('A later bridge snack does not erase the plate logged earlier', () {
      final burger = SatietyResult.fromFoods(
        mealName: 'Burger',
        components: const ['Burger', 'Side salad'],
      );
      final tea = SatietyResult.fromFoods(
        mealName: 'Matcha',
        components: const ['Green tea'],
      );
      expect(
        SatietyInsightState.fromToday([
          meal(id: 'tea', result: tea, when: DateTime(2026, 9, 14, 15)),
          meal(id: 'burger', result: burger),
        ], now: DateTime(2026, 9, 14)).type,
        isNot(InsightStateType.emptyEngine),
      );
    });
  });

  group('SatietyInsightState.apiError', () {
    test('Shows the server message instead of a generic wait line', () {
      expect(
        SatietyInsightState.apiError('Vision analysis timed out').description,
        'Vision analysis timed out',
      );
      expect(
        SatietyInsightState.apiError('Exception: boom').description,
        'Wait a moment and try the photo again.',
      );
      expect(
        SatietyInsightState.apiError(
          'Gemini Vision analysis failed',
        ).description,
        'Wait a moment and try the photo again.',
      );
    });

    test('Weekly limit uses the approved heading', () {
      expect(SatietyInsightState.weeklyLimit().title, 'Weekly Scans Complete');
    });
  });
}
