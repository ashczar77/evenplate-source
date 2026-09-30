import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:evenplate/features/auth/password_recovery_screen.dart';
import 'package:evenplate/services/local_storage_service.dart';
import 'package:evenplate/services/supabase_service.dart';

class RecoveryService extends SupabaseService {
  RecoveryService() : super(LocalStorageService());
  final pending = Completer<void>();
  int saves = 0;
  @override
  Future<void> completePasswordRecovery(String password) {
    saves++;
    return pending.future;
  }
}

void main() {
  Future<RecoveryService> show(WidgetTester tester) async {
    final service = RecoveryService();
    await tester.pumpWidget(
      MaterialApp(home: PasswordRecoveryScreen(supabase: service)),
    );
    await tester.enterText(find.byType(TextField), 'FixturePassword9!');
    return service;
  }

  testWidgets(
    'duplicate taps submit once and timeout does not claim an expired link',
    (tester) async {
      final service = await show(tester);
      await tester.tap(find.text('Save password'));
      await tester.tap(find.text('Save password'));
      await tester.pump();
      expect(service.saves, 1);
      service.pending.completeError(TimeoutException('fixture'));
      await tester.pump();
      expect(
        find.textContaining('Your password may have changed'),
        findsOneWidget,
      );
      expect(find.textContaining('session has expired'), findsNothing);
    },
  );
  testWidgets('same-password rejection asks for a different password', (
    tester,
  ) async {
    final service = await show(tester);
    await tester.tap(find.text('Save password'));
    service.pending.completeError(
      const AuthException('fixture', code: 'same_password'),
    );
    await tester.pump();
    expect(
      find.text('Choose a password different from your current password.'),
      findsOneWidget,
    );
  });
}
