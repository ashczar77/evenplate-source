import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../core/errors/telemetry.dart';
import '../core/security/app_secrets.dart';
import 'local_storage_service.dart';

enum SubscriptionRenewalState { inactive, renewing, ending }

/// RevenueCat Subscription & In-App Purchase Service
class RevenueCatService extends ChangeNotifier {
  final LocalStorageService _storage;
  bool _isConfigured = false;
  Future<void>? _initializing;
  Future<void> _identityWork = Future<void>.value();
  String? _boundUserId;
  String? _requestedUserId;
  final Set<String> _trialEligible = {};
  Future<void> Function({required bool subscription})? onPurchaseCompleted;

  bool trialEligible(Package package) =>
      _trialEligible.contains(package.storeProduct.identifier);
  bool get isAccountBound =>
      _boundUserId != null &&
      _boundUserId == _storage.userProfile.id &&
      _boundUserId == _requestedUserId;

  static const creditProductIds = {
    'scan_pack_25',
    'scan_pack_80',
    'food_pack_40',
  };
  List<Package> creditPackages = [];
  bool _isLoading = false;
  List<Package> _availablePackages = [];

  RevenueCatService(this._storage);

  bool get isPro => _storage.hasPro;
  bool get isLoading => _isLoading;
  bool get isConfigured => _isConfigured;

  Future<void> _reconcilePurchase({required bool subscription}) async {
    try {
      await onPurchaseCompleted?.call(subscription: subscription);
    } catch (error, stack) {
      Telemetry.report(
        name: 'billing.reconcile_failed',
        error: error,
        stack: stack,
      );
    }
  }

  List<Package> get availablePackages => _availablePackages;

  /// The package backing a plan, or null when offerings have not loaded.
  /// Callers must resolve by type: package order is set in the RevenueCat
  /// dashboard and must never decide what a user is charged.
  Package? packageFor(PackageType type) {
    for (final package in _availablePackages) {
      if (package.packageType == type) return package;
    }
    return null;
  }

  /// Test seam: offerings normally come from the store, which is not reachable
  /// from a widget test.
  @visibleForTesting
  void debugSetPackages(
    List<Package> packages, {
    Set<String> eligibleProductIds = const {},
  }) {
    _availablePackages = packages;
    _trialEligible
      ..clear()
      ..addAll(eligibleProductIds);
    notifyListeners();
  }

  Future<void> init() => _initializing ??= _initialize();

  Future<void> _initialize() async {
    if (_isConfigured) return;

    final apiKey = Platform.isIOS
        ? AppSecrets.revenueCatAppleKey
        : AppSecrets.revenueCatGoogleKey;

    try {
      if (apiKey.contains('mock') || apiKey.isEmpty) {
        debugPrint(
          'RevenueCat credentials unconfigured or mock. Bypassing init.',
        );
        return;
      }
      await Purchases.setLogLevel(kDebugMode ? LogLevel.debug : LogLevel.info);
      final configuration = PurchasesConfiguration(apiKey);
      await Purchases.configure(
        configuration,
      ).timeout(const Duration(seconds: 12));
      _isConfigured = true;

      unawaited(fetchOfferings());
    } catch (e) {
      debugPrint('RevenueCat initialization notice: $e');
    }
  }

  Future<void> logIn(String userId) {
    _requestedUserId = userId;
    final next = _identityWork.then((_) async {
      await init();
      if (!_isConfigured || _requestedUserId != userId) return;
      try {
        await Purchases.logIn(userId).timeout(const Duration(seconds: 8));
        if (_requestedUserId != userId) return;
        _boundUserId = userId;
        await checkProStatus();
        await fetchOfferings();
      } catch (e, st) {
        _boundUserId = null;
        Telemetry.report(name: 'billing.identity_failed', error: e, stack: st);
      }
    });
    _identityWork = next.catchError((Object _) {});
    return next;
  }

