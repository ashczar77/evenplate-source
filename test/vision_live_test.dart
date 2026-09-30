// Manual diagnostic harness that calls the real analyze-plate backend.
// It is skipped unless both environment variables below are set:
//   EVENPLATE_LIVE_VISION_TEST=1
//   EVENPLATE_LIVE_FIXTURE_DIR=/path/to/meal/photos
// Run with: flutter test test/vision_live_test.dart --run-skipped
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:evenplate/services/gemini_vision_service.dart';

String? get _fixtureDir => Platform.environment['EVENPLATE_LIVE_FIXTURE_DIR'];

bool get _isEnabled =>
    Platform.environment['EVENPLATE_LIVE_VISION_TEST'] != null &&
    _fixtureDir != null;

void main() {
  test(
    'Live Gemini Vision Test',
    () async {
      final service = GeminiVisionService();
      final dir = Directory(_fixtureDir!);

      final images = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.jpg'))
          .toList();

      expect(
        images,
        isNotEmpty,
        reason: 'No .jpg fixtures found in ${dir.path}',
      );

      const encoder = JsonEncoder.withIndent('  ');
      for (final file in images) {
        print('\n--- Testing ${file.uri.pathSegments.last} ---');
        final analysis = await service.analyzePlate(
          imageBytes: file.readAsBytesSync(),
        );
        print(encoder.convert(analysis.result.toJson()));
      }
    },
    skip: _isEnabled
        ? false
        : 'Set EVENPLATE_LIVE_VISION_TEST and EVENPLATE_LIVE_FIXTURE_DIR to run.',
  );
}
