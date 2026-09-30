import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:evenplate/core/theme/even_theme.dart';
import 'package:evenplate/features/settings/credit_packs_section.dart';
import 'package:evenplate/services/local_storage_service.dart';
import 'package:evenplate/services/revenuecat_service.dart';

class PackService extends RevenueCatService {
  PackService(super.storage);
  final result = Completer<bool>();
  final purchases = <Package>[];
  @override
  Future<bool> purchasePackage(Package package) {
    purchases.add(package);
    return result.future;
  }
}

Package pack(String id, String price) => Package(
  id,
  PackageType.custom,
  StoreProduct(id, 'Store description', 'Store title', 2.99, price, 'USD'),
  const PresentedOfferingContext('packs', null, null),
);

void main() {
  testWidgets('Pack cards use live prices and buy the selected product once', (
    tester,
  ) async {
    final service = PackService(LocalStorageService());
    final photo = pack('scan_pack_25', '\$2.99');
    service.creditPackages = [
      photo,
      pack('scan_pack_80', '\$7.99'),
      pack('food_pack_40', '\$1.99'),
      pack('unknown', '\$99.99'),
    ];
    await tester.pumpWidget(
      MaterialApp(
        theme: EvenTheme.lightTheme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: CreditPacksSection(service: service),
          ),
        ),
      ),
    );
    expect(find.text('25 photo scans'), findsOneWidget);
    expect(find.text('80 photo scans'), findsOneWidget);
    expect(find.text('40 food assessments'), findsOneWidget);
    expect(find.text('Buy for \$99.99'), findsNothing);
    await tester.tap(find.text('Buy for \$2.99'));
    await tester.pump();
    expect(service.purchases, [photo]);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Purchasing...'),
          )
          .onPressed,
      isNull,
    );
    service.result.complete(true);
    await tester.pumpAndSettle();
    expect(
      find.text('Purchase confirmed. Credits may take a moment to sync.'),
      findsOneWidget,
    );
  });
}
