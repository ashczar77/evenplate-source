import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/a11y/access.dart';
import '../core/theme/even_colors.dart';
import '../core/theme/even_fonts.dart';

class SatietyEngineWidget extends StatefulWidget {
  final double proteinProgress;
  final double fiberProgress;
  final double fatsProgress;
  final double carbsProgress;

  const SatietyEngineWidget({
    super.key,
    required this.proteinProgress,
    required this.fiberProgress,
    required this.fatsProgress,
    required this.carbsProgress,
  });

  @override
  State<SatietyEngineWidget> createState() => _SatietyEngineWidgetState();
}

class _SatietyEngineWidgetState extends State<SatietyEngineWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (prefersReducedMotion(context)) {
      _controller.stop();
      _controller.value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final phase = _controller.value * 2 * math.pi;
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _LiquidChamber(
              label: 'PROTEIN',
              progress: widget.proteinProgress,
              color: EvenColors.anchorTerracotta,
              phase: phase,
            ),
            _LiquidChamber(
              label: 'FIBER',
              progress: widget.fiberProgress,
              color: EvenColors.netSage,
              phase: phase + 1.1,
            ),
            _LiquidChamber(
              label: 'FAT',
              progress: widget.fatsProgress,
              color: EvenColors.bufferAmber,
              phase: phase + 2.3,
            ),
            _LiquidChamber(
              label: 'VOLUME',
              progress: widget.carbsProgress,
              color: EvenColors.sparkBlush,
              phase: phase + 3.4,
            ),
          ],
        );
      },
    );
  }
}

class _LiquidChamber extends StatelessWidget {
  final String label;
  final double progress;
  final Color color;
  final double phase;

  const _LiquidChamber({
    required this.label,
    required this.progress,
    required this.color,
    required this.phase,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final over = progress > 1.0;

    return Semantics(
      label: over ? '$label chamber, over target' : '$label chamber',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: evenPoppins(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: isDark
                  ? EvenColors.textDarkMuted
                  : EvenColors.textLightMuted,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: 52,
            height: 190,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              color: isDark ? const Color(0x1AFFFFFF) : const Color(0x0F000000),
              border: Border.all(
                color: isDark
                    ? EvenColors.darkGlassBorder
                    : EvenColors.lightGlassBorder,
                width: 1.5,
              ),
              boxShadow: safeBoxShadows([
                BoxShadow(
                  color: color.withValues(alpha: 0.25),
                  blurRadius: 12,
                  spreadRadius: 0,
                ),
              ]),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24.5),
              child: CustomPaint(
                size: const Size(52, 190),
                painter: _LiquidPainter(
                  progress: progress,
                  color: color,
                  phase: phase,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiquidPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double phase;

  _LiquidPainter({
    required this.progress,
    required this.color,
    required this.phase,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;

    final visual = progress.clamp(0.0, 1.0);
    final fillFraction = 0.08 + (visual * 0.82);
    final fillHeight = size.height * fillFraction;
    final topY = size.height - fillHeight;
    final waveAmplitude = progress >= 1.0 ? 2.8 : 3.6;
    final water = Color.lerp(color, const Color(0xFFD7F3FF), 0.22)!;

    double surfaceY(double x, double shift) {
      final nx = x / size.width;
      return topY +
          math.sin(nx * 1.7 * math.pi + phase + shift) * waveAmplitude +
          math.sin(nx * 3.1 * math.pi + phase * 0.85 + shift) *
              (waveAmplitude * 0.35);
    }

    Path fillPath(double shift) {
      final path = Path()
        ..moveTo(0, size.height)
        ..lineTo(0, surfaceY(0, shift));
      for (double x = 1; x <= size.width; x++) {
        path.lineTo(x, surfaceY(x, shift));
      }
      path
        ..lineTo(size.width, size.height)
        ..close();
      return path;
    }

    canvas.drawPath(
      fillPath(math.pi / 2),
      Paint()..color = water.withValues(alpha: 0.2),
    );

    canvas.drawPath(
      fillPath(0),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            water.withValues(alpha: 0.78),
            water.withValues(alpha: 0.48),
            Color.lerp(water, Colors.white, 0.35)!.withValues(alpha: 0.28),
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(Rect.fromLTWH(0, topY, size.width, fillHeight)),
    );

    _paintBubbles(canvas, size, topY, fillHeight);

    final rim = Path()..moveTo(0, surfaceY(0, 0));
    for (double x = 1; x <= size.width; x++) {
      rim.lineTo(x, surfaceY(x, 0));
    }
    canvas.drawPath(
      rim,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.8),
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(4, 8, size.width * 0.22, size.height - 16),
        const Radius.circular(12),
      ),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.white.withValues(alpha: 0.28),
            Colors.white.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );
  }

  void _paintBubbles(Canvas canvas, Size size, double topY, double fillHeight) {
    final travel = fillHeight - 20;
    if (travel <= 12) return;

    for (int i = 0; i < 5; i++) {
      final speed = 0.18 + i * 0.05;
      final t = _fract(phase * speed / (2 * math.pi) + i * 0.23);
      final fade = math.sin(t * math.pi);
      if (fade <= 0.04) continue;

      final x =
          size.width * (0.24 + (i * 0.13) % 0.52) +
          math.sin(phase * 0.6 + i) * 2.2;
      final y = size.height - 12 - t * travel;
      if (y < topY + 6) continue;

      final r = 1.3 + (i % 3) * 0.45;
      final alpha = 0.22 + fade * 0.35;
      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = Colors.white.withValues(alpha: alpha),
      );
      canvas.drawCircle(
        Offset(x - r * 0.25, y - r * 0.28),
        r * 0.25,
        Paint()..color = Colors.white.withValues(alpha: alpha * 0.9),
      );
    }
  }

  static double _fract(double value) => value - value.floorToDouble();

  @override
  bool shouldRepaint(covariant _LiquidPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.phase != phase;
  }
}
