import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evenplate/services/local_storage_service.dart';
import 'package:evenplate/widgets/analysis_consent_prompt.dart';

void main() {
  testWidgets(
    'consent is saved and not requested again; declining grants nothing',
    (tester) async {
      final storage = LocalStorageService();
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await AnalysisConsentPrompt.ensure(context, storage);
                },
                child: const Text('Analyze'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Analyze'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(OutlinedButton, 'Not now'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Allow analysis'),
        findsOneWidget,
      );
      final cancel = tester.getRect(
        find.widgetWithText(OutlinedButton, 'Not now'),
      );
      final allow = tester.getRect(
        find.widgetWithText(FilledButton, 'Allow analysis'),
      );
      expect(cancel.left, allow.left);
      expect(cancel.width, allow.width);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
      expect(storage.analysisConsentGranted, isFalse);
      await tester.tap(find.text('Analyze'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Allow analysis'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
      expect(storage.analysisConsentGranted, isTrue);
      await tester.tap(find.text('Analyze'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await storage.setAnalysisConsent(false);
      await tester.tap(find.text('Analyze'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
    },
  );
}
