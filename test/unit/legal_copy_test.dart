import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evenplate/core/legal/legal_copy.dart';
import 'package:evenplate/core/legal/legal_document_screen.dart';

void main() {
  test('Privacy policy names the processors and forbids ad tracking', () {
    expect(LegalCopy.privacyBody, contains('Supabase'));
    expect(LegalCopy.privacyBody, contains('Gemini'));
    expect(LegalCopy.privacyBody, contains('RevenueCat'));
    expect(LegalCopy.privacyBody, contains('OneSignal'));
    expect(LegalCopy.privacyBody, contains('Sentry'));
    expect(LegalCopy.privacyBody, contains('do not sell personal data'));
  });

  test('Short disclaimer is not medical advice', () {
    expect(LegalCopy.shortDisclaimer.toLowerCase(), contains('not medical'));
    expect(
      LegalCopy.shortDisclaimer.toLowerCase(),
      contains('not a medical device'),
    );
  });

  testWidgets('Privacy document screen shows the policy body', (tester) async {
    await tester.pumpWidget(MaterialApp(home: LegalDocumentScreen.privacy()));
    await tester.pump();

    expect(find.text(LegalCopy.privacyTitle), findsOneWidget);
    expect(find.textContaining('What we collect'), findsOneWidget);
  });
}
