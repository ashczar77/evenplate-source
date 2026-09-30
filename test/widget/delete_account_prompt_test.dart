import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evenplate/core/theme/even_theme.dart';
import 'package:evenplate/widgets/delete_account_prompt.dart';

void main() {
  testWidgets('Delete stays off until the user types DELETE', (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: EvenTheme.darkTheme,
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () async {
                result = await DeleteAccountPrompt.confirm(context);
              },
              child: const Text('open'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final delete = find.widgetWithText(ElevatedButton, 'Delete permanently');
    expect(tester.widget<ElevatedButton>(delete).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'DELETE');
    await tester.pump();
    expect(tester.widget<ElevatedButton>(delete).onPressed, isNotNull);

    await tester.tap(delete);
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('Cancel leaves the account in place', (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: EvenTheme.darkTheme,
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () async {
                result = await DeleteAccountPrompt.confirm(context);
              },
              child: const Text('open'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });
}
