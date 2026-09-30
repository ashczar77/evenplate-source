import 'package:flutter_test/flutter_test.dart';
import 'package:evenplate/features/insights/check_in_verdict.dart';
import 'package:evenplate/models/meal_log.dart';
import 'package:evenplate/models/satiety_matrix.dart';

MealLog _meal({
  required String checkIn,
  required List<String> foods,
  double hours = 2.0,
}) {
  final result = SatietyResult.fromFoods(
    mealName: 'Test plate',
    components: foods,
  );
  return MealLog(
    id: 'v1',
    mealName: result.mealName,
    timestamp: DateTime.now(),
    satietyResult: result.copyWith(durationHours: hours),
    energyCheckIn: checkIn,
  );
}

void main() {
  test('steady full combo says it held', () {
    final verdict = CheckInVerdict.from(
      _meal(
        checkIn: 'steady',
        foods: const ['Eggs', 'Side salad', 'Avocado'],
        hours: 4.2,
      ),
    );
    expect(verdict.held, isTrue);
    expect(verdict.headline, 'You reported steady energy.');
    expect(verdict.body, contains('check-in'));
  });

  test('dip on a protein gap names eggs next', () {
    final verdict = CheckInVerdict.from(
      _meal(checkIn: 'dip', foods: const ['Pasta'], hours: 1.8),
    );
    expect(verdict.held, isFalse);
    expect(verdict.headline, 'You reported an energy dip.');
    expect(verdict.body, contains('protein'));
    expect(verdict.gapId, 'protein');
    expect(verdict.nextTip, contains('eggs'));
  });
}
