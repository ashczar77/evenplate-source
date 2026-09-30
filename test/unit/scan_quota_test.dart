import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:evenplate/core/billing/scan_allowance.dart';
import 'package:evenplate/models/satiety_matrix.dart';
import 'package:evenplate/services/gemini_vision_service.dart';
import 'package:evenplate/services/local_storage_service.dart';

const _sampleResult = SatietyResult(
  mealName: 'Grilled Salmon Bowl',
  components: ['Salmon', 'Spinach', 'Avocado'],
  pillars: SatietyPillars(
    anchor: PillarDetail(detected: true, items: ['Salmon'], quality: 'high'),
    net: PillarDetail(detected: true, items: ['Spinach'], quality: 'high'),
    buffer: PillarDetail(detected: true, items: ['Avocado'], quality: 'high'),
    spark: PillarDetail(detected: false, items: [], quality: 'low'),
  ),
  satietyScore: 88,
  durationHours: 4.5,
  crashRisk: 'low',
  hybridUpgrade: HybridUpgrade(
    instantAdd: 'Add hemp hearts.',
    smartSwap: 'Great base.',
    digestiveCatalyst: 'Enjoy mindfully.',
  ),
);

GeminiVisionService serviceReturning(
  Map<String, dynamic> body, {
  int status = 200,
}) {
  return GeminiVisionService(
    null,
    MockClient(
      (_) async => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      ),
    ),
  );
}

