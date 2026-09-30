import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'local_storage_service.dart';
import '../core/errors/telemetry.dart';
import 'onesignal_service.dart';
import 'retention_plan.dart';

class OutgoingNotice {
  final int id;
  final String title;
  final String body;
  final DateTime when;
  final String payload;
  final String? repeat;

  const OutgoingNotice({
    required this.id,
    required this.title,
    required this.body,
    required this.when,
    required this.payload,
    this.repeat,
  });
}

abstract class RetentionCopy {
  OutgoingNotice noticeFor(RetentionIntent intent);
}

abstract class RetentionPoster {
  Future<void> replace(List<OutgoingNotice> notices);
}

class OneSignalRetentionCopy implements RetentionCopy {
  final OneSignalService _oneSignal;

  OneSignalRetentionCopy(this._oneSignal);

  @override
  OutgoingNotice noticeFor(RetentionIntent intent) {
    final RetentionNotificationEvent event;
    switch (intent.slot) {
      case RetentionSlot.checkIn:
        event = _oneSignal.buildPostMealCheckIn(meal: intent.meal!);
      case RetentionSlot.lunch:
        event = _oneSignal.buildPreMealAnchorNudge(isLunch: true);
      case RetentionSlot.dinner:
        event = _oneSignal.buildPreMealAnchorNudge(isLunch: false);
      case RetentionSlot.sunday:
        event = _oneSignal.buildSundayRecap(
          totalBalancedPlates: intent.balancedPlates,
        );
    }
    return OutgoingNotice(
      id: intent.id,
      title: event.title,
      body: event.body,
      when: intent.when,
      payload: jsonEncode(event.data),
      repeat: intent.slot == RetentionSlot.checkIn
          ? null
          : intent.slot == RetentionSlot.sunday
          ? 'weekly'
          : 'daily',
    );
  }
}

/// Asks the OS to deliver [RetentionPlan] when the app is closed.
class RetentionScheduler {
  final LocalStorageService storage;
  final RetentionCopy copy;
  final RetentionPoster poster;
  final DateTime Function() _clock;
  final bool Function()? isAuthenticated;
  final Listenable? sessionChanges;

  bool _busy = false;
  bool _queued = false;

  RetentionScheduler({
    required this.storage,
    required this.copy,
    required this.poster,
    DateTime Function()? clock,
    this.isAuthenticated,
    this.sessionChanges,
  }) : _clock = clock ?? DateTime.now;

  void start() {
    sessionChanges?.addListener(_onStore);
    storage.mealChanges.addListener(_onStore);
    storage.profileChanges.addListener(_onStore);
    unawaited(refresh());
  }

  void _onStore() {
    unawaited(refresh());
  }

  Future<void> refresh() async {
    if (_busy) {
      _queued = true;
      return;
    }
    _busy = true;
    try {
      do {
        _queued = false;
        await _push();
      } while (_queued);
    } finally {
      _busy = false;
    }
  }

  Future<void> _push() async {
    final profile = storage.userProfile;
    final meals = storage.meals;
    final intents = (isAuthenticated?.call() ?? true)
        ? RetentionPlan.upcoming(profile: profile, meals: meals, now: _clock())
        : <RetentionIntent>[];
    final notices = <OutgoingNotice>[
      for (final intent in intents) copy.noticeFor(intent),
    ];
    await poster.replace(notices);
    debugPrint(
      'EvenPlate reminders scheduled=${notices.length} '
      'checkIn=${profile.checkInRemindersEnabled} '
      'preMeal=${profile.preMealNudgesEnabled} '
      'sunday=${profile.weeklyRecapEnabled}',
    );
  }
}

class PlatformReminderPoster implements RetentionPoster {
  static const _channel = MethodChannel('evenplate/reminders');

  @override
  Future<void> replace(List<OutgoingNotice> notices) async {
    try {
      await _channel.invokeMethod<void>('replace', [
        for (final notice in notices)
          {
            'id': notice.id,
            'title': notice.title,
            'body': notice.body,
            'when': notice.when.millisecondsSinceEpoch,
            'payload': notice.payload,
            if (notice.repeat != null) 'repeat': notice.repeat,
          },
      ]);
    } catch (e) {
      Telemetry.report(name: 'reminders.schedule_failed', error: e);
    }
  }
}
