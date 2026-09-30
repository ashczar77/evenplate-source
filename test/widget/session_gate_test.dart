import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evenplate/features/auth/auth_screen.dart';
import 'package:evenplate/main.dart';
import 'package:evenplate/services/local_storage_service.dart';
import 'package:evenplate/services/onesignal_service.dart';
import 'package:evenplate/services/revenuecat_service.dart';
import 'package:evenplate/services/supabase_service.dart';

void main() {
  late LocalStorageService storage;
  late SupabaseService supabase;
  late RevenueCatService revenueCat;
  late OneSignalService oneSignal;

  setUp(() async {
    storage = LocalStorageService();
    revenueCat = RevenueCatService(storage);
    supabase = SupabaseService(storage);
    supabase.setRevenueCatService(revenueCat);
    await supabase.init();
    oneSignal = OneSignalService(storage);
  });

  Widget app() {
    return EvenPlateApp(
      storage: storage,
      revenueCat: revenueCat,
      oneSignal: oneSignal,
      supabase: supabase,
    );
  }

  testWidgets('boot splash paints before services finish', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const EvenPlateSplash());
    await tester.pump();

    expect(find.text('EvenPlate', findRichText: true), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('a leftover Hive profile id does not skip the sign-in screen', (
    WidgetTester tester,
  ) async {
    await storage.saveUserProfile(
      storage.userProfile.copyWith(id: 'leftover-uuid-from-hive'),
    );

    await tester.pumpWidget(app());
    await tester.pump();

    expect(find.byType(AuthScreen), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
  });

  testWidgets('email sign-in keeps MaterialApp mounted and opens onboarding', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pump();

    expect(find.byType(AuthScreen), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('input_email')),
      'user@evenplate.app',
    );
    await tester.enterText(
      find.byKey(const ValueKey('input_password')),
      'balancedPlate7',
    );
    await tester.tap(find.byKey(const ValueKey('btn_primary_auth')));
    await tester.pump();
    // MaterialApp must still be the same route host mid-auth.
    expect(find.byType(MaterialApp), findsOneWidget);
    await tester.pumpAndSettle();

    expect(find.byType(AuthScreen), findsNothing);
    expect(supabase.isAuthenticated, isTrue);
    expect(supabase.isAnonymous, isFalse);
    expect(supabase.isLoading, isFalse);
    expect(
      find.text('Afternoons hit a wall. I need energy that lasts.'),
      findsOneWidget,
    );
  });
}
