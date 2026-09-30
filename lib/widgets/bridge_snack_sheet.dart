import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../core/theme/even_colors.dart';
import '../core/utils/sensory_feedback.dart';
import '../models/meal_log.dart';
import '../services/local_storage_service.dart';
import '../services/food_list_scorer.dart';
import 'even_snack.dart';
import 'glass_card.dart';

/// Organic Zen Glass Modal Sheet for Instant 30-Second Energy Fixes
/// Triggered when the user reports a satiety or glucose energy dip.
class BridgeSnackSheet extends StatefulWidget {
  final LocalStorageService storage;
  final MealLog? applyTo;
  final VoidCallback? onLogged;

  const BridgeSnackSheet({
    super.key,
    required this.storage,
    this.applyTo,
    this.onLogged,
  });

  static Future<void> show(
    BuildContext context,
    LocalStorageService storage, {
    MealLog? applyTo,
  }) {
    SensoryFeedback.gentleTap();
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BridgeSnackSheet(storage: storage, applyTo: applyTo),
    );
  }

  @override
  State<BridgeSnackSheet> createState() => _BridgeSnackSheetState();
}

class _BridgeSnackSheetState extends State<BridgeSnackSheet> {
  LocalStorageService get storage => widget.storage;
  MealLog? get applyTo => widget.applyTo;
  bool _busy = false;
  bool _saved = false;
  String? _selectedName;
  final String _logId = const Uuid().v4();
  String? _error;

  List<String> _foodsFor(String pillarType) {
    switch (pillarType) {
      case 'buffer':
        return storage.userProfile.dietaryPreference.contains('Sensitive')
            ? const ['Olive oil']
            : const ['Almonds'];
      case 'anchor':
        return storage.userProfile.dietaryPreference.contains('Vegan')
            ? const ['Tofu']
            : const ['Hardboiled egg'];
      case 'spark':
        return const ['Cucumber', 'Hummus'];
      default:
        return const ['Green tea'];
    }
  }

  void _logSnack(BuildContext context, String name, String pillarType) async {
    if (_busy || _saved) return;
    final owner = storage.userProfile.id;
    setState(() {
      _busy = true;
      _selectedName = name;
      _error = null;
    });
    try {
      final outcome = await FoodListScorer.instance.score(
        mealName: name,
        foods: _foodsFor(pillarType),
      );
      if (!mounted || storage.userProfile.id != owner) return;
      await storage.applyFoodsQuota(outcome.quota);
      if (!mounted || storage.userProfile.id != owner) return;
      if (!outcome.settled ||
          !outcome.isFood ||
          outcome.rejected.isNotEmpty ||
          !outcome.result.hasModelAssessment) {
        setState(() {
          _error =
              outcome.failureMessage ??
              'Could not assess this snack. Please try again.';
        });
        return;
      }
      final parent = applyTo;
      final log = MealLog(
        id: _logId,
        mealName: name,
        timestamp: DateTime.now(),
        satietyResult: outcome.result,
        isBridgeFix: true,
        bridgedFromId: parent?.id,
      );
      await storage.addMealLog(log);
      _saved = true;
      if (storage.userProfile.id != owner) return;
      if (parent != null) {
        await storage.updateMealEnergyCheckIn(parent.id, 'dip');
      }
      if (!context.mounted) return;
      Navigator.of(context).pop();
      EvenSnack.show(
        context,
        '$name logged. Check how you feel later.',
        icon: Icons.check_circle_rounded,
      );
      widget.onLogged?.call();
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not assess this snack. Please try again.';
        });
      }
    } finally {
      if (mounted && !_saved) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? EvenColors.darkSurfaceElevated
            : EvenColors.lightSurfaceElevated,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(
          color: isDark
              ? EvenColors.darkGlassBorder
              : EvenColors.lightGlassBorder,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black26,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: EvenColors.bufferAmber.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.energy_savings_leaf_rounded,
                      color: EvenColors.bufferAmber,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'The 30-Second Bridge Fix',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Choose foods you tolerate. Check ingredients for allergens.',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? EvenColors.textDarkSecondary
                                : EvenColors.textLightSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              if (_busy) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                const Text('Assessing snack...'),
                const SizedBox(height: 12),
              ],
              if (_error != null) ...[
                Text(
                  _error!,
                  style: const TextStyle(color: EvenColors.anchorTerracotta),
                ),
                const SizedBox(height: 12),
              ],

              // Snack Options
              _buildSnackTile(
                context: context,
                icon: Icons.spa_outlined,
                title:
                    storage.userProfile.dietaryPreference.contains('Sensitive')
                    ? 'Olive Oil with a Tolerated Snack'
                    : 'Handful of Raw Almonds',
                subtitle:
                    'Healthy lipids buffer glycemic swings and smooth energy.',
                pillarType: 'buffer',
                badge: 'Buffer Fix',
                color: EvenColors.bufferAmber,
              ),
              const SizedBox(height: 10),
              _buildSnackTile(
                context: context,
                icon: Icons.egg_alt_outlined,
                title: storage.userProfile.dietaryPreference.contains('Vegan')
                    ? 'Tofu'
                    : 'Hardboiled Egg',
                subtitle: 'A simple protein option for a more filling snack.',
                pillarType: 'anchor',
                badge: 'Anchor Fix',
                color: EvenColors.anchorTerracotta,
              ),
              const SizedBox(height: 10),
              _buildSnackTile(
                context: context,
                icon: Icons.emoji_food_beverage_outlined,
                title: 'Warm Matcha or Green Tea',
                subtitle:
                    'Cellular rehydration + L-theanine calm for mental clarity.',
                pillarType: 'catalyst',
                badge: 'Catalyst Fix',
                color: EvenColors.netSage,
              ),
              const SizedBox(height: 10),
              _buildSnackTile(
                context: context,
                icon: Icons.eco_outlined,
                title: 'Cucumber Sticks with Hummus',
                subtitle:
                    'Crunch volume + sesame seed lipids satisfy sensory chewing.',
                pillarType: 'spark',
                badge: 'Crunch',
                color: EvenColors.sparkBlush,
              ),

              const SizedBox(height: 18),

              // Dismiss Button
              TextButton(
                key: const ValueKey('btn_dismiss_bridge_sheet'),
                onPressed: _busy || _saved
                    ? null
                    : () => Navigator.of(context).pop(),
                child: const Text('I will power through (Dismiss)'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSnackTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required String pillarType,
    required String badge,
    required Color color,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Opacity(
      opacity: (_busy || _saved) && title != _selectedName ? 0.4 : 1,
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        radius: 16,
        child: InkWell(
          onTap: _busy || _saved
              ? null
              : () => _logSnack(context, title, pillarType),
          borderRadius: BorderRadius.circular(16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            badge,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: color,
                            ),
                          ),
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
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (_busy && title == _selectedName)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                  ),
                )
              else
                Icon(Icons.add_circle_outline_rounded, size: 20, color: color),
            ],
          ),
        ),
      ),
    );
  }
}
