/// Represents the local user profile, goals, dietary preferences, and subscription status
class UserProfile {
  final String id;
  final String? email;
  final String
  primaryGoal; // 'Steady Energy', 'Stop Crashes', 'Intuitive Fullness', etc.
  final String eatingStyle; // Legacy support
  final String
  crashPattern; // 'Afternoon Slump (2:00-3:30 PM)', 'Mid-Morning (11:00 AM)', etc.
  final String
  dietaryPreference; // 'Omnivore', 'Vegetarian', 'Vegan', 'Low-Carb', 'Sensitive'
  final String
  mealSchedule; // '3 Balanced Meals', '2 Meals (Intermittent Fasting)', etc.
  final String
  coachingStyle; // '30-Second Pantry Sprinkles', 'Smart Swaps', etc.
  final int targetMealsPerDay; // 2 or 3
  final double targetSatietyHoursDaily; // 9.0 or 12.0
  final bool hasCompletedOnboarding;
  final bool isPro;
  final int freeScansRemaining;
  final int photoPurchased;
  final int textRemaining;
  final int textPurchased;
  final DateTime lastQuotaReset;
  final bool checkInRemindersEnabled;
  final bool preMealNudgesEnabled;
  final bool weeklyRecapEnabled;

  /// True after the user opts into OneSignal. The SDK must not run as if
  /// consented before this is set.
  final bool pushConsentGranted;

  /// Wake time as 'HH:mm' string, inferred from the onboarding bubble timeline.
  final String wakeTime; // e.g. '07:00'
  /// Sleep time as 'HH:mm' string, inferred from the onboarding bubble timeline.
  final String sleepTime; // e.g. '23:00'

  const UserProfile({
    this.id = 'default_user',
    this.email,
    this.primaryGoal = 'Steady Energy All Day',
    this.eatingStyle = 'Busy & Quick Meals',
    this.crashPattern = 'Afternoon Slump (2:00-3:30 PM)',
    this.dietaryPreference = 'Omnivore / Balanced',
    this.mealSchedule = '3 Balanced Meals',
    this.coachingStyle = '30-Second Pantry Sprinkles',
    this.targetMealsPerDay = 3,
    this.targetSatietyHoursDaily = 12.0,
    this.hasCompletedOnboarding = false,
    this.isPro = false,
    this.freeScansRemaining = 3,
    this.photoPurchased = 0,
    this.textRemaining = 20,
    this.textPurchased = 0,
    required this.lastQuotaReset,
    this.checkInRemindersEnabled = true,
    this.preMealNudgesEnabled = true,
    this.weeklyRecapEnabled = true,
    this.pushConsentGranted = false,
    this.wakeTime = '07:00',
    this.sleepTime = '23:00',
  });

  /// Athletic vitality is the only goal that uses two larger meals.
  static bool usesTwoMealDay(String primaryGoal) =>
      primaryGoal.contains('Athletic');

  /// Keeps the Home pillar denominators in lockstep with the selected goal.
  UserProfile withPrimaryGoal(String goal) {
    final twoMeals = usesTwoMealDay(goal);
    return copyWith(
      primaryGoal: goal,
      mealSchedule: twoMeals
          ? '2 Substantial Meals (Intermittent Fasting)'
          : '3 Balanced Meals',
      targetMealsPerDay: twoMeals ? 2 : 3,
      targetSatietyHoursDaily: twoMeals ? 9.0 : 12.0,
    );
  }

  /// Bind a live session onto a saved account without dropping a Pro grant
  /// or the higher weekly remaining from this session.
  UserProfile mergedWithLiveSession(UserProfile live) {
    return copyWith(
      email: live.email ?? email,
      isPro: isPro || live.isPro,
      freeScansRemaining: live.freeScansRemaining > freeScansRemaining
          ? live.freeScansRemaining
          : freeScansRemaining,
      photoPurchased: live.photoPurchased > photoPurchased
          ? live.photoPurchased
          : photoPurchased,
      textRemaining: live.textRemaining > textRemaining
          ? live.textRemaining
          : textRemaining,
      textPurchased: live.textPurchased > textPurchased
          ? live.textPurchased
          : textPurchased,
      hasCompletedOnboarding:
          hasCompletedOnboarding || live.hasCompletedOnboarding,
    );
  }

