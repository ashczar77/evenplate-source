import 'package:flutter_test/flutter_test.dart';
import 'package:evenplate/models/satiety_matrix.dart';
import 'package:evenplate/services/food_score_cache.dart';

SatietyResult _result(String name) {
  return SatietyResult.fromFoods(
    mealName: name,
    components: const ['Eggs', 'Avocado'],
  );
}

void main() {
  test('key is sorted lowercase foods', () {
    expect(
      FoodScoreCache.keyFor(['Avocado', 'eggs', ' Avocado ']),
      'avocado|eggs',
    );
  });

  test('success hits stay until the 30 day ttl', () {
    final cache = FoodScoreCache();
    const key = 'avocado|eggs';
    cache.writeSuccess(key, _result('Lunch'));

    final hit = cache.read(key);
    expect(hit, isNotNull);
    expect(hit!.isFood, isTrue);
    expect(hit.result!.mealName, 'Lunch');
  });

  test('expired not-food entries are dropped', () {
    final cache = FoodScoreCache();
    const key = 'asdf';
    cache.seed(
      key,
      FoodScoreCacheEntry(
        isFood: false,
        cachedAt: DateTime.now().toUtc().subtract(const Duration(hours: 25)),
        lastAccess: DateTime.now().toUtc().subtract(const Duration(hours: 25)),
      ),
    );

    expect(cache.read(key), isNull);
  });

  test('evicts the least recently used extra entries', () {
    final cache = FoodScoreCache();
    for (var i = 0; i < FoodScoreCache.maxEntries + 5; i++) {
      cache.writeSuccess('food-$i', _result('Meal $i'));
    }

    expect(cache.length, FoodScoreCache.maxEntries);
    expect(cache.read('food-0'), isNull);
    expect(cache.read('food-${FoodScoreCache.maxEntries + 4}'), isNotNull);
  });
}
