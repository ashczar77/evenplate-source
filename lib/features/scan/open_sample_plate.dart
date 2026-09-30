import 'package:flutter/material.dart';
import '../../core/utils/sensory_feedback.dart';
import '../../models/satiety_matrix.dart';
import '../../services/local_storage_service.dart';
import 'plate_analysis_screen.dart';

/// Opens analysis for a canned plate. Does not use a scan credit.
Future<bool?> openSamplePlate(
  BuildContext context, {
  required LocalStorageService storage,
  required SatietyResult result,
}) {
  SensoryFeedback.gentleTap();
  return Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => PlateAnalysisScreen(result: result, storage: storage),
    ),
  );
}
