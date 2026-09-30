import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evenplate/core/theme/even_theme.dart';
import 'package:evenplate/features/settings/settings_screen.dart';
import 'package:evenplate/features/today/today_screen.dart';
import 'package:evenplate/services/local_storage_service.dart';
import 'package:evenplate/services/revenuecat_service.dart';

class SettingsRestoreService extends RevenueCatService {
  SettingsRestoreService(super.storage);
  final result = Completer<bool>();
  int restores = 0;

  @override
  Future<void> checkProStatus() async {}

  @override
  Future<bool> restorePurchases() {
    restores++;
    return result.future;
  }
}

void main() {
  testWidgets('Purchased scans are separate from the Free weekly allowance', (
    tester,
  ) async {
    final storage = LocalStorageService();
    await storage.applyServerQuota(
      isPro: false,
      freeScansRemaining: 1,
      photoPurchased: 25,
      textRemaining: 14,
      textPurchased: 40,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: EvenTheme.lightTheme,
        home: SettingsScreen(storage: storage),
      ),
    );
    await tester.pumpAndSettle();
    expect(storage.photoLeft, 26);
    expect(
      find.textContaining('1 of 3 photo scans and 14 of 20 food scores'),
      findsOneWidget,
    );
    expect(
      find.text('Extra credits: 25 photo scans and 40 food assessments.'),
      findsOneWidget,
    );
    expect(find.textContaining('26 of 3'), findsNothing);
    expect(find.text('EvenPlate Free'), findsOneWidget);
  });
  testWidgets('Pro restore remains available and prevents duplicate requests', (
    tester,
  ) async {
    final storage = LocalStorageService();
    await storage.applyServerQuota(isPro: true, freeScansRemaining: 75);
    final service = SettingsRestoreService(storage);
    await tester.pumpWidget(
      MaterialApp(
        theme: EvenTheme.lightTheme,
        home: SettingsScreen(storage: storage, revenueCat: service),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wallet'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Restore purchases'));
    await tester.tap(find.text('Restore purchases'));
    await tester.pump();
    expect(service.restores, 1);
    final tile = tester.widget<ListTile>(
      find.widgetWithText(ListTile, 'Restoring purchases...'),
    );
    expect(tile.enabled, isFalse);
    service.result.complete(true);
    await tester.pumpAndSettle();
    expect(
      find.text('Purchases restored successfully. Pro active.'),
      findsOneWidget,
    );
    expect(storage.hasPro, isTrue);
    expect(find.text('Restore purchases'), findsOneWidget);
    expect(find.text('Manage subscription'), findsOneWidget);
    expect(find.text('Extra credits'), findsOneWidget);
  });
  testWidgets('Settings cannot pair a Pro leftover with a Free cap of 3', (
    tester,
  ) async {
    final storage = LocalStorageService();
    await storage.applyServerQuota(isPro: false, freeScansRemaining: 67);

    await tester.pumpWidget(
      MaterialApp(
        theme: EvenTheme.lightTheme,
        home: SettingsScreen(storage: storage),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('EvenPlate Pro Active'), findsOneWidget);
    expect(find.text('Wallet'), findsOneWidget);
    expect(find.text('Extra credits'), findsNothing);
    expect(find.text('EvenPlate Free'), findsNothing);
    expect(find.textContaining('67 of 75 photo scans'), findsOneWidget);
    expect(find.textContaining('of 3 photo scans'), findsNothing);
    expect(find.text('Developer & Reviewer Tools'), findsNothing);
  });

  testWidgets('Expired store shows Free and Upgrade, not leftover Pro', (
    tester,
  ) async {
    final storage = LocalStorageService();
    await storage.applyServerQuota(isPro: true, freeScansRemaining: 72);
    await storage.applyStoreEntitlement(false);

    await tester.pumpWidget(
      MaterialApp(
        theme: EvenTheme.lightTheme,
        home: SettingsScreen(storage: storage),
      ),
    );
    await tester.pumpAndSettle();

    expect(storage.hasPro, isFalse);
    expect(find.text('EvenPlate Free'), findsOneWidget);
    expect(find.text('EvenPlate Pro Active'), findsNothing);
    expect(find.textContaining('of 3 photo scans'), findsOneWidget);
    expect(find.textContaining('of 75 photo scans'), findsNothing);
    expect(find.text('Upgrade'), findsOneWidget);
    expect(find.text('Wallet'), findsOneWidget);
    expect(find.text('Extra credits'), findsNothing);
  });

  testWidgets('Free tier shows the promo code without a tier reset', (
    tester,
  ) async {
    final storage = LocalStorageService();
    await storage.applyServerQuota(isPro: false, freeScansRemaining: 3);

    await tester.pumpWidget(
      MaterialApp(
        theme: EvenTheme.lightTheme,
        home: SettingsScreen(storage: storage),
      ),
    );
    await tester.pumpAndSettle();

    expect(storage.hasPro, isFalse);
    expect(find.text('EvenPlate Free'), findsOneWidget);
    expect(find.textContaining('of 3 photo scans'), findsOneWidget);
    expect(find.textContaining('of 75 photo scans'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('Promo Bypass Code'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Privileged access'), findsOneWidget);
    expect(find.text('Promo Bypass Code'), findsOneWidget);
    expect(find.text('Return to Free tier'), findsNothing);
    expect(find.text('Developer & Reviewer Tools'), findsNothing);

    await tester.tap(find.text('Promo Bypass Code'));
    await tester.pumpAndSettle();
    expect(find.text('Promo code'), findsWidgets);
    expect(find.text('Enter a promo code to unlock Pro.'), findsOneWidget);
  });

  testWidgets('Home pill uses the same leftover count Settings uses', (
    tester,
  ) async {
    final storage = LocalStorageService();
    await storage.applyServerQuota(isPro: true, freeScansRemaining: 0);

    await tester.pumpWidget(
      MaterialApp(
        theme: EvenTheme.lightTheme,
        home: TodayScreen(storage: storage, onScanPressed: () {}),
      ),
    );
    await tester.pump();

    expect(find.text('0 left'), findsOneWidget);
    expect(storage.hasPro, isTrue);
    expect(storage.photoLeft, 0);
  });

  testWidgets('Sign Out asks before leaving', (tester) async {
    final storage = LocalStorageService();
    await tester.pumpWidget(
      MaterialApp(
        theme: EvenTheme.lightTheme,
        home: SettingsScreen(storage: storage),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Sign Out'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Sign Out'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign Out'));
    await tester.pumpAndSettle();

    expect(find.text('Sign out?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Sign out?'), findsNothing);
  });
}
