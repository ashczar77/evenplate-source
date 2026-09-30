import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evenplate/core/theme/even_colors.dart';
import 'package:evenplate/core/utils/sensory_feedback.dart';
import 'package:evenplate/models/satiety_matrix.dart';
import 'package:evenplate/widgets/crash_risk_horizon_graph.dart';
import 'package:evenplate/widgets/satiety_matrix_widget.dart';
import 'package:evenplate/widgets/zen_bloom_overlay.dart';

void main() {
  const fullPillars = SatietyPillars(
    anchor: PillarDetail(
      detected: true,
      items: ['Grass-fed Bison'],
      quality: 'high',
    ),
    net: PillarDetail(
      detected: true,
      items: ['Roasted Asparagus'],
      quality: 'high',
    ),
    buffer: PillarDetail(
      detected: true,
      items: ['Extra Virgin Olive Oil'],
      quality: 'high',
    ),
    spark: PillarDetail(detected: true, items: ['Lemon Zest'], quality: 'high'),
  );

  const partialPillars = SatietyPillars(
    anchor: PillarDetail(
      detected: true,
      items: ['Grilled Chicken'],
      quality: 'high',
    ),
    net: PillarDetail(detected: false, items: [], quality: 'low'),
    buffer: PillarDetail(detected: true, items: ['Avocado'], quality: 'medium'),
    spark: PillarDetail(detected: false, items: [], quality: 'low'),
  );

  group('SensoryFeedback Haptics Utility Tests', () {
    test(
      'All tactile feedback methods execute gracefully without throwing',
      () async {
        await expectLater(SensoryFeedback.resonanceSnap(), completes);
        await expectLater(SensoryFeedback.zenBloomPulse(), completes);
        await expectLater(SensoryFeedback.gentleTap(), completes);
        await expectLater(SensoryFeedback.softWarning(), completes);
      },
    );
  });

  group('SatietyMatrixWidget Magnetic Resonance Tests', () {
    testWidgets('Renders full matrix with 4/4 Pillars Resonant and lock icon', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SatietyMatrixWidget(
                pillars: fullPillars,
                animateOnMount: true,
              ),
            ),
          ),
        ),
      );

      // Advance animation through the spring curve
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 550));

      expect(find.text('The Satiety Matrix'), findsOneWidget);
      expect(find.text('4/4 Pillars Resonant'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
      expect(find.text('Grass-fed Bison'), findsOneWidget);
      expect(find.text('Roasted Asparagus'), findsOneWidget);
    });

    testWidgets(
      'Renders partial matrix with Aligned badge and unchecked state',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: SatietyMatrixWidget(
                  pillars: partialPillars,
                  animateOnMount: false,
                ),
              ),
            ),
          ),
        );

        await tester.pump();

        expect(find.text('2/4 Pillars Aligned'), findsOneWidget);
        expect(find.byIcon(Icons.lock_outline_rounded), findsNothing);
        expect(find.text('Grilled Chicken'), findsOneWidget);
      },
    );
  });

  testWidgets(
    'legacy graph callers cannot display glucose or hours predictions',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CrashRiskHorizonGraph(
              durationHours: 4.8,
              crashRisk: 'high',
              satietyScore: 92,
            ),
          ),
        ),
      );
      expect(find.textContaining('Your own energy check-ins'), findsOneWidget);
      expect(find.text('Crash Risk Horizon'), findsNothing);
      expect(find.text('4.8h (Full)'), findsNothing);
    },
  );

  group('ZenBloomOverlay Celebration Tests', () {
    testWidgets(
      'Renders bioluminescent mandala, meal summary, and dismisses on tap',
      (WidgetTester tester) async {
        bool completed = false;

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark().copyWith(
              scaffoldBackgroundColor: EvenColors.darkBackground,
            ),
            home: Scaffold(
              body: ZenBloomOverlay(
                mealName: 'Atlantic Cod & Lentil Bowl',
                durationHours: 4.5,
                pillarsAligned: 4,
                animate: true,
                autoDismiss: false,
                onComplete: () {
                  completed = true;
                },
              ),
            ),
          ),
        );

        // Advance entrance animation
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 800));

        expect(find.byKey(const ValueKey('zen_bloom_overlay')), findsOneWidget);
        expect(find.text('Plate Harmonized'), findsOneWidget);
        expect(find.text('Atlantic Cod & Lentil Bowl'), findsOneWidget);
        expect(find.text('Plate saved to your diary'), findsOneWidget);
        expect(find.text('4/4 Pillars Locked in Equilibrium'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('btn_zen_bloom_done')),
          findsOneWidget,
        );

        // Tap Done button
        await tester.tap(find.byKey(const ValueKey('btn_zen_bloom_done')));
        await tester.pump();

        expect(completed, isTrue);
      },
    );

    testWidgets('Auto-dismiss triggers onComplete upon animation completion', (
      WidgetTester tester,
    ) async {
      bool completed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ZenBloomOverlay(
              mealName: 'Tofu Greens Warm Salad',
              durationHours: 3.8,
              pillarsAligned: 3,
              animate: true,
              autoDismiss: true,
              onComplete: () {
                completed = true;
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(completed, isTrue);
    });
  });
}
