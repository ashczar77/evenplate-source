import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:evenplate/core/theme/even_colors.dart';
import 'package:evenplate/features/meals/plate_blueprint_screen.dart';
import 'package:evenplate/models/meal_log.dart';
import 'package:evenplate/models/satiety_matrix.dart';
import 'package:evenplate/services/food_list_scorer.dart';
import 'package:evenplate/services/gemini_vision_service.dart';
import 'package:evenplate/services/local_storage_service.dart';
import 'package:evenplate/services/pantry_catalog.dart';

void _installForecast({double hours = 2.4, int score = 48}) {
  FoodListScorer.instance.resetForTest(
    vision: GeminiVisionService(
      null,
      MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final foods = (body['foods'] as List).map((item) => '$item').toList();
        bool has(String needle) =>
            foods.any((food) => food.toLowerCase().contains(needle));
        return http.Response(
          jsonEncode({
            'mealName': 'Plate',
            'components': foods,
            'rejected': <String>[],
            'pillars': {
              'anchor': {
                'detected': has('egg') || has('sloppy'),
                'items': has('egg') ? ['Eggs'] : <String>[],
                'quality': 'high',
              },
              'net': {
                'detected': has('salad'),
                'items': has('salad') ? ['Side salad'] : <String>[],
                'quality': 'high',
              },
              'buffer': {
                'detected': has('avocado'),
                'items': has('avocado') ? ['Avocado'] : <String>[],
                'quality': 'high',
              },
              'spark': {
                'detected': has('salad') || has('cucumber'),
                'items': has('salad') ? ['Side salad'] : <String>[],
                'quality': 'high',
              },
            },
            'assessmentMethod': SatietyResult.modelMethod,
            'satietyScore': score,
            'durationHours': 0,
            'fullnessEstimate': {
              'minHours': 2,
              'maxHours': 4,
              'portion': 'regular',
              'basis': 'model_regular_portion_v1',
            },
            'crashRisk': 'moderate',
            'captureIssue': 'none',
            'hybridUpgrade': {
              'instantAdd': 'Add a side salad.',
              'smartSwap': 'Keep the protein.',
              'digestiveCatalyst': 'Sip water first.',
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(PantryCatalog.loadProfiles);
  setUp(_installForecast);

  testWidgets('typed food waits for one explicit complete-plate assessment', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final storage = LocalStorageService();
    await storage.setAnalysisConsent(true);
    await storage.setAnalysisConsent(true);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: PlateBlueprintScreen(storage: storage),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('blueprint_add_food')),
      'cake',
    );
    await tester.tap(find.byKey(const ValueKey('btn_blueprint_add_food')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Ready to assess'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('btn_assess_plate')));
    await tester.tap(find.byKey(const ValueKey('btn_assess_plate')));
    await tester.pumpAndSettle();
    expect(find.text('48 / 100'), findsOneWidget);
    expect(find.text('Scoring temporarily unavailable'), findsNothing);
    expect(storage.meals, isEmpty);
  });

  testWidgets('failed typed lookup shows feedback before saving', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    FoodListScorer.instance.resetForTest(
      vision: GeminiVisionService(
        null,
        MockClient((_) async => http.Response('{"error":"down"}', 503)),
      ),
    );
    final storage = LocalStorageService();
    await storage.setAnalysisConsent(true);
    await storage.setAnalysisConsent(true);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: PlateBlueprintScreen(storage: storage),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('blueprint_add_food')),
      'cake',
    );
    await tester.tap(find.byKey(const ValueKey('btn_blueprint_add_food')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('btn_assess_plate')));
    await tester.tap(find.byKey(const ValueKey('btn_assess_plate')));
    await tester.pumpAndSettle();
    expect(find.text('down'), findsOneWidget);
    expect(storage.meals, isEmpty);
  });

  testWidgets('Building eggs, salad, and avocado saves a scored plate', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final storage = LocalStorageService();
    await storage.setAnalysisConsent(true);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: EvenColors.darkBackground,
        ),
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: ElevatedButton(
                key: const ValueKey('btn_open_blueprint'),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PlateBlueprintScreen(storage: storage),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('btn_open_blueprint')));
    await tester.pumpAndSettle();

    expect(find.text('Build a plate'), findsOneWidget);
    expect(find.text('Lunch'), findsNothing);
    expect(find.text('Add a food'), findsWidgets);
    expect(find.text('Relative fullness'), findsOneWidget);
    expect(
      find.text('Add food. An empty plate does not last.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('blueprint_chip_eggs')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('blueprint_chip_side salad')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('blueprint_chip_avocado')));
    await tester.pumpAndSettle();

    expect(find.text('Ready to assess'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('btn_assess_plate')));
    await tester.tap(find.byKey(const ValueKey('btn_assess_plate')));
    await tester.pumpAndSettle();
    expect(find.text('48 / 100'), findsOneWidget);
    expect(find.text('5.2'), findsNothing);
    expect(
      find.text('Protein, fiber, and fat are on this plate.'),
      findsOneWidget,
    );

    if (find.byKey(const ValueKey('btn_assess_plate')).evaluate().isNotEmpty) {
      expect(
        tester
            .widget<ElevatedButton>(
              find.byKey(const ValueKey('btn_save_blueprint')),
            )
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('btn_assess_plate')),
      );
      await tester.tap(find.byKey(const ValueKey('btn_assess_plate')));
      await tester.pumpAndSettle();
    }
    expect(
      tester
          .widget<ElevatedButton>(
            find.byKey(const ValueKey('btn_save_blueprint')),
          )
          .onPressed,
      isNotNull,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('btn_save_blueprint')),
    );
    await tester.tap(find.byKey(const ValueKey('btn_save_blueprint')));
    await tester.pumpAndSettle();

    expect(storage.meals, hasLength(1));
    expect(storage.meals.first.satietyResult.durationHours, 0);
    expect(storage.meals.first.satietyResult.fullness, isNotNull);
    expect(storage.meals.first.satietyResult.pillars.hccComplete, isTrue);
  });

  testWidgets('Typed foods join the plate without a scan credit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final storage = LocalStorageService();
    await storage.setAnalysisConsent(true);
    await storage.saveUserProfile(
      storage.userProfile.copyWith(freeScansRemaining: 3),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: EvenColors.darkBackground,
        ),
        home: PlateBlueprintScreen(storage: storage),
      ),
    );
    await tester.pump();

    await tester.enterText(
      find.byKey(const ValueKey('blueprint_add_food')),
      'Sloppy joes',
    );
    await tester.tap(find.byKey(const ValueKey('btn_blueprint_add_food')));
    await tester.pump();

    expect(find.text('Sloppy joes'), findsOneWidget);
    expect(storage.userProfile.freeScansRemaining, 3);

    if (find.byKey(const ValueKey('btn_assess_plate')).evaluate().isNotEmpty) {
      expect(
        tester
            .widget<ElevatedButton>(
              find.byKey(const ValueKey('btn_save_blueprint')),
            )
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('btn_assess_plate')),
      );
      await tester.tap(find.byKey(const ValueKey('btn_assess_plate')));
      await tester.pumpAndSettle();
    }
    expect(
      tester
          .widget<ElevatedButton>(
            find.byKey(const ValueKey('btn_save_blueprint')),
          )
          .onPressed,
      isNotNull,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('btn_save_blueprint')),
    );
    await tester.tap(find.byKey(const ValueKey('btn_save_blueprint')));
    await tester.pumpAndSettle();

    expect(storage.meals, hasLength(1));
    expect(
      storage.meals.first.satietyResult.components,
      contains('Sloppy joes'),
    );
    expect(storage.userProfile.freeScansRemaining, 3);
  });

  testWidgets('A saved plate can be opened and updated', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final storage = LocalStorageService();
    await storage.setAnalysisConsent(true);
    final existing = MealLog(
      id: 'meal-1',
      mealName: 'Plate',
      timestamp: DateTime(2026, 9, 20, 12),
      satietyResult: SatietyResult.fromFoods(
        mealName: 'Plate',
        components: const ['Eggs'],
      ),
    );
    await storage.addMealLog(existing);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: EvenColors.darkBackground,
        ),
        home: PlateBlueprintScreen(storage: storage, existing: existing),
      ),
    );
    await tester.pump();

    expect(find.text('Edit plate'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('blueprint_chip_avocado')));
    await tester.pump();

    if (find.byKey(const ValueKey('btn_assess_plate')).evaluate().isNotEmpty) {
      expect(
        tester
            .widget<ElevatedButton>(
              find.byKey(const ValueKey('btn_save_blueprint')),
            )
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('btn_assess_plate')),
      );
      await tester.tap(find.byKey(const ValueKey('btn_assess_plate')));
      await tester.pumpAndSettle();
    }
    expect(
      tester
          .widget<ElevatedButton>(
            find.byKey(const ValueKey('btn_save_blueprint')),
          )
          .onPressed,
      isNotNull,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('btn_save_blueprint')),
    );
    await tester.tap(find.byKey(const ValueKey('btn_save_blueprint')));
    await tester.pumpAndSettle();

    expect(storage.meals, hasLength(1));
    expect(storage.meals.first.id, 'meal-1');
    expect(storage.meals.first.satietyResult.pillars.buffer.detected, isTrue);
  });
  testWidgets(
    'builder responses arriving in reverse order never overwrite the newer plate',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      final pending = <List<String>, Completer<http.Response>>{};
      FoodListScorer.instance.resetForTest(
        vision: GeminiVisionService(
          null,
          MockClient((req) {
            final foods = List<String>.from(jsonDecode(req.body)['foods']);
            final response = Completer<http.Response>();
            pending[foods] = response;
            return response.future;
          }),
        ),
      );
      final storage = LocalStorageService();
      await storage.setAnalysisConsent(true);
      await tester.pumpWidget(
        MaterialApp(home: PlateBlueprintScreen(storage: storage)),
      );
      await tester.tap(find.byKey(const ValueKey('blueprint_chip_eggs')));
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const ValueKey('btn_assess_plate')),
      );
      await tester.tap(find.byKey(const ValueKey('btn_assess_plate')));
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const ValueKey('blueprint_chip_avocado')),
      );
      await tester.tap(find.byKey(const ValueKey('blueprint_chip_avocado')));
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const ValueKey('btn_assess_plate')),
      );
      await tester.tap(find.byKey(const ValueKey('btn_assess_plate')));
      await tester.pump();
      expect(pending, hasLength(2));
      http.Response result(List<String> foods, int score) => http.Response(
        jsonEncode({
          ...SatietyResult.fromFoods(mealName: 'Plate', components: foods)
              .copyWith(
                assessmentMethod: SatietyResult.modelMethod,
                satietyScore: score,
              )
              .toJson(),
          'captureIssue': 'none',
        }),
        200,
      );
      final newer = pending.entries.last;
      newer.value.complete(result(newer.key, 70));
      await tester.pumpAndSettle();
      final older = pending.entries.first;
      older.value.complete(result(older.key, 40));
      await tester.pumpAndSettle();
      expect(find.text('70 / 100'), findsOneWidget);
      expect(find.text('40 / 100'), findsNothing);
      await tester.ensureVisible(
        find.byKey(const ValueKey('blueprint_chip_avocado')),
      );
      await tester.tap(find.byKey(const ValueKey('blueprint_chip_avocado')));
      await tester.pump();
      expect(find.text('40 / 100'), findsOneWidget);
      expect(pending, hasLength(2));
    },
  );
}
