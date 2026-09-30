import 'package:flutter/material.dart';
import '../../core/theme/even_colors.dart';
import '../../core/utils/sensory_feedback.dart';
import '../../models/meal_log.dart';
import '../../models/satiety_matrix.dart';
import '../../services/local_storage_service.dart';
import '../../widgets/glass_card.dart';

/// Typed diary entry. Does not call vision and does not consume a scan credit.
class ManualMealSheet extends StatefulWidget {
  final LocalStorageService storage;

  const ManualMealSheet({super.key, required this.storage});

  static Future<void> show(BuildContext context, LocalStorageService storage) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ManualMealSheet(storage: storage),
    );
  }

  @override
  State<ManualMealSheet> createState() => _ManualMealSheetState();
}

class _ManualMealSheetState extends State<ManualMealSheet> {
  final _name = TextEditingController();
  bool _anchor = true;
  bool _net = false;
  bool _buffer = false;
  bool _spark = false;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  SatietyPillars get _pillars {
    return SatietyPillars(
      anchor: PillarDetail(
        detected: _anchor,
        items: _anchor ? const ['Protein'] : const [],
        quality: _anchor ? 'medium' : 'low',
      ),
      net: PillarDetail(
        detected: _net,
        items: _net ? const ['Fiber'] : const [],
        quality: _net ? 'medium' : 'low',
      ),
      buffer: PillarDetail(
        detected: _buffer,
        items: _buffer ? const ['Fat'] : const [],
        quality: _buffer ? 'medium' : 'low',
      ),
      spark: PillarDetail(
        detected: _spark,
        items: _spark ? const ['Volume'] : const [],
        quality: _spark ? 'medium' : 'low',
      ),
    );
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty || _saving) return;
    setState(() => _saving = true);
    await SensoryFeedback.zenBloomPulse();
    await widget.storage.addMealLog(
      MealLog(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        mealName: name,
        timestamp: DateTime.now(),
        satietyResult: SatietyResult.manual(mealName: name, pillars: _pillars),
      ),
    );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Log without a photo',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                'Does not use a weekly scan. Estimates fullness from the pillars you mark.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('manual_meal_name'),
                controller: _name,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'What did you eat?',
                  hintText: 'Oatmeal with berries',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              Text(
                'Pillars on the plate',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _chip('Protein', _anchor, (v) => setState(() => _anchor = v)),
                  _chip('Fiber', _net, (v) => setState(() => _net = v)),
                  _chip('Fat', _buffer, (v) => setState(() => _buffer = v)),
                  _chip('Volume', _spark, (v) => setState(() => _spark = v)),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Manual entries record your meal without predicting fullness. Use Build a plate for a complete-meal estimate.',
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                key: const ValueKey('btn_save_manual_meal'),
                onPressed: _name.text.trim().isEmpty || _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: EvenColors.netSage,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Save to diary'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, bool selected, ValueChanged<bool> onSelected) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: onSelected,
    );
  }
}
