import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/a11y/access.dart';
import '../core/theme/even_colors.dart';

/// A premium, organic "liquid" orb animation used for AI loading states.
/// It uses multiple rotating, semi-transparent gradients to simulate a "thinking" brain.
class AiThinkingOrb extends StatefulWidget {
  final double size;
  final String statusText;

  const AiThinkingOrb({
    super.key,
    this.size = 120.0,
    this.statusText =
        'Just a minute. Our in-house chef is analyzing your meal.',
  });

  @override
  State<AiThinkingOrb> createState() => _AiThinkingOrbState();
}

class _AiThinkingOrbState extends State<AiThinkingOrb>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: widget.size,
          height: widget.size,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  // Base glow
                  Container(
                    width: widget.size * 0.8,
                    height: widget.size * 0.8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: safeBoxShadows([
                        BoxShadow(
                          color: EvenColors.primaryGreen.withValues(alpha: 0.3),
                          blurRadius: 40,
                          spreadRadius: 10,
                        ),
                      ]),
                    ),
                  ),
                  // Rotating liquid blob 1
                  Transform.rotate(
                    angle: _controller.value * 2 * math.pi,
                    child: _buildBlob(
                      color: EvenColors.netSage.withValues(alpha: 0.7),
                      offset: Offset(
                        math.sin(_controller.value * math.pi * 2) * 10,
                        math.cos(_controller.value * math.pi * 2) * 10,
                      ),
                    ),
                  ),
                  // Rotating liquid blob 2 (counter-rotating)
                  Transform.rotate(
                    angle: -_controller.value * 2 * math.pi,
                    child: _buildBlob(
                      color: EvenColors.bufferAmber.withValues(alpha: 0.6),
                      offset: Offset(
                        math.cos(_controller.value * math.pi * 2) * 8,
                        math.sin(_controller.value * math.pi * 2) * 8,
                      ),
                    ),
                  ),
                  // Rotating liquid blob 3 (faster)
                  Transform.rotate(
                    angle: _controller.value * 4 * math.pi,
                    child: _buildBlob(
                      color: EvenColors.anchorTerracotta.withValues(alpha: 0.5),
                      offset: Offset(
                        math.sin(_controller.value * math.pi * 4) * 6,
                        math.cos(_controller.value * math.pi * 4) * 6,
                      ),
                      scale: 0.8,
                    ),
                  ),
                  // Center core
                  Container(
                    width: widget.size * 0.4,
                    height: widget.size * 0.4,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: safeBoxShadows(const [
                        BoxShadow(
                          color: Colors.white,
                          blurRadius: 15,
                          spreadRadius: 2,
                        ),
                      ]),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 24),
        // Pulsing text
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final opacity =
                0.5 + (math.sin(_controller.value * math.pi * 4) + 1) / 4;
            return Opacity(
              opacity: opacity,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Text(
                  widget.statusText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildBlob({
    required Color color,
    required Offset offset,
    double scale = 1.0,
  }) {
    return Transform.translate(
      offset: offset,
      child: Transform.scale(
        scale: scale,
        child: Container(
          width: widget.size * 0.7,
          height: widget.size * 0.7,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(50),
              topRight: const Radius.circular(60),
              bottomLeft: const Radius.circular(40),
              bottomRight: const Radius.circular(70),
            ),
          ),
        ),
      ),
    );
  }
}