  Future<void> manageSubscriptions() async {
    final url = Platform.isIOS
        ? 'https://apps.apple.com/account/subscriptions'
        : 'https://play.google.com/store/account/subscriptions';
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<SubscriptionRenewalState?> subscriptionRenewalState() async {
    if (!_isConfigured || !isAccountBound) return null;
    final owner = _boundUserId;
    try {
      await Purchases.invalidateCustomerInfoCache();
      final info = await Purchases.getCustomerInfo().timeout(
        const Duration(seconds: 8),
      );
      if (owner != _boundUserId || !isAccountBound) return null;
      final entitlement =
          info.entitlements.all[AppSecrets.revenueCatEntitlement];
      if (entitlement?.isActive != true) {
        return SubscriptionRenewalState.inactive;
      }
      return entitlement!.willRenew
          ? SubscriptionRenewalState.renewing
          : SubscriptionRenewalState.ending;
    } catch (error, stack) {
      Telemetry.report(
        name: 'billing.subscription_state_failed',
        error: error,
        stack: stack,
      );
      return null;
    }
  }

  Future<void> logOut() {
    _requestedUserId = null;
    _boundUserId = null;
    final next = _identityWork.then((_) async {
      if (!_isConfigured) return;
      try {
        if (await Purchases.isAnonymous.timeout(const Duration(seconds: 5))) {
          return;
        }
        await Purchases.logOut().timeout(const Duration(seconds: 8));
      } catch (e, st) {
        Telemetry.report(name: 'billing.logout_failed', error: e, stack: st);
      }
    });
    _identityWork = next.catchError((Object _) {});
    return next;
  }

  Future<void> checkProStatus() async {
    if (!_isConfigured || !isAccountBound) return;
    final owner = _boundUserId;
    try {
      final customerInfo = await Purchases.getCustomerInfo().timeout(
        const Duration(seconds: 8),
      );
      final hasPro =
          customerInfo
              .entitlements
              .all[AppSecrets.revenueCatEntitlement]
              ?.isActive ??
          false;

      if (owner != _boundUserId || !isAccountBound) return;
      final before = _storage.userProfile;
      await _storage.applyStoreEntitlement(hasPro);
      final after = _storage.userProfile;
      if (before.isPro != after.isPro ||
          before.freeScansRemaining != after.freeScansRemaining ||
          before.textRemaining != after.textRemaining) {
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error checking RevenueCat entitlements: $e');
    }
  }

  Future<void> fetchOfferings() async {
    if (!_isConfigured) return;
    try {
      final offerings = await Purchases.getOfferings();
      creditPackages = {
        for (final offering in offerings.all.values)
          for (final package in offering.availablePackages)
            if (creditProductIds.contains(package.storeProduct.identifier))
              package.storeProduct.identifier: package,
      }.values.toList();
      if (offerings.current != null) {
        _availablePackages = offerings.current!.availablePackages;
        _trialEligible.clear();
        if (Platform.isIOS) {
          final eligibility =
              await Purchases.checkTrialOrIntroductoryPriceEligibility(
                _availablePackages
                    .map((p) => p.storeProduct.identifier)
                    .toList(),
              );
          eligibility.forEach((id, status) {
            if (status.status ==
                IntroEligibilityStatus.introEligibilityStatusEligible) {
              _trialEligible.add(id);
            }
          });
        }
        notifyListeners();
      }
    } catch (e, stack) {
      debugPrint('Error fetching RevenueCat offerings: $e');
      Telemetry.report(name: 'offerings.failed', error: e, stack: stack);
    }
  }

  Future<bool> purchasePackage(Package package) async {
    if (!_isConfigured || !isAccountBound) {
      debugPrint('Purchase attempted before RevenueCat was configured.');
      Telemetry.report(name: 'purchase.unconfigured');
      return false;
    }

    _isLoading = true;
    notifyListeners();
    final purchaseOwner = _boundUserId;
    try {
      final purchaseResult = await Purchases.purchase(
        PurchaseParams.package(package),
      );
      final isPro =
          purchaseResult
              .customerInfo
              .entitlements
              .all[AppSecrets.revenueCatEntitlement]
              ?.isActive ??
          false;

      if (!isAccountBound || purchaseOwner != _boundUserId) return false;
      await _storage.applyStoreEntitlement(isPro);
      if (!isAccountBound || purchaseOwner != _boundUserId) return false;
      await _reconcilePurchase(
        subscription: !creditProductIds.contains(
          package.storeProduct.identifier,
        ),
      );
      _isLoading = false;
      notifyListeners();
      return isPro ||
          creditProductIds.contains(package.storeProduct.identifier);
    } on PlatformException catch (e) {
      _isLoading = false;
      notifyListeners();
      var cancelled = false;
      try {
        cancelled =
            PurchasesErrorHelper.getErrorCode(e) ==
            PurchasesErrorCode.purchaseCancelledError;
      } catch (_) {}
      if (cancelled) {
        Telemetry.report(name: 'purchase.cancelled', alert: false);
      } else {
        Telemetry.report(name: 'purchase.failed', error: e);
      }
      debugPrint('Purchase cancelled or failed: $e');
      return false;
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      Telemetry.report(name: 'purchase.failed', error: e);
      debugPrint('Purchase cancelled or failed: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> restorePurchases() async {
    if (!_isConfigured || !isAccountBound) {
      debugPrint('Restore attempted before RevenueCat was configured.');
      return false;
    }

    _isLoading = true;
    notifyListeners();
    try {
      final customerInfo = await Purchases.restorePurchases();
      final isPro =
          customerInfo
              .entitlements
              .all[AppSecrets.revenueCatEntitlement]
              ?.isActive ??
          false;

      if (!isAccountBound) return false;
      await _storage.applyStoreEntitlement(isPro);
      await onPurchaseCompleted?.call(subscription: isPro);
      _isLoading = false;
      notifyListeners();
      return isPro;
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      Telemetry.report(name: 'restore.failed', error: e);
      debugPrint('Restore failed: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Promo redemption writes Pro through LocalStorageService. Listeners on
  /// this service (paywall, settings chrome) would otherwise stay stale.
  void notifyEntitlementChanged() {
    notifyListeners();
  }
}
