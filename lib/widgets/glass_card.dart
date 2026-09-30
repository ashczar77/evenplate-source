import 'package:flutter/material.dart';
import '../core/theme/even_glass.dart';

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final double blur;
  final Color? customFill;
  final Color? customBorder;
  final VoidCallback? onTap;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.radius = EvenGlass.defaultRadius,
    this.blur = EvenGlass.defaultBlur,
    this.customFill,
    this.customBorder,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return EvenGlass.frostedCard(
      context: context,
      padding: padding,
      radius: radius,
      blur: blur,
      customFill: customFill,
      customBorder: customBorder,
      onTap: onTap,
      child: child,
    );
  }
}
