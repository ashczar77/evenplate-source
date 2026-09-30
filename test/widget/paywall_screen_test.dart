import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:evenplate/core/theme/even_colors.dart';
import 'package:evenplate/core/theme/even_theme.dart';
import 'package:evenplate/features/settings/paywall_screen.dart';
import 'package:evenplate/services/local_storage_service.dart';
import 'package:evenplate/services/revenuecat_service.dart';

/// Records what was purchased without touching the store. The real
/// purchasePackage refuses to run when RevenueCat is unconfigured, which is
/// always the case in a test.
class RecordingRevenueCatService extends RevenueCatService {
  RecordingRevenueCatService(this.storage) : super(storage);

  final LocalStorageService storage;
  Package? purchased;
  SubscriptionRenewalState? renewalState = SubscriptionRenewalState.inactive;

  @override
  Future<SubscriptionRenewalState?> subscriptionRenewalState() async =>
      renewalState;

  @override
  Future<bool> purchasePackage(Package package) async {
    purchased = package;
    await storage.setProStatus(true);
    return true;
  }
}

StoreProduct buildProduct({
  required String identifier,
  required double price,
  required String priceString,
  IntroductoryPrice? introductoryPrice,
  String? pricePerMonthString,
}) {
  return StoreProduct(
    identifier,
    'EvenPlate Pro',
    'EvenPlate Pro',
    price,
    priceString,
    'USD',
    introductoryPrice: introductoryPrice,
    pricePerMonthString: pricePerMonthString,
  );
}

Package buildPackage(PackageType type, StoreProduct product) {
  return Package(
    type.name,
    type,
    product,
    const PresentedOfferingContext('default', null, null),
  );
}

Package annualPackage({
  double price = 29.99,
  String priceString = '\$29.99',
  IntroductoryPrice? trial,
  String? perMonth = '\$2.49',
}) {
  return buildPackage(
    PackageType.annual,
    buildProduct(
      identifier: 'yearly',
      price: price,
      priceString: priceString,
      introductoryPrice: trial,
      pricePerMonthString: perMonth,
    ),
  );
}

Package monthlyPackage({double price = 4.99, String priceString = '\$4.99'}) {
  return buildPackage(
    PackageType.monthly,
    buildProduct(identifier: 'monthly', price: price, priceString: priceString),
  );
}

