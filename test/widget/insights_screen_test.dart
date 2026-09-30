import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evenplate/features/insights/insights_screen.dart';
import 'package:evenplate/models/meal_log.dart';
import 'package:evenplate/models/satiety_matrix.dart';
import 'package:evenplate/services/local_storage_service.dart';

MealLog _plate({
  required String id,
  required String name,
  required DateTime when,
  bool protein = true,
}) {
  return MealLog(
    id: id,
    mealName: name,
    timestamp: when,
    satietyResult: SatietyResult(
      mealName: name,
      components: const ['item'],
      pillars: SatietyPillars(
        anchor: PillarDetail(
          detected: protein,
          items: protein ? const ['Eggs'] : const [],
          quality: 'high',
        ),
        net: const PillarDetail(
          detected: true,
          items: ['Greens'],
          quality: 'high',
        ),
        buffer: const PillarDetail(
          detected: true,
          items: ['Avocado'],
          quality: 'high',
        ),
        spark: const PillarDetail(
          detected: true,
          items: ['Crunch'],
          quality: 'medium',
        ),
      ),
      satietyScore: protein ? 88 : 42,
      durationHours: 3.5,
      crashRisk: 'low',
      hybridUpgrade: const HybridUpgrade(
        instantAdd: 'Add seeds.',
        smartSwap: 'Keep it.',
        digestiveCatalyst: 'Sip water.',
      ),
    ),
  );
}

void main() {
  testWidgets('Range chips and tappable plates open an editable plate', (
    tester,
  ) async {
    final storage = LocalStorageService();
    final now = DateTime.now();
    await storage.addMealLog(
      _plate(id: 'today-meal', name: 'Salmon bowl', when: now, protein: false),
    );
    await storage.addMealLog(
      _plate(
        id: 'old-meal',
        name: 'Old stew',
        when: now.subtract(const Duration(days: 20)),
      ),
    );
    await storage.addMealLog(
      _plate(
        id: 'ancient-meal',
        name: 'Ancient soup',
        when: now.subtract(const Duration(days: 40)),
      ),
    );

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(home: InsightsScreen(storage: storage)),
    );
    await tester.pumpAndSettle();

    expect(find.text('7 days'), findsOneWidget);
    expect(find.text('30 days'), findsOneWidget);
    expect(find.textContaining('of 1 plate this week'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Salmon bowl'),
      200,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('Salmon bowl'), findsWidgets);
    expect(find.text('Old stew'), findsNothing);
    expect(find.text('Ancient soup'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('chip_insights_month')));
    await tester.pumpAndSettle();
    expect(find.text('Old stew'), findsOneWidget);
    expect(find.text('Ancient soup'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('pillar_protein')));
    await tester.pumpAndSettle();
    expect(find.text('Missed protein'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('insight_meal_today-meal')));
    await tester.pumpAndSettle();
    expect(find.text('Edit plate'), findsOneWidget);
    expect(find.text('Update this plate'), findsOneWidget);
  });

  testWidgets('Week and month plate lists start at 6 and page in more', (
    tester,
  ) async {
    final storage = LocalStorageService();
    final now = DateTime.now();
    for (var i = 1; i <= 8; i++) {
      await storage.addMealLog(
        _plate(
          id: 'week-$i',
          name: 'Week plate $i',
          when: now.subtract(Duration(hours: i)),
        ),
      );
    }
    for (var i = 1; i <= 4; i++) {
      await storage.addMealLog(
        _plate(
          id: 'month-$i',
          name: 'Month plate $i',
          when: now.subtract(Duration(days: 10 + i)),
        ),
      );
    }

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(home: InsightsScreen(storage: storage)),
    );
    await tester.pumpAndSettle();

    Future<void> reveal(Finder finder) {
      return tester.scrollUntilVisible(
        finder,
        240,
        scrollable: find.byType(Scrollable),
      );
    }

    await reveal(find.byKey(const ValueKey('btn_insights_show_more')));
    expect(find.text('Week plate 1'), findsOneWidget);
    expect(find.text('Week plate 6'), findsOneWidget);
    expect(find.text('Week plate 7'), findsNothing);
    expect(find.text('Week plate 8'), findsNothing);
    expect(find.text('Show 2 more'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('btn_insights_show_more')));
    await tester.pumpAndSettle();
    await reveal(find.text('Week plate 8'));
    expect(find.text('Week plate 7'), findsOneWidget);
    expect(find.text('Week plate 8'), findsOneWidget);
    expect(find.text('Show less'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('chip_insights_month')));
    await tester.pumpAndSettle();
    await reveal(find.byKey(const ValueKey('btn_insights_show_more')));
    expect(find.text('Week plate 1'), findsOneWidget);
    expect(find.text('Week plate 6'), findsOneWidget);
    expect(find.text('Week plate 7'), findsNothing);
    expect(find.text('Month plate 1'), findsNothing);
    expect(find.text('Show 6 more'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('btn_insights_show_more')));
    await tester.pumpAndSettle();
    await reveal(find.text('Month plate 4'));
    expect(find.text('Week plate 7'), findsOneWidget);
    expect(find.text('Month plate 1'), findsOneWidget);
    expect(find.text('Month plate 4'), findsOneWidget);
    expect(find.text('Show less'), findsOneWidget);
  });
}
