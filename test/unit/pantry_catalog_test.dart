import 'package:flutter_test/flutter_test.dart';
import 'package:evenplate/services/pantry_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(PantryCatalog.loadProfiles);
  test('every pantry chip has a sourced record', () {
    for (final food in PantryCatalog.foods) {
      final result = PantryCatalog.score(mealName: 'Plate', foods: [food.name]);
      expect(result.foodProfiles.single.fdcId, greaterThan(0));
      expect(result.durationHours, 0);
      if (!['Milk', 'Orange juice'].contains(food.name)) {
        expect(result.fullness, isNotNull);
      }
    }
  });
  test('unrelated foods do not silently use another source', () {
    expect(PantryCatalog.resolve('brown rice'), isNull);
    expect(PantryCatalog.resolve('raspberries'), isNull);
    expect(PantryCatalog.resolve('oatmeal'), isNull);
    expect(PantryCatalog.covers([]), isFalse);
  });
  test('composition is order independent and edamame removal restores it', () {
    final original = PantryCatalog.score(
      mealName: 'Plate',
      foods: ['Eggs', 'Rice'],
    );
    final added = PantryCatalog.score(
      mealName: 'Plate',
      foods: ['Eggs', 'Rice', 'Edamame'],
    );
    final reversed = PantryCatalog.score(
      mealName: 'Plate',
      foods: ['Edamame', 'Rice', 'Eggs'],
    );
    final removed = PantryCatalog.score(
      mealName: 'Plate',
      foods: ['Eggs', 'Rice'],
    );
    expect(added.fullness!.value, closeTo(reversed.fullness!.value, 1e-12));
    expect(removed.fullness!.value, original.fullness!.value);
    expect(added.foodProfiles.last.fdcId, 168411);
    expect(added.durationHours, 0);
  });
}
