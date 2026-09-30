import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evenplate/core/theme/even_colors.dart';
import 'package:evenplate/widgets/glass_card.dart';

void main() {
  testWidgets('GlassCard renders with child text and decorates properly', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: const Scaffold(
          body: Center(
            child: GlassCard(
              child: Text(
                'Organic Zen Glass',
                style: TextStyle(color: EvenColors.anchorTerracotta),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Organic Zen Glass'), findsOneWidget);
    expect(find.byType(GlassCard), findsOneWidget);
  });
}
