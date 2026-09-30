import 'package:flutter_test/flutter_test.dart';
import 'package:evenplate/core/security/app_secrets.dart';
import 'package:evenplate/core/security/config_guard.dart';

// The suite runs without --dart-define-from-file, so AppSecrets falls back to
// its placeholder defaults. That is what these tests assert against.
void main() {
  group('AppSecrets placeholder detection', () {
    test('reports mock Supabase configuration', () {
      expect(AppSecrets.usesMockSupabase, isTrue);
    });

    test('reports mock RevenueCat configuration', () {
      expect(AppSecrets.usesMockRevenueCat, isTrue);
    });

    test('lists keys required by the current platform', () {
      expect(
        AppSecrets.placeholders(),
        containsAll(<String>[
          'SUPABASE_URL',
          'SUPABASE_ANON_KEY',
          'REVENUECAT_GOOGLE_KEY',
          'ONESIGNAL_APP_ID',
        ]),
      );
    });

    test('entitlement identifier matches the RevenueCat dashboard value', () {
      expect(AppSecrets.revenueCatEntitlement, 'evenplate_pro');
    });

    test('backend URL falls back to being derived from the Supabase URL', () {
      expect(AppSecrets.backendEndpointUrl, isEmpty);
    });
  });

  // .env.example ships every key blank, so a build made straight from the
  // template must be reported as unconfigured. Comparing only against the mock
  // sentinel let a blank value pass as real.
  group('AppSecrets.isPlaceholder', () {
    const mock = AppSecrets.mockSupabaseUrl;

    test('an empty value is a placeholder', () {
      expect(AppSecrets.isPlaceholder('', mock), isTrue);
    });

    test('a whitespace only value is a placeholder', () {
      expect(AppSecrets.isPlaceholder('   ', mock), isTrue);
      expect(AppSecrets.isPlaceholder('\n\t', mock), isTrue);
    });

    test('the mock sentinel is a placeholder', () {
      expect(AppSecrets.isPlaceholder(mock, mock), isTrue);
    });

    test('a real value is not a placeholder', () {
      expect(
        AppSecrets.isPlaceholder(
          'https://dioynjwmaehzpsctlioj.supabase.co',
          mock,
        ),
        isFalse,
      );
    });
  });

  group('ConfigGuard', () {
    test('warns instead of throwing outside release builds', () {
      expect(ConfigGuard.assertConfigured, returnsNormally);
    });
  });
}
