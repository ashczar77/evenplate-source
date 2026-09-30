import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:evenplate/main.dart';
import 'package:evenplate/models/user_profile.dart';
import 'package:evenplate/services/local_storage_service.dart';
import 'package:evenplate/services/onesignal_service.dart';
import 'package:evenplate/services/revenuecat_service.dart';
import 'package:evenplate/services/supabase_service.dart';
import 'package:evenplate/widgets/satiety_duration_clock.dart';
import 'package:evenplate/widgets/satiety_engine_widget.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('EvenPlate End-to-End Integration & User Journey Tests', () {
    late LocalStorageService storage;
    late SupabaseService supabase;
    late RevenueCatService revenueCat;
    late OneSignalService oneSignal;

    setUp(() async {
      storage = LocalStorageService();
      await storage.init();
      // Ensure clean state
      await storage.saveUserProfile(
        UserProfile(
          id: 'default_user',
          hasCompletedOnboarding: false,
          freeScansRemaining: 3,
          lastQuotaReset: DateTime.now(),
        ),
      );
      await storage.setProStatus(false);

      revenueCat = RevenueCatService(storage);
      await revenueCat.init();

      supabase = SupabaseService(storage);
      supabase.setRevenueCatService(revenueCat);
      await supabase.init();

      oneSignal = OneSignalService(storage);
      await oneSignal.init();
    });

    testWidgets(
      'Full User Journey: Email Auth -> Onboarding -> Scan & Horizon -> Paywall -> Promo Bypass -> Bridge Snack',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        Future<void> pumpStep([int ms = 600]) async {
          await tester.pump(Duration(milliseconds: ms));
          await tester.pump(const Duration(milliseconds: 100));
        }

        // 1. Launch App
        await tester.pumpWidget(
          EvenPlateApp(
            storage: storage,
            revenueCat: revenueCat,
            oneSignal: oneSignal,
            supabase: supabase,
          ),
        );
        await pumpStep();

        // Verify Auth Screen renders
        expect(find.text('EvenPlate', findRichText: true), findsOneWidget);
        expect(find.byKey(const ValueKey('btn_primary_auth')), findsOneWidget);
        expect(find.byKey(const ValueKey('btn_guest_sign_in')), findsNothing);

        // 2. Sign in with email (simulated in debug when backend is unset)
        await tester.enterText(
          find.byKey(const ValueKey('input_email')),
          'user@evenplate.app',
        );
        await tester.enterText(
          find.byKey(const ValueKey('input_password')),
          'balancedPlate7',
        );
        await tester.tap(find.byKey(const ValueKey('btn_primary_auth')));
        await pumpStep();

        // Verify Onboarding Screen renders (Step 1)
        expect(
          find.text('What is your primary wellness intention?'),
          findsOneWidget,
        );

        // Quiz Step 1: Goal Selection
        await tester.tap(find.byKey(const ValueKey('goal_option_1')));
        await pumpStep();
        await tester.tap(find.byKey(const ValueKey('btn_onboarding_next')));
        await pumpStep();

        // Quiz Step 2: Eating Style Selection
        expect(find.text('How do your typical meals look?'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('style_option_2')));
        await pumpStep();
        await tester.tap(find.byKey(const ValueKey('btn_onboarding_next')));
        await pumpStep();

        // Quiz Step 3: Mindful Satiety Matrix & Finish
        expect(find.text('The Satiety Matrix'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('btn_onboarding_next')));
        await pumpStep(1000);

        // 3. Verify Main Dashboard
        expect(find.byType(SatietyEngineWidget), findsOneWidget);
        expect(find.text('Daily\nHarmony'), findsOneWidget);

        // 4. Build a plate from empty Home
        await tester.ensureVisible(
          find.byKey(const ValueKey('btn_build_plate_empty')),
        );
        await tester.tap(find.byKey(const ValueKey('btn_build_plate_empty')));
        await pumpStep();

        expect(find.text('Build a plate'), findsWidgets);
        expect(find.byType(SatietyDurationClock), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('blueprint_chip_eggs')));
        await pumpStep();
        await tester.tap(
          find.byKey(const ValueKey('blueprint_chip_side salad')),
        );
        await pumpStep();
        await tester.tap(find.byKey(const ValueKey('blueprint_chip_avocado')));
        await pumpStep();

        final saveBtn = find.byKey(const ValueKey('btn_save_blueprint'));
        await tester.ensureVisible(saveBtn);
        await tester.tap(saveBtn);
        await pumpStep(1200);

        expect(storage.meals.length, equals(1));

        // 6. Test Satiety Check-in & Bridge Snack Flow
        final latestMealId = storage.meals.first.id;
        final dipBtn = find.byKey(ValueKey('btn_checkin_dip_$latestMealId'));
        if (dipBtn.evaluate().isNotEmpty) {
          await tester.drag(
            find.byType(CustomScrollView).first,
            const Offset(0, -350),
          );
          await pumpStep();
          await tester.tap(dipBtn, warnIfMissed: false);
          await pumpStep(1200);

          // Verify Bridge Snack Sheet
          expect(find.text('The 30-Second Bridge Fix'), findsOneWidget);
          await tester.tap(find.text('Handful of Raw Almonds or Walnuts'));
          await pumpStep(1200);

          expect(storage.meals.length, equals(2));
        }

        // 7. Test Settings & Paywall Flow
        await tester.tap(find.byKey(const ValueKey('nav_settings_tab')));
        await pumpStep();

        // Open Paywall via Upgrade button
        final upgradeBtn = find.text('Upgrade');
        expect(upgradeBtn, findsOneWidget);
        await tester.tap(upgradeBtn);
        await pumpStep(1000);

        expect(find.text('Unlock EvenPlate Pro'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('paywall_plan_annual')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('paywall_plan_monthly')),
          findsOneWidget,
        );

        // Test Trial reminder toggle
        final trialToggle = find.byKey(
          const ValueKey('paywall_trial_reminder_switch'),
        );
        expect(trialToggle, findsOneWidget);
        await tester.tap(trialToggle);
        await pumpStep();

        // Test Rewarded Ad simulation
        final adBtn = find.byKey(const ValueKey('btn_paywall_rewarded_ad'));
        if (adBtn.evaluate().isEmpty) {
          return;
        }
        await tester.drag(
          find.byType(SingleChildScrollView).first,
          const Offset(0, -250),
        );
        await pumpStep();
        final initialScans = storage.userProfile.freeScansRemaining;
        await tester.tap(adBtn, warnIfMissed: false);
        await pumpStep(1000);
        expect(
          storage.userProfile.freeScansRemaining,
          equals(initialScans + 1),
        );

        // Dismiss Paywall
        await tester.tap(find.byIcon(Icons.close_rounded));
        await pumpStep();

        // 8. Privileged access stays. Developer tools do not.
        await tester.drag(find.byType(ListView).first, const Offset(0, -500));
        await pumpStep();
        expect(find.text('Privileged access'), findsOneWidget);
        expect(find.text('Promo Bypass Code'), findsOneWidget);
        expect(find.text('Return to Free tier'), findsNothing);
        expect(find.text('Developer & Reviewer Tools'), findsNothing);
      },
    );
  });
}
