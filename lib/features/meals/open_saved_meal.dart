import 'package:flutter/material.dart';

import '../../core/utils/sensory_feedback.dart';
import '../../models/meal_log.dart';
import '../../services/local_storage_service.dart';
import '../scan/plate_analysis_screen.dart';
import 'plate_blueprint_screen.dart';

Future<bool?> openSavedMeal(
  BuildContext context, {
  required LocalStorageService storage,
  required MealLog meal,
}) {
  SensoryFeedback.gentleTap();
  final photo = meal.imagePath;
  if (photo != null && photo.isNotEmpty) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PlateAnalysisScreen(
          result: meal.satietyResult,
          imagePath: photo,
          storage: storage,
          existingMeal: meal,
          animateSensory: false,
        ),
      ),
    );
  }
  return PlateBlueprintScreen.show(context, storage, existing: meal);
}
