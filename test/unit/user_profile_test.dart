import 'package:flutter_test/flutter_test.dart';
import 'package:evenplate/models/user_profile.dart';

void main() {
  UserProfile profile() => UserProfile(lastQuotaReset: DateTime(2026, 1, 1));

  test('Athletic vitality writes a two-meal daily target', () {
    final updated = profile().withPrimaryGoal('Lean Fuel & Athletic Vitality');

    expect(updated.primaryGoal, 'Lean Fuel & Athletic Vitality');
    expect(updated.targetMealsPerDay, 2);
    expect(updated.targetSatietyHoursDaily, 9.0);
    expect(updated.mealSchedule, contains('Intermittent'));
  });

  test('Any other satiety goal writes a three-meal daily target', () {
    final athletic = profile().withPrimaryGoal('Lean Fuel & Athletic Vitality');
    final updated = athletic.withPrimaryGoal('Steady Energy All Day');

    expect(updated.primaryGoal, 'Steady Energy All Day');
    expect(updated.targetMealsPerDay, 3);
    expect(updated.targetSatietyHoursDaily, 12.0);
    expect(updated.mealSchedule, '3 Balanced Meals');
  });

  test('quota meters survive a json round trip', () {
    final original = UserProfile(
      lastQuotaReset: DateTime(2026, 1, 1),
      freeScansRemaining: 12,
      photoPurchased: 25,
      textRemaining: 80,
      textPurchased: 40,
      isPro: true,
    );
    final copy = UserProfile.fromJson(original.toJson());
    expect(copy.freeScansRemaining, 12);
    expect(copy.photoPurchased, 25);
    expect(copy.textRemaining, 80);
    expect(copy.textPurchased, 40);
    expect(copy.isPro, isTrue);
  });

  test('A live Pro session wins over a saved Free account', () {
    final stored = profile();
    final live = profile().copyWith(
      isPro: true,
      freeScansRemaining: 75,
      textRemaining: 100,
      hasCompletedOnboarding: true,
    );

    final merged = stored.mergedWithLiveSession(live);

    expect(merged.isPro, isTrue);
    expect(merged.freeScansRemaining, 75);
    expect(merged.textRemaining, 100);
    expect(merged.hasCompletedOnboarding, isTrue);
  });
}
