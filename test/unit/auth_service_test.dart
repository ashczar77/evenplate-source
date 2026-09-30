import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:evenplate/services/local_storage_service.dart';
import 'package:evenplate/services/revenuecat_service.dart';
import 'package:evenplate/services/supabase_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalStorageService storage;
  late RevenueCatService revenueCat;
  late SupabaseService supabase;

  setUp(() {
    storage = LocalStorageService();
    revenueCat = RevenueCatService(storage);
    supabase = SupabaseService(storage);
    supabase.setRevenueCatService(revenueCat);
  });

  group('SupabaseService Unit Tests', () {
    test(
      'Initializes cleanly without live network in unconfigured environment',
      () async {
        await supabase.init();
        expect(supabase.isInitialized, isTrue);
        expect(supabase.isAuthenticated, isFalse);
        expect(supabase.isAnonymous, isFalse);
        expect(supabase.currentAccessToken, isNull);
      },
    );

    test('RevenueCatService handles logIn and logOut without errors', () async {
      await revenueCat.init();
      // Verify aliasing methods do not throw
      await expectLater(revenueCat.logIn('test-user-uuid-123'), completes);
      await expectLater(revenueCat.logOut(), completes);
    });

    test('Anonymous sign-in completes with success in fallback mode', () async {
      await supabase.init();
      final result = await supabase.signInAnonymously();
      expect(result, isTrue);
      expect(supabase.errorMessage, isNull);
      expect(supabase.isLoading, isFalse);
      expect(supabase.isAuthenticated, isTrue);
    });

    test('Email sign-in completes with success in fallback mode', () async {
      await supabase.init();
      final result = await supabase.signInWithEmail(
        email: 'test@evenplate.app',
        password: 'securePassword123',
      );
      expect(result, isTrue);
    });

    test('An empty identities list means the email is already registered', () {
      final existing = User(
        id: 'existing',
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: '2026-01-01T00:00:00Z',
        identities: const [],
      );
      final unknown = User(
        id: 'unknown',
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: '2026-01-01T00:00:00Z',
      );

      expect(signupIsExistingAccount(existing), isTrue);
      expect(signupIsExistingAccount(unknown), isFalse);
      expect(signupIsExistingAccount(null), isFalse);
    });

    test('Email sign-up completes with success in fallback mode', () async {
      await supabase.init();
      final result = await supabase.signUpWithEmail(
        email: 'newuser@evenplate.app',
        password: 'securePassword123',
      );
      expect(result, EmailAuthOutcome.authenticated);
    });
  });

  // Release builds disable simulated auth. Without this an unconfigured build,
  // which is what .env.example produces, would accept any password.
  group('SupabaseService with simulated auth disabled', () {
    late SupabaseService release;

    setUp(() async {
      release = SupabaseService(storage, allowSimulatedAuth: false);
      release.setRevenueCatService(revenueCat);
      await release.init();
    });

    test('Initializes but reports nobody signed in', () {
      expect(release.isInitialized, isTrue);
      expect(release.isAuthenticated, isFalse);
      expect(release.currentAccessToken, isNull);
    });

    test('Email sign-in is refused rather than simulated', () async {
      final result = await release.signInWithEmail(
        email: 'test@evenplate.app',
        password: 'securePassword123',
      );

      expect(result, isFalse);
      expect(release.isAuthenticated, isFalse);
      expect(release.currentAccessToken, isNull);
      expect(release.errorMessage, isNotNull);
      expect(release.isLoading, isFalse);
    });

    test('Any password is refused, not just wrong ones', () async {
      for (final password in ['', 'x', 'hunter2', 'a' * 200]) {
        expect(
          await release.signInWithEmail(
            email: 'victim@evenplate.app',
            password: password,
          ),
          isFalse,
          reason: 'password "$password" must not authenticate',
        );
        expect(release.isAuthenticated, isFalse);
      }
    });

    test('Email sign-up is refused rather than simulated', () async {
      final result = await release.signUpWithEmail(
        email: 'newuser@evenplate.app',
        password: 'securePassword123',
      );

      expect(result, EmailAuthOutcome.failed);
      expect(release.isAuthenticated, isFalse);
      expect(release.errorMessage, isNotNull);
    });

    test('Anonymous sign-in is refused rather than simulated', () async {
      final result = await release.signInAnonymously();

      expect(result, isFalse);
      expect(release.isAuthenticated, isFalse);
      expect(release.isAnonymous, isFalse);
      expect(release.currentAccessToken, isNull);
    });

    test('A refused sign-in does not write a profile id', () async {
      final before = storage.userProfile.id;

      await release.signInWithEmail(
        email: 'test@evenplate.app',
        password: 'securePassword123',
      );

      expect(storage.userProfile.id, before);
    });

    test(
      'Promo redemption does not grant Pro without a live backend',
      () async {
        await storage.setProStatus(false);

        final empty = await release.redeemPromoCode('');
        expect(empty.redeemed, isFalse);
        expect(storage.userProfile.isPro, isFalse);

        final guess = await release.redeemPromoCode('SHIPATON2026');
        expect(guess.redeemed, isFalse);
        expect(storage.userProfile.isPro, isFalse);
      },
    );
  });
}
