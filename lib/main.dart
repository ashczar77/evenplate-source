import 'dart:async';

import 'package:flutter/material.dart';
import 'core/a11y/access.dart';
import 'core/errors/error_reporter.dart';
import 'core/errors/telemetry.dart';
import 'core/security/config_guard.dart';
import 'core/theme/even_colors.dart';
import 'core/theme/even_theme.dart';
import 'features/auth/auth_screen.dart';
import 'features/auth/password_recovery_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/shell/main_navigation_shell.dart';
import 'services/food_list_scorer.dart';
import 'services/gemini_vision_service.dart';
import 'services/local_storage_service.dart';
import 'services/onesignal_service.dart';
import 'services/retention_scheduler.dart';
import 'services/revenuecat_service.dart';
import 'services/supabase_service.dart';

void main() {
  // ensureInitialized and runApp must share this zone. Binding outside
  // runZonedGuarded and runApp inside it is a fatal Zone mismatch in debug.
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    ErrorReporter.install();
    ErrorWidget.builder = (details) {
      ErrorReporter.record(details.exception, details.stack);
      return const ColoredBox(
        color: EvenColors.darkBackground,
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'EvenPlate could not display this screen. Reopen the app or contact evenplatesupport@gmail.com.',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
        ),
      );
    };
    // Paint a splash on the first frame. Awaiting Hive/RevenueCat/Supabase
    // before runApp left a black Flutter view after the native splash.
    runApp(const EvenPlateRoot());
  }, ErrorReporter.record);
}

/// Production root. Tests construct [EvenPlateApp] with ready services.
class EvenPlateRoot extends StatefulWidget {
  const EvenPlateRoot({super.key});

  @override
  State<EvenPlateRoot> createState() => _EvenPlateRootState();
}

class _EvenPlateRootState extends State<EvenPlateRoot> {
  Widget? _app;

  @override
  void initState() {
    super.initState();
    unawaited(_boot());
  }

