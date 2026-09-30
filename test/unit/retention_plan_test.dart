import 'package:flutter_test/flutter_test.dart';
import 'package:evenplate/models/meal_log.dart';
import 'package:evenplate/models/satiety_matrix.dart';
import 'package:evenplate/models/user_profile.dart';
import 'package:evenplate/services/local_storage_service.dart';
import 'package:evenplate/services/onesignal_service.dart';
import 'package:evenplate/services/retention_plan.dart';
import 'package:evenplate/services/retention_scheduler.dart';

SatietyResult _result({bool full = false}) {
  return SatietyResult(
    mealName: 'Canary Bowl',
    components: const ['Beans'],
    pillars: SatietyPillars(
      anchor: const PillarDetail(
        detected: true,
        items: ['Beans'],
        quality: 'high',
      ),
      net: PillarDetail(
        detected: full,
        items: full ? const ['Greens'] : const [],
        quality: full ? 'high' : 'low',
      ),
      buffer: PillarDetail(
        detected: full,
        items: full ? const ['Oil'] : const [],
        quality: full ? 'high' : 'low',
      ),
      spark: const PillarDetail(detected: false, items: [], quality: 'low'),
    ),
    satietyScore: 70,
    durationHours: 3,
    crashRisk: 'low',
    hybridUpgrade: const HybridUpgrade(
      instantAdd: 'Add greens.',
      smartSwap: 'Keep it simple.',
      digestiveCatalyst: 'Sip water.',
    ),
  );
}

MealLog _meal({
  required String id,
  required DateTime timestamp,
  bool full = false,
  String? energy,
}) {
  return MealLog(
    id: id,
    mealName: 'Canary Bowl',
    timestamp: timestamp,
    satietyResult: _result(full: full),
    energyCheckIn: energy,
  );
}

void main() {
  final now = DateTime(2026, 9, 26, 10);

  UserProfile profile({
    bool checkIn = true,
    bool preMeal = true,
    bool sunday = true,
  }) {
    return UserProfile(
      lastQuotaReset: now,
      pushConsentGranted: true,
      checkInRemindersEnabled: checkIn,
      preMealNudgesEnabled: preMeal,
      weeklyRecapEnabled: sunday,
    );
  }

  test('Check-in is 3.5h after a plate, and a passed window is skipped', () {
    final plan = RetentionPlan.upcoming(
      profile: profile(preMeal: false, sunday: false),
      meals: [
        _meal(id: 'fresh', timestamp: DateTime(2026, 9, 26, 9)),
        _meal(id: 'old', timestamp: DateTime(2026, 9, 26, 6)),
        _meal(
          id: 'done',
          timestamp: DateTime(2026, 9, 26, 9, 30),
          energy: 'steady',
        ),
      ],
      now: now,
    );

    expect(plan, hasLength(1));
    expect(plan.single.slot, RetentionSlot.checkIn);
    expect(plan.single.meal!.id, 'fresh');
    expect(plan.single.when, DateTime(2026, 9, 26, 12, 30));
  });

  test('Lunch is 12:15, dinner is 18:45, and Sunday is 17:00', () {
    final plan = RetentionPlan.upcoming(
      profile: profile(checkIn: false),
      meals: [
        _meal(id: 'full', timestamp: DateTime(2026, 9, 25, 12), full: true),
      ],
      now: now,
    );

    final lunches = plan.where((item) => item.slot == RetentionSlot.lunch);
    final dinners = plan.where((item) => item.slot == RetentionSlot.dinner);
    final sundays = plan.where((item) => item.slot == RetentionSlot.sunday);

    expect(lunches.length, 1);
    expect(lunches.first.when, DateTime(2026, 9, 26, 12, 15));
    expect(dinners.length, 1);
    expect(dinners.first.when, DateTime(2026, 9, 26, 18, 45));
    expect(sundays.length, 1);
    expect(sundays.first.when.weekday, DateTime.sunday);
    expect(sundays.first.when.hour, 17);
    expect(sundays.first.when.isAfter(now), isTrue);
    expect(sundays.first.balancedPlates, 1);
  });

  test('No reminders are planned without consent', () {
    expect(
      RetentionPlan.upcoming(
        profile: profile().copyWith(pushConsentGranted: false),
        meals: [],
        now: now,
      ),
      isEmpty,
    );
  });

  test('A switch that is off is not scheduled', () {
    final plan = RetentionPlan.upcoming(
      profile: profile(checkIn: false, preMeal: false, sunday: false),
      meals: [_meal(id: 'fresh', timestamp: DateTime(2026, 9, 26, 9))],
      now: now,
    );

    expect(plan, isEmpty);
  });

  test(
    'The scheduler posts the check-in copy that is already in the app',
    () async {
      final storage = LocalStorageService();
      await storage.addMealLog(
        _meal(id: 'fresh', timestamp: DateTime(2026, 9, 26, 9)),
      );
      await storage.saveUserProfile(profile(preMeal: false, sunday: false));
      final posted = <OutgoingNotice>[];
      final scheduler = RetentionScheduler(
        storage: storage,
        copy: OneSignalRetentionCopy(OneSignalService(storage)),
        poster: _RecordingPoster(posted),
        clock: () => now,
      );

      await scheduler.refresh();

      expect(posted, hasLength(1));
      expect(posted.single.title, contains("How's your energy?"));
      expect(posted.single.when, DateTime(2026, 9, 26, 12, 30));
    },
  );
}

class _RecordingPoster implements RetentionPoster {
  final List<OutgoingNotice> posted;

  _RecordingPoster(this.posted);

  @override
  Future<void> replace(List<OutgoingNotice> notices) async {
    posted
      ..clear()
      ..addAll(notices);
  }
}
