import 'package:flutter_test/flutter_test.dart';
import 'package:evenplate/features/today/today_day_status.dart';

void main() {
  TodayDayStatus status({
    required int plates,
    int target = 3,
    double protein = 0,
    double fiber = 0,
    double fats = 0,
    double carbs = 0,
  }) {
    return TodayDayStatus.from(
      plateCount: plates,
      targetMeals: target,
      proteinProgress: protein,
      fiberProgress: fiber,
      fatsProgress: fats,
      carbsProgress: carbs,
    );
  }

  test('zero plates asks for a first log, not a fill-up', () {
    final day = status(plates: 0);
    expect(day.title, 'No plates yet');
    expect(day.subtitle, contains('Build the combo'));
    expect(day.addPlateLabel, 'Add Plate');
    expect(day.dayLogged, isFalse);
  });

  test('one weak plate is in progress, not unfinished tanks', () {
    final day = status(plates: 1);
    expect(day.title, '1 of 3 plates in');
    expect(day.subtitle, contains('protein'));
    expect(day.addPlateLabel, 'Add Plate');
    expect(day.dayLogged, isFalse);
  });

  test('target plates with empty chambers suggest the weakest gap', () {
    final day = status(plates: 3);
    expect(day.title, 'Day is logged');
    expect(day.subtitle, contains('protein'));
    expect(day.subtitle, isNot(contains('did not hold')));
    expect(day.addPlateLabel, 'Log another');
    expect(day.dayLogged, isTrue);
  });

  test('a fiber gap is named when protein is already in', () {
    final day = status(plates: 3, protein: 1);
    expect(day.subtitle, contains('fiber'));
  });

  test('target plates with full chambers say the day held', () {
    final day = status(plates: 3, protein: 1, fiber: 1, fats: 1, carbs: 1);
    expect(day.title, 'Day is logged');
    expect(day.subtitle, 'These plates held.');
    expect(day.dayLogged, isTrue);
  });

  test('an extra plate does not ask them to keep eating', () {
    final day = status(plates: 4, protein: 1, fiber: 1, fats: 1, carbs: 1);
    expect(day.title, 'Day is logged');
    expect(day.subtitle, contains('already in'));
    expect(day.addPlateLabel, 'Log another');
  });

  test('pillar badges never show 0/3', () {
    expect(TodayDayStatus.pillarLabel(0, hasPlates: false), '-');
    expect(TodayDayStatus.pillarLabel(0, hasPlates: true), 'Low');
    expect(TodayDayStatus.pillarLabel(0.4, hasPlates: true), 'Partial');
    expect(TodayDayStatus.pillarLabel(1.0, hasPlates: true), 'In');
  });
}
