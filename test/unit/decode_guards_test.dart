import 'package:flutter_test/flutter_test.dart';
import 'package:evenplate/core/errors/error_reporter.dart';
import 'package:evenplate/features/insights/insights_stats.dart';
import 'package:evenplate/models/meal_log.dart';
import 'package:evenplate/models/satiety_matrix.dart';
import 'package:evenplate/models/user_profile.dart';

const _upgrade = HybridUpgrade(
  instantAdd: 'Add seeds.',
  smartSwap: 'Keep it.',
  digestiveCatalyst: 'Sip water.',
);

MealLog _meal({
  required String id,
  bool balanced = true,
  double hours = 4,
  DateTime? timestamp,
}) {
  return MealLog(
    id: id,
    mealName: id,
    timestamp: timestamp ?? DateTime.utc(2026, 9, 14),
    satietyResult: SatietyResult(
      mealName: id,
      components: const ['item'],
      pillars: SatietyPillars(
        anchor: PillarDetail(
          detected: balanced,
          items: balanced ? const ['protein'] : const [],
          quality: 'high',
        ),
        net: PillarDetail(
          detected: balanced,
          items: balanced ? const ['fiber'] : const [],
          quality: 'high',
        ),
        buffer: PillarDetail(
          detected: balanced,
          items: balanced ? const ['fat'] : const [],
          quality: 'high',
        ),
        spark: PillarDetail(
          detected: balanced,
          items: balanced ? const ['crunch'] : const [],
          quality: 'medium',
        ),
      ),
      satietyScore: balanced ? 90 : 40,
      durationHours: hours,
      crashRisk: 'low',
      hybridUpgrade: _upgrade,
    ),
  );
}

void main() {
  group('InsightsStats', () {
    test('Empty logs stay at zero instead of inventing 85 percent', () {
      final stats = InsightsStats.fromMeals(const []);
      expect(stats.isEmpty, isTrue);
      expect(stats.harmonyPercent, 0);
      expect(stats.avgHours, 0);
      expect(stats.anchorRate, 0);
      expect(stats.netRate, 0);
      expect(stats.bufferRate, 0);
      expect(stats.sparkRate, 0);
    });

    test('Averages real logged plates', () {
      final stats = InsightsStats.fromMeals([
        _meal(id: 'a', hours: 4),
        _meal(id: 'b', balanced: false, hours: 2),
      ]);
      expect(stats.isEmpty, isFalse);
      expect(stats.totalLogged, 2);
      expect(stats.harmonyPercent, 50);
      expect(stats.avgHours, 3);
      expect(stats.anchorRate, 0.5);
    });

    test('Today, week, and month ranges ignore older plates', () {
      final now = DateTime(2026, 9, 15, 12);
      final today = _meal(id: 'today', timestamp: DateTime(2026, 9, 15, 9));
      final week = _meal(id: 'week', timestamp: DateTime(2026, 9, 10, 9));
      final month = _meal(id: 'month', timestamp: DateTime(2026, 8, 20, 9));
      final old = _meal(id: 'old', timestamp: DateTime(2026, 8, 1, 9));

      final todayStats = InsightsStats.fromMeals(
        [today, week, month, old],
        range: InsightsRange.today,
        now: now,
      );
      expect(todayStats.totalLogged, 1);
      expect(todayStats.plates.first.id, 'today');
      expect(todayStats.headline, contains('today'));

      final weekStats = InsightsStats.fromMeals(
        [today, week, month, old],
        range: InsightsRange.week,
        now: now,
      );
      expect(weekStats.totalLogged, 2);

      final monthStats = InsightsStats.fromMeals(
        [today, week, month, old],
        range: InsightsRange.month,
        now: now,
      );
      expect(monthStats.totalLogged, 3);
      expect(monthStats.plates.map((meal) => meal.id), isNot(contains('old')));
    });

    test('Headline names the weakest pillar', () {
      final proteinOnly = _meal(id: 'p', balanced: true);
      final weakFiber = _meal(id: 'f', balanced: false);
      final stats = InsightsStats.fromMeals([proteinOnly, weakFiber]);
      expect(stats.headline, contains('of 2 plates'));
    });

    test('Headline uses plate for a single meal', () {
      final now = DateTime(2026, 9, 15, 12);
      final stats = InsightsStats.fromMeals(
        [_meal(id: 'one', timestamp: DateTime(2026, 9, 15, 9))],
        range: InsightsRange.today,
        now: now,
      );
      expect(stats.headline, 'All four pillars held on 1 plate today.');
      expect(stats.plateCountLabel, '1 plate');
    });
  });

  group('MealLog.tryParse', () {
    test('Skips corrupt or incomplete rows', () {
      expect(MealLog.tryParse('{not json'), isNull);
      expect(MealLog.tryParse(<int>[1, 2]), isNull);
      expect(MealLog.tryParse({'id': 'x'}), isNull);
      expect(
        MealLog.tryParse({
          'id': 'ok',
          'mealName': 'Toast',
          'timestamp': 'not-a-date',
          'satietyResult': {'mealName': 'Toast'},
        }),
        isNull,
      );
    });

    test('Reads a valid row including wrapped JSON strings', () {
      final meal = _meal(id: 'meal-1');
      final parsed = MealLog.tryParse(meal.toJson());
      expect(parsed, isNotNull);
      expect(parsed!.id, 'meal-1');
      expect(
        MealLog.tryParse(
          '{"id":"s","mealName":"Soup","timestamp":"2026-09-14T12:00:00.000Z",'
          '"satietyResult":{"mealName":"Soup"}}',
        ),
        isNotNull,
      );
    });

    test('Clears energy check-in and round-trips bridge snacks', () {
      final meal = _meal(id: 'm1').copyWith(energyCheckIn: 'dip');
      expect(meal.energyCheckIn, 'dip');
      expect(meal.copyWith(energyCheckIn: null).energyCheckIn, isNull);

      final snack = MealLog(
        id: 's1',
        mealName: 'Almonds',
        timestamp: DateTime.utc(2026, 9, 14),
        satietyResult: meal.satietyResult,
        isBridgeFix: true,
        bridgedFromId: 'm1',
      );
      final parsed = MealLog.tryParse(snack.toJson());
      expect(parsed, isNotNull);
      expect(parsed!.isBridgeFix, isTrue);
      expect(parsed.bridgedFromId, 'm1');
    });

    test('Round-trips a user id so two accounts can share a phone', () {
      final meal = _meal(id: 'm1').copyWith(userId: 'user-a');
      final parsed = MealLog.tryParse(meal.toJson());
      expect(parsed, isNotNull);
      expect(parsed!.userId, 'user-a');
    });
  });

  group('UserProfile.fromJson', () {
    test('Bad lastQuotaReset does not throw', () {
      final profile = UserProfile.fromJson({
        'lastQuotaReset': 'tomorrow-ish',
        'freeScansRemaining': 2.0,
      });
      expect(profile.freeScansRemaining, 2);
      expect(profile.lastQuotaReset, isA<DateTime>());
    });
  });

  group('ErrorReporter', () {
    setUp(ErrorReporter.resetForTest);

    test('Records into a bounded ring', () {
      ErrorReporter.record(StateError('boom'));
      expect(ErrorReporter.recent, contains('Bad state: boom'));
    });
  });
}
