import 'satiety_matrix.dart';

/// Canned plates for first-run, scan presets, and tests.
class SamplePlates {
  SamplePlates._();

  /// Weak lunch so the rescue visibly moves the clock.
  static SatietyResult get pastaLunch => SatietyResult.fromFoods(
    mealName: 'Lunch pasta',
    components: const ['Pasta'],
    hybridUpgrade: const HybridUpgrade(
      instantAdd: 'Add a hardboiled egg so protein can hold this plate.',
      smartSwap: 'Next time, cook the pasta with beans or chicken in the pan.',
      digestiveCatalyst: 'Eat the protein first, then the pasta.',
    ),
  );

  static const avocado = SatietyResult(
    mealName: 'Avocado Toast with Poached Eggs',
    components: [
      'Seeded Sourdough',
      'Ripe Avocado',
      'Free-Range Eggs',
      'Microgreens',
      'Chili Flakes',
    ],
    pillars: SatietyPillars(
      anchor: PillarDetail(
        detected: true,
        items: ['Poached Eggs'],
        quality: 'high',
      ),
      net: PillarDetail(
        detected: true,
        items: ['Microgreens', 'Seeded Sourdough'],
        quality: 'medium',
      ),
      buffer: PillarDetail(
        detected: true,
        items: ['Avocado', 'Egg Yolks'],
        quality: 'high',
      ),
      spark: PillarDetail(
        detected: true,
        items: ['Chili Flakes', 'Lemon Spritz'],
        quality: 'medium',
      ),
    ),
    satietyScore: 91,
    durationHours: 4.0,
    crashRisk: 'low',
    hybridUpgrade: HybridUpgrade(
      instantAdd:
          'Add a handful of mixed berries or cherry tomatoes for prebiotic fiber volume.',
      smartSwap:
          'Great bread choice with seeded sourdough, keep this anchor steady.',
      digestiveCatalyst:
          'Pair with warm green tea to support antioxidant uptake.',
    ),
  );

  static const salmon = SatietyResult(
    mealName: 'Harvest Salmon & Wild Grains',
    components: [
      'Pan-Seared Salmon',
      'Wild Rice',
      'Steamed Asparagus',
      'Olive Oil Herb Dressing',
    ],
    pillars: SatietyPillars(
      anchor: PillarDetail(detected: true, items: ['Salmon'], quality: 'high'),
      net: PillarDetail(
        detected: true,
        items: ['Wild Rice', 'Asparagus'],
        quality: 'high',
      ),
      buffer: PillarDetail(
        detected: true,
        items: ['Olive Oil', 'Omega-3s'],
        quality: 'high',
      ),
      spark: PillarDetail(
        detected: true,
        items: ['Lemon Herb Vinaigrette'],
        quality: 'high',
      ),
    ),
    satietyScore: 96,
    durationHours: 4.8,
    crashRisk: 'low',
    hybridUpgrade: HybridUpgrade(
      instantAdd:
          'Plate is already exceptionally balanced with all 4 pillars confirmed.',
      smartSwap: 'No swaps needed; high protein and healthy lipid ratio.',
      digestiveCatalyst:
          'Take 5 mindful deep breaths before starting to promote parasympathetic rest-and-digest mode.',
    ),
  );
}
