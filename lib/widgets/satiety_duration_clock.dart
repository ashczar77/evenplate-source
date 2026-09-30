import 'package:flutter/material.dart';
import '../models/fullness_assessment.dart';
import '../models/fullness_estimate.dart';
import 'glass_card.dart';

enum SatietyClockMode { ready, empty, scoring, unavailable }

class SatietyDurationClock extends StatelessWidget {
  final FullnessAssessment? assessment;
  final FullnessEstimate? fullnessEstimate;
  final bool scoring;
  final bool pendingChanges;
  final VoidCallback? onAssess;
  final SatietyClockMode mode;
  const SatietyDurationClock({
    super.key,
    this.assessment,
    this.fullnessEstimate,
    required double durationHours,
    required String crashRisk,
    required int satietyScore,
    double? hoursDelta,
    this.scoring = false,
    this.pendingChanges = false,
    this.onAssess,
    this.mode = SatietyClockMode.ready,
  });
  @override
  Widget build(BuildContext context) {
    final rating = assessment;
    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            pendingChanges && rating != null
                ? 'Previous assessment'
                : 'Relative fullness',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Text(
            rating?.label ??
                (mode == SatietyClockMode.empty
                    ? 'Add a food'
                    : 'Ready to assess'),
            key: const ValueKey('fullness_rating'),
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 8),
          if (!pendingChanges &&
              !scoring &&
              rating?.modelEstimated == true &&
              fullnessEstimate != null) ...[
            Text(
              'Rough fullness estimate: ${fullnessEstimate!.label}',
              key: const ValueKey('fullness_hours_estimate'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            Text(
              'Estimated for a regular portion.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
          ],
          if (pendingChanges)
            const Text(
              'Your food selection has changed. Assess the complete plate to update this estimate.',
            ),
          if (scoring) ...[
            const SizedBox(height: 8),
            const Text('Assessing the complete plate...'),
            const LinearProgressIndicator(),
          ],
          if (!pendingChanges &&
              rating != null &&
              (!rating.modelEstimated || fullnessEstimate == null))
            Text(
              rating.modelEstimated
                  ? 'Estimated from this meal.'
                  : 'Saved nutrient-density comparison. This uses the previous rating method.',
            ),
          if (onAssess != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              key: const ValueKey('btn_assess_plate'),
              onPressed: scoring ? null : onAssess,
              child: Text(scoring ? 'Assessing...' : 'Assess plate'),
            ),
            const Text(
              'A new plate assessment uses one food-score credit. Repeating an assessed plate uses none.',
            ),
          ],
          if (rating != null)
            TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('About this estimate'),
                  content: Text(
                    rating.modelEstimated
                        ? 'Gemini considers the complete meal and preparation. The relative score is not converted into hours. A separate rough range, when available, assumes one regular-sized meal and is an unvalidated model estimate, not a measured or personalized hunger forecast. Portions, activity, and individual differences can change how long you feel full. Neither result predicts focus or blood sugar. Individual food scores and hours are not added.\n\n${rating.note}'
                        : 'This saved rating used NutritionData Fullness Factor with assumed portions and nutrient records. New assessments use Gemini meal estimates, so the two scales should not be compared.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ),
              child: const Text('About this estimate'),
            ),
        ],
      ),
    );
  }
}
