import 'package:flutter/material.dart';
import '../core/legal/legal_document_screen.dart';
import '../services/local_storage_service.dart';

class AnalysisConsentPrompt {
  static Future<bool> ensure(
    BuildContext context,
    LocalStorageService storage,
  ) async {
    if (storage.analysisConsentGranted) return true;
    final owner = storage.userProfile.id;
    final agreed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Allow meal analysis?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Photos and typed foods you choose to analyze are sent through Supabase to Google Gemini. Avoid photos containing people or private information. You can withdraw permission in Settings and view saved meals and reuse cached assessments. This choice is saved for your account on this device.',
            ),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => LegalDocumentScreen.privacy(),
                ),
              ),
              child: const Text('Privacy Policy'),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Allow analysis'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Not now'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (agreed != true || storage.userProfile.id != owner) return false;
    await storage.setAnalysisConsent(true);
    return true;
  }
}