  Future<void> _boot() async {
    try {
      ConfigGuard.assertConfigured();
    } catch (e, st) {
      ErrorReporter.record(e, st);
      if (mounted) {
        setState(
          () => _app = EvenPlateBootRetry(onRetry: () => unawaited(_boot())),
        );
      }
      return;
    }
    try {
      await Telemetry.init().timeout(const Duration(seconds: 4));
    } catch (e, st) {
      ErrorReporter.record(e, st);
    }
    // SentryFlutter.init replaces FlutterError.onError. Take it back so
    // text-selection nulls are classified here, not as crash.uncaught.
    ErrorReporter.install();

    final localStorage = LocalStorageService();
    final revenueCatService = RevenueCatService(localStorage);
    final supabaseService = SupabaseService(localStorage);
    supabaseService.setRevenueCatService(revenueCatService);
    final oneSignalService = OneSignalService(localStorage);
    supabaseService.setOneSignalService(oneSignalService);

    // Do not abandon Hive. A short boot timeout used to launch on empty
    // storage while Keychain was still reading, then mint a new AES key.
    try {
      await localStorage.init();
    } catch (e, st) {
      ErrorReporter.record(e, st);
      if (!mounted) return;
      setState(() {
        _app = EvenPlateBootRetry(
          onRetry: () {
            setState(() => _app = null);
            unawaited(_boot());
          },
        );
      });
      return;
    }

    // Profile must be loaded first. Starting OneSignal on the empty default
    // made a granted opt-in look like unsubscribed, so dashboard sends missed
    // the phone.
    unawaited(revenueCatService.init());
    try {
      await oneSignalService.init().timeout(const Duration(seconds: 5));
    } catch (e, st) {
      Telemetry.report(name: 'push.init_failed', error: e, stack: st);
    }
    RetentionScheduler(
      storage: localStorage,
      isAuthenticated: () => supabaseService.isAuthenticated,
      sessionChanges: supabaseService,
      copy: OneSignalRetentionCopy(oneSignalService),
      poster: PlatformReminderPoster(),
    ).start();

    try {
      await supabaseService.init().timeout(const Duration(seconds: 8));
    } catch (e, st) {
      ErrorReporter.record(e, st);
    }

    FoodListScorer.instance.configure(
      vision: GeminiVisionService(supabaseService),
      persistCache: true,
    );

    Telemetry.setUser(
      id: supabaseService.telemetryUserId,
      guest: supabaseService.isAnonymous,
    );

    if (!mounted) return;
    debugPrint(
      'EvenPlate: boot done, simGpuSkip=$isIosSimulator '
      'auth=${supabaseService.isAuthenticated}',
    );
    setState(() {
      _app = EvenPlateApp(
        storage: localStorage,
        revenueCat: revenueCatService,
        oneSignal: oneSignalService,
        supabase: supabaseService,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return _app ?? const EvenPlateSplash();
  }
}

class EvenPlateBootRetry extends StatefulWidget {
  final VoidCallback onRetry;

  const EvenPlateBootRetry({super.key, required this.onRetry});

  @override
  State<EvenPlateBootRetry> createState() => _EvenPlateBootRetryState();
}

class _EvenPlateBootRetryState extends State<EvenPlateBootRetry>
    with WidgetsBindingObserver {
  Timer? _autoRetry;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _autoRetry = Timer(const Duration(seconds: 2), widget.onRetry);
  }

  @override
  void dispose() {
    _autoRetry?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _autoRetry?.cancel();
      widget.onRetry();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: EvenColors.darkBackground,
        colorScheme: const ColorScheme.dark(primary: EvenColors.primaryGreen),
      ),
      home: Scaffold(
        backgroundColor: EvenColors.darkBackground,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'EvenPlate could not start. Try again. If this continues, contact evenplatesupport@gmail.com.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: widget.onRetry,
                  child: const Text('Try now'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class EvenPlateSplash extends StatelessWidget {
  const EvenPlateSplash({super.key});

  @override
  Widget build(BuildContext context) {
    // No Image.asset or GoogleFonts here. First frame must paint even if
    // the brand PNG or a font fetch would stall Impeller on the simulator.
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: EvenColors.darkBackground,
        colorScheme: const ColorScheme.dark(primary: EvenColors.primaryGreen),
      ),
      home: Scaffold(
        backgroundColor: EvenColors.darkBackground,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.eco_rounded,
                color: EvenColors.primaryGreen,
                size: 56,
              ),
              const SizedBox(height: 16),
              Text.rich(
                TextSpan(
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.8,
                  ),
                  children: const [
                    TextSpan(text: 'Even'),
                    TextSpan(
                      text: 'Plate',
                      style: TextStyle(color: EvenColors.primaryGreen),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: EvenColors.primaryGreen,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class EvenPlateApp extends StatelessWidget {
  final LocalStorageService storage;
  final RevenueCatService revenueCat;
  final OneSignalService oneSignal;
  final SupabaseService supabase;

  const EvenPlateApp({
    super.key,
    required this.storage,
    required this.revenueCat,
    required this.oneSignal,
    required this.supabase,
  });

  @override
  Widget build(BuildContext context) {
    // MaterialApp must stay mounted. Rebuilding it on every auth/storage
    // notifyListeners destroyed AuthScreen mid-tap (frozen spinner, then crash).
    return MaterialApp(
      title: 'EvenPlate',
      debugShowCheckedModeBanner: false,
      theme: EvenTheme.darkTheme,
      darkTheme: EvenTheme.darkTheme,
      themeMode: ThemeMode.dark,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(textScaler: clampedTextScaler(media.textScaler)),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: _SessionGate(
        storage: storage,
        revenueCat: revenueCat,
        oneSignal: oneSignal,
        supabase: supabase,
      ),
    );
  }
}

class _SessionGate extends StatelessWidget {
  final LocalStorageService storage;
  final RevenueCatService revenueCat;
  final OneSignalService oneSignal;
  final SupabaseService supabase;

  const _SessionGate({
    required this.storage,
    required this.revenueCat,
    required this.oneSignal,
    required this.supabase,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        storage.profileChanges,
        storage.mealChanges,
        supabase,
      ]),
      builder: (context, _) {
        final signedIn = supabase.isAuthenticated;
        final onboarded = storage.questionnaireDone;
        debugPrint(
          'EvenPlate gate: signedIn=$signedIn onboarded=$onboarded '
          'meals=${storage.meals.length}',
        );
        Telemetry.setUser(
          id: supabase.telemetryUserId,
          guest: supabase.isAnonymous,
        );

        if (supabase.needsPasswordRecovery) {
          return PasswordRecoveryScreen(supabase: supabase);
        }
        if (!signedIn) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              Navigator.of(context).popUntil((route) => route.isFirst);
            }
          });
          return AuthScreen(
            supabase: supabase,
            storage: storage,
            onAuthSuccess: () {},
          );
        }
        if (!onboarded) {
          return OnboardingScreen(
            storage: storage,
            supabase: supabase,
            oneSignal: oneSignal,
          );
        }
        return MainNavigationShell(
          storage: storage,
          supabase: supabase,
          oneSignal: oneSignal,
          revenueCat: revenueCat,
        );
      },
    );
  }
}
