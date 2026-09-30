import 'package:flutter/material.dart';
import '../core/a11y/access.dart';
import '../core/utils/sensory_feedback.dart';
import 'harmony_rings_painter.dart';

/// Animated Triple Harmony Rings Widget with Spring Physics
/// Displays the 3 concentric rings (Anchor, Net, Horizon) with staggered spring animation.
class HarmonyRingsWidget extends StatefulWidget {
  final double anchorProgress;
  final double netProgress;
  final double horizonProgress;
  final double size;
  final double strokeWidth;
  final double gap;
  final bool interactive;

  const HarmonyRingsWidget({
    super.key,
    required this.anchorProgress,
    required this.netProgress,
    required this.horizonProgress,
    this.size = 130.0,
    this.strokeWidth = 12.0,
    this.gap = 5.5,
    this.interactive = true,
  });

  @override
  State<HarmonyRingsWidget> createState() => _HarmonyRingsWidgetState();
}

class _HarmonyRingsWidgetState extends State<HarmonyRingsWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _anchorAnimation;
  late Animation<double> _netAnimation;
  late Animation<double> _horizonAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _buildAnimations(
      fromAnchor: 0.0,
      toAnchor: widget.anchorProgress,
      fromNet: 0.0,
      toNet: widget.netProgress,
      fromHorizon: 0.0,
      toHorizon: widget.horizonProgress,
    );

    _controller.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (prefersReducedMotion(context) && _controller.value < 1.0) {
      _controller.value = 1.0;
    }
  }

  void _buildAnimations({
    required double fromAnchor,
    required double toAnchor,
    required double fromNet,
    required double toNet,
    required double fromHorizon,
    required double toHorizon,
  }) {
    // Staggered spring animations for organic feeling
    _anchorAnimation = Tween<double>(begin: fromAnchor, end: toAnchor).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.75, curve: Curves.easeOutCubic),
      ),
    );

    _netAnimation = Tween<double>(begin: fromNet, end: toNet).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.15, 0.88, curve: Curves.easeOutCubic),
      ),
    );

    _horizonAnimation = Tween<double>(begin: fromHorizon, end: toHorizon)
        .animate(
          CurvedAnimation(
            parent: _controller,
            curve: const Interval(0.28, 1.0, curve: Curves.easeOutBack),
          ),
        );
  }

  @override
  void didUpdateWidget(covariant HarmonyRingsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.anchorProgress != widget.anchorProgress ||
        oldWidget.netProgress != widget.netProgress ||
        oldWidget.horizonProgress != widget.horizonProgress) {
      _buildAnimations(
        fromAnchor: _anchorAnimation.value,
        toAnchor: widget.anchorProgress,
        fromNet: _netAnimation.value,
        toNet: widget.netProgress,
        fromHorizon: _horizonAnimation.value,
        toHorizon: widget.horizonProgress,
      );
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (!widget.interactive) return;
    SensoryFeedback.gentleTap();
    if (prefersReducedMotion(context)) return;
    _controller.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    final label =
        'Harmony rings. Anchor ${(widget.anchorProgress * 100).round()} percent, '
        'Net ${(widget.netProgress * 100).round()} percent, '
        'Horizon ${(widget.horizonProgress * 100).round()} percent.';

    return Semantics(
      label: label,
      button: widget.interactive,
      child: GestureDetector(
        onTap: _handleTap,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return SizedBox(
              width: widget.size,
              height: widget.size,
              child: CustomPaint(
                painter: HarmonyRingsPainter(
                  anchorProgress: _anchorAnimation.value,
                  netProgress: _netAnimation.value,
                  horizonProgress: _horizonAnimation.value,
                  strokeWidth: widget.strokeWidth,
                  gap: widget.gap,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
