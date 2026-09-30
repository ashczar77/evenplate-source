import 'package:flutter/material.dart';
import '../../core/theme/even_colors.dart';
import 'satiety_insight_state.dart';

/// In-theme mark for scan insight dialogs. No stock cartoons.
class InsightMark extends StatelessWidget {
  final InsightStateType type;

  const InsightMark({super.key, required this.type});

  @override
  Widget build(BuildContext context) {
    final asset = _assetFor(type);
    if (asset != null) {
      return ClipOval(
        child: Image.asset(
          asset.path,
          height: 168,
          width: 168,
          fit: BoxFit.cover,
          semanticLabel: asset.label,
        ),
      );
    }

    return Container(
      height: 148,
      width: 148,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: EvenColors.primaryGreen.withValues(alpha: 0.12),
        border: Border.all(
          color: EvenColors.primaryGreen.withValues(alpha: 0.35),
        ),
      ),
      child: Icon(_iconFor(type), size: 56, color: EvenColors.primaryGreen),
    );
  }

  static ({String path, String label})? _assetFor(InsightStateType type) {
    switch (type) {
      case InsightStateType.notFood:
        return (
          path: 'assets/images/insights/cloche.png',
          label: "Oops, doesn't look like food",
        );
      case InsightStateType.apiError:
        return (
          path: 'assets/images/insights/closed_cloche.png',
          label: 'Analysis temporarily unavailable',
        );
      case InsightStateType.tooDark:
        return (path: 'assets/images/insights/too_dark.png', label: 'Too dark');
      case InsightStateType.blurry:
        return (
          path: 'assets/images/insights/blurry.png',
          label: 'A bit blurry',
        );
      case InsightStateType.weeklyLimit:
        return (
          path: 'assets/images/insights/weekly_limit.png',
          label: 'Weekly Scans Complete',
        );
      default:
        return null;
    }
  }

  static IconData _iconFor(InsightStateType type) {
    switch (type) {
      case InsightStateType.tooDark:
        return Icons.wb_twilight_outlined;
      case InsightStateType.blurry:
        return Icons.filter_center_focus;
      case InsightStateType.notFood:
        return Icons.no_meals_outlined;
      case InsightStateType.apiError:
        return Icons.cloud_off_outlined;
      case InsightStateType.weeklyLimit:
        return Icons.event_busy_outlined;
      case InsightStateType.sugarSpike:
        return Icons.trending_down_rounded;
      case InsightStateType.missingAnchor:
        return Icons.restaurant_rounded;
      case InsightStateType.missingNet:
        return Icons.eco_outlined;
      case InsightStateType.missingBuffer:
        return Icons.water_drop_outlined;
      case InsightStateType.emptyEngine:
        return Icons.hourglass_empty_rounded;
      default:
        return Icons.insights_outlined;
    }
  }
}
