import '../models/meal_log.dart';
import '../models/user_profile.dart';

enum RetentionSlot { checkIn, lunch, dinner, sunday }

class RetentionIntent {
  final RetentionSlot slot;
  final int id;
  final DateTime when;
  final MealLog? meal;
  final int balancedPlates;

  const RetentionIntent({
    required this.slot,
    required this.id,
    required this.when,
    this.meal,
    this.balancedPlates = 0,
  });
}

/// When the check-in, midday nudge, and Sunday recap should fire.
/// OneSignal's phone SDK can subscribe and tag. It cannot put a message
/// on a clock, so the phone schedules these itself.
class RetentionPlan {
  static const checkInAfter = Duration(minutes: 210);
  static const horizonDays = 7;
  static const maxCheckIns = 40;

  static List<RetentionIntent> upcoming({
    required UserProfile profile,
    required List<MealLog> meals,
    required DateTime now,
  }) {
    final plan = <RetentionIntent>[];
    if (!profile.pushConsentGranted) return plan;
    if (profile.checkInRemindersEnabled) {
      plan.addAll(_checkIns(meals, now));
    }
    if (profile.preMealNudgesEnabled) {
      plan.addAll(_anchors(now));
    }
    if (profile.weeklyRecapEnabled) {
      plan.addAll(_sundays(meals, now));
    }
    return plan;
  }

  static List<RetentionIntent> _checkIns(List<MealLog> meals, DateTime now) {
    final due = <RetentionIntent>[];
    for (final meal in meals) {
      if (meal.isBridgeFix) continue;
      if (meal.energyCheckIn != null) continue;
      final when = meal.timestamp.add(checkInAfter);
      if (!when.isAfter(now)) continue;
      due.add(
        RetentionIntent(
          slot: RetentionSlot.checkIn,
          id: _checkInId(meal.id),
          when: when,
          meal: meal,
        ),
      );
    }
    due.sort((a, b) => a.when.compareTo(b.when));
    if (due.length <= maxCheckIns) return due;
    return due.sublist(0, maxCheckIns);
  }

  static List<RetentionIntent> _anchors(DateTime now) {
    final plan = <RetentionIntent>[];
    for (final hour in [12, 18]) {
      var when = DateTime(
        now.year,
        now.month,
        now.day,
        hour,
        hour == 12 ? 15 : 45,
      );
      if (!when.isAfter(now)) {
        when = DateTime(
          now.year,
          now.month,
          now.day + 1,
          hour,
          hour == 12 ? 15 : 45,
        );
      }
      plan.add(
        RetentionIntent(
          slot: hour == 12 ? RetentionSlot.lunch : RetentionSlot.dinner,
          id: hour == 12 ? 12150 : 18450,
          when: when,
        ),
      );
    }
    return plan;
  }

  static List<RetentionIntent> _sundays(List<MealLog> meals, DateTime now) {
    final plates = _balancedThisWeek(meals, now);
    final first = _nextSunday(now);
    return [
      RetentionIntent(
        slot: RetentionSlot.sunday,
        id: 7001,
        when: first,
        balancedPlates: plates,
      ),
    ];
  }

  static DateTime _nextSunday(DateTime now) {
    final daysUntil = (DateTime.sunday - now.weekday) % 7;
    var when = DateTime(
      now.year,
      now.month,
      now.day,
      17,
    ).add(Duration(days: daysUntil));
    if (!when.isAfter(now)) {
      when = when.add(const Duration(days: 7));
    }
    return when;
  }

  static int _balancedThisWeek(List<MealLog> meals, DateTime now) {
    final start = now.subtract(const Duration(days: 7));
    var count = 0;
    for (final meal in meals) {
      if (meal.timestamp.isBefore(start)) continue;
      if (!meal.satietyResult.pillars.isFullMatrix) continue;
      count++;
    }
    return count;
  }

  static int _checkInId(String mealId) {
    var hash = 17;
    for (final unit in mealId.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return 100000 + (hash % 500000);
  }
}
