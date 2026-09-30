import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import '../core/security/app_secrets.dart';
import '../core/errors/telemetry.dart';
import '../models/meal_log.dart';
import '../models/user_profile.dart';
import 'local_storage_service.dart';

enum RetentionCampaignType {
  postMealCheckIn,
  preMealAnchor,
  midWeekMomentum,
  sundayRecap,
  trialTrustReminder,
}

class RetentionNotificationEvent {
  final RetentionCampaignType type;
  final String title;
  final String body;
  final List<String> actionButtons;
  final Map<String, dynamic> data;

  const RetentionNotificationEvent({
    required this.type,
    required this.title,
    required this.body,
    required this.actionButtons,
    required this.data,
  });
}

/// Push requires explicit consent and at least one enabled reminder.
bool profileWantsPush(UserProfile profile) {
  return profile.pushConsentGranted &&
      (profile.checkInRemindersEnabled ||
          profile.preMealNudgesEnabled ||
          profile.weeklyRecapEnabled);
}

/// OneSignal Push Notification Service & 5-Stage Smart Satiety Retention Engine
class OneSignalService {
  // Action button labels. The action ids are the stable contract; these are display text.
  static const String actionSteadyLabel = 'Feeling steady';
  static const String actionDipLabel = 'Low energy';
  static const String actionOpenScannerLabel = 'Open scanner';
  static const String actionViewHarmonyLabel = 'View recap';
  static const String actionManageSettingsLabel = '⚙️ Manage in Settings';

  final LocalStorageService _storage;
  bool _isInitialized = false;
  void Function(String?, Map<String, dynamic>?)? onNotificationTap;
  Map<String, dynamic>? _pendingTap;

  void routeNotificationTap(String? action, Map<String, dynamic>? data) {
    final handler = onNotificationTap;
    if (handler == null) {
      _pendingTap = {'action': action, 'data': data};
    } else {
      handler(action, data);
    }
  }

  void replayPendingTap() {
    final pending = _pendingTap;
    if (pending == null || onNotificationTap == null) return;
    _pendingTap = null;
    onNotificationTap!(
      pending['action'] as String?,
      pending['data'] as Map<String, dynamic>?,
    );
  }

  String? _pendingLogin;

  final StreamController<RetentionNotificationEvent> _campaignStreamController =
      StreamController<RetentionNotificationEvent>.broadcast();

  final StreamController<String> _bridgeSnackRequestedController =
      StreamController<String>.broadcast();

  Stream<RetentionNotificationEvent> get onCampaignTriggered =>
      _campaignStreamController.stream;

  Stream<String> get onBridgeSnackRequested =>
      _bridgeSnackRequestedController.stream;

  OneSignalService(this._storage);

  bool get isInitialized => _isInitialized;

  Future<void> init() async {
    if (_isInitialized) return;

    if (AppSecrets.oneSignalAppId.isEmpty) {
      debugPrint(
        'No ONESIGNAL_APP_ID specified. Running in local simulation mode.',
      );
      _isInitialized = true;
      return;
    }

    try {
      OneSignal.Debug.setLogLevel(
        kDebugMode ? OSLogLevel.verbose : OSLogLevel.none,
      );
      // Must run before initialize so the SDK does not create a player
      // until grantPushConsent has been called.
      await OneSignal.consentRequired(true);
      await OneSignal.initialize(AppSecrets.oneSignalAppId);

      if (profileWantsPush(_storage.userProfile)) {
        await _unlockPush();
      }

      OneSignal.Notifications.addClickListener((event) {
        final actionId = event.result.actionId;
        final additionalData = event.notification.additionalData;
        routeNotificationTap(actionId, additionalData);
      });

      _isInitialized = true;
      final pending = _pendingLogin;
      if (pending != null) {
        _pendingLogin = null;
        await identify(pending);
      }
    } catch (e) {
      debugPrint('OneSignal initialization error: $e');
    }
  }

  Future<void> _unlockPush() async {
    if (!_storage.userProfile.pushConsentGranted) return;
    final owner = _storage.userProfile.id;
    await OneSignal.consentGiven(true);
    if (_storage.userProfile.id != owner) return;
    final canAsk = await OneSignal.Notifications.canRequest();
    if (_storage.userProfile.id != owner) return;
    if (canAsk) {
      await OneSignal.Notifications.requestPermission(false);
    }
    if (_storage.userProfile.id != owner) return;
    await OneSignal.User.pushSubscription.optIn();
    final sub = OneSignal.User.pushSubscription;
    debugPrint(
      'OneSignal push permission=${OneSignal.Notifications.permission} '
      'optedIn=${sub.optedIn} id=${sub.id == null ? 'none' : 'set'} '
      'token=${sub.token == null ? 'none' : 'set'}',
    );
  }

