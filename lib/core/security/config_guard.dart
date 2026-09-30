import 'package:flutter/foundation.dart';
import 'app_secrets.dart';

/// Fails fast when a release build was compiled without real configuration.
///
/// Without this a release build silently falls back to the mock Supabase host,
/// which looks like a network outage at runtime rather than a build mistake.
class ConfigGuard {
  ConfigGuard._();

  static const String _runHint =
      'Pass configuration at build time: --dart-define-from-file=.env '
      '(copy .env.example to .env first).';

  /// Throws in release builds if required configuration is missing, and warns
  /// in debug builds so local runs against mocks stay possible.
  static void assertConfigured() {
    final missing = AppSecrets.placeholders();
    if (missing.isEmpty) return;

    final summary = missing.join(', ');

    if (kReleaseMode) {
      throw StateError(
        'EvenPlate is not configured for release. Still on placeholder '
        'values: $summary. $_runHint',
      );
    }

    debugPrint(
      'WARNING: running with placeholder configuration: $summary. $_runHint',
    );
  }
}
