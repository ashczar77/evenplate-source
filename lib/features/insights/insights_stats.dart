import '../../models/meal_log.dart';
import '../../models/satiety_matrix.dart';
import '../../services/meal_diary_sync.dart';

enum InsightsRange { today, week, month }

enum InsightPillar { protein, fiber, fats, spark }

/// Derived Insights numbers for a chosen range. Empty logs stay at zero.
class InsightsStats {
  final InsightsRange range;
  final List<MealLog> plates;
  final int totalLogged;
  final int fullMatrixCount;
  final int harmonyPercent;
  final double avgHours;
  final int highCrashCount;
  final int dipCount;
  final int steadyCount;
  final int proteinHit;
  final int fiberHit;
  final int fatsHit;
  final int sparkHit;

  const InsightsStats({
    required this.range,
    required this.plates,
    required this.totalLogged,
    required this.fullMatrixCount,
    required this.harmonyPercent,
    required this.avgHours,
    required this.highCrashCount,
    required this.dipCount,
    required this.steadyCount,
    required this.proteinHit,
    required this.fiberHit,
    required this.fatsHit,
    required this.sparkHit,
  });

  List<MealLog> get heldPlates =>
      plates.where((meal) => meal.energyCheckIn == 'steady').toList();

  List<MealLog> get dippedPlates =>
      plates.where((meal) => meal.energyCheckIn == 'dip').toList();

  double? get avgFullness {
    final values = plates
        .where((m) => m.satietyResult.hasModelAssessment)
        .map((m) => m.satietyResult.fullness?.value)
        .whereType<double>()
        .toList();
    return values.isEmpty
        ? null
        : values.reduce((a, b) => a + b) / values.length;
  }

  bool get isEmpty => totalLogged == 0;

  double get proteinRate => _rate(proteinHit);
  double get fiberRate => _rate(fiberHit);
  double get netRate => fiberRate;
  double get bufferRate => _rate(fatsHit);
  double get sparkRate => _rate(sparkHit);
  double get anchorRate => proteinRate;

  double _rate(int hit) => totalLogged == 0 ? 0 : hit / totalLogged;

  String get rangePhrase {
    switch (range) {
      case InsightsRange.today:
        return 'today';
      case InsightsRange.week:
        return 'this week';
      case InsightsRange.month:
        return 'in the last 30 days';
    }
  }

  int hitsFor(InsightPillar pillar) {
    switch (pillar) {
      case InsightPillar.protein:
        return proteinHit;
      case InsightPillar.fiber:
        return fiberHit;
      case InsightPillar.fats:
        return fatsHit;
      case InsightPillar.spark:
        return sparkHit;
    }
  }

  List<MealLog> missed(InsightPillar pillar) {
    return plates
        .where((meal) => !_hit(meal.satietyResult.pillars, pillar))
        .toList();
  }

  List<MealLog> hitPlates(InsightPillar pillar) {
    return plates
        .where((meal) => _hit(meal.satietyResult.pillars, pillar))
        .toList();
  }

  static bool _hit(SatietyPillars pillars, InsightPillar pillar) {
    switch (pillar) {
      case InsightPillar.protein:
        return pillars.protein.isAligned;
      case InsightPillar.fiber:
        return pillars.fiber.isAligned;
      case InsightPillar.fats:
        return pillars.fats.isAligned;
      case InsightPillar.spark:
        return pillars.spark.isAligned;
    }
  }

  static String labelFor(InsightPillar pillar) {
    switch (pillar) {
      case InsightPillar.protein:
        return 'Protein';
      case InsightPillar.fiber:
        return 'Fiber';
      case InsightPillar.fats:
        return 'Fat';
      case InsightPillar.spark:
        return 'Volume';
    }
  }

  InsightPillar get weakestPillar {
    final ranked = <InsightPillar, int>{
      InsightPillar.protein: proteinHit,
      InsightPillar.fiber: fiberHit,
      InsightPillar.fats: fatsHit,
      InsightPillar.spark: sparkHit,
    };
    var weakest = InsightPillar.protein;
    var low = proteinHit;
    ranked.forEach((pillar, hit) {
      if (hit < low) {
        weakest = pillar;
        low = hit;
      }
    });
    return weakest;
  }

  String get plateCountLabel => '$totalLogged ${plateNoun(totalLogged)}';

  static String plateNoun(int count) => count == 1 ? 'plate' : 'plates';

  String get headline {
    if (isEmpty) return '';
    final allSame =
        proteinHit == fiberHit && fiberHit == fatsHit && fatsHit == sparkHit;
    if (allSame && proteinHit == totalLogged) {
      return 'All four pillars held on $plateCountLabel $rangePhrase.';
    }
    if (allSame) {
      return 'Each pillar held on $proteinHit of $plateCountLabel $rangePhrase.';
    }
    final pillar = weakestPillar;
    return '${labelFor(pillar)} held on ${hitsFor(pillar)} of $plateCountLabel $rangePhrase.';
  }

  factory InsightsStats.fromMeals(
    List<MealLog> meals, {
    InsightsRange range = InsightsRange.month,
    DateTime? now,
  }) {
    final moment = now ?? DateTime.now();
    final plates = meals.where((meal) {
      if (meal.isBridgeFix) return false;
      if (meal.satietyResult.captureIssue != null) return false;
      return inRange(meal.timestamp, range, moment);
    }).toList()..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    if (plates.isEmpty) {
      return InsightsStats(
        range: range,
        plates: const [],
        totalLogged: 0,
        fullMatrixCount: 0,
        harmonyPercent: 0,
        avgHours: 0,
        highCrashCount: 0,
        dipCount: 0,
        steadyCount: 0,
        proteinHit: 0,
        fiberHit: 0,
        fatsHit: 0,
        sparkHit: 0,
      );
    }

    var balanced = 0;
    var hours = 0.0;
    var highCrash = 0;
    var dips = 0;
    var steady = 0;
    var protein = 0;
    var fiber = 0;
    var fats = 0;
    var spark = 0;

    for (final meal in plates) {
      final pillars = meal.satietyResult.pillars;
      hours += meal.satietyResult.durationHours;
      if (pillars.isFullMatrix) balanced++;
      if (meal.satietyResult.crashRisk == 'high') highCrash++;
      if (meal.energyCheckIn == 'dip') dips++;
      if (meal.energyCheckIn == 'steady') steady++;
      if (pillars.protein.isAligned) protein++;
      if (pillars.fiber.isAligned) fiber++;
      if (pillars.fats.isAligned) fats++;
      if (pillars.spark.isAligned) spark++;
    }

    final total = plates.length;
    return InsightsStats(
      range: range,
      plates: List.unmodifiable(plates),
      totalLogged: total,
      fullMatrixCount: balanced,
      harmonyPercent: ((balanced / total) * 100).round(),
      avgHours: hours / total,
      highCrashCount: highCrash,
      dipCount: dips,
      steadyCount: steady,
      proteinHit: protein,
      fiberHit: fiber,
      fatsHit: fats,
      sparkHit: spark,
    );
  }

  static bool inRange(DateTime stamp, InsightsRange range, DateTime now) {
    final day = DateTime(now.year, now.month, now.day);
    final stampDay = DateTime(stamp.year, stamp.month, stamp.day);
    switch (range) {
      case InsightsRange.today:
        return stampDay == day;
      case InsightsRange.week:
        return !stampDay.isBefore(day.subtract(const Duration(days: 6)));
      case InsightsRange.month:
        return MealDiarySync.withinKeepWindow(stamp, now: now);
    }
  }
}