  /// Binds this device to the signed-in account so sends hit this phone.
  Future<void> identify(String userId) async {
    if (AppSecrets.oneSignalAppId.isEmpty) return;
    if (!_isInitialized) {
      _pendingLogin = userId;
      return;
    }
    try {
      if (_storage.userProfile.id != userId) return;
      await OneSignal.consentGiven(profileWantsPush(_storage.userProfile));
      if (_storage.userProfile.id != userId) return;
      await OneSignal.login(userId);
      if (_storage.userProfile.id != userId) return;
      if (profileWantsPush(_storage.userProfile)) {
        await OneSignal.User.pushSubscription.optIn();
      }
      await syncUserTags();
    } catch (e, st) {
      Telemetry.report(name: 'push.identity_failed', error: e, stack: st);
    }
  }

  Future<void> logOut() async {
    if (!_isInitialized || AppSecrets.oneSignalAppId.isEmpty) return;
    final owner = _storage.userProfile.id;
    try {
      await OneSignal.User.pushSubscription.optOut();
      if (_storage.userProfile.id != owner) return;
      await OneSignal.logout();
      if (_storage.userProfile.id != owner) return;
      await OneSignal.consentGiven(false);
    } catch (e) {
      debugPrint('OneSignal logout failed: $e');
    }
  }

  void handleNotificationAction(
    String? actionId,
    Map<String, dynamic>? additionalData,
  ) {
    if (actionId == null && additionalData == null) return;

    final mealId = additionalData?['meal_id'] as String?;

    if (actionId == 'action_steady' || actionId == actionSteadyLabel) {
      if (mealId != null) {
        _storage.updateMealEnergyCheckIn(mealId, 'steady');
      }
    } else if (actionId == 'action_dip' || actionId == actionDipLabel) {
      if (mealId != null) {
        unawaited(_recordDipAndOfferSnack(mealId));
      }
    }
  }

  Future<void> _recordDipAndOfferSnack(String mealId) async {
    final owner = _storage.userProfile.id;
    if (!_storage.meals.any((meal) => meal.id == mealId)) return;
    await _storage.updateMealEnergyCheckIn(mealId, 'dip');
    if (_storage.userProfile.id != owner) return;
    _bridgeSnackRequestedController.add(mealId);
  }

  Future<bool> requestNotificationPermission() async {
    try {
      if (AppSecrets.oneSignalAppId.isEmpty) {
        return true;
      }
      final granted = await OneSignal.Notifications.requestPermission(true);
      return granted;
    } catch (e) {
      debugPrint('Error requesting OneSignal permission: $e');
      return false;
    }
  }

  /// Records in-app consent, unlocks the OneSignal SDK, then asks the OS.
  Future<bool> grantPushConsent() async {
    final owner = _storage.userProfile.id;
    await _storage.saveUserProfile(
      _storage.userProfile.copyWith(pushConsentGranted: true),
    );
    if (_storage.userProfile.id != owner) return false;
    if (AppSecrets.oneSignalAppId.isEmpty) {
      return true;
    }
    try {
      await _unlockPush();
      if (_storage.userProfile.id != owner) return false;
      await identify(owner);
    } catch (e) {
      debugPrint('OneSignal consentGiven failed: $e');
    }
    return OneSignal.Notifications.permission;
  }

  /// Sets user tags for intelligent retention campaigns
  Future<void> syncUserTags() async {
    final profile = _storage.userProfile;

    if (!_isInitialized || AppSecrets.oneSignalAppId.isEmpty) {
      debugPrint(
        'Simulated OneSignal Tag Sync: persona=${profile.primaryGoal}, is_pro=${profile.isPro}',
      );
      return;
    }

    try {
      if (!profileWantsPush(profile)) {
        await OneSignal.User.pushSubscription.optOut();
        if (_storage.userProfile.id != profile.id ||
            profileWantsPush(_storage.userProfile)) {
          return;
        }
        await OneSignal.consentGiven(false);
        return;
      }
      await OneSignal.consentGiven(true);
      if (_storage.userProfile.id != profile.id ||
          !profileWantsPush(_storage.userProfile)) {
        return;
      }
      await OneSignal.login(profile.id);
      if (_storage.userProfile.id != profile.id ||
          !profileWantsPush(_storage.userProfile)) {
        return;
      }
      await OneSignal.User.pushSubscription.optIn();
      if (_storage.userProfile.id != profile.id ||
          !profileWantsPush(_storage.userProfile)) {
        return;
      }
      await OneSignal.User.removeTags([
        'eating_style',
        'total_balanced_meals',
        'checkin_reminders_enabled',
        'premeal_nudges_enabled',
        'weekly_recap_enabled',
      ]);
      if (_storage.userProfile.id != profile.id ||
          !profileWantsPush(_storage.userProfile)) {
        return;
      }
      await OneSignal.User.addTags({
        'satiety_persona': profile.primaryGoal,
        'is_pro': profile.isPro.toString(),
      });
    } catch (e) {
      Telemetry.report(name: 'push.tags_failed', error: e);
    }
  }

