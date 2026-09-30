import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evenplate/widgets/meal_thumb.dart';

void main() {
  testWidgets('shows a centered circular mark when no photo is on disk', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: MealThumb(imagePath: null))),
    );

    expect(find.byIcon(Icons.restaurant_rounded), findsOneWidget);
    expect(find.byType(Image), findsNothing);

    final box = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byType(MealThumb),
        matching: find.byType(DecoratedBox),
      ),
    );
    final decoration = box.decoration as BoxDecoration;
    expect(decoration.shape, BoxShape.circle);

    final thumb = tester.getRect(find.byType(MealThumb));
    final icon = tester.getRect(find.byIcon(Icons.restaurant_rounded));
    expect((thumb.center - icon.center).distance, lessThan(0.6));
    expect(thumb.width, thumb.height);
  });
}
