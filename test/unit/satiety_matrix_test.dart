import 'package:flutter_test/flutter_test.dart';
import 'package:evenplate/models/satiety_matrix.dart';

void main() {
  group('Satiety Matrix Unit Tests', () {
    test('Correctly parses full 4-pillar meal JSON', () {
      final json = {
        'mealName': 'Harvest Salmon Bowl',
        'components': ['Salmon', 'Quinoa', 'Avocado', 'Greens'],
        'pillars': {
          'anchor': {
            'detected': true,
            'items': ['Salmon'],
            'quality': 'high',
          },
          'net': {
            'detected': true,
            'items': ['Greens', 'Quinoa'],
            'quality': 'high',
          },
          'buffer': {
            'detected': true,
            'items': ['Avocado'],
            'quality': 'high',
          },
          'spark': {
            'detected': true,
            'items': ['Lemon'],
            'quality': 'medium',
          },
        },
        'satietyScore': 95,
        'durationHours': 4.5,
        'crashRisk': 'low',
        'hybridUpgrade': {
          'instantAdd': 'Add pumpkin seeds',
          'smartSwap': 'Use brown rice',
          'digestiveCatalyst': 'Drink water before',
        },
      };

      final result = SatietyResult.fromJson(json);

      expect(result.mealName, 'Harvest Salmon Bowl');
      expect(result.pillars.anchor.detected, isTrue);
      expect(result.pillars.net.detected, isTrue);
      expect(result.pillars.buffer.detected, isTrue);
      expect(result.pillars.spark.detected, isTrue);
      expect(result.pillars.completedCount, 4);
      expect(result.pillars.isFullMatrix, isTrue);
      expect(result.durationHours, 4.5);
      expect(result.crashRisk, 'low');
    });

    test('Correctly identifies partial combo (< 3 pillars)', () {
      final json = {
        'mealName': 'Plain White Bagel',
        'components': ['Bagel'],
        'pillars': {
          'anchor': {'detected': false, 'items': []},
          'net': {'detected': false, 'items': []},
          'buffer': {
            'detected': true,
            'items': ['Cream cheese'],
          },
          'spark': {'detected': false, 'items': []},
        },
        'satietyScore': 42,
        'durationHours': 1.5,
        'crashRisk': 'high',
      };

      final result = SatietyResult.fromJson(json);

      expect(result.pillars.completedCount, 1);
      expect(result.pillars.isFullMatrix, isFalse);
      expect(result.crashRisk, 'high');
    });

    test('Clamps duration, maps medium crash risk, and keeps captureIssue', () {
      final result = SatietyResult.fromJson({
        'mealName': 12,
        'pillars': 'nope',
        'satietyScore': -2,
        'durationHours': 99,
        'crashRisk': 'medium',
        'captureIssue': 'TOO_DARK',
        'hybridUpgrade': ['not', 'a', 'map'],
      });

      expect(result.mealName, 'Mindful Plate');
      expect(result.satietyScore, 0);
      expect(result.durationHours, kMaxDurationHours);
      expect(result.crashRisk, 'moderate');
      expect(result.captureIssue, 'too_dark');
    });

    test('Drops unknown captureIssue and clamps a negative duration up', () {
      final result = SatietyResult.fromJson({
        'durationHours': -4,
        'captureIssue': 'explode',
      });

      expect(result.durationHours, kMinDurationHours);
      expect(result.captureIssue, isNull);
    });

    test('rebalanced does not invent a score for not_food', () {
      final result = SatietyResult.fromJson({
        'mealName': 'Forest',
        'components': ['Trees'],
        'satietyScore': 88,
        'durationHours': 4,
        'crashRisk': 'low',
        'captureIssue': 'not_food',
      }).rebalanced();
      expect(result.captureIssue, 'not_food');
      expect(result.satietyScore, 88);
    });

    test('A burger and chips feast is not scored like a balanced plate', () {
      final inflated = SatietyResult.fromJson({
        'mealName': 'Gourmet Beef Burger & BBQ Meat Spread',
        'components': ['Beef burger', 'BBQ meat', 'Potato chips', 'Fries'],
        'pillars': {
          'anchor': {
            'detected': true,
            'items': ['Beef burger patties'],
            'quality': 'high',
          },
          'net': {
            'detected': true,
            'items': ['Fiber'],
            'quality': 'high',
          },
          'buffer': {
            'detected': true,
            'items': ['Melted cheese sauce'],
            'quality': 'high',
          },
          'spark': {
            'detected': true,
            'items': ['Crispy potato chips'],
            'quality': 'high',
          },
        },
        'satietyScore': 84,
        'durationHours': 5.0,
        'crashRisk': 'moderate',
      }).rebalanced();

      expect(inflated.crashRisk, 'moderate');
      expect(inflated.durationHours, lessThanOrEqualTo(2.5));
      expect(inflated.satietyScore, lessThanOrEqualTo(50));
      expect(inflated.pillars.buffer.quality, 'low');
      expect(inflated.pillars.spark.quality, 'low');
      expect(inflated.pillars.net.quality, isNot('high'));
      expect(inflated.pillars.completedCount, lessThan(3));
    });

    test('detectedFoods skips generic Fiber labels', () {
      final result = SatietyResult.fromJson({
        'mealName': 'BBQ Spread',
        'components': ['Burger', 'Beer'],
        'pillars': {
          'anchor': {
            'detected': true,
            'items': ['Beef patty'],
            'quality': 'high',
          },
          'net': {
            'detected': true,
            'items': ['Fiber'],
            'quality': 'high',
          },
          'buffer': {
            'detected': true,
            'items': ['Melted cheese sauce'],
            'quality': 'high',
          },
          'spark': {
            'detected': true,
            'items': ['Potato chips'],
            'quality': 'high',
          },
        },
        'satietyScore': 84,
        'durationHours': 5.0,
        'crashRisk': 'moderate',
      });

      expect(
        result.detectedFoods,
        containsAll(['Burger', 'Beer', 'Potato chips']),
      );
      expect(result.detectedFoods, isNot(contains('Fiber')));
    });

    test('Editing the food list rebuilds the forecast', () {
      final feast = SatietyResult.fromFoods(
        mealName: 'BBQ Spread',
        components: const ['Burger', 'Beer', 'Pizza', 'Potato chips'],
      );
      expect(feast.crashRisk, 'moderate');
      expect(feast.satietyScore, lessThanOrEqualTo(45));
      expect(feast.detectedFoods, contains('Beer'));

      final cleaned = feast.withFoods(const [
        'Burger',
        'Side salad',
        'Avocado',
      ]);
      expect(cleaned.satietyScore, 0);
      expect(cleaned.fullness, isNull);
      expect(cleaned.crashRisk, isNot('high'));
      expect(cleaned.pillars.net.detected, isTrue);
      expect(cleaned.components, contains('Side salad'));
    });

    test('Low quality detections do not fill a daily chamber', () {
      const chips = PillarDetail(
        detected: true,
        items: ['Potato chips'],
        quality: 'low',
      );
      const burger = PillarDetail(
        detected: true,
        items: ['Burger'],
        quality: 'high',
      );
      const oil = PillarDetail(
        detected: true,
        items: ['Olive oil'],
        quality: 'medium',
      );

      expect(chips.isAligned, isFalse);
      expect(chips.dailyCredit, 0);
      expect(burger.isAligned, isTrue);
      expect(burger.dailyCredit, 1);
      expect(oil.dailyCredit, 0.5);
    });

    test('Plus-one foods land on a weak plate', () {
      final feast = SatietyResult.fromFoods(
        mealName: 'BBQ Spread',
        components: const ['Burger', 'Beer', 'Potato chips'],
        hybridUpgrade: const HybridUpgrade(
          instantAdd: 'Add a side salad',
          smartSwap: '',
          digestiveCatalyst: '',
        ),
      );
      expect(feast.suggestedPlusOneFoods, isNotEmpty);
      final upgraded = feast.withFoods([
        ...feast.detectedFoods,
        ...feast.suggestedPlusOneFoods,
      ]);
      expect(upgraded.satietyScore, 0);
      expect(upgraded.fullness, isNull);
      expect(
        upgraded.pillars.completedCount,
        greaterThan(feast.pillars.completedCount),
      );
    });

    test('an empty food list does not invent hours of focus', () {
      final empty = SatietyResult.fromFoods(
        mealName: 'Plate',
        components: const [],
      );
      expect(empty.durationHours, 0);
      expect(empty.satietyScore, 0);
    });

    test('comboLine names the first missing combo piece', () {
      final pasta = SatietyResult.fromFoods(
        mealName: 'Lunch pasta',
        components: const ['Pasta'],
      );
      expect(pasta.pillars.hccComplete, isFalse);
      expect(pasta.pillars.firstGapId, 'protein');
      expect(pasta.pillars.comboLine, contains('protein'));

      final full = SatietyResult.fromFoods(
        mealName: 'Bowl',
        components: const ['Eggs', 'Side salad', 'Avocado', 'Cucumber'],
      );
      expect(full.pillars.hccComplete, isTrue);
      expect(full.pillars.firstGapId, isNull);
    });

    test('local recognition covers pantry names, not dish titles', () {
      expect(foodRecognizedLocally('Olive oil'), isTrue);
      expect(foodRecognizedLocally('Eggs'), isTrue);
      expect(foodRecognizedLocally('Sloppy joes'), isFalse);
      expect(foodRecognizedLocally('chiken'), isFalse);
      expect(foodsRecognizedLocally(['Eggs', 'Avocado', 'Side salad']), isTrue);
    });
  });
}