  /// 5-Stage Smart Satiety Retention Campaign Builders

  RetentionNotificationEvent buildPostMealCheckIn({required MealLog meal}) {
    return RetentionNotificationEvent(
      type: RetentionCampaignType.postMealCheckIn,
      title: 'How\'s your energy?',
      body: 'How do you feel after your meal? Tap to check in.',
      actionButtons: const [actionSteadyLabel, actionDipLabel],
      data: {'meal_id': meal.id, 'campaign': 'post_meal_checkin'},
    );
  }

  RetentionNotificationEvent buildPreMealAnchorNudge({bool isLunch = true}) {
    return RetentionNotificationEvent(
      type: RetentionCampaignType.preMealAnchor,
      title: isLunch ? 'Planning lunch?' : 'Planning dinner?',
      body: isLunch
          ? 'Build or scan your plate with EvenPlate.'
          : 'Build or scan your plate with EvenPlate.',
      actionButtons: const [actionOpenScannerLabel, 'Later'],
      data: {
        'campaign': 'pre_meal_anchor',
        'period': isLunch ? 'lunch' : 'dinner',
      },
    );
  }

  RetentionNotificationEvent buildMidWeekMomentum() {
    return const RetentionNotificationEvent(
      type: RetentionCampaignType.midWeekMomentum,
      title: 'Mid-Week Satiety Momentum',
      body:
          'You have kept steady energy across your meals this week. Keep stacking balanced plates.',
      actionButtons: [actionViewHarmonyLabel, 'Dismiss'],
      data: {'campaign': 'midweek_momentum'},
    );
  }

  RetentionNotificationEvent buildSundayRecap({
    required int totalBalancedPlates,
  }) {
    return RetentionNotificationEvent(
      type: RetentionCampaignType.sundayRecap,
      title: 'Your week in review',
      body: 'See your meals and energy check-ins from this week.',
      actionButtons: const [actionViewHarmonyLabel, 'Dismiss'],
      data: {'campaign': 'sunday_recap', 'plates': totalBalancedPlates},
    );
  }

  RetentionNotificationEvent buildTrialTrustReminder() {
    return const RetentionNotificationEvent(
      type: RetentionCampaignType.trialTrustReminder,
      title: 'EvenPlate Pro: 2 Days Left on Your Free Trial',
      body:
          'Friendly reminder: your trial finishes in 2 days. You have full control to continue or manage anytime in Settings.',
      actionButtons: [actionManageSettingsLabel, 'Continue Pro'],
      data: {'campaign': 'trial_trust'},
    );
  }

  /// Dispatches a simulated retention campaign event for in-app demo & testing
  void simulateCampaign(RetentionCampaignType type, {MealLog? meal}) {
    RetentionNotificationEvent event;
    switch (type) {
      case RetentionCampaignType.postMealCheckIn:
        final fallbackMeal =
            meal ?? (_storage.meals.isNotEmpty ? _storage.meals.first : null);
        if (fallbackMeal != null) {
          event = buildPostMealCheckIn(meal: fallbackMeal);
        } else {
          event = const RetentionNotificationEvent(
            type: RetentionCampaignType.postMealCheckIn,
            title: 'How\'s your energy?',
            body:
                'How did you feel after lunch? Record your own energy check-in.',
            actionButtons: [actionSteadyLabel, actionDipLabel],
            data: {'campaign': 'post_meal_checkin'},
          );
        }
        break;
      case RetentionCampaignType.preMealAnchor:
        event = buildPreMealAnchorNudge(isLunch: true);
        break;
      case RetentionCampaignType.midWeekMomentum:
        event = buildMidWeekMomentum();
        break;
      case RetentionCampaignType.sundayRecap:
        event = buildSundayRecap(
          totalBalancedPlates: _storage.balancedMealCount,
        );
        break;
      case RetentionCampaignType.trialTrustReminder:
        event = buildTrialTrustReminder();
        break;
    }

    _campaignStreamController.add(event);
  }

  void dispose() {
    _campaignStreamController.close();
    _bridgeSnackRequestedController.close();
  }
}
