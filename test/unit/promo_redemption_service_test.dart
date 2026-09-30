import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:evenplate/models/user_profile.dart';
import 'package:evenplate/services/local_storage_service.dart';
import 'package:evenplate/services/supabase_service.dart';

class PromoClientService extends SupabaseService {
  PromoClientService(super.storage, this.live);
  final SupabaseClient live;
  @override
  SupabaseClient get client => live;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'repeat promo adopts consumed server balances without a local refill',
    () async {
      final storage = LocalStorageService();
      await storage.saveUserProfile(
        UserProfile(id: 'promo-owner', lastQuotaReset: DateTime.now()),
      );
      var quotaReads = 0;
      final until = DateTime.now()
          .add(const Duration(days: 90))
          .toUtc()
          .toIso8601String();
      final live = SupabaseClient(
        'https://fixture.example',
        'public-test-key',
        authOptions: const AuthClientOptions(
          autoRefreshToken: false,
          authFlowType: AuthFlowType.implicit,
        ),
        httpClient: MockClient((request) async {
          Object body;
          if (request.url.path.endsWith('/redeem_promo_code')) {
            body = {'redeemed': true, 'duplicate': true, 'until': until};
          } else if (request.url.path.endsWith('/get_my_quota')) {
            quotaReads++;
            body = {
              'is_pro': false,
              'promo_pro_until': until,
              'free_scans_remaining': 2,
              'text_included_remaining': 8,
              'photo_purchased': 25,
              'text_purchased': 40,
            };
          } else {
            body = {
              'access_token': 'fixture-access',
              'refresh_token': 'fixture-refresh',
              'token_type': 'bearer',
              'expires_in': 3600,
              'user': {
                'id': 'promo-owner',
                'aud': 'authenticated',
                'email': 'promo@invalid.example',
                'app_metadata': <String, Object>{},
                'user_metadata': <String, Object>{},
                'created_at': '2026-01-01T00:00:00Z',
              },
            };
          }
          return http.Response(
            jsonEncode(body),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(live.dispose);
      await live.auth.signInWithPassword(
        email: 'promo@invalid.example',
        password: 'FixturePassword9!',
      );
      final service = PromoClientService(storage, live);
      addTearDown(service.dispose);
      await storage.applyStoreEntitlement(false);

      expect((await service.redeemPromoCode('FIXTURE')).redeemed, isTrue);
      expect(quotaReads, 1);
      expect(storage.hasPro, isTrue);
      expect(storage.photoLeft, 27);
      expect(storage.textLeft, 48);
      await storage.applyStoreEntitlement(false);
      expect(storage.hasPro, isTrue);
      expect(storage.photoLeft, 27);
      expect(storage.textLeft, 48);
      expect((await service.redeemPromoCode('FIXTURE')).redeemed, isTrue);
      expect(storage.photoLeft, 27);
      expect(storage.textLeft, 48);
    },
  );
}
