import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evenplate/core/a11y/access.dart';
import 'package:evenplate/core/theme/even_theme.dart';
import 'package:evenplate/features/meals/manual_meal_sheet.dart';
import 'package:evenplate/features/scan/plate_analysis_screen.dart';
import 'package:evenplate/models/satiety_matrix.dart';
import 'package:evenplate/services/local_storage_service.dart';
import 'package:evenplate/widgets/harmony_rings_widget.dart';

const _balanced = SatietyResult(
  mealName: 'Wild Salmon Bowl',
  components: ['Salmon'],
  pillars: SatietyPillars(
    anchor: PillarDetail(detected: true, items: ['Salmon'], quality: 'high'),
    net: PillarDetail(detected: true, items: ['Greens'], quality: 'high'),
    buffer: PillarDetail(detected: true, items: ['Avocado'], quality: 'high'),
    spark: PillarDetail(detected: true, items: ['Lemon'], quality: 'medium'),
  ),
  satietyScore: 90,
  durationHours: 4.5,
  crashRisk: 'low',
  hybridUpgrade: HybridUpgrade(
    instantAdd: 'Add seeds.',
    smartSwap: 'Keep it.',
    digestiveCatalyst: 'Sip water.',
  ),
);

void main() {
  test('clampedTextScaler caps at 1.5', () {
    final scaled = clampedTextScaler(const TextScaler.linear(2.4));
    expect(scaled.scale(10), 15);
  });

  test('isIosSimulator is false on the host test VM', () {
    expect(isIosSimulator, isFalse);
  });

  testWidgets('useBackdropBlur is off when animations are disabled', (
    WidgetTester tester,
  ) async {
    late bool allowed;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Builder(
          builder: (context) {
            allowed = useBackdropBlur(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(allowed, isFalse);
  });

  test('SatietyResult.manual derives score from pillars', () {
    final result = SatietyResult.manual(
      mealName: 'Toast',
      pillars: const SatietyPillars(
        anchor: PillarDetail(
          detected: true,
          items: ['Eggs'],
          quality: 'medium',
        ),
        net: PillarDetail(detected: false, items: [], quality: 'low'),
        buffer: PillarDetail(detected: false, items: [], quality: 'low'),
        spark: PillarDetail(detected: false, items: [], quality: 'low'),
      ),
      durationHours: 2,
      crashRisk: 'moderate',
    );
    expect(result.satietyScore, 0);
    expect(result.durationHours, 0);
  });

  testWidgets('Harmony rings expose a spoken label', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HarmonyRingsWidget(
            anchorProgress: 0.5,
            netProgress: 0.25,
            horizonProgress: 1,
            interactive: false,
          ),
        ),
      ),
    );
    expect(find.bySemanticsLabel(RegExp('Harmony rings')), findsOneWidget);
  });

  testWidgets('Manual meal sheet saves without a photo', (tester) async {
    final storage = LocalStorageService();
    await tester.pumpWidget(
      MaterialApp(
        theme: EvenTheme.darkTheme,
        home: Scaffold(body: ManualMealSheet(storage: storage)),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('manual_meal_name')),
      'Oats',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('btn_save_manual_meal')));
    await tester.pumpAndSettle();

    expect(storage.meals, hasLength(1));
    expect(storage.meals.first.mealName, 'Oats');
    expect(storage.meals.first.imagePath, isNull);
  });

  testWidgets('Plate analysis keeps an edited name on save', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final storage = LocalStorageService();
    await tester.pumpWidget(
      MaterialApp(
        theme: EvenTheme.darkTheme,
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              key: const ValueKey('btn_open'),
              onPressed: () => Navigator.of(ctx).push(
                MaterialPageRoute(
                  builder: (_) => PlateAnalysisScreen(
                    result: _balanced,
                    storage: storage,
                    animateSensory: false,
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('btn_open')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('edit_meal_name')),
      'Edited Bowl',
    );
    await tester.pump();

    final saveBtn = find.byKey(const ValueKey('btn_save_diary'));
    await tester.ensureVisible(saveBtn);
    await tester.tap(saveBtn);
    await tester.pumpAndSettle();

    expect(storage.meals, hasLength(1));
    expect(storage.meals.first.mealName, 'Edited Bowl');
  });
}
