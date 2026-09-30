import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:evenplate/services/local_storage_service.dart';
import 'package:evenplate/services/supabase_service.dart';

class RecoveryClientService extends SupabaseService {
  RecoveryClientService(this.live) : super(LocalStorageService());
  final SupabaseClient live;
  @override
  SupabaseClient get client => live;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'a timed-out save remains single-flight and a late success completes recovery',
    () async {
      final response = Completer<http.Response>();
      var updates = 0;
      final user = {
        'id': 'fixture-user',
        'aud': 'authenticated',
        'email': 'fixture@example.com',
        'app_metadata': <String, Object>{},
        'user_metadata': <String, Object>{},
        'created_at': '2026-01-01T00:00:00Z',
      };
      final live = SupabaseClient(
        'https://fixture.example',
        'public-test-key',
        authOptions: const AuthClientOptions(
          autoRefreshToken: false,
          authFlowType: AuthFlowType.implicit,
        ),
        httpClient: MockClient((request) async {
          if (request.method == 'PUT') {
            updates++;
            return response.future;
          }
          return http.Response(
            jsonEncode({
              'access_token': 'fixture-access',
              'refresh_token': 'fixture-refresh',
              'token_type': 'bearer',
              'expires_in': 3600,
              'user': user,
            }),
            200,
          );
        }),
      );
      await live.auth.signInWithPassword(
        email: 'fixture@example.com',
        password: 'FixturePassword9!',
      );
      final service = RecoveryClientService(live)..needsPasswordRecovery = true;
      final first = expectLater(
        service.completePasswordRecovery('FixturePassword9!'),
        throwsA(isA<TimeoutException>()),
      );
      await first;
      expect(service.needsPasswordRecovery, isTrue);
      final retry = service.completePasswordRecovery('FixturePassword9!');
      expect(updates, 1);
      response.complete(http.Response(jsonEncode({'user': user}), 200));
      await retry;
      expect(service.needsPasswordRecovery, isFalse);
      expect(updates, 1);
      service.dispose();
      await live.dispose();
    },
  );
}
