import 'package:flutter/material.dart';
import '../core/a11y/access.dart';
import '../core/theme/even_colors.dart';
import '../core/utils/sensory_feedback.dart';
import '../models/satiety_matrix.dart';
import 'glass_card.dart';

/// Animated Satiety Matrix Widget with Magnetic Resonance Ring Lock
/// Animates 4 pillars with spring entrance and magnetic seal alignment.
class SatietyMatrixWidget extends StatefulWidget {
  final SatietyPillars pillars;
  final bool animateOnMount;

  const SatietyMatrixWidget({
    super.key,
    required this.pillars,
    this.animateOnMount = true,
  });

  @override
  State<SatietyMatrixWidget> createState() => _SatietyMatrixWidgetState();
}

class _SatietyMatrixWidgetState extends State<SatietyMatrixWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _lockAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _lockAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );

    if (widget.animateOnMount) {
      _controller.forward();
      if (widget.pillars.isFullMatrix) {
        SensoryFeedback.resonanceSnap();
      }
    } else {
      _controller.value = 1.0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (prefersReducedMotion(context)) {
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pillars = widget.pillars;
    final isFull = pillars.isFullMatrix;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'The Satiety Matrix',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(width: 8),
            AnimatedBuilder(
              animation: _lockAnimation,
              builder: (context, _) {
                return Transform.scale(
                  scale: 0.85 + (0.15 * _lockAnimation.value),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isFull
                          ? EvenColors.stableHorizon.withValues(alpha: 0.18)
                          : EvenColors.moderateCurve.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isFull
                            ? EvenColors.stableHorizon
                            : EvenColors.moderateCurve,
                        width: 1,
                      ),
                      boxShadow: isFull
                          ? safeBoxShadows([
                              BoxShadow(
                                color: EvenColors.stableHorizon.withValues(
                                  alpha: 0.25 * _lockAnimation.value,
                                ),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ])
                          : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isFull) ...[
                          const Icon(
                            Icons.lock_outline_rounded,
                            size: 11,
                            color: EvenColors.stableHorizon,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          isFull
                              ? '${pillars.completedCount}/4 Pillars Resonant'
                              : '${pillars.completedCount}/4 Pillars Aligned',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isFull
                                ? EvenColors.stableHorizon
                                : EvenColors.moderateCurve,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 14),

        // 4 Pillar Nodes Grid with Staggered Scale Animation
        AnimatedBuilder(
          animation: _lockAnimation,
          builder: (context, _) {
            return GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.55,
              children: [
                _buildPillarNode(
                  context: context,
                  icon: Icons.fitness_center_rounded,
                  title: 'Protein',
                  subtitle: 'The anchor',
                  detail: pillars.anchor,
                  activeColor: EvenColors.anchorTerracotta,
                  delayFactor: 0.0,
                ),
                _buildPillarNode(
                  context: context,
                  icon: Icons.eco_rounded,
                  title: 'Fiber',
                  subtitle: 'Slows digestion',
                  detail: pillars.net,
                  activeColor: EvenColors.netSage,
                  delayFactor: 0.15,
                ),
                _buildPillarNode(
                  context: context,
                  icon: Icons.water_drop_rounded,
                  title: 'Fat',
                  subtitle: 'Blunts the spike',
                  detail: pillars.buffer,
                  activeColor: EvenColors.bufferAmber,
                  delayFactor: 0.30,
                ),
                _buildPillarNode(
                  context: context,
                  icon: Icons.grain_rounded,
                  title: 'Volume',
                  subtitle: 'Crunch and plants',
                  detail: pillars.spark,
                  activeColor: EvenColors.sparkBlush,
                  delayFactor: 0.45,
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildPillarNode({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required PillarDetail detail,
    required Color activeColor,
    required double delayFactor,
  }) {
    final isDetected = detail.detected;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final progress =
        (_lockAnimation.value - delayFactor).clamp(0.0, 1.0) /
        (1.0 - delayFactor);
    final scale = 0.90 + (0.10 * progress);

    return Transform.scale(
      scale: scale,
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        radius: 18,
        customFill: isDetected
            ? activeColor.withValues(alpha: isDark ? 0.14 : 0.09)
            : null,
        customBorder: isDetected
            ? activeColor.withValues(alpha: 0.55)
            : (isDark
                  ? EvenColors.darkGlassBorder
                  : EvenColors.lightGlassBorder),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: isDetected
                      ? activeColor
                      : (isDark
                            ? EvenColors.textDarkMuted
                            : EvenColors.textLightMuted),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDetected
                          ? activeColor
                          : (isDark
                                ? EvenColors.textDarkMuted
                                : EvenColors.textLightMuted),
                    ),
                  ),
                ),
                Icon(
                  isDetected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked,
                  size: 16,
                  color: isDetected
                      ? activeColor
                      : (isDark
                            ? EvenColors.textDarkMuted
                            : EvenColors.textLightMuted),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: isDark
                    ? EvenColors.textDarkSecondary
                    : EvenColors.textLightSecondary,
              ),
            ),
            if (isDetected && detail.items.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  detail.items.first,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: isDark
                        ? EvenColors.textDarkPrimary
                        : EvenColors.textLightPrimary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
