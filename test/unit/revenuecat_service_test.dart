import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:evenplate/services/local_storage_service.dart';
import 'package:evenplate/services/revenuecat_service.dart';

void main() {
  late LocalStorageService storage;
  late RevenueCatService revenueCat;

  setUp(() {
    storage = LocalStorageService();
    revenueCat = RevenueCatService(storage);
  });

  group('RevenueCatService Unit Tests', () {
    test('Initial state reflects local storage pro status', () {
      expect(revenueCat.isPro, isFalse);
      expect(revenueCat.isLoading, isFalse);
      expect(revenueCat.isConfigured, isFalse);
      expect(revenueCat.availablePackages, isEmpty);
    });

    test('An unconfigured RevenueCat never grants Pro', () async {
      await storage.setProStatus(false);
      expect(revenueCat.isConfigured, isFalse);

      expect(await revenueCat.restorePurchases(), isFalse);
      expect(revenueCat.isPro, isFalse);
      expect(storage.userProfile.isPro, isFalse);
    });

    test('packageFor returns null before any offering has loaded', () {
      expect(revenueCat.packageFor(PackageType.annual), isNull);
      expect(revenueCat.packageFor(PackageType.monthly), isNull);
    });
  });

  group('LocalStorageService quota', () {
    test('zero remaining blocks a scan for free and Pro', () async {
      await storage.setProStatus(false);
      await storage.setFreeScansRemaining(0);
      expect(storage.canScanPlate(), isFalse);

      await storage.setFreeScansRemaining(2);
      expect(storage.canScanPlate(), isTrue);

      await storage.setProStatus(true);
      await storage.setFreeScansRemaining(0);
      expect(storage.canScanPlate(), isFalse);
    });
  });
}
