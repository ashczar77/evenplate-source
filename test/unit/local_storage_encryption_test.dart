import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:evenplate/core/security/hive_key_store.dart';
import 'package:evenplate/models/meal_log.dart';
import 'package:evenplate/models/satiety_matrix.dart';
import 'package:evenplate/models/user_profile.dart';
import 'package:evenplate/services/local_storage_service.dart';
import 'package:evenplate/services/meal_photo_store.dart';

const _canary = 'EVENPLATE_SECRET_MEAL_CANARY_7QK2';

final _sampleResult = SatietyResult(
  mealName: _canary,
  components: const ['Canary Bean'],
  pillars: const SatietyPillars(
    anchor: PillarDetail(
      detected: true,
      items: ['Canary Bean'],
      quality: 'high',
    ),
    net: PillarDetail(detected: false, items: [], quality: 'low'),
    buffer: PillarDetail(detected: false, items: [], quality: 'low'),
    spark: PillarDetail(detected: false, items: [], quality: 'low'),
  ),
  satietyScore: 70,
  durationHours: 3,
  crashRisk: 'low',
  hybridUpgrade: const HybridUpgrade(
    instantAdd: 'Add greens.',
    smartSwap: 'Keep it simple.',
    digestiveCatalyst: 'Sip water.',
  ),
);

MealLog _canaryMeal({
  String id = 'meal-canary',
  DateTime? timestamp,
  String userId = '',
}) => MealLog(
  id: id,
  userId: userId,
  mealName: _canary,
  timestamp: timestamp ?? DateTime.now().toUtc(),
  satietyResult: _sampleResult,
);

