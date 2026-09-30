import 'package:flutter_test/flutter_test.dart';
import 'package:evenplate/models/satiety_matrix.dart';

void main() {
  const advice = HybridUpgrade(
    instantAdd: 'Add eggs and Greek yogurt',
    smartSwap: 'Swap chicken for fish',
    digestiveCatalyst: 'Sip water',
  );
  test('Vegan advice cannot suggest animal foods', () {
    final filtered = advice.forDietaryPreference('100% Plant-Based / Vegan');
    expect(filtered.instantAdd, contains('tofu'));
    expect(filtered.smartSwap, contains('tofu'));
    expect(filtered.digestiveCatalyst, 'Sip water');
  });
  test('Sensitive advice makes no allergy safety promise', () {
    final filtered = advice.forDietaryPreference(
      'Sensitive / Simple Ingredients',
    );
    expect(filtered.instantAdd, contains('personal allergy plan'));
    expect(filtered.smartSwap, isNot(contains('chicken')));
  });
}