void main() {
  final imageBytes = Uint8List.fromList([1, 2, 3, 4]);

  group('analyzePlate quota handling', () {
    test(
      'adopts the quota the backend reports alongside the analysis',
      () async {
        final service = serviceReturning({
          ..._sampleResult.toJson(),
          'quota': {'isPro': false, 'freeScansRemaining': 2},
        });

        final analysis = await service.analyzePlate(imageBytes: imageBytes);

        expect(analysis.result.mealName, 'Grilled Salmon Bowl');
        expect(analysis.quota, isNotNull);
        expect(analysis.quota!.isPro, isFalse);
        expect(analysis.quota!.freeScansRemaining, 2);
      },
    );

    test('leaves quota null when the backend omits it', () async {
      final service = serviceReturning(_sampleResult.toJson());

      final analysis = await service.analyzePlate(imageBytes: imageBytes);

      expect(analysis.quota, isNull);
    });

    test('throws ScanQuotaExceededException on a 403 quota refusal', () async {
      final service = serviceReturning({
        'error': 'Quota exceeded.',
        'code': 'QUOTA_EXCEEDED',
        'quota': {'isPro': false, 'freeScansRemaining': 0},
      }, status: 403);

      await expectLater(
        service.analyzePlate(imageBytes: imageBytes),
        throwsA(
          isA<ScanQuotaExceededException>().having(
            (e) => e.quota?.freeScansRemaining,
            'reported remaining',
            0,
          ),
        ),
      );
    });

    test('surfaces the backend error message on other failures', () async {
      final service = serviceReturning({
        'error': 'Gemini Vision analysis failed',
        'code': 'GEMINI_EMPTY',
      }, status: 502);

      await expectLater(
        service.analyzePlate(imageBytes: imageBytes),
        throwsA(
          isA<PlateAnalysisException>()
              .having(
                (e) => e.message,
                'message',
                'Gemini Vision analysis failed',
              )
              .having((e) => e.code, 'code', 'GEMINI_EMPTY')
              .having((e) => e.telemetryName, 'telemetry', 'scan.empty'),
        ),
      );
    });

    test('does not mistake a non quota 403 for a quota refusal', () async {
      final service = serviceReturning({
        'error': 'Unable to authorize this scan',
      }, status: 403);

      await expectLater(
        service.analyzePlate(imageBytes: imageBytes),
        throwsA(isA<PlateAnalysisException>()),
      );
    });

    test('sends the dev unlimited header only when asked', () async {
      http.BaseRequest? seen;
      final service = GeminiVisionService(
        null,
        MockClient((request) async {
          seen = request;
          return http.Response(
            jsonEncode(_sampleResult.toJson()),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await service.analyzePlate(imageBytes: imageBytes, devUnlimited: true);

      expect(seen!.headers[GeminiVisionService.devUnlimitedHeader], '1');

      await service.analyzePlate(imageBytes: imageBytes);
      expect(seen!.headers[GeminiVisionService.devUnlimitedHeader], isNull);
    });
  });

  group('analyzeFoods', () {
    test('does not treat a typed plate as a photo quota event', () async {
      final service = GeminiVisionService(
        null,
        MockClient((request) async {
          expect(request.url.path, contains('analyze-foods'));
          expect(request.body, contains('Sloppy joes'));
          expect(request.body, isNot(contains('imageBase64')));
          return http.Response(
            jsonEncode({
              ..._sampleResult.toJson(),
              'mealName': 'Sloppy Joes',
              'components': ['Sloppy joes'],
              'rejected': <String>[],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final analysis = await service.analyzeFoods(
        mealName: 'Lunch',
        foods: const ['Sloppy joes'],
      );

      expect(analysis.result.mealName, 'Sloppy Joes');
      expect(analysis.quota, isNull);
      expect(analysis.rejected, isEmpty);
    });
  });

  group('applyServerQuota', () {
    late LocalStorageService storage;

    setUp(() {
      storage = LocalStorageService();
    });

    test('takes the server count as authoritative', () async {
      await storage.setFreeScansRemaining(3);

      await storage.applyServerQuota(isPro: false, freeScansRemaining: 1);

      expect(storage.userProfile.freeScansRemaining, 1);
    });

    test('raises Pro when the server reports it', () async {
      await storage.setProStatus(false);

      await storage.applyServerQuota(isPro: true, freeScansRemaining: 0);

      expect(storage.userProfile.isPro, isTrue);
    });

    test('takes the server Pro flag as authoritative', () async {
      await storage.setProStatus(true);

      await storage.applyServerQuota(
        isPro: false,
        freeScansRemaining: 0,
        textRemaining: 0,
      );

      expect(storage.userProfile.isPro, isFalse);
    });

    test('remaining above the Free cap is Pro, not a Free week of 3', () async {
      await storage.applyServerQuota(isPro: false, freeScansRemaining: 67);

      expect(storage.userProfile.isPro, isTrue);
      expect(storage.hasPro, isTrue);
      expect(storage.userProfile.freeScansRemaining, 67);
      expect(ScanAllowance.includedPhotoWeekly(isPro: storage.hasPro), 75);
    });

    test('a cancelled store entitlement drops the Pro leftover', () async {
      await storage.applyServerQuota(isPro: false, freeScansRemaining: 67);
      expect(storage.hasPro, isTrue);

      await storage.applyStoreEntitlement(false);

      expect(storage.hasPro, isFalse);
      expect(storage.userProfile.freeScansRemaining, 3);
    });

    test(
      'a stale server Pro flag cannot resurrect after the store expired',
      () async {
        await storage.applyStoreEntitlement(false);

        await storage.applyServerQuota(isPro: true, freeScansRemaining: 72);

        expect(storage.hasPro, isFalse);
        expect(storage.storeEntitlementDenied, isTrue);
        expect(storage.userProfile.freeScansRemaining, 3);
        expect(ScanAllowance.includedPhotoWeekly(isPro: storage.hasPro), 3);
      },
    );

    test('a healed ledger remaining of 2 is adopted after expire', () async {
      await storage.applyStoreEntitlement(false);
      await storage.applyServerQuota(isPro: false, freeScansRemaining: 2);

      expect(storage.hasPro, isFalse);
      expect(storage.photoLeft, 2);
    });

    test(
      'leftover Pro meters after expire become the Free cap, not a local guess',
      () async {
        await storage.applyStoreEntitlement(false);

        await storage.applyServerQuota(isPro: true, freeScansRemaining: 71);

        expect(storage.hasPro, isFalse);
        expect(storage.photoLeft, 3);
      },
    );

    test(
      'a refunded capture does not drop the Free meter after expire',
      () async {
        await storage.applyStoreEntitlement(false);
        await storage.applyServerQuota(isPro: true, freeScansRemaining: 72);
        expect(storage.photoLeft, 3);

        await storage.applyServerQuota(isPro: true, freeScansRemaining: 72);

        expect(storage.hasPro, isFalse);
        expect(storage.photoLeft, 3);
      },
    );

    test('an already-Pro week at 0 stays 0, it is not refilled', () async {
      await storage.applyServerQuota(isPro: true, freeScansRemaining: 0);

      await storage.setProStatus(true);

      expect(storage.hasPro, isTrue);
      expect(storage.photoLeft, 0);
    });

    test('clamps a negative count to zero', () async {
      await storage.applyServerQuota(isPro: false, freeScansRemaining: -5);

      expect(storage.userProfile.freeScansRemaining, 0);
    });

    test(
      'a live promo preserves depleted balances when the store says Free',
      () async {
        await storage.applyPromoGrant(
          DateTime.now().add(const Duration(days: 90)),
        );
        await storage.applyServerQuota(
          isPro: true,
          freeScansRemaining: 2,
          textRemaining: 8,
          photoPurchased: 25,
          textPurchased: 40,
        );
        final balances = <int>[];
        storage.profileChanges.addListener(
          () => balances.add(storage.photoLeft),
        );
        await storage.applyStoreEntitlement(false);
        expect(storage.hasPro, isTrue);
        expect(storage.storeEntitlementDenied, isFalse);
        expect(storage.photoLeft, 27);
        expect(storage.textLeft, 48);
        expect(balances, everyElement(27));
        await storage.applyPromoGrant(
          DateTime.now().add(const Duration(days: 90)),
        );
        expect(storage.photoLeft, 27);
        expect(storage.textLeft, 48);
      },
    );

    test(
      'an expired promo does not override a denied store entitlement',
      () async {
        await storage.applyPromoGrant(
          DateTime.now().add(const Duration(days: 1)),
        );
        await storage.applyServerQuota(
          isPro: true,
          freeScansRemaining: 75,
          textRemaining: 100,
        );
        await storage.applyStoreEntitlement(false);
        await storage.applyPromoGrant(
          DateTime.now().subtract(const Duration(seconds: 1)),
        );
        expect(storage.hasPro, isFalse);
        expect(storage.userProfile.isPro, isFalse);
        expect(storage.photoLeft, 3);
        expect(storage.textLeft, 20);
      },
    );

    test(
      'store entitlement refresh does not refill included credits',
      () async {
        await storage.applyServerQuota(
          isPro: true,
          freeScansRemaining: 2,
          textRemaining: 8,
        );
        await storage.applyStoreEntitlement(true);
        await storage.applyStoreEntitlement(true);
        expect(storage.userProfile.freeScansRemaining, 2);
        expect(storage.userProfile.textRemaining, 8);
      },
    );

    test('food-score quota leaves photo remaining alone', () async {
      await storage.applyServerQuota(isPro: false, freeScansRemaining: 2);
      await storage.applyFoodsQuota(
        const ScanQuota(
          isPro: false,
          freeScansRemaining: 0,
          textRemaining: 7,
          textPurchased: 40,
        ),
      );

      expect(storage.userProfile.freeScansRemaining, 2);
      expect(storage.userProfile.textRemaining, 7);
      expect(storage.userProfile.textPurchased, 40);
      expect(storage.canScoreFoods(), isTrue);
    });
  });

  group('canScanPlate', () {
    late LocalStorageService storage;

    setUp(() {
      storage = LocalStorageService();
    });

    test('becoming Pro grants the weekly included caps', () async {
      await storage.setFreeScansRemaining(0);
      await storage.setProStatus(true);

      expect(storage.userProfile.freeScansRemaining, 75);
      expect(storage.userProfile.textRemaining, 100);
      expect(storage.canScanPlate(), isTrue);
    });

    test('zero remaining from the server still blocks Pro', () async {
      await storage.applyServerQuota(
        isPro: true,
        freeScansRemaining: 0,
        textRemaining: 0,
      );

      expect(storage.canScanPlate(), isFalse);
    });

    test('blocks free users with no scans left', () async {
      await storage.setProStatus(false);
      await storage.setFreeScansRemaining(0);

      expect(storage.canScanPlate(), isFalse);
    });

    test('a zero server count blocks a free user', () async {
      await storage.applyServerQuota(isPro: false, freeScansRemaining: 0);

      expect(storage.canScanPlate(), isFalse);
    });
  });
}