void main() {
  late Directory dir;
  late MemoryHiveKeyStore keys;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('evenplate_hive_');
    keys = MemoryHiveKeyStore();
  });

  tearDown(() async {
    await Hive.close();
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
  });

  test('Persisted meals reopen under the same key', () async {
    final first = LocalStorageService(keyStore: keys);
    await first.init(hivePath: dir.path);
    await first.addMealLog(_canaryMeal());
    await Hive.close();

    final second = LocalStorageService(keyStore: keys);
    await second.init(hivePath: dir.path);

    expect(second.meals, hasLength(1));
    expect(second.meals.first.mealName, _canary);
  });

  test('Hive files on disk do not contain meal plaintext', () async {
    final storage = LocalStorageService(keyStore: keys);
    await storage.init(hivePath: dir.path);
    await storage.addMealLog(_canaryMeal());
    await Hive.close();

    final files = dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => !f.path.endsWith('.lock'));
    expect(files, isNotEmpty, reason: 'Hive should have written box files');

    for (final file in files) {
      final contents = file.readAsStringSync(encoding: latin1);
      expect(
        contents.contains(_canary),
        isFalse,
        reason: 'plaintext leaked into ${file.path}',
      );
    }
  });

  test('A plaintext box from before encryption is migrated', () async {
    Hive.init(dir.path);
    final legacy = await Hive.openBox<String>('evenplate_meals_box');
    await legacy.put('meal-canary', jsonEncode(_canaryMeal().toJson()));
    await legacy.close();

    final storage = LocalStorageService(keyStore: keys);
    await storage.init(hivePath: dir.path);

    expect(storage.meals, hasLength(1));
    expect(storage.meals.first.mealName, _canary);
    expect(await Hive.boxExists('evenplate_meals_box'), isFalse);
    await Hive.close();

    final files = dir.listSync(recursive: true).whereType<File>();
    for (final file in files) {
      final contents = file.readAsStringSync(encoding: latin1);
      expect(contents.contains(_canary), isFalse);
    }
  });

  test('A lost key recreates empty boxes instead of crashing', () async {
    final first = LocalStorageService(keyStore: keys);
    await first.init(hivePath: dir.path);
    await first.addMealLog(_canaryMeal());
    await Hive.close();

    final rotated = MemoryHiveKeyStore(stored: Hive.generateSecureKey());
    final second = LocalStorageService(keyStore: rotated);
    await second.init(hivePath: dir.path);

    expect(second.meals, isEmpty);
  });

  test(
    'Signing back into the same email keeps the questionnaire done',
    () async {
      final storage = LocalStorageService(keyStore: keys);
      await storage.init(hivePath: dir.path);
      await storage.adoptAccount(userId: 'auth-id', email: 'a@evenplate.app');
      await storage.saveUserProfile(
        storage.userProfile.copyWith(
          id: 'phone-session',
          hasCompletedOnboarding: true,
        ),
      );

      await storage.adoptAccount(userId: 'auth-id', email: 'a@evenplate.app');

      expect(storage.userProfile.hasCompletedOnboarding, isTrue);

      await storage.adoptAccount(
        userId: 'other-person',
        email: 'b@evenplate.app',
      );
      expect(storage.userProfile.hasCompletedOnboarding, isFalse);
    },
  );

  test('The same account keeps meals after sign-out and sign-in', () async {
    final storage = LocalStorageService(keyStore: keys);
    await storage.init(hivePath: dir.path);
    await storage.adoptAccount(userId: 'user-a', email: 'a@evenplate.app');
    await storage.addMealLog(_canaryMeal());

    await storage.adoptAccount(userId: 'user-a', email: 'a@evenplate.app');

    expect(storage.meals, hasLength(1));
    expect(storage.meals.first.mealName, _canary);
  });

  test(
    'Remote plates merge without duplicating a plate already on the phone',
    () async {
      final storage = LocalStorageService(keyStore: keys);
      await storage.init(hivePath: dir.path);
      await storage.addMealLog(_canaryMeal());

      final added = await storage.mergeRemoteMeals([
        _canaryMeal(),
        MealLog(
          id: 'meal-remote',
          mealName: 'Remote Bowl',
          timestamp: DateTime.utc(2026, 9, 24, 12),
          satietyResult: _sampleResult,
        ),
      ]);

      expect(added, 1);
      expect(storage.meals, hasLength(2));
    },
  );

  test('A different account does not inherit meals', () async {
    final storage = LocalStorageService(keyStore: keys);
    await storage.init(hivePath: dir.path);
    await storage.adoptAccount(userId: 'user-a', email: 'a@evenplate.app');
    await storage.addMealLog(_canaryMeal());

    await storage.adoptAccount(userId: 'user-b', email: 'b@evenplate.app');

    expect(storage.meals, isEmpty);
    expect(storage.userProfile.id, 'user-b');
  });

  test('Switching back to an account restores its meals', () async {
    final storage = LocalStorageService(keyStore: keys);
    await storage.init(hivePath: dir.path);
    await storage.adoptAccount(userId: 'user-a', email: 'a@evenplate.app');
    await storage.addMealLog(_canaryMeal(id: 'a-1'));
    await storage.adoptAccount(userId: 'user-b', email: 'b@evenplate.app');
    await storage.addMealLog(
      MealLog(
        id: 'b-1',
        mealName: 'B Bowl',
        timestamp: DateTime.now().toUtc(),
        satietyResult: _sampleResult,
      ),
    );

    await storage.adoptAccount(userId: 'user-a', email: 'a@evenplate.app');

    expect(storage.meals, hasLength(1));
    expect(storage.meals.first.id, 'a-1');
    expect(storage.userProfile.email, 'a@evenplate.app');
  });

  test(
    'First sign-in keeps plates logged before an account id existed',
    () async {
      final storage = LocalStorageService(keyStore: keys);
      await storage.init(hivePath: dir.path);
      await storage.addMealLog(_canaryMeal());

      await storage.adoptAccount(userId: 'user-a', email: 'a@evenplate.app');

      expect(storage.meals, hasLength(1));
      expect(storage.meals.first.userId, 'user-a');
    },
  );

  test('Plates older than 30 days are dropped', () async {
    final storage = LocalStorageService(keyStore: keys);
    await storage.init(hivePath: dir.path);
    await storage.adoptAccount(userId: 'user-a');
    final now = DateTime.utc(2026, 9, 25, 12);
    await storage.addMealLog(_canaryMeal(id: 'fresh', timestamp: now));
    await storage.addMealLog(
      _canaryMeal(id: 'stale', timestamp: DateTime.utc(2026, 8, 1, 12)),
    );

    final removed = await storage.pruneStaleMeals(now: now);

    expect(removed, 1);
    expect(storage.meals, hasLength(1));
    expect(storage.meals.first.id, 'fresh');
  });

  test('Binding a saved Free profile does not drop a live Pro grant', () async {
    final storage = LocalStorageService(keyStore: keys);
    await storage.init(hivePath: dir.path);
    await storage.adoptAccount(userId: 'user-a', email: 'a@evenplate.app');
    await storage.setProStatus(false);

    await storage.saveUserProfile(
      UserProfile(
        id: 'default_user',
        isPro: true,
        freeScansRemaining: 75,
        textRemaining: 100,
        lastQuotaReset: DateTime.now(),
      ),
    );
    await storage.adoptAccount(userId: 'user-a', email: 'a@evenplate.app');

    expect(storage.userProfile.id, 'user-a');
    expect(storage.userProfile.isPro, isTrue);
    expect(storage.userProfile.freeScansRemaining, 75);
  });

  test('Delete account erases only the signed-in diary', () async {
    final storage = LocalStorageService(
      keyStore: keys,
      photoStore: MealPhotoStore(root: Directory('${dir.path}/photos')),
    );
    await storage.init(hivePath: dir.path);
    await storage.adoptAccount(userId: 'user-a', email: 'a@evenplate.app');
    await storage.addMealLog(_canaryMeal(id: 'a-1'));
    await storage.adoptAccount(userId: 'user-b', email: 'b@evenplate.app');
    await storage.addMealLog(_canaryMeal(id: 'b-1'));

    await storage.clearAll();
    expect(storage.meals, isEmpty);

    await storage.adoptAccount(userId: 'user-a', email: 'a@evenplate.app');
    expect(storage.meals, hasLength(1));
    expect(storage.meals.first.id, 'a-1');
  });

  test(
    'Delayed deletion removes its owner without clearing a newly active account',
    () async {
      final storage = LocalStorageService(
        keyStore: keys,
        photoStore: MealPhotoStore(root: Directory('${dir.path}/photos')),
      );
      await storage.init(hivePath: dir.path);
      await storage.adoptAccount(userId: 'user-a', email: 'a@evenplate.app');
      await storage.addMealLog(_canaryMeal(id: 'a-1'));
      await storage.setAnalysisConsent(true);
      await storage.adoptAccount(userId: 'user-b', email: 'b@evenplate.app');
      await storage.addMealLog(_canaryMeal(id: 'b-1'));
      await storage.clearAccountData('user-a');
      expect(storage.userProfile.id, 'user-b');
      expect(storage.meals.single.id, 'b-1');
      expect(storage.pendingMealSync('user-b'), hasLength(1));
      expect(storage.pendingMealSync('user-a'), isEmpty);
      await storage.adoptAccount(userId: 'user-a', email: 'a@evenplate.app');
      expect(storage.meals, isEmpty);
      expect(storage.analysisConsentGranted, isFalse);
    },
  );

  test('A deleted plate does not come back from a cloud pull', () async {
    final storage = LocalStorageService(keyStore: keys);
    await storage.init(hivePath: dir.path);
    await storage.adoptAccount(userId: 'user-a', email: 'a@evenplate.app');
    await storage.addMealLog(_canaryMeal(id: 'local-1'));

    await storage.deleteMeal('local-1');
    expect(storage.meals, isEmpty);

    final added = await storage.mergeRemoteMeals([_canaryMeal(id: 'local-1')]);

    expect(added, 0);
    expect(storage.meals, isEmpty);
  });

  test('A Pro leftover persists as Pro after a restart', () async {
    final first = LocalStorageService(keyStore: keys);
    await first.init(hivePath: dir.path);
    await first.applyServerQuota(isPro: false, freeScansRemaining: 67);
    expect(first.hasPro, isTrue);
    expect(first.userProfile.isPro, isTrue);
    await Hive.close();

    final second = LocalStorageService(keyStore: keys);
    await second.init(hivePath: dir.path);

    expect(second.hasPro, isTrue);
    expect(second.userProfile.isPro, isTrue);
    expect(second.userProfile.freeScansRemaining, 67);
  });

  test(
    'Promo access and depleted balances survive restart and account switching',
    () async {
      final first = LocalStorageService(
        keyStore: keys,
        photoStore: MealPhotoStore(root: Directory('${dir.path}/photos')),
      );
      await first.init(hivePath: dir.path);
      await first.adoptAccount(
        userId: 'promo-owner',
        email: 'promo@invalid.example',
      );
      await first.applyPromoGrant(DateTime.now().add(const Duration(days: 90)));
      await first.applyStoreEntitlement(false);
      await first.applyServerQuota(
        isPro: true,
        freeScansRemaining: 2,
        textRemaining: 8,
        photoPurchased: 25,
      );
      await Hive.close();

      final second = LocalStorageService(
        keyStore: keys,
        photoStore: MealPhotoStore(root: Directory('${dir.path}/photos')),
      );
      await second.init(hivePath: dir.path);
      expect(second.hasPro, isTrue);
      expect(second.photoLeft, 27);
      expect(second.textLeft, 8);
      await second.applyStoreEntitlement(false);
      expect(second.photoLeft, 27);
      await second.adoptAccount(
        userId: 'other-owner',
        email: 'other@invalid.example',
      );
      expect(second.hasPro, isFalse);
      await second.adoptAccount(
        userId: 'promo-owner',
        email: 'promo@invalid.example',
      );
      expect(second.hasPro, isTrue);
      expect(second.photoLeft, 27);
      expect(second.textLeft, 8);
      await second.clearAccountData('promo-owner');
      expect(second.hasPro, isFalse);
    },
  );

  test('An expired store stay Free after a restart', () async {
    final first = LocalStorageService(keyStore: keys);
    await first.init(hivePath: dir.path);
    await first.applyServerQuota(isPro: true, freeScansRemaining: 72);
    await first.applyStoreEntitlement(false);
    expect(first.hasPro, isFalse);
    await Hive.close();

    final second = LocalStorageService(keyStore: keys);
    await second.init(hivePath: dir.path);

    expect(second.hasPro, isFalse);
    expect(second.storeEntitlementDenied, isTrue);
    expect(second.userProfile.freeScansRemaining, 3);
  });

  test('A ledger remaining of 2 stays 2 after a restart', () async {
    final first = LocalStorageService(keyStore: keys);
    await first.init(hivePath: dir.path);
    await first.applyStoreEntitlement(false);
    await first.applyServerQuota(isPro: false, freeScansRemaining: 2);
    expect(first.photoLeft, 2);
    await Hive.close();

    final second = LocalStorageService(keyStore: keys);
    await second.init(hivePath: dir.path);
    await second.applyServerQuota(isPro: false, freeScansRemaining: 2);

    expect(second.hasPro, isFalse);
    expect(second.photoLeft, 2);
    expect(second.userProfile.textRemaining, lessThanOrEqualTo(20));
  });

  test('Corrupt meal rows are skipped on reopen', () async {
    final first = LocalStorageService(keyStore: keys);
    await first.init(hivePath: dir.path);
    await first.addMealLog(_canaryMeal());
    await Hive.box<String>(
      'evenplate_meals_box_aes',
    ).put('broken', '{not-json');
    await Hive.close();

    final second = LocalStorageService(keyStore: keys);
    await second.init(hivePath: dir.path);

    expect(second.meals, hasLength(1));
    expect(second.meals.first.mealName, _canary);
  });

  test('A later profile write cannot clear a finished questionnaire', () async {
    final storage = LocalStorageService(keyStore: keys);
    await storage.init(hivePath: dir.path);
    await storage.adoptAccount(userId: 'user-a', email: 'a@evenplate.app');
    await storage.saveUserProfile(
      storage.userProfile.copyWith(hasCompletedOnboarding: true),
    );

    await storage.saveUserProfile(
      storage.userProfile.copyWith(hasCompletedOnboarding: false),
    );

    expect(storage.questionnaireDone, isTrue);
  });

  test('Plates already on the phone skip the questionnaire', () async {
    final storage = LocalStorageService(keyStore: keys);
    await storage.init(hivePath: dir.path);
    await storage.adoptAccount(userId: 'user-a', email: 'a@evenplate.app');
    await storage.addMealLog(_canaryMeal());
    await storage.saveUserProfile(
      storage.userProfile.copyWith(hasCompletedOnboarding: false),
    );

    expect(storage.questionnaireDone, isTrue);
    await Hive.close();

    final reopened = LocalStorageService(keyStore: keys);
    await reopened.init(hivePath: dir.path);
    expect(reopened.questionnaireDone, isTrue);
    expect(reopened.meals, hasLength(1));
  });

  test(
    'The same email keeps its plates and photo paths after sign-in',
    () async {
      final storage = LocalStorageService(keyStore: keys);
      await storage.init(hivePath: dir.path);
      await storage.adoptAccount(userId: 'user-a', email: 'a@evenplate.app');
      await storage.addMealLog(
        _canaryMeal(id: 'plate-1').copyWith(imagePath: '/photos/plate-1.ep'),
      );
      await storage.saveUserProfile(
        storage.userProfile.copyWith(hasCompletedOnboarding: true),
      );

      await storage.adoptAccount(userId: 'user-b', email: 'a@evenplate.app');

      expect(storage.questionnaireDone, isTrue);
      expect(storage.meals, hasLength(1));
      expect(storage.meals.single.userId, 'user-b');
      expect(storage.meals.single.imagePath, '/photos/plate-1.ep');
    },
  );

  test('A cloud plate does not drop the photo saved on the phone', () async {
    final storage = LocalStorageService(keyStore: keys);
    await storage.init(hivePath: dir.path);
    await storage.adoptAccount(userId: 'user-a', email: 'a@evenplate.app');
    await storage.addMealLog(
      _canaryMeal(
        id: 'plate-1',
        userId: 'user-a',
      ).copyWith(imagePath: '/photos/plate-1.ep'),
    );

    await storage.mergeRemoteMeals([
      _canaryMeal(id: 'plate-1', userId: 'user-a'),
    ]);

    expect(storage.meals, hasLength(1));
    expect(storage.meals.single.imagePath, '/photos/plate-1.ep');
  });
  test(
    'Durable meal outbox survives restart and revision acknowledgements',
    () async {
      final first = LocalStorageService(keyStore: keys);
      await first.init(hivePath: dir.path);
      await first.adoptAccount(userId: 'user-a');
      await first.addMealLog(_canaryMeal(id: 'retry-1'));
      final old = first.pendingMealSync('user-a').single;
      await first.updateMealEnergyCheckIn('retry-1', 'steady');
      await first.acknowledgeMealSync(
        old['key'] as String,
        old['revision'] as String,
      );
      expect(first.pendingMealSync('user-a'), hasLength(1));
      await Hive.close();
      final restored = LocalStorageService(keyStore: keys);
      await restored.init(hivePath: dir.path);
      expect(restored.pendingMealSync('user-a'), hasLength(1));
      expect(restored.meals.single.energyCheckIn, 'steady');
      await restored.adoptAccount(userId: 'user-b');
      expect(restored.pendingMealSync('user-b'), isEmpty);
      expect(restored.meals, isEmpty);
    },
  );

  test('Analysis consent is account scoped and can be withdrawn', () async {
    final storage = LocalStorageService(keyStore: keys);
    await storage.init(hivePath: dir.path);
    await storage.adoptAccount(userId: 'user-a');
    await storage.setAnalysisConsent(true);
    expect(storage.analysisConsentGranted, isTrue);
    await storage.adoptAccount(userId: 'user-b');
    expect(storage.analysisConsentGranted, isFalse);
    await storage.adoptAccount(userId: 'user-a');
    expect(storage.analysisConsentGranted, isTrue);
    await storage.setAnalysisConsent(false);
    expect(storage.analysisConsentGranted, isFalse);
  });

  test('Remote preferences cannot write billing or device consent', () async {
    final storage = LocalStorageService(keyStore: keys);
    await storage.init(hivePath: dir.path);
    await storage.adoptAccount(userId: 'user-a');
    await storage.adoptRemotePreferences('user-a', {
      'dietaryPreference': '100% Plant-Based / Vegan',
      'isPro': true,
      'photoPurchased': 999,
      'pushConsentGranted': true,
      'id': 'user-b',
    });
    expect(storage.userProfile.dietaryPreference, contains('Vegan'));
    expect(storage.userProfile.id, 'user-a');
    expect(storage.userProfile.isPro, isFalse);
    expect(storage.userProfile.photoPurchased, 0);
    expect(storage.userProfile.pushConsentGranted, isFalse);
  });

  test('Meal history older than 30 days is retained after restart', () async {
    final first = LocalStorageService(keyStore: keys);
    await first.init(hivePath: dir.path);
    await first.adoptAccount(userId: 'user-a');
    await first.addMealLog(
      _canaryMeal(
        id: 'old-1',
        timestamp: DateTime.now().subtract(const Duration(days: 90)),
      ),
    );
    await Hive.close();
    final restored = LocalStorageService(keyStore: keys);
    await restored.init(hivePath: dir.path);
    expect(restored.meals.single.id, 'old-1');
  });
}