  UserProfile copyWith({
    String? id,
    String? email,
    String? primaryGoal,
    String? eatingStyle,
    String? crashPattern,
    String? dietaryPreference,
    String? mealSchedule,
    String? coachingStyle,
    int? targetMealsPerDay,
    double? targetSatietyHoursDaily,
    bool? hasCompletedOnboarding,
    bool? isPro,
    int? freeScansRemaining,
    int? photoPurchased,
    int? textRemaining,
    int? textPurchased,
    DateTime? lastQuotaReset,
    bool? checkInRemindersEnabled,
    bool? preMealNudgesEnabled,
    bool? weeklyRecapEnabled,
    bool? pushConsentGranted,
    String? wakeTime,
    String? sleepTime,
  }) {
    return UserProfile(
      id: id ?? this.id,
      email: email ?? this.email,
      primaryGoal: primaryGoal ?? this.primaryGoal,
      eatingStyle: eatingStyle ?? this.eatingStyle,
      crashPattern: crashPattern ?? this.crashPattern,
      dietaryPreference: dietaryPreference ?? this.dietaryPreference,
      mealSchedule: mealSchedule ?? this.mealSchedule,
      coachingStyle: coachingStyle ?? this.coachingStyle,
      targetMealsPerDay: targetMealsPerDay ?? this.targetMealsPerDay,
      targetSatietyHoursDaily:
          targetSatietyHoursDaily ?? this.targetSatietyHoursDaily,
      hasCompletedOnboarding:
          hasCompletedOnboarding ?? this.hasCompletedOnboarding,
      isPro: isPro ?? this.isPro,
      freeScansRemaining: freeScansRemaining ?? this.freeScansRemaining,
      photoPurchased: photoPurchased ?? this.photoPurchased,
      textRemaining: textRemaining ?? this.textRemaining,
      textPurchased: textPurchased ?? this.textPurchased,
      lastQuotaReset: lastQuotaReset ?? this.lastQuotaReset,
      checkInRemindersEnabled:
          checkInRemindersEnabled ?? this.checkInRemindersEnabled,
      preMealNudgesEnabled: preMealNudgesEnabled ?? this.preMealNudgesEnabled,
      weeklyRecapEnabled: weeklyRecapEnabled ?? this.weeklyRecapEnabled,
      pushConsentGranted: pushConsentGranted ?? this.pushConsentGranted,
      wakeTime: wakeTime ?? this.wakeTime,
      sleepTime: sleepTime ?? this.sleepTime,
    );
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final schedule = json['mealSchedule'] as String? ?? '3 Balanced Meals';
    final isTwoMeals =
        schedule.contains('2 Meals') || schedule.contains('Intermittent');

    return UserProfile(
      id: json['id'] as String? ?? 'default_user',
      email: json['email'] as String?,
      primaryGoal: json['primaryGoal'] as String? ?? 'Steady Energy All Day',
      eatingStyle: json['eatingStyle'] as String? ?? 'Busy & Quick Meals',
      crashPattern:
          json['crashPattern'] as String? ?? 'Afternoon Slump (2:00-3:30 PM)',
      dietaryPreference:
          json['dietaryPreference'] as String? ?? 'Omnivore / Balanced',
      mealSchedule: schedule,
      coachingStyle:
          json['coachingStyle'] as String? ?? '30-Second Pantry Sprinkles',
      targetMealsPerDay:
          (json['targetMealsPerDay'] as num?)?.toInt() ?? (isTwoMeals ? 2 : 3),
      targetSatietyHoursDaily:
          (json['targetSatietyHoursDaily'] as num?)?.toDouble() ??
          (isTwoMeals ? 9.0 : 12.0),
      hasCompletedOnboarding: json['hasCompletedOnboarding'] as bool? ?? false,
      isPro: json['isPro'] as bool? ?? false,
      freeScansRemaining: (json['freeScansRemaining'] as num?)?.toInt() ?? 3,
      photoPurchased: (json['photoPurchased'] as num?)?.toInt() ?? 0,
      textRemaining: (json['textRemaining'] as num?)?.toInt() ?? 20,
      textPurchased: (json['textPurchased'] as num?)?.toInt() ?? 0,
      lastQuotaReset:
          DateTime.tryParse(json['lastQuotaReset']?.toString() ?? '') ??
          DateTime.now(),
      checkInRemindersEnabled: json['checkInRemindersEnabled'] as bool? ?? true,
      preMealNudgesEnabled: json['preMealNudgesEnabled'] as bool? ?? true,
      weeklyRecapEnabled: json['weeklyRecapEnabled'] as bool? ?? true,
      pushConsentGranted: json['pushConsentGranted'] as bool? ?? false,
      wakeTime: json['wakeTime'] as String? ?? '07:00',
      sleepTime: json['sleepTime'] as String? ?? '23:00',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'primaryGoal': primaryGoal,
    'eatingStyle': eatingStyle,
    'crashPattern': crashPattern,
    'dietaryPreference': dietaryPreference,
    'mealSchedule': mealSchedule,
    'coachingStyle': coachingStyle,
    'targetMealsPerDay': targetMealsPerDay,
    'targetSatietyHoursDaily': targetSatietyHoursDaily,
    'hasCompletedOnboarding': hasCompletedOnboarding,
    'isPro': isPro,
    'freeScansRemaining': freeScansRemaining,
    'photoPurchased': photoPurchased,
    'textRemaining': textRemaining,
    'textPurchased': textPurchased,
    'lastQuotaReset': lastQuotaReset.toIso8601String(),
    'checkInRemindersEnabled': checkInRemindersEnabled,
    'preMealNudgesEnabled': preMealNudgesEnabled,
    'weeklyRecapEnabled': weeklyRecapEnabled,
    'pushConsentGranted': pushConsentGranted,
    'wakeTime': wakeTime,
    'sleepTime': sleepTime,
  };
}
