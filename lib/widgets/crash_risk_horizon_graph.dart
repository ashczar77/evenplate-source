import 'package:flutter/material.dart';
import 'glass_card.dart';

// Compatibility view for older callers. No predicted glucose curve is drawn.
class CrashRiskHorizonGraph extends StatelessWidget {
  const CrashRiskHorizonGraph({
    super.key,
    required double durationHours,
    required String crashRisk,
    required int satietyScore,
    bool animateOnMount = true,
  });

  @override
  Widget build(BuildContext context) => const GlassCard(
    child: Padding(
      padding: EdgeInsets.all(16),
      child: Text(
        'Your own energy check-ins help you notice meal patterns. Food ratings do not predict blood sugar or how long you will stay full.',
      ),
    ),
  );
}
