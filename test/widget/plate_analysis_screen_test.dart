import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evenplate/core/theme/even_colors.dart';
import 'package:evenplate/features/scan/plate_analysis_screen.dart';
import 'package:evenplate/models/satiety_matrix.dart';
import 'package:evenplate/services/local_storage_service.dart';
import 'package:evenplate/widgets/crash_risk_horizon_graph.dart';
import 'package:evenplate/widgets/nutrition_disclaimer.dart';
import 'package:evenplate/widgets/satiety_duration_clock.dart';
import 'package:evenplate/widgets/satiety_matrix_widget.dart';
import 'package:evenplate/widgets/upgrade_card.dart';

void main() {
  late LocalStorageService storage;

  setUp(() {
    storage = LocalStorageService();
  });

  const balancedMeal = SatietyResult(
    mealName: 'Wild Salmon & Quinoa Harvest Bowl',
    components: [
      'Wild Sockeye Salmon',
      'Tricolor Quinoa',
      'Hass Avocado',
      'Steamed Broccoli',
    ],
    pillars: SatietyPillars(
      anchor: PillarDetail(
        detected: true,
        items: ['Wild Sockeye Salmon'],
        quality: 'high',
      ),
      net: PillarDetail(
        detected: true,
        items: ['Tricolor Quinoa', 'Steamed Broccoli'],
        quality: 'high',
      ),
      buffer: PillarDetail(
        detected: true,
        items: ['Hass Avocado'],
        quality: 'high',
      ),
      spark: PillarDetail(
        detected: true,
        items: ['Lemon Herb Dressing'],
        quality: 'medium',
      ),
    ),
    assessmentMethod: SatietyResult.modelMethod,
    satietyScore: 96,
    durationHours: 5.0,
    crashRisk: 'low',
    hybridUpgrade: HybridUpgrade(
      instantAdd: 'Top with 1 tbsp pumpkin seeds for zinc crunch.',
      smartSwap: 'Swap quinoa for mixed wild grains.',
      digestiveCatalyst: 'Take 3 calming belly breaths.',
    ),
  );

  const crashMeal = SatietyResult(
    mealName: 'Glazed Cinnamon Donut',
    components: ['Enriched Flour', 'Sugar Glaze', 'Palm Oil'],
    pillars: SatietyPillars(
      anchor: PillarDetail(detected: false, items: [], quality: 'low'),
      net: PillarDetail(detected: false, items: [], quality: 'low'),
      buffer: PillarDetail(
        detected: true,
        items: ['Frying Fat'],
        quality: 'low',
      ),
      spark: PillarDetail(detected: false, items: [], quality: 'low'),
    ),
    assessmentMethod: SatietyResult.modelMethod,
    satietyScore: 32,
    durationHours: 1.2,
    crashRisk: 'high',
    hybridUpgrade: HybridUpgrade(
      instantAdd: 'Pair with raw walnuts or a hardboiled egg.',
      smartSwap: 'Choose sourdough toast with nut butter next time.',
      digestiveCatalyst: 'Go for a light 10-minute walk post-meal.',
    ),
  );

  Widget createTestWidget(SatietyResult result, {String? imagePath}) {
    return MaterialApp(
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: EvenColors.darkBackground,
      ),
      home: PlateAnalysisScreen(
        result: result,
        imagePath: imagePath,
        storage: storage,
      ),
    );
  }

  Future<void> expandHowScored(WidgetTester tester) async {
    final tile = find.byKey(const ValueKey('btn_how_scored'));
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();
  }

  group('PlateAnalysisScreen & Satiety Horizon Widget Tests', () {
    testWidgets('Renders all balanced meal analysis components correctly', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createTestWidget(balancedMeal));
      await tester.pump();

      expect(find.text('Wild Salmon & Quinoa Harvest Bowl'), findsWidgets);
      expect(find.text('Wild Sockeye Salmon'), findsWidgets);
      expect(find.text('Tricolor Quinoa'), findsWidgets);
      expect(find.text('Hass Avocado'), findsWidgets);

      expect(find.byType(SatietyDurationClock), findsOneWidget);
      expect(find.text('96 / 100'), findsOneWidget);
      expect(find.text('Stable Energy Horizon'), findsNothing);
      expect(find.text('96 / 100'), findsOneWidget);
      expect(
        find.text('Protein, fiber, and fat are on this plate.'),
        findsOneWidget,
      );

      await expandHowScored(tester);

      expect(find.byType(CrashRiskHorizonGraph), findsNothing);
      expect(find.text('Stable Glucose & Satiety Plateau'), findsNothing);
      expect(find.text('LOW'), findsNothing);

      expect(find.byType(SatietyMatrixWidget), findsOneWidget);
      expect(find.text('4/4 Pillars Resonant'), findsOneWidget);

      expect(find.byType(UpgradeCard), findsOneWidget);
      expect(
        find.text('Top with 1 tbsp pumpkin seeds for zinc crunch.'),
        findsOneWidget,
      );
      expect(find.text('Swap quinoa for mixed wild grains.'), findsOneWidget);
      expect(find.text('Take 3 calming belly breaths.'), findsOneWidget);

      expect(find.text('On this plate'), findsOneWidget);
      expect(find.byKey(const ValueKey('add_detected_food')), findsOneWidget);

      expect(find.byKey(const ValueKey('btn_save_diary')), findsOneWidget);
      expect(find.text('Save this plate'), findsOneWidget);
      expect(find.byType(NutritionDisclaimer), findsOneWidget);
      expect(find.textContaining('not medical advice'), findsOneWidget);
    });

    testWidgets(
      'Renders high crash risk meal with appropriate warning horizon',
      (WidgetTester tester) async {
        await tester.pumpWidget(createTestWidget(crashMeal));
        await tester.pump();

        // Verify title & high crash risk horizon indicators
        expect(find.text('Glazed Cinnamon Donut'), findsWidgets);
        expect(find.text('High Crash Risk'), findsNothing);
        expect(find.text('32 / 100'), findsOneWidget);
        expect(find.text('32 / 100'), findsOneWidget);
        expect(find.text('Consider a protein food.'), findsOneWidget);

        await expandHowScored(tester);

        expect(find.text('HIGH'), findsNothing);
        expect(find.text('Spike & Precipitous Crash Risk'), findsNothing);
        expect(find.text('0/4 Pillars Aligned'), findsOneWidget);
      },
    );

    testWidgets('Interactive EvenUpgrade Coaching allows toggling actions', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createTestWidget(balancedMeal));
      await tester.pump();

      // Initial state
      final addBtn = find.text('I Added This');
      await tester.ensureVisible(addBtn);
      await tester.pumpAndSettle();
      expect(addBtn, findsOneWidget);

      // Tap Quick Add toggle
      await tester.tap(addBtn);
      await tester.pump(const Duration(milliseconds: 600));
      if (find.text('Allow analysis').evaluate().isNotEmpty) {
        await tester.tap(find.text('Allow analysis'));
        await tester.pumpAndSettle();
      }

      expect(find.text('Added'), findsOneWidget);
      expect(find.text('Upgraded'), findsOneWidget);

      // Tap Digestive Catalyst toggle
      final catalystBtn = find.text('Mark Done');
      await tester.ensureVisible(catalystBtn);
      await tester.pumpAndSettle();
      await tester.tap(catalystBtn);
      await tester.pumpAndSettle();

      expect(find.text('Done'), findsOneWidget);

      // Toggle Smart Swap expand icon
      final swapIcon = find.byIcon(Icons.keyboard_arrow_down_rounded);
      await tester.ensureVisible(swapIcon);
      await tester.pumpAndSettle();
      await tester.tap(swapIcon);
      await tester.pumpAndSettle();

      expect(find.text('A pairing idea for next time.'), findsOneWidget);
    });

    testWidgets(
      'Tapping Save to Diary stores meal log and displays confirmation',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  key: const ValueKey('btn_open'),
                  onPressed: () => Navigator.of(ctx).push(
                    MaterialPageRoute(
                      builder: (_) => PlateAnalysisScreen(
                        result: balancedMeal,
                        storage: storage,
                      ),
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        // Open PlateAnalysisScreen
        await tester.tap(find.byKey(const ValueKey('btn_open')));
        await tester.pumpAndSettle();

        expect(storage.meals.isEmpty, isTrue);

        // Tap Save this plate
        final saveBtn = find.byKey(const ValueKey('btn_save_diary'));
        await tester.ensureVisible(saveBtn);
        await tester.pumpAndSettle();
        await tester.tap(saveBtn);
        await tester.pumpAndSettle();

        // Verifies meal was logged to storage
        expect(storage.meals.length, 1);
        expect(
          storage.meals.first.mealName,
          'Wild Salmon & Quinoa Harvest Bowl',
        );
        expect(storage.meals.first.satietyResult.satietyScore, 96);

        // Verifies screen popped back to root
        expect(find.byKey(const ValueKey('btn_open')), findsOneWidget);

        // Verifies SnackBar feedback was displayed
        expect(find.text('Plate saved.'), findsOneWidget);
      },
    );

    testWidgets('Adding and removing foods refreshes the visible score', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final feast = SatietyResult.fromFoods(
        mealName: 'BBQ Spread',
        components: const ['Burger', 'Beer', 'Pizza', 'Potato chips'],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark().copyWith(
            scaffoldBackgroundColor: EvenColors.darkBackground,
          ),
          home: PlateAnalysisScreen(
            result: feast,
            storage: storage,
            animateSensory: false,
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('food_chip_beer')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('food_chip_potato chips')),
        findsOneWidget,
      );
      expect(find.text('${feast.satietyScore} / 100'), findsNothing);

      await tester.tap(find.byTooltip('Remove Potato chips'));
      await tester.pump();
      await tester.tap(find.byTooltip('Remove Beer'));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('food_chip_potato chips')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('food_chip_beer')), findsNothing);

      await tester.enterText(
        find.byKey(const ValueKey('add_detected_food')),
        'Side salad',
      );
      await tester.tap(find.byKey(const ValueKey('btn_add_food')));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('food_chip_side salad')),
        findsOneWidget,
      );
      expect(find.text('${feast.satietyScore} / 100'), findsNothing);
      expect(find.byKey(const ValueKey('btn_assess_plate')), findsOneWidget);
      expect(find.text('Assessing the complete plate...'), findsNothing);
    });
  });
}
