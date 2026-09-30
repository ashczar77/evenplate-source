import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/a11y/access.dart';
import '../core/theme/even_colors.dart';

/// Custom canvas painter for the Concentric Triple Harmony Rings
/// Inspired by Apple Health, Oura, and biophilic zen aesthetics.
///
/// Ring Structure (Outer to Inner):
/// 1. Outer Ring: Anchor (Protein, terracotta glow)
/// 2. Middle Ring: Net (Prebiotic fiber, sage glow)
/// 3. Inner Ring: Satiety Horizon (Sustained energy hours, amber glow)
class HarmonyRingsPainter extends CustomPainter {
  final double anchorProgress;
  final double netProgress;
  final double horizonProgress;
  final double strokeWidth;
  final double gap;
  final bool showCenterGlow;

  const HarmonyRingsPainter({
    required this.anchorProgress,
    required this.netProgress,
    required this.horizonProgress,
    this.strokeWidth = 12.0,
    this.gap = 5.5,
    this.showCenterGlow = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = math.min(size.width, size.height) / 2 - (strokeWidth / 2);

    final outerRadius = maxRadius;
    final middleRadius = outerRadius - strokeWidth - gap;
    final innerRadius = middleRadius - strokeWidth - gap;

    // 1. Outer Ring: Anchor (Protein)
    _drawRing(
      canvas: canvas,
      center: center,
      radius: outerRadius,
      progress: anchorProgress,
      color: EvenColors.anchorTerracotta,
      glowColor: EvenColors.anchorGlow,
    );

    // 2. Middle Ring: Net (Fiber)
    _drawRing(
      canvas: canvas,
      center: center,
      radius: middleRadius,
      progress: netProgress,
      color: EvenColors.netSageLight,
      glowColor: EvenColors.netGlow,
    );

    // 3. Inner Ring: Satiety Horizon (Energy hours)
    _drawRing(
      canvas: canvas,
      center: center,
      radius: innerRadius,
      progress: horizonProgress,
      color: EvenColors.bufferAmber,
      glowColor: EvenColors.bufferGlow,
    );

    // 4. Center Harmony Seal: Subtle radiance when daily balance is active
    if (showCenterGlow && innerRadius > strokeWidth) {
      _drawCenterZenCore(canvas, center, innerRadius - (strokeWidth / 2) - 2);
    }
  }

  void _drawRing({
    required Canvas canvas,
    required Offset center,
    required double radius,
    required double progress,
    required Color color,
    required Color glowColor,
  }) {
    if (radius <= 0) return;

    // Track Background (Muted translucent ring)
    final trackPaint = Paint()
      ..color = color.withValues(alpha: 0.14)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);

    if (progress <= 0.001) return;

    final sweepAngle = 2 * math.pi * progress;
    const startAngle = -math.pi / 2;

    // Layer 1: Diffused Bioluminescent Glow
    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth + 4.5
      ..maskFilter = safeMaskBlur(4.0);

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      math.min(sweepAngle, 2 * math.pi),
      false,
      glowPaint,
    );

    // Layer 2: Main Solid Progress Arc with Rounded Caps
    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromCircle(center: center, radius: radius);

    if (progress <= 1.0) {
      canvas.drawArc(rect, startAngle, sweepAngle, false, progressPaint);
    } else {
      // Over-completion loop: Draw full base circle, then overlap arc
      canvas.drawArc(rect, startAngle, 2 * math.pi, false, progressPaint);

      // Overlap shadow under the head to give tactile 3D depth
      final overlapAngle = 2 * math.pi * (progress - 1.0).clamp(0.0, 1.0);
      final shadowCapAngle = startAngle + overlapAngle;
      final capCenter = Offset(
        center.dx + radius * math.cos(shadowCapAngle),
        center.dy + radius * math.sin(shadowCapAngle),
      );

      final shadowPaint = Paint()
        ..color = Colors.black.withValues(alpha: 0.45)
        ..maskFilter = safeMaskBlur(3.5);
      canvas.drawCircle(capCenter, strokeWidth / 2, shadowPaint);

      // Overlap arc
      canvas.drawArc(rect, startAngle, overlapAngle, false, progressPaint);
    }

    // Layer 3: Completed Glint Starburst Particle (when ring reaches 100%)
    if (progress >= 1.0) {
      final apex = Offset(center.dx, center.dy - radius);
      final starAura = Paint()
        ..color = Colors.white.withValues(alpha: 0.7)
        ..maskFilter = safeMaskBlur(2.5);
      final starCore = Paint()..color = Colors.white;

      canvas.drawCircle(apex, 2.8, starAura);
      canvas.drawCircle(apex, 1.4, starCore);
    }
  }

  void _drawCenterZenCore(Canvas canvas, Offset center, double coreRadius) {
    if (coreRadius <= 2) return;

    final isAllClosed =
        anchorProgress >= 1.0 && netProgress >= 1.0 && horizonProgress >= 1.0;

    final corePaint = Paint()
      ..color = (isAllClosed ? EvenColors.stableHorizon : EvenColors.netSage)
          .withValues(alpha: isAllClosed ? 0.25 : 0.08)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, coreRadius, corePaint);

    if (isAllClosed) {
      final ringPaint = Paint()
        ..color = EvenColors.stableHorizon.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      canvas.drawCircle(center, coreRadius, ringPaint);
    }
  }

  @override
  bool shouldRepaint(covariant HarmonyRingsPainter oldDelegate) {
    return oldDelegate.anchorProgress != anchorProgress ||
        oldDelegate.netProgress != netProgress ||
        oldDelegate.horizonProgress != horizonProgress ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.gap != gap ||
        oldDelegate.showCenterGlow != showCenterGlow;
  }
}
