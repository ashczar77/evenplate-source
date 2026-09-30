/// Home copy for today's plates vs how well they held.
///
/// Plate count is "did you log the day." Chamber fill is "did those
/// plates last." Empty tanks after several plates must not read as
/// "eat again."
class TodayDayStatus {
  final String title;
  final String subtitle;
  final String addPlateLabel;
  final bool dayLogged;

  const TodayDayStatus({
    required this.title,
    required this.subtitle,
    required this.addPlateLabel,
    required this.dayLogged,
  });

  /// [plateCount] is real meals only, not bridge snacks.
  factory TodayDayStatus.from({
    required int plateCount,
    required int targetMeals,
    required double proteinProgress,
    required double fiberProgress,
    required double fatsProgress,
    required double carbsProgress,
  }) {
    final target = targetMeals < 1 ? 1 : targetMeals;
    final held = _chambersHeld(
      proteinProgress,
      fiberProgress,
      fatsProgress,
      carbsProgress,
    );
    final tip = nextPlateTip(
      proteinProgress: proteinProgress,
      fiberProgress: fiberProgress,
      fatsProgress: fatsProgress,
      carbsProgress: carbsProgress,
    );
    final dayLogged = plateCount >= target;

    if (plateCount <= 0) {
      return const TodayDayStatus(
        title: 'No plates yet',
        subtitle:
            'Build the combo before you eat, or scan what is in front of you.',
        addPlateLabel: 'Add Plate',
        dayLogged: false,
      );
    }

    if (!dayLogged) {
      return TodayDayStatus(
        title: '$plateCount of $target plates in',
        subtitle: held ? 'This is holding so far.' : tip,
        addPlateLabel: 'Add Plate',
        dayLogged: false,
      );
    }

    if (plateCount > target) {
      return TodayDayStatus(
        title: 'Day is logged',
        subtitle: held
            ? 'Extra plate logged. The day was already in.'
            : 'Extra plate logged. $tip',
        addPlateLabel: 'Log another',
        dayLogged: true,
      );
    }

    return TodayDayStatus(
      title: 'Day is logged',
      subtitle: held ? 'These plates held.' : tip,
      addPlateLabel: 'Log another',
      dayLogged: true,
    );
  }

  /// One concrete gap, not a fail line. Lowest chamber first.
  static String nextPlateTip({
    required double proteinProgress,
    required double fiberProgress,
    required double fatsProgress,
    required double carbsProgress,
  }) {
    final gaps = <({double progress, String tip})>[
      (
        progress: proteinProgress,
        tip: 'Add protein so fullness lasts (eggs, yogurt, fish).',
      ),
      (
        progress: fiberProgress,
        tip: 'Add fiber to slow down digestion (beans, veg, oats).',
      ),
      (
        progress: fatsProgress,
        tip: 'Add a fat to blunt a dip (olive oil, nuts, avocado).',
      ),
      (
        progress: carbsProgress,
        tip: 'Add volume so the plate feels finished (salad, fruit, slaw).',
      ),
    ]..sort((a, b) => a.progress.compareTo(b.progress));

    for (final gap in gaps) {
      if (gap.progress < 1.0) return gap.tip;
    }
    return 'These plates held.';
  }

  static bool _chambersHeld(
    double protein,
    double fiber,
    double fats,
    double carbs,
  ) {
    final mean =
        (protein.clamp(0.0, 1.0) +
            fiber.clamp(0.0, 1.0) +
            fats.clamp(0.0, 1.0) +
            carbs.clamp(0.0, 1.0)) /
        4;
    return mean >= 0.5;
  }

  /// Quality of one pillar after meals exist. Never "0/3".
  static String pillarLabel(double progress, {required bool hasPlates}) {
    if (!hasPlates) return '-';
    if (progress >= 1.0) return 'In';
    if (progress > 0) return 'Partial';
    return 'Low';
  }
}
