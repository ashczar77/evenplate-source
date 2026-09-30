import '../../models/meal_log.dart';

/// Forecast vs how the plate actually felt.
class CheckInVerdict {
  final String headline;
  final String body;
  final String nextTip;
  final String? gapId;
  final bool held;

  const CheckInVerdict({
    required this.headline,
    required this.body,
    required this.nextTip,
    required this.gapId,
    required this.held,
  });

  factory CheckInVerdict.from(MealLog meal) {
    final held = meal.energyCheckIn == 'steady';
    final gapId = meal.satietyResult.pillars.firstGapId;
    final combo = meal.satietyResult.pillars.comboLine;

    if (held) {
      if (gapId == null || gapId == 'volume') {
        return CheckInVerdict(
          headline: 'You reported steady energy.',
          body: 'Your own check-in helps you notice patterns over time.',
          nextTip: 'Build the next plate the same way.',
          gapId: gapId,
          held: true,
        );
      }
      return CheckInVerdict(
        headline: 'You reported steady energy.',
        body: 'Your check-in is recorded. $combo',
        nextTip: _nextTip(gapId),
        gapId: gapId,
        held: true,
      );
    }

    return CheckInVerdict(
      headline: 'You reported an energy dip.',
      body: (gapId == null || gapId == 'volume')
          ? 'Energy has many influences. Record how you felt without assuming this meal caused it.'
          : combo,
      nextTip: _nextTip(gapId),
      gapId: gapId,
      held: false,
    );
  }

  static String _nextTip(String? gapId) {
    switch (gapId) {
      case 'protein':
        return 'Next plate: add eggs, yogurt, or fish first.';
      case 'fiber':
        return 'Next plate: add beans, oats, or a side salad.';
      case 'fat':
        return 'Next plate: add olive oil, nuts, or avocado.';
      case 'volume':
        return 'Next plate: add cucumber, fruit, or slaw.';
      default:
        return 'Build the next plate the same way.';
    }
  }
}
