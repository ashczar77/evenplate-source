import 'package:flutter_test/flutter_test.dart';
import 'package:evenplate/models/fullness_assessment.dart';

void main() {
  test('matches published cooked eggplant example', () {
    expect(
      FullnessAssessment.calculate(kcal: 35.4, proteinG: 1, fiberG: 2, fatG: 0),
      closeTo(4.1, 0.06),
    );
  });
  test('nutrient limits keep the rating between 0.5 and 5', () {
    for (final kcal in [0.0, 30.0, 500.0, 1000.0]) {
      for (final protein in [0.0, 30.0, 100.0]) {
        final v = FullnessAssessment.calculate(
          kcal: kcal,
          proteinG: protein,
          fiberG: 100,
          fatG: 100,
        );
        expect(v, inInclusiveRange(0.5, 5));
      }
    }
    expect(
      () => FullnessAssessment.calculate(
        kcal: double.nan,
        proteinG: 1,
        fiberG: 1,
        fatG: 1,
      ),
      throwsArgumentError,
    );
  });
  const egg = FoodNutrientProfile(
    name: 'Egg',
    fdcId: 173424,
    description: 'Egg, hard-boiled',
    kcal: 155,
    proteinG: 12.58,
    fiberG: 0,
    fatG: 10.61,
  );
  test('whole plate uses nutrient density, not additive food scores', () {
    final one = FullnessAssessment.forFoods(['Egg'], [egg])!;
    final two = FullnessAssessment.forFoods(['Egg', 'Egg'], [egg])!;
    expect(two.value, one.value);
  });
  test('incomplete or liquid profiles never imply a numeric rating', () {
    expect(FullnessAssessment.forFoods(['Egg', 'Sushi'], [egg]), isNull);
    final drink = FoodNutrientProfile.parse({...egg.toJson(), 'liquid': true})!;
    expect(FullnessAssessment.forFoods(['Egg'], [drink]), isNull);
    expect(FullnessAssessment.forFoods([], [egg]), isNull);
    expect(
      FoodNutrientProfile.parse({...egg.toJson(), 'fiberG': null}),
      isNull,
    );
  });
}
