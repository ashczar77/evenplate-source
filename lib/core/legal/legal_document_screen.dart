import 'package:flutter/material.dart';
import '../theme/even_colors.dart';
import 'legal_copy.dart';

class LegalDocumentScreen extends StatelessWidget {
  final String title;
  final String body;

  const LegalDocumentScreen({
    super.key,
    required this.title,
    required this.body,
  });

  factory LegalDocumentScreen.privacy() => const LegalDocumentScreen(
    title: LegalCopy.privacyTitle,
    body: LegalCopy.privacyBody,
  );

  factory LegalDocumentScreen.terms() => const LegalDocumentScreen(
    title: LegalCopy.termsTitle,
    body: LegalCopy.termsBody,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Text(
            body,
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              color: Theme.of(context).brightness == Brightness.dark
                  ? EvenColors.textDarkSecondary
                  : EvenColors.textLightSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
