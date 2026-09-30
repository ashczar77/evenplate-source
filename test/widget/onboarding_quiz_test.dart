import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evenplate/core/theme/even_theme.dart';
import 'package:evenplate/features/onboarding/onboarding_screen.dart';
import 'package:evenplate/services/local_storage_service.dart';

void main() {
  late LocalStorageService storage;

  setUp(() {
    storage = LocalStorageService();
  });

  // Option keys are built as 'opt_<indexOnPage>_<label>'. Later options can sit
  // below the fold, so they are scrolled into view before being tapped.
  Future<void> selectOption(
    WidgetTester tester,
    int index,
    String label,
  ) async {
    final finder = find.byKey(ValueKey('opt_${index}_$label'));
    expect(finder, findsOneWidget);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pump();
  }

  Widget createOnboardingWidget({
    Size screenSize = const Size(390, 844),
    ThemeMode themeMode = ThemeMode.dark,
    VoidCallback? onComplete,
  }) {
    return MediaQuery(
      data: MediaQueryData(size: screenSize),
      child: MaterialApp(
        theme: EvenTheme.lightTheme,
        darkTheme: EvenTheme.darkTheme,
        themeMode: themeMode,
        home: OnboardingScreen(storage: storage, onComplete: onComplete),
      ),
    );
  }

  testWidgets(
    'OnboardingScreen walks the 3 question pages and saves the blueprint',
    (WidgetTester tester) async {
      var completed = false;
      await tester.pumpWidget(
        createOnboardingWidget(onComplete: () => completed = true),
      );
      await tester.pump();

      // Question 1: primary goal.
      expect(find.text('What are we actually\nfixing here?'), findsOneWidget);
      expect(
        find.text('Afternoons hit a wall. I need energy that lasts.'),
        findsOneWidget,
      );
      expect(find.textContaining('villain origin'), findsNothing);
      await selectOption(tester, 1, 'I eat fine but still feel foggy all day');

      await tester.tap(find.byKey(const ValueKey('btn_onboarding_next')));
      await tester.pumpAndSettle();

      // Question 2: crash window.
      expect(find.text('When does your energy\nbetray you?'), findsOneWidget);

      // Back returns to question 1, then forward again.
      await tester.tap(find.byKey(const ValueKey('btn_onboarding_back')));
      await tester.pumpAndSettle();
      expect(find.text('What are we actually\nfixing here?'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('btn_onboarding_next')));
      await tester.pumpAndSettle();

      await selectOption(tester, 1, 'Post-lunch. Every. Single. Day.');

      await tester.tap(find.byKey(const ValueKey('btn_onboarding_next')));
      await tester.pumpAndSettle();

      // Question 3: dietary identity.
      expect(find.text('How do you typically\neat?'), findsOneWidget);
      await selectOption(tester, 1, 'Mostly plants, flexibly');

      await tester.tap(find.byKey(const ValueKey('btn_onboarding_next')));
      await tester.pumpAndSettle();

      // Blueprint reveal with the notification opt-in, which sits below the fold.
      expect(find.text('Your Satiety\nBlueprint'), findsOneWidget);

      final optInCard = find.byKey(const ValueKey('card_notification_opt_in'));
      await tester.dragUntilVisible(
        optInCard,
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      expect(optInCard, findsOneWidget);

      expect(find.byKey(const ValueKey('push_opt_in_switch')), findsOneWidget);

      expect(find.text('Enter EvenPlate'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('btn_onboarding_next')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final profile = storage.userProfile;
      expect(profile.hasCompletedOnboarding, isTrue);
      expect(profile.primaryGoal, 'Steady Energy All Day');
      expect(profile.crashPattern, 'Afternoon Slump (2:00-3:30 PM)');
      expect(profile.dietaryPreference, 'Plant-Forward & Flexitarian');
      expect(profile.targetMealsPerDay, 3);
      expect(profile.targetSatietyHoursDaily, 12.0);
      expect(profile.pushConsentGranted, isFalse);
      expect(profile.checkInRemindersEnabled, isFalse);

      // Navigation is the caller's responsibility, signalled via onComplete.
      expect(completed, isTrue);
    },
  );

  testWidgets('Athletic goal switches the blueprint to a two meal schedule', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(createOnboardingWidget(onComplete: () {}));
    await tester.pump();

    await selectOption(
      tester,
      3,
      "I need consistent fuel. I'm building something.",
    );

    for (var page = 0; page < 3; page++) {
      await tester.tap(find.byKey(const ValueKey('btn_onboarding_next')));
      await tester.pumpAndSettle();
    }

    await tester.tap(find.byKey(const ValueKey('btn_onboarding_next')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final profile = storage.userProfile;
    expect(profile.primaryGoal, 'Lean Fuel & Athletic Vitality');
    expect(profile.targetMealsPerDay, 2);
    expect(profile.targetSatietyHoursDaily, 9.0);
    expect(profile.mealSchedule, '2 Substantial Meals (Intermittent Fasting)');
  });

  testWidgets('OnboardingScreen renders responsively without overflow', (
    WidgetTester tester,
  ) async {
    // Compact screen.
    await tester.pumpWidget(
      createOnboardingWidget(screenSize: const Size(360, 640)),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    // Large tablet screen.
    await tester.pumpWidget(
      createOnboardingWidget(screenSize: const Size(768, 1024)),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
