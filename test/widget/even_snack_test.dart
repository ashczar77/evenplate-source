import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evenplate/core/theme/even_colors.dart';
import 'package:evenplate/core/theme/even_theme.dart';
import 'package:evenplate/widgets/even_notice.dart';
import 'package:evenplate/widgets/even_snack.dart';

void main() {
  testWidgets('Snackbars use white copy on the elevated dark mint bar', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: EvenTheme.darkTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () {
                  EvenSnack.show(
                    context,
                    'Purchases restored successfully. Pro unlocked.',
                    icon: Icons.check_circle_rounded,
                  );
                },
                child: const Text('show'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('show'));
    await tester.pump();

    expect(
      find.text('Purchases restored successfully. Pro unlocked.'),
      findsOneWidget,
    );
    final snackTheme = Theme.of(
      tester.element(find.byType(SnackBar)),
    ).snackBarTheme;
    expect(snackTheme.backgroundColor, EvenColors.darkSurfaceElevated);
    expect(snackTheme.contentTextStyle?.color, EvenColors.textDarkPrimary);
    expect(snackTheme.behavior, SnackBarBehavior.floating);
  });

  testWidgets('Notice cards use the same dark bar and white copy', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EvenNotice(
            message: 'Check your email to confirm this account.',
            icon: Icons.mark_email_read_outlined,
            accent: EvenColors.netSageLight,
          ),
        ),
      ),
    );

    final box = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(EvenNotice),
            matching: find.byType(Container),
          )
          .first,
    );
    final decoration = box.decoration as BoxDecoration;
    expect(decoration.color, EvenColors.darkSurfaceElevated);
    expect(decoration.borderRadius, BorderRadius.circular(16));

    final text = tester.widget<Text>(
      find.text('Check your email to confirm this account.'),
    );
    expect(text.style?.color, EvenColors.textDarkPrimary);
  });
}
