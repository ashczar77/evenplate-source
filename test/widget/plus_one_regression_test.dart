import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:evenplate/features/scan/plate_analysis_screen.dart';
import 'package:evenplate/models/satiety_matrix.dart';
import 'package:evenplate/models/fullness_estimate.dart';
import 'package:evenplate/services/food_list_scorer.dart';
import 'package:evenplate/services/gemini_vision_service.dart';
import 'package:evenplate/services/local_storage_service.dart';
import 'package:evenplate/services/pantry_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(PantryCatalog.loadProfiles);
  final sushi =
      SatietyResult.fromFoods(
        mealName: 'Sushi',
        components: ['Sushi roll'],
        hybridUpgrade: const HybridUpgrade(
          instantAdd: 'Add a side of edamame beans.',
          smartSwap: '',
          digestiveCatalyst: '',
        ),
      ).copyWith(
        assessmentMethod: SatietyResult.modelMethod,
        assessmentId: 'photo-one',
        satietyScore: 66,
        fullnessEstimate: const FullnessEstimate(minHours: 2, maxHours: 4),
      );
  for (final rescue in <String, String>{
    'Edamame': 'Add a side of edamame beans.',
    'Almonds': 'Add almonds.',
    'Avocado': 'Add avocado.',
    'Greek yogurt': 'Add Greek yogurt.',
  }.entries) {
    testWidgets(
      '${rescue.key} selects a food, assesses the whole plate, and restores the original without another request',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        var calls = 0;
        FoodListScorer.instance.resetForTest(
          vision: GeminiVisionService(
            null,
            MockClient((req) async {
              calls++;
              final body = jsonDecode(req.body);
              expect(body['foods'], ['Sushi roll', rescue.key]);
              return http.Response(
                jsonEncode({
                  ...sushi
                      .copyWith(
                        components: ['Sushi roll', rescue.key],
                        satietyScore: 71,
                        fullnessEstimate: const FullnessEstimate(
                          minHours: 3,
                          maxHours: 5,
                        ),
                      )
                      .toJson(),
                  'captureIssue': 'none',
                }),
                200,
              );
            }),
          ),
        );
        final storage = LocalStorageService();
        await storage.setAnalysisConsent(true);
        await tester.pumpWidget(
          MaterialApp(
            home: PlateAnalysisScreen(
              result: sushi.copyWith(
                hybridUpgrade: HybridUpgrade(
                  instantAdd: rescue.value,
                  smartSwap: '',
                  digestiveCatalyst: '',
                ),
              ),
              storage: storage,
              animateSensory: false,
            ),
          ),
        );
        final before = (tester.widget<Text>(
          find.byKey(const ValueKey('fullness_rating')),
        )).data;
        expect(find.text('Rough fullness estimate: 2-4 hours'), findsOneWidget);
        await tester.ensureVisible(find.text('I Added This'));
        await tester.tap(find.text('I Added This'));
        await tester.pump();
        expect(
          find.byKey(ValueKey('food_chip_${rescue.key.toLowerCase()}')),
          findsOneWidget,
        );
        final added = (tester.widget<Text>(
          find.byKey(const ValueKey('fullness_rating')),
        )).data;
        expect(added, before);
        expect(find.text('Previous assessment'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('fullness_hours_estimate')),
          findsNothing,
        );
        expect(calls, 0);
        await tester.ensureVisible(
          find.byKey(const ValueKey('btn_assess_plate')),
        );
        await tester.tap(find.byKey(const ValueKey('btn_assess_plate')));
        await tester.pumpAndSettle();
        expect(find.text('71 / 100'), findsOneWidget);
        expect(find.text('Rough fullness estimate: 3-5 hours'), findsOneWidget);
        expect(find.text('Looking up the new food...'), findsNothing);
        await tester.ensureVisible(find.text('Added'));
        await tester.tap(find.text('Added'));
        await tester.pump();
        expect(
          find.byKey(ValueKey('food_chip_${rescue.key.toLowerCase()}')),
          findsNothing,
        );
        expect(
          (tester.widget<Text>(
            find.byKey(const ValueKey('fullness_rating')),
          )).data,
          before,
        );
        expect(calls, 1);
        expect(find.text('Rough fullness estimate: 2-4 hours'), findsOneWidget);
        await tester.ensureVisible(find.text('I Added This'));
        await tester.tap(find.text('I Added This'));
        await tester.pumpAndSettle();
        expect(find.text('71 / 100'), findsOneWidget);
        expect(calls, 1);
      },
    );
  }
  testWidgets('an in-flight lookup cannot reapply an unchecked add-on', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final pending = Completer<http.Response>();
    FoodListScorer.instance.resetForTest(
      vision: GeminiVisionService(null, MockClient((_) => pending.future)),
    );
    final storage = LocalStorageService();
    await storage.setAnalysisConsent(true);
    final meal = sushi.copyWith(
      hybridUpgrade: const HybridUpgrade(
        instantAdd: 'Add chia seeds.',
        smartSwap: '',
        digestiveCatalyst: '',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PlateAnalysisScreen(
          result: meal,
          storage: storage,
          animateSensory: false,
        ),
      ),
    );
    final before = (tester.widget<Text>(
      find.byKey(const ValueKey('fullness_rating')),
    )).data;
    await tester.ensureVisible(find.text('I Added This'));
    await tester.tap(find.text('I Added This'));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('btn_assess_plate')));
    await tester.tap(find.byKey(const ValueKey('btn_assess_plate')));
    await tester.pump();
    await tester.ensureVisible(find.text('Added'));
    await tester.tap(find.text('Added'));
    await tester.pump();
    final response = SatietyResult.fromFoods(
      mealName: 'Food',
      components: ['Sushi roll', 'Chia seeds'],
    ).copyWith(assessmentMethod: SatietyResult.modelMethod, satietyScore: 72);
    pending.complete(
      http.Response(
        jsonEncode({...response.toJson(), 'captureIssue': 'none'}),
        200,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('food_chip_chia seeds')), findsNothing);
    expect(
      (tester.widget<Text>(find.byKey(const ValueKey('fullness_rating')))).data,
      before,
    );
  });
  testWidgets(
    'an uncommon structured add-on and unrelated typed food use the same reversible path',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      var calls = 0;
      FoodListScorer.instance.resetForTest(
        vision: GeminiVisionService(
          null,
          MockClient((req) async {
            calls++;
            final foods = List<String>.from(jsonDecode(req.body)['foods']);
            return http.Response(
              jsonEncode({
                ...sushi.copyWith(components: foods, satietyScore: 73).toJson(),
                'captureIssue': 'none',
              }),
              200,
            );
          }),
        ),
      );
      final storage = LocalStorageService();
      await storage.setAnalysisConsent(true);
      await tester.pumpWidget(
        MaterialApp(
          home: PlateAnalysisScreen(
            result: sushi.copyWith(
              hybridUpgrade: const HybridUpgrade(
                instantAdd: 'Try roasted chickpeas.',
                instantAddFood: 'Roasted chickpeas',
                smartSwap: '',
                digestiveCatalyst: '',
              ),
            ),
            storage: storage,
            animateSensory: false,
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('add_detected_food')),
        'Miso soup',
      );
      await tester.tap(find.byKey(const ValueKey('btn_add_food')));
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const ValueKey('btn_assess_plate')),
      );
      await tester.tap(find.byKey(const ValueKey('btn_assess_plate')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('I Added This'));
      await tester.tap(find.text('I Added This'));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('food_chip_roasted chickpeas')),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Added'));
      await tester.tap(find.text('Added'));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('food_chip_roasted chickpeas')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('food_chip_miso soup')), findsOneWidget);
      expect(find.text('73 / 100'), findsOneWidget);
      expect(calls, 1);
      await tester.ensureVisible(find.byTooltip('Remove Miso soup'));
      await tester.tap(find.byTooltip('Remove Miso soup'));
      await tester.pump();
      expect(find.text('66 / 100'), findsOneWidget);
      expect(calls, 1);
    },
  );
  testWidgets(
    'a late typed-food response cannot change a restored original plate',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      final pending = Completer<http.Response>();
      FoodListScorer.instance.resetForTest(
        vision: GeminiVisionService(null, MockClient((req) => pending.future)),
      );
      final storage = LocalStorageService();
      await storage.setAnalysisConsent(true);
      await tester.pumpWidget(
        MaterialApp(
          home: PlateAnalysisScreen(
            result: sushi,
            storage: storage,
            animateSensory: false,
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('add_detected_food')),
        'Cake',
      );
      await tester.tap(find.byKey(const ValueKey('btn_add_food')));
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const ValueKey('btn_assess_plate')),
      );
      await tester.tap(find.byKey(const ValueKey('btn_assess_plate')));
      await tester.pump();
      await tester.ensureVisible(find.byTooltip('Remove Cake'));
      await tester.tap(find.byTooltip('Remove Cake'));
      await tester.pump();
      pending.complete(
        http.Response(
          jsonEncode({
            ...sushi
                .copyWith(components: ['Sushi roll', 'Cake'], satietyScore: 52)
                .toJson(),
            'captureIssue': 'none',
          }),
          200,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('food_chip_cake')), findsNothing);
      expect(find.text('66 / 100'), findsOneWidget);
    },
  );
}
