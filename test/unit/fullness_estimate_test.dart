import 'package:flutter_test/flutter_test.dart';
import 'package:evenplate/models/fullness_estimate.dart';
import 'package:evenplate/models/satiety_matrix.dart';

void main() {
  const range = {
    'minHours': 2,
    'maxHours': 4,
    'portion': 'regular',
    'basis': 'model_regular_portion_v1',
  };
  test('range round-trips without converting or changing the meal score', () {
    final meal =
        SatietyResult.fromFoods(
          mealName: 'Plate',
          components: ['Eggs'],
        ).copyWith(
          assessmentMethod: SatietyResult.modelMethod,
          satietyScore: 63,
          fullnessEstimate: FullnessEstimate.parse(range),
        );
    final restored = SatietyResult.fromJson(meal.toJson());
    expect(restored.satietyScore, 63);
    expect(restored.durationHours, 0);
    expect(restored.fullnessEstimate?.label, '2-4 hours');
    expect(restored.assessmentContext['fullnessEstimate'], range);
  });
  test('bad and legacy ranges are absent, never clamped or fabricated', () {
    for (final raw in [
      null,
      {},
      {...range, 'minHours': 4},
      {...range, 'maxHours': 16},
      {...range, 'minHours': 2.5},
      {...range, 'minHours': double.nan},
      {...range, 'portion': 'large'},
      {...range, 'basis': 'score-conversion'},
    ]) {
      expect(FullnessEstimate.parse(raw), isNull);
    }
    final old = SatietyResult.fromFoods(
      mealName: 'Plate',
      components: ['Eggs'],
    );
    expect(
      SatietyResult.fromJson({
        ...old.toJson(),
        'fullnessEstimate': range,
      }).fullnessEstimate,
      isNull,
    );
    expect(
      SatietyResult.fromJson({
        ...old.toJson(),
        'assessmentMethod': SatietyResult.modelMethod,
        'captureIssue': 'not_food',
        'fullnessEstimate': range,
      }).fullnessEstimate,
      isNull,
    );
  });
}
