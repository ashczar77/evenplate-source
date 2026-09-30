import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evenplate/core/theme/even_theme.dart';
import 'package:evenplate/features/scan/scan_plate_screen.dart';
import 'package:evenplate/features/settings/settings_screen.dart';
import 'package:evenplate/features/shell/main_navigation_shell.dart';
import 'package:evenplate/features/today/today_screen.dart';
import 'package:evenplate/services/local_storage_service.dart';

void main() {
  late LocalStorageService storage;

  setUp(() {
    storage = LocalStorageService();
  });

  Widget createShellWidget({
    Size screenSize = const Size(390, 844),
    EdgeInsets padding = const EdgeInsets.only(bottom: 34),
    ThemeMode themeMode = ThemeMode.dark,
  }) {
    return MediaQuery(
      data: MediaQueryData(
        size: screenSize,
        padding: padding,
        viewPadding: padding,
      ),
      child: MaterialApp(
        theme: EvenTheme.lightTheme,
        darkTheme: EvenTheme.darkTheme,
        themeMode: themeMode,
        home: MainNavigationShell(storage: storage),
      ),
    );
  }

  // The dock keeps both destinations alive in an IndexedStack, so the active
  // destination is read from the stack index rather than widget presence.
  int? activeDestIndex(WidgetTester tester) => tester
      .widget<IndexedStack>(find.byKey(const ValueKey('nav_body_stack')))
      .index;

  testWidgets(
    'MainNavigationShell renders dock destinations and center scan action',
    (WidgetTester tester) async {
      await tester.pumpWidget(createShellWidget());
      await tester.pump();

      expect(find.byKey(const ValueKey('nav_home_tab')), findsOneWidget);
      expect(find.byKey(const ValueKey('nav_scan_button')), findsOneWidget);
      expect(find.byKey(const ValueKey('nav_profile_tab')), findsOneWidget);

      // Home is the initial destination.
      expect(activeDestIndex(tester), equals(0));
      expect(find.text('Daily\nHarmony'), findsOneWidget);
    },
  );

  testWidgets('MainNavigationShell switches destinations and preserves state', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(createShellWidget());
    await tester.pump();

    expect(activeDestIndex(tester), equals(0));

    await tester.tap(find.byKey(const ValueKey('nav_profile_tab')));
    await tester.pump(const Duration(milliseconds: 300));

    expect(activeDestIndex(tester), equals(1));
    expect(find.byType(SettingsScreen), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nav_home_tab')));
    await tester.pump(const Duration(milliseconds: 300));

    expect(activeDestIndex(tester), equals(0));

    // Both destinations stay mounted so their scroll and form state survives.
    // The inactive one is offstage, so it has to be searched for explicitly.
    expect(find.byType(TodayScreen), findsOneWidget);
    expect(find.byType(SettingsScreen, skipOffstage: false), findsOneWidget);
  });

  testWidgets('Settings follows a Pro grant without leaving the tab', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(createShellWidget());
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('nav_profile_tab')));
    await tester.pump();

    expect(find.text('EvenPlate Free'), findsOneWidget);

    await storage.setProStatus(true);
    await tester.pump();

    expect(find.text('EvenPlate Pro Active'), findsOneWidget);
    expect(find.text('EvenPlate Free'), findsNothing);
  });

  testWidgets('Center scan button pushes ScanPlateScreen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(createShellWidget());
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('nav_scan_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(ScanPlateScreen), findsOneWidget);
  });

  for (final coldStart in [false, true]) {
    testWidgets(
      '${coldStart ? 'Cold-start' : 'Open-app'} dinner reminder opens Scan',
      (tester) async {
        const channel = MethodChannel('evenplate/reminders');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        const notification = {
          'action': 'com.apple.UNNotificationDefaultActionIdentifier',
          'payload': '{"campaign":"pre_meal_anchor","period":"dinner"}',
        };
        var acknowledgments = 0;
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'pending') {
            return coldStart ? notification : null;
          }
          if (call.method == 'acknowledge') acknowledgments++;
          return null;
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

        await tester.pumpWidget(createShellWidget());
        await tester.pump();
        if (!coldStart) {
          await messenger.handlePlatformMessage(
            channel.name,
            const StandardMethodCodec().encodeMethodCall(
              const MethodCall('notification', notification),
            ),
            (_) {},
          );
        }
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.byType(ScanPlateScreen), findsOneWidget);
        expect(acknowledgments, coldStart ? 0 : 1);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final manualFirst in [false, true]) {
    testWidgets(
      'Repeated reminders reuse ${manualFirst ? 'manually opened' : 'notification-opened'} Scan',
      (tester) async {
        const channel = MethodChannel('evenplate/reminders');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(channel, (_) async => null);
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

        Future<void> notify(String period) async {
          await messenger.handlePlatformMessage(
            channel.name,
            const StandardMethodCodec().encodeMethodCall(
              MethodCall('notification', {
                'action': 'com.apple.UNNotificationDefaultActionIdentifier',
                'payload': '{"campaign":"pre_meal_anchor","period":"$period"}',
              }),
            ),
            (_) {},
          );
        }

        await tester.pumpWidget(createShellWidget());
        await tester.pump();
        if (manualFirst) {
          await tester.tap(find.byKey(const ValueKey('nav_scan_button')));
        } else {
          await notify('lunch');
        }
        await notify('dinner');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await notify('dinner');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(
          find.byType(ScanPlateScreen, skipOffstage: false),
          findsOneWidget,
        );
        final navigator = tester.state<NavigatorState>(
          find.byType(Navigator).first,
        );
        navigator.pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(ScanPlateScreen, skipOffstage: false), findsNothing);
        expect(navigator.canPop(), isFalse);

        await notify('dinner');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(ScanPlateScreen), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'MainNavigationShell adapts responsively across screen aspect ratios',
    (WidgetTester tester) async {
      // Modern device with a bottom home indicator inset.
      await tester.pumpWidget(
        createShellWidget(
          screenSize: const Size(390, 844),
          padding: const EdgeInsets.only(bottom: 34),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      // Compact device with zero bottom safe area.
      await tester.pumpWidget(
        createShellWidget(
          screenSize: const Size(360, 640),
          padding: EdgeInsets.zero,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      // Tablet or wide layout.
      await tester.pumpWidget(
        createShellWidget(
          screenSize: const Size(768, 1024),
          padding: const EdgeInsets.only(bottom: 20),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
