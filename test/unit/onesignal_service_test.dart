import 'package:flutter_test/flutter_test.dart';
import 'package:evenplate/models/meal_log.dart';
import 'package:evenplate/models/satiety_matrix.dart';
import 'package:evenplate/services/local_storage_service.dart';
import 'package:evenplate/services/onesignal_service.dart';

void main() {
  late LocalStorageService storage;
  late OneSignalService oneSignal;

  final sampleMeal = MealLog(
    id: 'meal_test_123',
    mealName: 'Grilled Salmon Bowl',
    timestamp: DateTime.now(),
    satietyResult: const SatietyResult(
      mealName: 'Grilled Salmon Bowl',
      components: ['Salmon', 'Brown Rice', 'Avocado', 'Spinach'],
      pillars: SatietyPillars(
        anchor: PillarDetail(
          detected: true,
          items: ['Salmon'],
          quality: 'high',
        ),
        net: PillarDetail(detected: true, items: ['Spinach'], quality: 'high'),
        buffer: PillarDetail(
          detected: true,
          items: ['Avocado'],
          quality: 'high',
        ),
        spark: PillarDetail(
          detected: true,
          items: ['Lemon'],
          quality: 'medium',
        ),
      ),
      satietyScore: 92,
      durationHours: 4.5,
      crashRisk: 'low',
      hybridUpgrade: HybridUpgrade(
        instantAdd: 'Add a sprinkle of hemp hearts.',
        smartSwap: 'Great base.',
        digestiveCatalyst: 'Enjoy mindfully.',
      ),
    ),
  );

  setUp(() async {
    storage = LocalStorageService();
    oneSignal = OneSignalService(storage);
    await oneSignal.init();
  });

  tearDown(() {
    oneSignal.dispose();
  });

  test('cold-start push tap waits for navigation and replays only once', () {
    final received = <String>[];
    oneSignal.routeNotificationTap(null, {'campaign': 'sunday_recap'});
    oneSignal.onNotificationTap = (action, data) {
      received.add(data!['campaign'] as String);
    };
    oneSignal.replayPendingTap();
    oneSignal.replayPendingTap();
    expect(received, ['sunday_recap']);
    oneSignal.routeNotificationTap(null, {'campaign': 'pre_meal_anchor'});
    expect(received, ['sunday_recap', 'pre_meal_anchor']);
  });

  group('OneSignalService Unit Tests', () {
    test('Initial state initializes in local simulated fallback mode', () {
      expect(oneSignal.isInitialized, isTrue);
    });

    test(
      'buildPostMealCheckIn constructs proper payload and action buttons',
      () {
        final event = oneSignal.buildPostMealCheckIn(meal: sampleMeal);

        expect(event.type, equals(RetentionCampaignType.postMealCheckIn));
        expect(event.title, contains('How\'s your energy?'));
        expect(event.body, contains('your meal'));
        expect(event.body, contains('Tap to check in'));
        expect(event.actionButtons, contains('Feeling steady'));
        expect(event.actionButtons, contains('Low energy'));
        expect(event.data['meal_id'], equals('meal_test_123'));
        expect(event.data['campaign'], equals('post_meal_checkin'));
      },
    );

    test('buildPreMealAnchorNudge produces lunch and dinner blueprints', () {
      final lunchEvent = oneSignal.buildPreMealAnchorNudge(isLunch: true);
      expect(lunchEvent.type, equals(RetentionCampaignType.preMealAnchor));
      expect(lunchEvent.title, contains('Planning lunch?'));
      expect(lunchEvent.body, contains('Build or scan'));
      expect(lunchEvent.actionButtons, contains('Open scanner'));
      expect(lunchEvent.data['period'], equals('lunch'));

      final dinnerEvent = oneSignal.buildPreMealAnchorNudge(isLunch: false);
      expect(dinnerEvent.title, contains('Planning dinner?'));
      expect(dinnerEvent.body, contains('Build or scan'));
      expect(dinnerEvent.data['period'], equals('dinner'));
    });

    test('buildMidWeekMomentum constructs balanced-plate motivation event', () {
      final event = oneSignal.buildMidWeekMomentum();
      expect(event.type, equals(RetentionCampaignType.midWeekMomentum));
      expect(event.title, contains('Mid-Week Satiety Momentum'));
      expect(event.body, contains('balanced plates'));
      expect(event.actionButtons, contains('View recap'));
    });

    test('Sunday reminder opens the live recap without a stale count', () {
      final event = oneSignal.buildSundayRecap(totalBalancedPlates: 14);
      expect(event.type, equals(RetentionCampaignType.sundayRecap));
      expect(event.title, contains('Your week in review'));
      expect(event.body, contains('energy check-ins'));
      expect(event.body, isNot(contains('14')));
      expect(event.actionButtons, contains('View recap'));
      expect(event.data['plates'], equals(14));
    });

    test(
      'buildTrialTrustReminder constructs friendly transparent reminder',
      () {
        final event = oneSignal.buildTrialTrustReminder();
        expect(event.type, equals(RetentionCampaignType.trialTrustReminder));
        expect(event.title, contains('2 Days Left on Your Free Trial'));
        expect(event.body, contains('manage anytime in Settings'));
        expect(event.actionButtons, contains('⚙️ Manage in Settings'));
        expect(event.actionButtons, contains('Continue Pro'));
      },
    );

    test(
      'handleNotificationAction for steady logs energy to meal log',
      () async {
        await storage.addMealLog(sampleMeal);

        oneSignal.handleNotificationAction('action_steady', {
          'meal_id': sampleMeal.id,
        });
        await Future<void>.delayed(Duration.zero);

        final updated = storage.meals.firstWhere((m) => m.id == sampleMeal.id);
        expect(updated.energyCheckIn, equals('steady'));
      },
    );

    test('dip answer is saved before snack suggestions open', () async {
      await storage.addMealLog(sampleMeal);

      String? requestedMealId;
      final sub = oneSignal.onBridgeSnackRequested.listen((id) {
        requestedMealId = id;
      });

      oneSignal.handleNotificationAction('action_dip', {
        'meal_id': sampleMeal.id,
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final updated = storage.meals.firstWhere((m) => m.id == sampleMeal.id);
      expect(updated.energyCheckIn, 'dip');
      expect(requestedMealId, equals(sampleMeal.id));

      await sub.cancel();
    });

    test('simulateCampaign emits event on campaignTriggered stream', () async {
      RetentionNotificationEvent? receivedEvent;
      final sub = oneSignal.onCampaignTriggered.listen((event) {
        receivedEvent = event;
      });

      oneSignal.simulateCampaign(RetentionCampaignType.trialTrustReminder);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(receivedEvent, isNotNull);
      expect(
        receivedEvent!.type,
        equals(RetentionCampaignType.trialTrustReminder),
      );

      await sub.cancel();
    });

    test(
      'syncUserTags executes gracefully without throwing in simulation mode',
      () async {
        await expectLater(oneSignal.syncUserTags(), completes);
      },
    );

    test(
      'requestNotificationPermission returns true in simulated fallback mode',
      () async {
        final granted = await oneSignal.requestNotificationPermission();
        expect(granted, isTrue);
      },
    );

    test('reminder switches do not grant push consent', () {
      final profile = storage.userProfile;
      expect(profile.pushConsentGranted, isFalse);
      expect(profile.checkInRemindersEnabled, isTrue);
      expect(profileWantsPush(profile), isFalse);
    });

    test('all reminders off and no consent does not register push', () {
      final profile = storage.userProfile.copyWith(
        checkInRemindersEnabled: false,
        preMealNudgesEnabled: false,
        weeklyRecapEnabled: false,
        pushConsentGranted: false,
      );
      expect(profileWantsPush(profile), isFalse);
    });

    test('grantPushConsent records consent on the profile', () async {
      expect(storage.userProfile.pushConsentGranted, isFalse);
      final granted = await oneSignal.grantPushConsent();
      expect(granted, isTrue);
      expect(storage.userProfile.pushConsentGranted, isTrue);
    });
  });
}
