import 'package:flutter_test/flutter_test.dart';
import 'package:evenplate/core/billing/scan_allowance.dart';
import 'package:evenplate/services/food_score_cache.dart';

void main() {
  test('Pro photo ceiling is 75 a week and about 3 dollars a month', () {
    expect(ScanAllowance.proPhotoWeekly, 75);
    expect(ScanAllowance.proPhotoMonthlyUsd(), 3.0);
    expect(ScanAllowance.includedPhotoWeekly(isPro: false), 3);
    expect(ScanAllowance.includedTextWeekly(isPro: true), 100);
    expect(ScanAllowance.includedTextWeekly(isPro: false), 20);
  });

  test('food cache keys ignore order, case, and duplicates', () {
    expect(
      FoodScoreCache.keyFor(['Rice', 'chicken', 'rice']),
      FoodScoreCache.keyFor(['chicken', 'Rice']),
    );
    expect(FoodScoreCache.keyFor(['Rice', 'chicken']), 'chicken|rice');
  });

  test('20 percent remaining is the low-credit banner', () {
    expect(ScanAllowance.photoLow(15, isPro: true), isTrue);
    expect(ScanAllowance.photoLow(16, isPro: true), isFalse);
    expect(ScanAllowance.textLow(4, isPro: false), isTrue);
  });

  test('demote clamps leftover and never raises a spent meter', () {
    expect(ScanAllowance.clampIncluded(71, ScanAllowance.freePhotoWeekly), 3);
    expect(ScanAllowance.clampIncluded(2, ScanAllowance.freePhotoWeekly), 2);
    expect(ScanAllowance.clampIncluded(3, ScanAllowance.freePhotoWeekly), 3);
    expect(ScanAllowance.clampIncluded(100, ScanAllowance.freeTextWeekly), 20);
    expect(ScanAllowance.clampIncluded(19, ScanAllowance.freeTextWeekly), 19);
    expect(ScanAllowance.clampIncluded(-1, ScanAllowance.freePhotoWeekly), 0);
  });

  test('Any leftover above the Free weekly cap is Pro, not Free of 3', () {
    for (final remaining in [4, 21, 67, 74]) {
      final isPro = ScanAllowance.hasProAccess(
        isPro: false,
        weeklyPhotoRemaining: remaining,
        weeklyTextRemaining: 16,
      );
      expect(isPro, isTrue, reason: '$remaining photo remaining is Pro');
      expect(ScanAllowance.includedPhotoWeekly(isPro: isPro), 75);
      expect(ScanAllowance.includedPhotoWeekly(isPro: isPro), isNot(3));
    }
    expect(
      ScanAllowance.hasProAccess(
        isPro: false,
        weeklyPhotoRemaining: 3,
        weeklyTextRemaining: 20,
      ),
      isFalse,
    );
  });
}
