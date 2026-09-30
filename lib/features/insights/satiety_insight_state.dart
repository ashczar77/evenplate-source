import 'package:flutter/material.dart';
import '../../core/theme/even_colors.dart';
import '../../models/meal_log.dart';
import '../../models/satiety_matrix.dart';

enum InsightStateType {
  // Core Biological States
  emptyEngine,
  sugarSpike,
  missingAnchor,
  missingNet,
  missingBuffer,
  keto,
  proteinOverload,
  satietyLock,
  engineOverflow,

  // Humorous Edge Cases
  notFood,
  tooDark,
  blurry,

  // System States
  apiError,
  weeklyLimit,
}

class SatietyInsightState {
  final InsightStateType type;
  final String title;
  final String description;
  final Color primaryColor;

  const SatietyInsightState({
    required this.type,
    required this.title,
    required this.description,
    this.primaryColor = EvenColors.primaryGreen,
  });

  /// Factory method for AI API Failures
  static SatietyInsightState apiError(String errorDetails) {
    final detail = errorDetails.trim();
    final looksTechnical =
        detail.startsWith('Exception:') ||
        detail.contains('Bad state:') ||
        detail.contains('RangeError') ||
        detail.toLowerCase().contains('gemini');
    return SatietyInsightState(
      type: InsightStateType.apiError,
      title: 'Analysis temporarily unavailable',
      description: (detail.isEmpty || looksTechnical)
          ? 'Wait a moment and try the photo again.'
          : detail,
      primaryColor: EvenColors.crashWarning,
    );
  }

  /// Factory method to determine the state from a SatietyResult
  static SatietyInsightState fromResult(SatietyResult result) {
    switch (result.captureIssue) {
      case 'not_food':
        return edgeCaseNotFood();
      case 'too_dark':
        return edgeCaseTooDark();
      case 'blurry':
        return edgeCaseBlurry();
    }

    final hasAnchor = result.pillars.anchor.isAligned;
    final hasNet = result.pillars.net.isAligned;
    final hasBuffer = result.pillars.buffer.isAligned;
    final hasSpark = result.pillars.spark.isAligned;

    if (!hasAnchor && !hasNet && !hasBuffer && !hasSpark) {
      return emptyEngine();
    }

    // Keto needs !hasNet, so it must run before the missing-net return.
    if (hasAnchor && hasBuffer && !hasNet) {
      return ketoState();
    }

    if (!hasAnchor) return missingAnchor();
    if (!hasNet) return missingNet();
    if (!hasBuffer) return missingBuffer();

    return satietyLock();
  }

  /// Home insights describe today, not whichever snack was logged last.
  static SatietyInsightState fromToday(List<MealLog> meals, {DateTime? now}) {
    final day = now ?? DateTime.now();
    final todays = meals.where((meal) {
      final stamp = meal.timestamp;
      return stamp.year == day.year &&
          stamp.month == day.month &&
          stamp.day == day.day;
    }).toList();
    if (todays.isEmpty) return emptyEngine();

    if (todays.length == 1) {
      final only = todays.first.satietyResult;
      if (only.captureIssue != null) return fromResult(only);
    }

    bool landed(bool Function(SatietyPillars pillars) pick) {
      return todays.any((meal) => pick(meal.satietyResult.pillars));
    }

    final hasAnchor = landed((p) => p.anchor.isAligned);
    final hasNet = landed((p) => p.net.isAligned);
    final hasBuffer = landed((p) => p.buffer.isAligned);
    final hasSpark = landed((p) => p.spark.isAligned);
    if (!hasAnchor && !hasNet && !hasBuffer && !hasSpark) {
      return missingAnchor();
    }
    if (hasAnchor && hasBuffer && !hasNet) return ketoState();
    if (!hasAnchor) return missingAnchor();
    if (!hasNet) return missingNet();
    if (!hasBuffer) return missingBuffer();
    return satietyLock();
  }

  // Core states
  static SatietyInsightState emptyEngine() => const SatietyInsightState(
    type: InsightStateType.emptyEngine,
    title: 'No plates yet',
    description:
        'Log a meal today to see how the engine is running. This reading is for today, not a leftover snack.',
  );

  static SatietyInsightState sugarSpike() => const SatietyInsightState(
    type: InsightStateType.sugarSpike,
    title: 'Consider protein and fiber',
    description: 'Consider a protein food or a fiber-rich pairing.',
    primaryColor: EvenColors.crashWarning,
  );

  static SatietyInsightState missingAnchor() => const SatietyInsightState(
    type: InsightStateType.missingAnchor,
    title: 'Missing protein',
    description: 'Consider a protein food such as eggs, tofu, or beans.',
  );

  static SatietyInsightState missingNet() => const SatietyInsightState(
    type: InsightStateType.missingNet,
    title: 'Missing fiber',
    description:
        'Consider a fiber-rich food such as beans, oats, or vegetables.',
  );

  static SatietyInsightState missingBuffer() => const SatietyInsightState(
    type: InsightStateType.missingBuffer,
    title: 'Missing healthy fats',
    description: 'Consider nuts, seeds, avocado, or olive oil.',
  );

  static SatietyInsightState ketoState() => const SatietyInsightState(
    type: InsightStateType.keto,
    title: 'Low fiber plate',
    description: 'Protein and fats are in. Fiber is the gap on this plate.',
  );

  static SatietyInsightState proteinOverload() => const SatietyInsightState(
    type: InsightStateType.proteinOverload,
    title: 'Meal pattern',
    description: 'Record how you felt after this meal.',
  );

  static SatietyInsightState satietyLock() => const SatietyInsightState(
    type: InsightStateType.satietyLock,
    title: 'Plate is even',
    description:
        'Protein, fiber, fat, and produce are on the plate. Record how you feel afterward.',
  );

  static SatietyInsightState engineOverflow() => const SatietyInsightState(
    type: InsightStateType.engineOverflow,
    title: 'Meal pattern',
    description: 'Record how you felt after this meal.',
  );

  static SatietyInsightState edgeCaseNotFood() => const SatietyInsightState(
    type: InsightStateType.notFood,
    title: "Oops, doesn't look like food",
    description: 'Point the camera at a meal and try again.',
  );

  static SatietyInsightState edgeCaseTooDark() => const SatietyInsightState(
    type: InsightStateType.tooDark,
    title: 'Too dark',
    description: 'Add a little light and take the photo again.',
  );

  static SatietyInsightState edgeCaseBlurry() => const SatietyInsightState(
    type: InsightStateType.blurry,
    title: 'A bit blurry',
    description: 'Hold steady and recapture the plate.',
  );

  static SatietyInsightState weeklyLimit() => const SatietyInsightState(
    type: InsightStateType.weeklyLimit,
    title: 'Weekly Scans Complete',
    description:
        'You have used this week\'s photo scans. Open a logged plate, build from foods we know, or buy more scans.',
  );
}
