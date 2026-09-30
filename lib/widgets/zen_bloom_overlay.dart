import 'dart:ui';
import 'package:flutter/material.dart';
import '../core/a11y/access.dart';
import '../core/theme/even_colors.dart';
import '../core/utils/sensory_feedback.dart';

/// Animated Bioluminescent Zen Bloom Overlay
/// Displays expanding harmonic aura ripples and a resonance seal
/// to celebrate meal logging and ring closure.
class ZenBloomOverlay extends StatefulWidget {
  final String mealName;
  final double durationHours;
  final int pillarsAligned;
  final VoidCallback onComplete;
  final bool animate;
  final bool autoDismiss;

  const ZenBloomOverlay({
    super.key,
    required this.mealName,
    required this.durationHours,
    required this.pillarsAligned,
    required this.onComplete,
    this.animate = true,
    this.autoDismiss = true,
  });

  @override
  State<ZenBloomOverlay> createState() => _ZenBloomOverlayState();
}

class _ZenBloomOverlayState extends State<ZenBloomOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _waveAnimation;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.35, curve: Curves.easeIn),
    );

    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.1, 0.7, curve: Curves.easeOutBack),
    );

    _waveAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.15, 1.0, curve: Curves.easeOutCubic),
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && widget.autoDismiss) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _dismiss();
          }
        });
      }
    });

    if (widget.animate) {
      _controller.forward();
      SensoryFeedback.zenBloomPulse();
    } else {
      _controller.value = 1.0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (prefersReducedMotion(context) && widget.animate) {
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _dismiss() {
    if (_dismissed) return;
    _dismissed = true;
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return FadeTransition(
          opacity: _fadeAnimation,
          child: GestureDetector(
            key: const ValueKey('zen_bloom_overlay'),
            onTap: _dismiss,
            behavior: HitTestBehavior.opaque,
            child: Material(
              color: Colors.transparent,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Frosted glass backdrop. Skip on the iOS Simulator; Impeller
                  // SIGABRTs if SimMetalHost drops mid-blur.
                  if (useBackdropBlur(context))
                    BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.72),
                      ),
                    )
                  else
                    Container(color: Colors.black.withValues(alpha: 0.72)),

                  // Expanding bioluminescent radial aura waves
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _ZenBloomWavePainter(
                        waveProgress: _waveAnimation.value,
                      ),
                    ),
                  ),

                  // Central Harmonic Seal Card
                  Transform.scale(
                    scale: _scaleAnimation.value,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 340),
                      margin: const EdgeInsets.symmetric(horizontal: 24),
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: EvenColors.darkSurfaceElevated.withValues(
                          alpha: 0.90,
                        ),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: EvenColors.stableHorizon.withValues(
                            alpha: 0.45,
                          ),
                          width: 1.5,
                        ),
                        boxShadow: safeBoxShadows([
                          BoxShadow(
                            color: EvenColors.stableHorizon.withValues(
                              alpha: 0.25,
                            ),
                            blurRadius: 36,
                            spreadRadius: 4,
                          ),
                          BoxShadow(
                            color: EvenColors.anchorTerracotta.withValues(
                              alpha: 0.15,
                            ),
                            blurRadius: 48,
                            spreadRadius: 8,
                          ),
                        ]),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Radiant Ring Mandala Glyph
                          Container(
                            width: 76,
                            height: 76,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  EvenColors.stableHorizon.withValues(
                                    alpha: 0.3,
                                  ),
                                  EvenColors.netSage.withValues(alpha: 0.1),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                            child: Center(
                              child: Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: EvenColors.stableHorizon.withValues(
                                    alpha: 0.2,
                                  ),
                                  border: Border.all(
                                    color: EvenColors.stableHorizon,
                                    width: 2,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.check_rounded,
                                  color: EvenColors.stableHorizon,
                                  size: 30,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 16),

                          const Text(
                            'Plate Harmonized',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: -0.5,
                            ),
                          ),

                          const SizedBox(height: 8),

                          Text(
                            widget.mealName,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: EvenColors.textDarkSecondary,
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Satiety Horizon & Alignment Badges
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: EvenColors.stableHorizon.withValues(
                                alpha: 0.15,
                              ),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: EvenColors.stableHorizon.withValues(
                                  alpha: 0.3,
                                ),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.hourglass_top_rounded,
                                  size: 15,
                                  color: EvenColors.stableHorizon,
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    'Plate saved to your diary',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: EvenColors.stableHorizon,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 8),

                          Text(
                            '${widget.pillarsAligned}/4 Pillars Locked in Equilibrium',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: EvenColors.textDarkMuted,
                            ),
                          ),

                          const SizedBox(height: 22),

                          // Return / Continue Button
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              key: const ValueKey('btn_zen_bloom_done'),
                              onPressed: _dismiss,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: EvenColors.stableHorizon,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                elevation: 0,
                              ),
                              child: const Text(
                                'Done',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Custom painter for expanding concentric bioluminescent ripples
class _ZenBloomWavePainter extends CustomPainter {
  final double waveProgress;

  _ZenBloomWavePainter({required this.waveProgress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width * 0.75;

    final rings = [
      {'color': EvenColors.stableHorizon, 'offset': 0.0, 'width': 3.0},
      {'color': EvenColors.anchorTerracotta, 'offset': 0.15, 'width': 2.5},
      {'color': EvenColors.bufferAmber, 'offset': 0.30, 'width': 2.0},
    ];

    for (final ring in rings) {
      final ringOffset = ring['offset'] as double;
      final strokeWidth = ring['width'] as double;
      final color = ring['color'] as Color;

      final progress =
          (waveProgress - ringOffset).clamp(0.0, 1.0) / (1.0 - ringOffset);
      if (progress <= 0.0) continue;

      final radius = 50 + (maxRadius * progress);
      final alpha = ((1.0 - progress) * 0.45).clamp(0.0, 1.0);

      final paint = Paint()
        ..color = color.withValues(alpha: alpha)
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke;

      canvas.drawCircle(center, radius, paint);

      // Soft glow shadow for each wave
      final glowPaint = Paint()
        ..color = color.withValues(alpha: alpha * 0.35)
        ..strokeWidth = strokeWidth * 3.5
        ..style = PaintingStyle.stroke
        ..maskFilter = safeMaskBlur(8);

      canvas.drawCircle(center, radius, glowPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ZenBloomWavePainter oldDelegate) {
    return oldDelegate.waveProgress != waveProgress;
  }
}
