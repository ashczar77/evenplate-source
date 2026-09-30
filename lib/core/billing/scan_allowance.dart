/// Weekly included credits and pack sizes. SQL defaults must match.
class ScanAllowance {
  static const int freePhotoWeekly = 3;
  static const int proPhotoWeekly = 75;
  static const int freeTextWeekly = 20;
  static const int proTextWeekly = 100;
  static const int textPerHour = 20;

  static const int photoPack25 = 25;
  static const int photoPack80 = 80;
  static const int textPack40 = 40;

  static const String photoPack25Id = 'scan_pack_25';
  static const String photoPack80Id = 'scan_pack_80';
  static const String textPack40Id = 'food_pack_40';

  /// Planning unit until live usageMetadata replaces it.
  static const double photoPlanningUsd = 0.01;
  static const double textPlanningUsd = 0.005;

  static double proPhotoMonthlyUsd() => proPhotoWeekly * 4 * photoPlanningUsd;

  static int includedPhotoWeekly({required bool isPro}) =>
      isPro ? proPhotoWeekly : freePhotoWeekly;

  static int includedTextWeekly({required bool isPro}) =>
      isPro ? proTextWeekly : freeTextWeekly;

  /// Same rule as least(remaining, cap) on the profile ledger. Never raises.
  static int clampIncluded(int remaining, int cap) {
    if (remaining < 0) return 0;
    return remaining > cap ? cap : remaining;
  }

  /// Weekly included meters, not packs. 74 remaining cannot be a Free week.
  static bool weeklyMetersImplyPro({
    required int weeklyPhotoRemaining,
    required int weeklyTextRemaining,
  }) {
    return weeklyPhotoRemaining > freePhotoWeekly ||
        weeklyTextRemaining > freeTextWeekly;
  }

  static bool hasProAccess({
    required bool isPro,
    required int weeklyPhotoRemaining,
    required int weeklyTextRemaining,
  }) {
    return isPro ||
        weeklyMetersImplyPro(
          weeklyPhotoRemaining: weeklyPhotoRemaining,
          weeklyTextRemaining: weeklyTextRemaining,
        );
  }

  static bool photoLow(int remaining, {required bool isPro}) {
    final cap = includedPhotoWeekly(isPro: isPro);
    return remaining > 0 && remaining <= (cap * 0.2).ceil();
  }

  static bool textLow(int remaining, {required bool isPro}) {
    final cap = includedTextWeekly(isPro: isPro);
    return remaining > 0 && remaining <= (cap * 0.2).ceil();
  }
}
