import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:evenplate/services/gemini_vision_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evenplate/models/meal_log.dart';
import 'package:evenplate/models/satiety_matrix.dart';
import 'package:evenplate/services/local_storage_service.dart';
import 'package:evenplate/services/food_list_scorer.dart';
import 'package:evenplate/widgets/bridge_snack_sheet.dart';
import 'package:evenplate/widgets/satiety_checkin_card.dart';

void main() {
  late LocalStorageService storage;

  final sampleMeal = MealLog(
    id: 'meal_checkin_test',
    mealName: 'Mediterranean Quinoa Salad',
    timestamp: DateTime.now().subtract(const Duration(hours: 3)),
    satietyResult: const SatietyResult(
      mealName: 'Mediterranean Quinoa Salad',
      components: [
        'Quinoa',
        'Feta',
        'Kalamata Olives',
        'Cucumber',
        'Chickpeas',
      ],
      pillars: SatietyPillars(
        anchor: PillarDetail(
          detected: true,
          items: ['Chickpeas', 'Feta'],
          quality: 'high',
        ),
        net: PillarDetail(detected: true, items: ['Cucumber'], quality: 'high'),
        buffer: PillarDetail(
          detected: true,
          items: ['Olives', 'Olive Oil'],
          quality: 'high',
        ),
        spark: PillarDetail(
          detected: true,
          items: ['Oregano'],
          quality: 'medium',
        ),
      ),
      satietyScore: 88,
      durationHours: 3.8,
      crashRisk: 'low',
      hybridUpgrade: HybridUpgrade(
        instantAdd: 'Sprinkle with pumpkin seeds.',
        smartSwap: 'Excellent whole-food profile.',
        digestiveCatalyst: 'Take time to chew thoroughly.',
      ),
    ),
  );

  setUp(() async {
    storage = LocalStorageService();
    await storage.addMealLog(sampleMeal);
    FoodListScorer.instance.resetForTest();
    for (final foods in <List<String>>[
      ['Almonds'],
      ['Hardboiled egg'],
      ['Green tea'],
      ['Cucumber', 'Hummus'],
      ['Tofu'],
      ['Olive oil'],
    ]) {
      FoodListScorer.instance.cache.writeSuccess(
        FoodListScorer.keyFor(foods),
        sampleMeal.satietyResult.copyWith(
          components: foods,
          assessmentMethod: SatietyResult.modelMethod,
        ),
      );
    }
  });

  tearDown(() => FoodListScorer.instance.resetForTest());

  Widget buildTestableWidget(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SingleChildScrollView(
            child: Padding(padding: const EdgeInsets.all(16.0), child: child),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'pending snack disables alternatives and repeated taps save once',
    (tester) async {
      final pending = Completer<http.Response>();
      var requests = 0;
      FoodListScorer.instance.resetForTest(
        vision: GeminiVisionService(
          null,
          MockClient((_) {
            requests++;
            return pending.future;
          }),
        ),
      );
      await tester.pumpWidget(
        buildTestableWidget(BridgeSnackSheet(storage: storage)),
      );
      final tile = find
          .ancestor(
            of: find.text('Hardboiled Egg'),
            matching: find.byType(InkWell),
          )
          .first;
      final tap = tester.widget<InkWell>(tile).onTap!;
      tap();
      tap();
      await tester.pump();
      expect(requests, 1);
      for (final ink in tester.widgetList<InkWell>(find.byType(InkWell))) {
        expect(ink.onTap, isNull);
      }
      final dismiss = tester.widget<TextButton>(
        find.byKey(const ValueKey('btn_dismiss_bridge_sheet')),
      );
      expect(dismiss.onPressed, isNull);
      pending.complete(
        http.Response(
          jsonEncode(
            SatietyResult.fromFoods(
                  mealName: 'Egg',
                  components: ['Hardboiled egg'],
                )
                .copyWith(
                  assessmentMethod: SatietyResult.modelMethod,
                  satietyScore: 60,
                )
                .toJson(),
          ),
          200,
        ),
      );
      await tester.pumpAndSettle();
      expect(storage.meals.where((meal) => meal.isBridgeFix), hasLength(1));
    },
  );

  testWidgets('failed snack assessment does not save an unassessed meal', (
    tester,
  ) async {
    FoodListScorer.instance.resetForTest();
    await tester.pumpWidget(
      buildTestableWidget(BridgeSnackSheet(storage: storage)),
    );
    await tester.tap(find.text('Hardboiled Egg'));
    await tester.pumpAndSettle();
    expect(storage.meals, hasLength(1));
    expect(find.textContaining('Connect to assess'), findsOneWidget);
  });

  group('Satiety Energy Checkin & Bridge Snack Widget Tests', () {
    testWidgets(
      'SatietyCheckinCard renders meal forecast and interactive action buttons',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          buildTestableWidget(
            SatietyCheckinCard(meal: sampleMeal, storage: storage),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Satiety Energy Check-in'), findsOneWidget);
        expect(find.text('Mediterranean Quinoa Salad'), findsOneWidget);
        expect(
          find.textContaining(
            'How did you feel after Mediterranean Quinoa Salad?',
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(ValueKey('btn_checkin_steady_${sampleMeal.id}')),
          findsOneWidget,
        );
        expect(
          find.byKey(ValueKey('btn_checkin_dip_${sampleMeal.id}')),
          findsOneWidget,
        );
      },
    );

    testWidgets('Tapping Steady & Focused records steady checkin milestone', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildTestableWidget(
          SatietyCheckinCard(meal: sampleMeal, storage: storage),
        ),
      );
      await tester.pumpAndSettle();

      final steadyButton = find.byKey(
        ValueKey('btn_checkin_steady_${sampleMeal.id}'),
      );
      await tester.tap(steadyButton);
      await tester.pumpAndSettle();

      expect(storage.meals.first.energyCheckIn, equals('steady'));
      expect(find.textContaining('Logged: you stayed even.'), findsOneWidget);
      expect(
        find.textContaining('You reported steady energy.'),
        findsOneWidget,
      );
    });

    testWidgets('Tapping Feeling a Dip opens BridgeSnackSheet modal', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildTestableWidget(
          SatietyCheckinCard(meal: sampleMeal, storage: storage),
        ),
      );
      await tester.pumpAndSettle();

      final dipButton = find.byKey(
        ValueKey('btn_checkin_dip_${sampleMeal.id}'),
      );
      await tester.tap(dipButton);
      await tester.pumpAndSettle();

      expect(storage.meals.first.energyCheckIn, 'dip');
      expect(find.text('The 30-Second Bridge Fix'), findsOneWidget);
      expect(find.text('Handful of Raw Almonds'), findsOneWidget);
      expect(find.text('Hardboiled Egg'), findsOneWidget);
    });

    testWidgets(
      'Dismissing optional snack suggestions preserves the dip answer',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          buildTestableWidget(
            SatietyCheckinCard(meal: sampleMeal, storage: storage),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(ValueKey('btn_checkin_dip_${sampleMeal.id}')),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('btn_dismiss_bridge_sheet')),
        );
        await tester.tap(
          find.byKey(const ValueKey('btn_dismiss_bridge_sheet')),
        );
        await tester.pumpAndSettle();

        expect(storage.meals.first.energyCheckIn, 'dip');
        expect(
          find.textContaining('You reported an energy dip.'),
          findsOneWidget,
        );
        expect(
          find.byKey(ValueKey('btn_checkin_dip_${sampleMeal.id}')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'BridgeSnackSheet logs chosen snack to diary and shows confirmation',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        addTearDown(tester.view.resetPhysicalSize);

        final initialMealCount = storage.meals.length;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () => BridgeSnackSheet.show(context, storage),
                    child: const Text('Open Bridge Sheet'),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Open sheet
        await tester.tap(find.text('Open Bridge Sheet'));
        await tester.pumpAndSettle();

        expect(find.text('The 30-Second Bridge Fix'), findsOneWidget);

        // Tap on Almonds buffer fix
        final snackOption = find.text('Handful of Raw Almonds');
        expect(snackOption, findsOneWidget);
        await tester.tap(snackOption);
        await tester.pumpAndSettle();

        // Sheet should dismiss and new snack meal added
        expect(storage.meals.length, equals(initialMealCount + 1));
        expect(storage.meals.first.mealName, equals('Handful of Raw Almonds'));
        expect(find.textContaining('Check how you feel later'), findsOneWidget);
      },
    );

    testWidgets('Bridge snack is logged as its own meal under today', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final plate = SatietyResult.fromFoods(
        mealName: 'Burger',
        components: const ['Burger', 'Potato chips'],
      );
      final meal = MealLog(
        id: 'dip-meal',
        mealName: plate.mealName,
        timestamp: DateTime.now(),
        satietyResult: plate,
      );
      await storage.addMealLog(meal);
      final mealCountBefore = storage.meals.length;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SatietyCheckinCard(meal: meal, storage: storage),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('btn_checkin_dip_${meal.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Handful of Raw Almonds'));
      await tester.pumpAndSettle();

      expect(storage.meals.length, equals(mealCountBefore + 1));
      final snack = storage.meals.firstWhere((m) => m.isBridgeFix);
      expect(snack.satietyResult.hasModelAssessment, isTrue);
      expect(snack.mealName, equals('Handful of Raw Almonds'));
      expect(snack.bridgedFromId, equals('dip-meal'));
      expect(
        storage.meals.firstWhere((m) => m.id == 'dip-meal').energyCheckIn,
        equals('dip'),
      );
      expect(
        find.textContaining('You reported an energy dip.'),
        findsOneWidget,
      );
    });

    testWidgets('Removing a bridge snack resets the check-in card', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final plate = SatietyResult.fromFoods(
        mealName: 'Burger',
        components: const ['Burger', 'Potato chips'],
      );
      final meal = MealLog(
        id: 'dip-meal-reset',
        mealName: plate.mealName,
        timestamp: DateTime.now(),
        satietyResult: plate,
      );
      await storage.addMealLog(meal);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SatietyCheckinCard(meal: meal, storage: storage),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('btn_checkin_dip_${meal.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Handful of Raw Almonds'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('You reported an energy dip.'),
        findsOneWidget,
      );

      final snack = storage.meals.firstWhere((m) => m.isBridgeFix);
      expect(snack.satietyResult.hasModelAssessment, isTrue);
      await storage.deleteMeal(snack.id);
      await tester.pumpAndSettle();

      expect(
        storage.meals.firstWhere((m) => m.id == meal.id).energyCheckIn,
        isNull,
      );
      expect(find.textContaining('You reported an energy dip.'), findsNothing);
      expect(
        find.byKey(ValueKey('btn_checkin_dip_${meal.id}')),
        findsOneWidget,
      );
    });
  });
}