void main() {
  late LocalStorageService storage;
  late RecordingRevenueCatService revenueCat;

  setUp(() {
    storage = LocalStorageService();
    revenueCat = RecordingRevenueCatService(storage);
  });

  Widget createPaywallWidget() {
    return MaterialApp(
      theme: EvenTheme.darkTheme,
      home: PaywallScreen(storage: storage, revenueCatService: revenueCat),
    );
  }

  void configureViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
  }

  ElevatedButton subscribeButton(WidgetTester tester) {
    return tester.widget<ElevatedButton>(
      find.byKey(const ValueKey('btn_paywall_subscribe')),
    );
  }

  Future<void> tapSubscribe(WidgetTester tester) async {
    final button = find.byKey(const ValueKey('btn_paywall_subscribe'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  group('PaywallScreen content', () {
    testWidgets('Renders all value propositions and plan cards', (
      WidgetTester tester,
    ) async {
      configureViewport(tester);
      await tester.pumpWidget(createPaywallWidget());
      await tester.pump();

      expect(find.text('Unlock EvenPlate Pro'), findsOneWidget);
      expect(find.text('Extra credits'), findsNothing);
      expect(
        find.text('75 photo scans and 100 food scores each week'),
        findsOneWidget,
      );
      expect(find.text('Relative Fullness Ratings'), findsOneWidget);
      expect(
        find.text('Food pairings and your own energy check-ins'),
        findsOneWidget,
      );
      expect(
        find.text('Weekly satiety recaps and check-in reminders'),
        findsOneWidget,
      );

      expect(find.byKey(const ValueKey('paywall_plan_annual')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('paywall_plan_monthly')),
        findsOneWidget,
      );
    });
  });

  group('PaywallScreen when offerings are unavailable', () {
    testWidgets('Shows no prices and disables Subscribe', (
      WidgetTester tester,
    ) async {
      configureViewport(tester);
      await tester.pumpWidget(createPaywallWidget());
      await tester.pump();

      expect(find.text('Unavailable'), findsNWidgets(2));
      expect(find.text('Plans unavailable'), findsOneWidget);
      expect(subscribeButton(tester).onPressed, isNull);
    });

    testWidgets('Tapping Subscribe never grants Pro', (
      WidgetTester tester,
    ) async {
      configureViewport(tester);
      await storage.setProStatus(false);
      await tester.pumpWidget(createPaywallWidget());
      await tester.pump();

      await tapSubscribe(tester);

      expect(revenueCat.purchased, isNull);
      expect(storage.userProfile.isPro, isFalse);
      expect(revenueCat.isPro, isFalse);
    });

    testWidgets('Restore reports nothing to restore and does not grant Pro', (
      WidgetTester tester,
    ) async {
      configureViewport(tester);
      await storage.setProStatus(false);
      await tester.pumpWidget(createPaywallWidget());
      await tester.pump();

      final restoreBtn = find.byKey(const ValueKey('btn_paywall_restore'));
      await tester.ensureVisible(restoreBtn);
      await tester.pumpAndSettle();
      await tester.tap(restoreBtn);
      await tester.pumpAndSettle();

      expect(
        find.text('No active purchases found to restore.'),
        findsOneWidget,
      );
      final snackTheme = Theme.of(
        tester.element(find.byType(SnackBar)),
      ).snackBarTheme;
      expect(snackTheme.backgroundColor, EvenColors.darkSurfaceElevated);
      expect(snackTheme.contentTextStyle?.color, EvenColors.textDarkPrimary);
      expect(storage.userProfile.isPro, isFalse);
    });
  });

  group('PaywallScreen pricing', () {
    testWidgets('Each card shows its own price regardless of offering order', (
      WidgetTester tester,
    ) async {
      configureViewport(tester);
      // Monthly deliberately first: the dashboard controls this order and it
      // must not decide what a card displays or charges.
      revenueCat.debugSetPackages([monthlyPackage(), annualPackage()]);
      await tester.pumpWidget(createPaywallWidget());
      await tester.pump();

      expect(find.text('\$29.99 / yr'), findsOneWidget);
      expect(find.text('\$4.99 / mo'), findsOneWidget);
      expect(find.text('Works out to \$2.49/mo'), findsOneWidget);
    });

    testWidgets('Savings badge is computed from the live prices', (
      WidgetTester tester,
    ) async {
      configureViewport(tester);
      revenueCat.debugSetPackages([annualPackage(), monthlyPackage()]);
      await tester.pumpWidget(createPaywallWidget());
      await tester.pump();

      // 4.99 x 12 = 59.88, so 29.99 is a 50% saving.
      expect(find.text('SAVE 50%'), findsOneWidget);
    });

    testWidgets('No savings badge when annual is not actually cheaper', (
      WidgetTester tester,
    ) async {
      configureViewport(tester);
      revenueCat.debugSetPackages([
        annualPackage(price: 59.88, priceString: '\$59.88'),
        monthlyPackage(),
      ]);
      await tester.pumpWidget(createPaywallWidget());
      await tester.pump();

      expect(find.textContaining('SAVE'), findsNothing);
    });
  });

  group('PaywallScreen plan selection', () {
    testWidgets(
      'Canceled active subscription shows management instead of purchase',
      (WidgetTester tester) async {
        configureViewport(tester);
        revenueCat.renewalState = SubscriptionRenewalState.ending;
        revenueCat.debugSetPackages([annualPackage(), monthlyPackage()]);
        await tester.pumpWidget(createPaywallWidget());
        await tester.pump();

        expect(find.textContaining('Renewal is off'), findsOneWidget);
        expect(find.text('Unlock Pro for \$29.99'), findsNothing);
        expect(find.text('Manage subscription'), findsWidgets);
        expect(revenueCat.purchased, isNull);
      },
    );

    testWidgets('Rechecks subscription before starting a purchase', (
      WidgetTester tester,
    ) async {
      configureViewport(tester);
      revenueCat.debugSetPackages([annualPackage(), monthlyPackage()]);
      await tester.pumpWidget(createPaywallWidget());
      await tester.pump();
      revenueCat.renewalState = SubscriptionRenewalState.ending;

      await tapSubscribe(tester);

      expect(revenueCat.purchased, isNull);
      expect(find.textContaining('Renewal is off'), findsOneWidget);
    });

    testWidgets('Does not purchase when subscription status is unavailable', (
      WidgetTester tester,
    ) async {
      configureViewport(tester);
      revenueCat.debugSetPackages([annualPackage(), monthlyPackage()]);
      await tester.pumpWidget(createPaywallWidget());
      await tester.pump();
      revenueCat.renewalState = null;

      await tapSubscribe(tester);

      expect(revenueCat.purchased, isNull);
      expect(
        find.textContaining('Subscription status is unavailable'),
        findsOneWidget,
      );
    });

    testWidgets('Annual selection purchases the annual package', (
      WidgetTester tester,
    ) async {
      configureViewport(tester);
      revenueCat.debugSetPackages([monthlyPackage(), annualPackage()]);
      await tester.pumpWidget(createPaywallWidget());
      await tester.pump();

      await tapSubscribe(tester);

      expect(revenueCat.purchased?.packageType, PackageType.annual);
    });

    testWidgets('Monthly selection purchases the monthly package', (
      WidgetTester tester,
    ) async {
      configureViewport(tester);
      revenueCat.debugSetPackages([monthlyPackage(), annualPackage()]);
      await tester.pumpWidget(createPaywallWidget());
      await tester.pump();

      final monthlyCard = find.byKey(const ValueKey('paywall_plan_monthly'));
      await tester.ensureVisible(monthlyCard);
      await tester.tap(monthlyCard);
      await tester.pumpAndSettle();

      expect(find.text('Unlock Pro for \$4.99'), findsOneWidget);

      await tapSubscribe(tester);

      expect(revenueCat.purchased?.packageType, PackageType.monthly);
    });

    testWidgets('Falls back to Monthly when there is no annual plan', (
      WidgetTester tester,
    ) async {
      configureViewport(tester);
      revenueCat.debugSetPackages([monthlyPackage()]);
      await tester.pumpWidget(createPaywallWidget());
      await tester.pump();

      expect(subscribeButton(tester).onPressed, isNotNull);

      await tapSubscribe(tester);

      expect(revenueCat.purchased?.packageType, PackageType.monthly);
    });

    testWidgets('Successful purchase unlocks Pro and pops', (
      WidgetTester tester,
    ) async {
      configureViewport(tester);
      await storage.setProStatus(false);
      revenueCat.debugSetPackages([annualPackage(), monthlyPackage()]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                key: const ValueKey('btn_open_paywall'),
                onPressed: () => Navigator.of(ctx).push(
                  MaterialPageRoute(
                    builder: (_) => PaywallScreen(
                      storage: storage,
                      revenueCatService: revenueCat,
                    ),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('btn_open_paywall')));
      await tester.pumpAndSettle();
      expect(find.text('Unlock EvenPlate Pro'), findsOneWidget);

      await tapSubscribe(tester);

      expect(storage.userProfile.isPro, isTrue);
      expect(revenueCat.isPro, isTrue);
      expect(find.byKey(const ValueKey('btn_open_paywall')), findsOneWidget);
    });
  });

  group('PaywallScreen free trial', () {
    IntroductoryPrice freeTrial({
      int units = 7,
      PeriodUnit unit = PeriodUnit.day,
    }) {
      return IntroductoryPrice(0, 'Free', 'P7D', 1, unit, units);
    }

    testWidgets(
      'Eligible customers see the real trial and full renewal price',
      (WidgetTester tester) async {
        configureViewport(tester);
        revenueCat.debugSetPackages(
          [annualPackage(trial: freeTrial()), monthlyPackage()],
          eligibleProductIds: {annualPackage().storeProduct.identifier},
        );
        await tester.pumpWidget(createPaywallWidget());
        await tester.pump();

        expect(find.text('Start 7-Day Free Trial'), findsOneWidget);
        expect(
          find.text('7-Day Free Trial, then \$29.99 per year'),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('paywall_trial_reminder_switch')),
          findsNothing,
        );
      },
    );

    testWidgets('Trial length comes from the product, not a hardcoded string', (
      WidgetTester tester,
    ) async {
      configureViewport(tester);
      revenueCat.debugSetPackages(
        [
          annualPackage(trial: freeTrial(units: 2, unit: PeriodUnit.week)),
          monthlyPackage(),
        ],
        eligibleProductIds: {annualPackage().storeProduct.identifier},
      );
      await tester.pumpWidget(createPaywallWidget());
      await tester.pump();

      expect(find.text('Start 2-Week Free Trial'), findsOneWidget);
      expect(find.textContaining('7-Day'), findsNothing);
    });

    testWidgets('No trial means no trial claim and no reminder toggle', (
      WidgetTester tester,
    ) async {
      configureViewport(tester);
      revenueCat.debugSetPackages([annualPackage(), monthlyPackage()]);
      await tester.pumpWidget(createPaywallWidget());
      await tester.pump();

      expect(find.text('Unlock Pro for \$29.99'), findsOneWidget);
      expect(find.textContaining('Free Trial'), findsNothing);
      expect(
        find.byKey(const ValueKey('paywall_trial_reminder_switch')),
        findsNothing,
      );
    });

    testWidgets('A discounted intro price is not advertised as a free trial', (
      WidgetTester tester,
    ) async {
      configureViewport(tester);
      revenueCat.debugSetPackages([
        annualPackage(
          trial: const IntroductoryPrice(
            2.99,
            '\$2.99',
            'P1M',
            1,
            PeriodUnit.month,
            1,
          ),
        ),
        monthlyPackage(),
      ]);
      await tester.pumpWidget(createPaywallWidget());
      await tester.pump();

      expect(find.textContaining('Free Trial'), findsNothing);
      expect(find.text('Unlock Pro for \$29.99'), findsOneWidget);
    });

    testWidgets('A returning customer is not promised an ineligible trial', (
      tester,
    ) async {
      configureViewport(tester);
      revenueCat.debugSetPackages([
        annualPackage(trial: freeTrial()),
        monthlyPackage(),
      ]);
      await tester.pumpWidget(createPaywallWidget());
      await tester.pump();
      expect(find.textContaining('Free Trial'), findsNothing);
      expect(find.text('Unlock Pro for \$29.99'), findsOneWidget);
    });
  });

  group('PaywallScreen rewarded ad', () {
    testWidgets('Does not offer a fake partner clip', (
      WidgetTester tester,
    ) async {
      configureViewport(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: PaywallScreen(storage: storage, revenueCatService: revenueCat),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('btn_paywall_rewarded_ad')),
        findsNothing,
      );
      expect(find.textContaining('75 photo scans'), findsWidgets);
    });
  });
}
