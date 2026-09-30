import 'package:flutter/material.dart';
import '../core/theme/even_colors.dart';
import '../core/utils/sensory_feedback.dart';
import '../models/satiety_matrix.dart';
import 'glass_card.dart';

/// Interactive EvenUpgrade Coaching Card
/// Provides 3-part hybrid coaching: Instant Add, Smart Swap, Meal habit.
class UpgradeCard extends StatefulWidget {
  final HybridUpgrade upgrade;
  final ValueChanged<bool>? onInstantAddChanged;
  final bool instantAddApplied;

  const UpgradeCard({
    super.key,
    required this.upgrade,
    this.onInstantAddChanged,
    this.instantAddApplied = false,
  });

  @override
  State<UpgradeCard> createState() => _UpgradeCardState();
}

class _UpgradeCardState extends State<UpgradeCard> {
  bool _appliedInstantAdd = false;
  bool _expandedSmartSwap = false;
  bool _completedCatalyst = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final appliedInstantAdd = widget.onInstantAddChanged != null
        ? widget.instantAddApplied
        : _appliedInstantAdd;

    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: EvenColors.bufferAmber.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.auto_awesome,
                      size: 16,
                      color: EvenColors.bufferAmber,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Ideas for this plate',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
              if (appliedInstantAdd || _completedCatalyst)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: EvenColors.netSage.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check,
                        size: 12,
                        color: EvenColors.stableHorizon,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Upgraded',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: EvenColors.stableHorizon,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // 1. Instant "Plus-One" Quick Add
          _buildInstantAddSection(isDark, appliedInstantAdd),

          const Divider(height: 24, thickness: 0.5),

          // 2. Next-Time Smart Swap
          _buildSmartSwapSection(isDark),

          const Divider(height: 24, thickness: 0.5),

          // 3. Meal habit
          _buildDigestiveCatalystSection(isDark),
        ],
      ),
    );
  }

  Widget _buildInstantAddSection(bool isDark, bool appliedInstantAdd) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.bolt_rounded,
              size: 18,
              color: EvenColors.anchorTerracotta,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Instant "Plus-One" Quick Add',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: EvenColors.anchorTerracotta,
                          letterSpacing: 0.2,
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          SensoryFeedback.gentleTap();
                          final next = !appliedInstantAdd;
                          if (widget.onInstantAddChanged == null) {
                            setState(() => _appliedInstantAdd = next);
                          }
                          widget.onInstantAddChanged?.call(next);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: appliedInstantAdd
                                ? EvenColors.stableHorizon.withValues(
                                    alpha: 0.2,
                                  )
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: appliedInstantAdd
                                  ? EvenColors.stableHorizon
                                  : (isDark ? Colors.white24 : Colors.black26),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                appliedInstantAdd
                                    ? Icons.check_circle_rounded
                                    : Icons.add_circle_outline_rounded,
                                size: 12,
                                color: appliedInstantAdd
                                    ? EvenColors.stableHorizon
                                    : (isDark
                                          ? EvenColors.textDarkMuted
                                          : EvenColors.textLightMuted),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                appliedInstantAdd ? 'Added' : 'I Added This',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: appliedInstantAdd
                                      ? EvenColors.stableHorizon
                                      : (isDark
                                            ? EvenColors.textDarkMuted
                                            : EvenColors.textLightMuted),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.upgrade.instantAdd,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: isDark
                          ? EvenColors.textDarkPrimary
                          : EvenColors.textLightPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSmartSwapSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.swap_horiz_rounded,
              size: 18,
              color: EvenColors.netSage,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Next-Time Smart Swap',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: EvenColors.netSageLight,
                          letterSpacing: 0.2,
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          SensoryFeedback.gentleTap();
                          setState(
                            () => _expandedSmartSwap = !_expandedSmartSwap,
                          );
                        },
                        child: Icon(
                          _expandedSmartSwap
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          size: 18,
                          color: isDark ? Colors.white54 : Colors.black45,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.upgrade.smartSwap,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: isDark
                          ? EvenColors.textDarkPrimary
                          : EvenColors.textLightPrimary,
                    ),
                  ),
                  if (_expandedSmartSwap) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: EvenColors.netSage.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'A pairing idea for next time.',
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.35,
                          fontStyle: FontStyle.italic,
                          color: isDark
                              ? EvenColors.textDarkSecondary
                              : EvenColors.textLightSecondary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDigestiveCatalystSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.water_drop_outlined,
              size: 18,
              color: EvenColors.bufferAmber,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Meal habit',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: EvenColors.bufferAmber,
                          letterSpacing: 0.2,
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          SensoryFeedback.gentleTap();
                          setState(
                            () => _completedCatalyst = !_completedCatalyst,
                          );
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _completedCatalyst
                                ? EvenColors.bufferAmber.withValues(alpha: 0.2)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _completedCatalyst
                                  ? EvenColors.bufferAmber
                                  : (isDark ? Colors.white24 : Colors.black26),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _completedCatalyst
                                    ? Icons.done_all_rounded
                                    : Icons.radio_button_unchecked_rounded,
                                size: 12,
                                color: _completedCatalyst
                                    ? EvenColors.bufferAmber
                                    : (isDark
                                          ? EvenColors.textDarkMuted
                                          : EvenColors.textLightMuted),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _completedCatalyst ? 'Done' : 'Mark Done',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: _completedCatalyst
                                      ? EvenColors.bufferAmber
                                      : (isDark
                                            ? EvenColors.textDarkMuted
                                            : EvenColors.textLightMuted),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.upgrade.digestiveCatalyst,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: isDark
                          ? EvenColors.textDarkPrimary
                          : EvenColors.textLightPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
