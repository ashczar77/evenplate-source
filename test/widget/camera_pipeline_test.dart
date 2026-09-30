import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:evenplate/core/theme/even_theme.dart';
import 'package:evenplate/features/insights/satiety_insight_modal.dart';
import 'package:evenplate/features/scan/plate_analysis_screen.dart';
import 'package:evenplate/features/scan/scan_plate_screen.dart';
import 'package:evenplate/models/satiety_matrix.dart';
import 'package:evenplate/services/gemini_vision_service.dart';
import 'package:evenplate/services/local_storage_service.dart';

void main() {
  late LocalStorageService storage;
  late GeminiVisionService visionService;

  const analyzedResult = SatietyResult(
    mealName: 'Grilled Salmon Bowl',
    components: ['Salmon', 'Brown Rice', 'Avocado', 'Spinach'],
    pillars: SatietyPillars(
      anchor: PillarDetail(detected: true, items: ['Salmon'], quality: 'high'),
      net: PillarDetail(detected: true, items: ['Spinach'], quality: 'high'),
      buffer: PillarDetail(detected: true, items: ['Avocado'], quality: 'high'),
      spark: PillarDetail(
        detected: true,
        items: ['Brown Rice'],
        quality: 'medium',
      ),
    ),
    satietyScore: 88,
    durationHours: 4.5,
    crashRisk: 'low',
    hybridUpgrade: HybridUpgrade(
      instantAdd: 'Add a sprinkle of hemp hearts.',
      smartSwap: 'Great base.',
      digestiveCatalyst: 'Enjoy mindfully.',
    ),
  );

  // 1x1 transparent PNG image bytes for testing image preview
  final sampleImageBytes = Uint8List.fromList([
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    0x00,
    0x00,
    0x00,
    0x0D,
    0x49,
    0x48,
    0x44,
    0x52,
    0x00,
    0x00,
    0x00,
    0x01,
    0x00,
    0x00,
    0x00,
    0x01,
    0x08,
    0x06,
    0x00,
    0x00,
    0x00,
    0x1F,
    0x15,
    0xC4,
    0x89,
    0x00,
    0x00,
    0x00,
    0x0A,
    0x49,
    0x44,
    0x41,
    0x54,
    0x78,
    0x9C,
    0x63,
    0x00,
    0x01,
    0x00,
    0x00,
    0x05,
    0x00,
    0x01,
    0x0D,
    0x0A,
    0x2D,
    0xB4,
    0x00,
    0x00,
    0x00,
    0x00,
    0x49,
    0x45,
    0x4E,
    0x44,
    0xAE,
    0x42,
    0x60,
    0x82,
  ]);

  setUp(() {
    storage = LocalStorageService();
    // Stubs the analyze-plate backend so the pipeline runs without a network.
    visionService = GeminiVisionService(
      null,
      MockClient(
        (request) async => http.Response(
          jsonEncode(analyzedResult.toJson()),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
  });

  Widget createScanWidget({
    Uint8List? previewBytes,
    ThemeMode themeMode = ThemeMode.dark,
    GeminiVisionService? vision,
    Future<void> Function()? refreshQuota,
  }) {
    return MaterialApp(
      theme: EvenTheme.lightTheme,
      darkTheme: EvenTheme.darkTheme,
      themeMode: themeMode,
      home: ScanPlateScreen(
        storage: storage,
        visionService: vision ?? visionService,
        refreshQuota: refreshQuota,
        initialPreviewBytes: previewBytes,
      ),
    );
  }

  testWidgets(
    'ScanPlateScreen renders viewfinder with reticle and no sample chips',
    (WidgetTester tester) async {
      await tester.pumpWidget(createScanWidget());
      await tester.pump();

      expect(find.text('Scan a plate'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('viewfinder_container')),
        findsOneWidget,
      );
      expect(find.text('Align Meal in Frame'), findsOneWidget);

      expect(find.byKey(const ValueKey('btn_capture_camera')), findsOneWidget);
      expect(find.byKey(const ValueKey('btn_pick_gallery')), findsOneWidget);

      expect(find.byKey(const ValueKey('chip_preset_0')), findsNothing);
      expect(find.byKey(const ValueKey('chip_preset_1')), findsNothing);
      expect(find.text('Avocado & Eggs'), findsNothing);
    },
  );

  testWidgets(
    'Instant Preview displays captured photo, retake and confirm buttons',
    (WidgetTester tester) async {
      await tester.pumpWidget(createScanWidget(previewBytes: sampleImageBytes));
      await tester.pump();

      // Preview mode
      expect(find.text('Plate Preview'), findsOneWidget);
      expect(find.byKey(const ValueKey('preview_container')), findsOneWidget);

      // Pre-compression tag
      expect(find.text('Full photo. Ready for analysis'), findsOneWidget);

      // Action buttons
      expect(find.byKey(const ValueKey('btn_retake_photo')), findsOneWidget);
      expect(find.byKey(const ValueKey('btn_confirm_analyze')), findsOneWidget);
    },
  );

  testWidgets('Tapping Retake clears photo preview and returns to viewfinder', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(createScanWidget(previewBytes: sampleImageBytes));
    await tester.pump();

    expect(find.byKey(const ValueKey('preview_container')), findsOneWidget);

    // Tap Retake
    await tester.tap(find.byKey(const ValueKey('btn_retake_photo')));
    await tester.pump();

    // Verifies returned to viewfinder mode
    expect(find.text('Scan a plate'), findsOneWidget);
    expect(find.byKey(const ValueKey('viewfinder_container')), findsOneWidget);
    expect(find.byKey(const ValueKey('preview_container')), findsNothing);
  });

  testWidgets('Confirm & Analyze photo navigates to PlateAnalysisScreen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(createScanWidget(previewBytes: sampleImageBytes));
    await tester.pump();

    // Tap Confirm & Analyze
    await tester.tap(find.byKey(const ValueKey('btn_confirm_analyze')));
    await tester.pumpAndSettle();
    expect(find.text('Allow meal analysis?'), findsOneWidget);
    await tester.tap(find.text('Allow analysis'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();

    // Verifies PlateAnalysisScreen is pushed
    expect(find.byType(PlateAnalysisScreen), findsOneWidget);
  });

  testWidgets('A zero cached balance refreshes before blocking a Pro scan', (
    WidgetTester tester,
  ) async {
    await storage.applyServerQuota(isPro: true, freeScansRemaining: 0);
    var refreshed = false;
    await tester.pumpWidget(
      createScanWidget(
        previewBytes: sampleImageBytes,
        refreshQuota: () async {
          refreshed = true;
          await storage.applyServerQuota(isPro: true, freeScansRemaining: 74);
        },
      ),
    );

    await tester.tap(find.byKey(const ValueKey('btn_confirm_analyze')));
    await tester.pumpAndSettle();
    expect(find.text('Allow meal analysis?'), findsOneWidget);
    await tester.tap(find.text('Allow analysis'));
    await tester.pumpAndSettle();

    expect(refreshed, isTrue);
    expect(storage.userProfile.freeScansRemaining, 73);
  });

  testWidgets('A not-food photo shows the miss instead of a score', (
    tester,
  ) async {
    final notFood = GeminiVisionService(
      null,
      MockClient(
        (request) async => http.Response(
          jsonEncode({
            'mealName': 'Not a plate',
            'components': <String>[],
            'pillars': {
              'anchor': {'detected': false, 'items': [], 'quality': 'low'},
              'net': {'detected': false, 'items': [], 'quality': 'low'},
              'buffer': {'detected': false, 'items': [], 'quality': 'low'},
              'spark': {'detected': false, 'items': [], 'quality': 'low'},
            },
            'satietyScore': 0,
            'durationHours': 0.5,
            'crashRisk': 'low',
            'captureIssue': 'not_food',
            'hybridUpgrade': {
              'instantAdd': 'Point the camera at a meal.',
              'smartSwap': 'Use a plate photo.',
              'digestiveCatalyst': 'Try again.',
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );

    await tester.pumpWidget(
      createScanWidget(previewBytes: sampleImageBytes, vision: notFood),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('btn_confirm_analyze')));
    await tester.pumpAndSettle();
    expect(find.text('Allow meal analysis?'), findsOneWidget);
    await tester.tap(find.text('Allow analysis'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.byType(PlateAnalysisScreen), findsNothing);
    expect(find.byType(SatietyInsightModal), findsOneWidget);
    expect(find.text("Oops, doesn't look like food"), findsOneWidget);
  });

  testWidgets('Quota exceeded dialog displays when scans are depleted', (
    WidgetTester tester,
  ) async {
    // Deplete free scans and ensure not Pro
    final depleted = storage.userProfile.copyWith(
      isPro: false,
      freeScansRemaining: 0,
    );
    await storage.saveUserProfile(depleted);

    await tester.pumpWidget(createScanWidget());
    await tester.pump();

    // Attempt capture
    await tester.tap(find.byKey(const ValueKey('btn_capture_camera')));
    await tester.pumpAndSettle();

    // Quota dialog appears
    expect(find.text('Weekly Scans Complete'), findsOneWidget);
    expect(find.text('View Pro Plans'), findsOneWidget);
  });
}
