import 'dart:io';
import 'package:flutter/foundation.dart';

/// Build time configuration, injected with --dart-define.
///
/// Values are supplied from a local .env file:
///   flutter run --dart-define-from-file=.env
///
/// Note that --dart-define is injection, not obfuscation: every value here is
/// recoverable from a release binary. Only publishable keys belong in this file.
/// Server side secrets (the Gemini key, the RevenueCat webhook secret) live as
/// Supabase function secrets and must never appear here.
class AppSecrets {
  AppSecrets._();

  static const String mockSupabaseUrl = 'https://mock.supabase.co';
  static const String mockSupabaseAnonKey = 'mock-anon-key';
  static const String mockRevenueCatAppleKey = 'appl_mock_sandbox_key';
  static const String mockRevenueCatGoogleKey = 'goog_mock_sandbox_key';

  static const String revenueCatAppleKey = String.fromEnvironment(
    'REVENUECAT_APPLE_KEY',
    defaultValue: mockRevenueCatAppleKey,
  );

  static const String revenueCatGoogleKey = String.fromEnvironment(
    'REVENUECAT_GOOGLE_KEY',
    defaultValue: mockRevenueCatGoogleKey,
  );

  static const String oneSignalAppId = String.fromEnvironment(
    'ONESIGNAL_APP_ID',
    defaultValue: '',
  );

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: mockSupabaseUrl,
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: mockSupabaseAnonKey,
  );

  /// Optional override for the functions base URL. When empty the URL is
  /// derived from [supabaseUrl].
  static const String backendEndpointUrl = String.fromEnvironment(
    'BACKEND_ENDPOINT_URL',
    defaultValue: '',
  );

  /// Sentry ingest URL. Blank leaves crash and feature reporting off.
  static const String sentryDsn = String.fromEnvironment(
    'SENTRY_DSN',
    defaultValue: '',
  );

  static const String revenueCatEntitlement = 'evenplate_pro';

  /// Whether a value still needs configuring. Blank counts as unconfigured:
  /// .env.example ships every key empty, so comparing only against the mock
  /// sentinel would let a build made straight from the template pass as real.
  @visibleForTesting
  static bool isPlaceholder(String value, String mockValue) =>
      value.trim().isEmpty || value == mockValue;

  static bool get usesMockSupabase =>
      isPlaceholder(supabaseUrl, mockSupabaseUrl) ||
      isPlaceholder(supabaseAnonKey, mockSupabaseAnonKey);

  static bool get usesMockRevenueCat =>
      isPlaceholder(revenueCatAppleKey, mockRevenueCatAppleKey) ||
      isPlaceholder(revenueCatGoogleKey, mockRevenueCatGoogleKey);

  /// Configuration that is still on a placeholder. Empty means fully wired.
  static List<String> placeholders() {
    return [
      if (isPlaceholder(supabaseUrl, mockSupabaseUrl)) 'SUPABASE_URL',
      if (isPlaceholder(supabaseAnonKey, mockSupabaseAnonKey))
        'SUPABASE_ANON_KEY',
      if (Platform.isIOS &&
          isPlaceholder(revenueCatAppleKey, mockRevenueCatAppleKey))
        'REVENUECAT_APPLE_KEY',
      if (!Platform.isIOS &&
          isPlaceholder(revenueCatGoogleKey, mockRevenueCatGoogleKey))
        'REVENUECAT_GOOGLE_KEY',
      if (oneSignalAppId.trim().isEmpty) 'ONESIGNAL_APP_ID',
    ];
  }
}
