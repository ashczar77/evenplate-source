import 'package:flutter/material.dart';
import '../core/theme/even_colors.dart';

/// Leaf mark plus EvenPlate word. The home-screen icon stays a filled
/// square; this lockup uses the cropped mark so it sits on the app canvas
/// without a black tile.
class EvenBrandLockup extends StatelessWidget {
  final double markSize;
  final double wordSize;
  final bool showTagline;
  final String tagline;
  final bool useTheme;

  static const assetPath = 'assets/branding/mark.png';

  const EvenBrandLockup({
    super.key,
    this.markSize = 72,
    this.wordSize = 28,
    this.showTagline = false,
    this.tagline = 'Balanced meals. Steady energy. Zero calorie counting.',
    this.useTheme = true,
  });

  @override
  Widget build(BuildContext context) {
    final wordStyle = useTheme
        ? Theme.of(
            context,
          ).textTheme.displayMedium?.copyWith(fontSize: wordSize)
        : TextStyle(
            fontSize: wordSize,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: -0.8,
          );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          assetPath,
          width: markSize,
          height: markSize,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          cacheWidth: (markSize * 3).round().clamp(64, 512).toInt(),
          cacheHeight: (markSize * 3).round().clamp(64, 512).toInt(),
          errorBuilder: (context, error, stackTrace) {
            return SizedBox(
              width: markSize,
              height: markSize,
              child: Icon(
                Icons.eco_rounded,
                color: EvenColors.primaryGreen,
                size: markSize * 0.5,
              ),
            );
          },
        ),
        SizedBox(height: markSize * 0.18),
        Text.rich(
          TextSpan(
            style: wordStyle,
            children: const [
              TextSpan(text: 'Even'),
              TextSpan(
                text: 'Plate',
                style: TextStyle(color: EvenColors.primaryGreen),
              ),
            ],
          ),
        ),
        if (showTagline) ...[
          const SizedBox(height: 6),
          Text(
            tagline,
            textAlign: TextAlign.center,
            style: useTheme
                ? Theme.of(context).textTheme.bodyMedium
                : const TextStyle(
                    fontSize: 13,
                    color: EvenColors.textDarkMuted,
                  ),
          ),
        ],
      ],
    );
  }
}
