import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evenplate/widgets/satiety_engine_widget.dart';

void main() {
  testWidgets('Chambers stay aligned with no percent or count labels', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SatietyEngineWidget(
            proteinProgress: 1.5,
            fiberProgress: 0.66,
            fatsProgress: 0,
            carbsProgress: 1,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('%'), findsNothing);
    expect(find.text('2/3'), findsNothing);
    expect(find.text('+2'), findsNothing);
    expect(find.text('PROTEIN'), findsOneWidget);
    expect(find.text('FIBER'), findsOneWidget);
    expect(find.text('FAT'), findsOneWidget);
    expect(find.text('VOLUME'), findsOneWidget);
  });
}
