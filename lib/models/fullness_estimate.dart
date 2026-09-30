/// An optional model range, with an explicit meal-size assumption.
class FullnessEstimate {
  final int minHours;
  final int maxHours;
  const FullnessEstimate({required this.minHours, required this.maxHours});

  String get label => '$minHours-$maxHours hours';

  static FullnessEstimate? parse(Object? raw) {
    if (raw is! Map ||
        raw['portion'] != 'regular' ||
        raw['basis'] != 'model_regular_portion_v1') {
      return null;
    }
    final min = raw['minHours'];
    final max = raw['maxHours'];
    if (min is! num ||
        max is! num ||
        !min.isFinite ||
        !max.isFinite ||
        min != min.roundToDouble() ||
        max != max.roundToDouble() ||
        min < 1 ||
        max > 12 ||
        max - min < 1) {
      return null;
    }
    return FullnessEstimate(minHours: min.toInt(), maxHours: max.toInt());
  }

  Map<String, dynamic> toJson() => {
    'minHours': minHours,
    'maxHours': maxHours,
    'portion': 'regular',
    'basis': 'model_regular_portion_v1',
  };
}
