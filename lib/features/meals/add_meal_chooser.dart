import 'package:flutter/material.dart';
import '../../core/theme/even_colors.dart';
import '../../core/utils/sensory_feedback.dart';
import '../../services/local_storage_service.dart';
import 'manual_meal_sheet.dart';
import 'plate_blueprint_screen.dart';

/// Lets the user build, scan, or type a plate.
Future<void> showAddMealChooser(
  BuildContext context, {
  required LocalStorageService storage,
  required VoidCallback onScan,
}) {
  SensoryFeedback.gentleTap();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: EvenColors.darkSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Add a plate',
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              ListTile(
                key: const ValueKey('chooser_blueprint'),
                leading: const Icon(
                  Icons.grid_view_rounded,
                  color: EvenColors.anchorTerracotta,
                ),
                title: const Text('Build a plate'),
                subtitle: const Text(
                  'Free if we already know the foods. New names use one food score.',
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  PlateBlueprintScreen.show(context, storage);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.camera_alt_rounded,
                  color: EvenColors.netSageLight,
                ),
                title: const Text('Scan a plate'),
                subtitle: const Text('Uses one photo scan.'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onScan();
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.edit_note_rounded,
                  color: EvenColors.bufferAmber,
                ),
                title: const Text('Log without a photo'),
                subtitle: const Text('Does not use a scan credit.'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await ManualMealSheet.show(context, storage);
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}
