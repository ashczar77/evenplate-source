import 'dart:async';
import 'dart:ui';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import '../../core/a11y/access.dart';
import '../../core/theme/even_colors.dart';
import '../../core/utils/sensory_feedback.dart';
import '../../models/meal_log.dart';
import '../../services/gemini_vision_service.dart';
import '../../services/local_storage_service.dart';
import '../../services/onesignal_service.dart';
import '../../services/supabase_service.dart';
import '../../services/revenuecat_service.dart';
import '../../widgets/bridge_snack_sheet.dart';
import '../../widgets/satiety_checkin_card.dart';
import '../insights/insights_screen.dart';
import '../scan/scan_plate_screen.dart';
import '../settings/settings_screen.dart';
import '../today/today_screen.dart';

// Nav has 3 destinations: Home (Today+Insights merged), Scan (FAB), Profile
// Scan is the centre action button, not a tab.
enum _NavDest { home, profile }

class MainNavigationShell extends StatefulWidget {
  final LocalStorageService storage;
  final SupabaseService? supabase;
  final OneSignalService? oneSignal;
  final RevenueCatService? revenueCat;

  const MainNavigationShell({
    super.key,
    required this.storage,
    this.supabase,
    this.oneSignal,
    this.revenueCat,
  });

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell>
    with TickerProviderStateMixin {
  _NavDest _dest = _NavDest.home;
  late final GeminiVisionService _visionService;
  late final AnimationController _scanPulse;
  late final Animation<double> _scanAura;
  StreamSubscription<String>? _bridgeSnackSub;
  Route<void>? _scanRoute;
  static const _reminders = MethodChannel('evenplate/reminders');

  @override
  void initState() {
    super.initState();
    _visionService = GeminiVisionService(widget.supabase);

    _scanPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _scanAura = CurvedAnimation(
      parent: _scanPulse,
      curve: Curves.easeInOutSine,
    );

    _reminders.setMethodCallHandler((call) async {
      if (call.method == 'notification') {
        _openReminder(call.arguments);
        await _reminders.invokeMethod<void>('acknowledge');
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final pending = await _reminders.invokeMethod<Object?>('pending');
        if (pending != null) _openReminder(pending);
      } catch (_) {}
    });
    widget.oneSignal?.onNotificationTap = (action, data) {
      _openReminder({'action': action, 'payload': jsonEncode(data ?? {})});
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.oneSignal?.replayPendingTap();
    });
    debugPrint('EvenPlate: Home shell mounted');

    _bridgeSnackSub = widget.oneSignal?.onBridgeSnackRequested.listen((mealId) {
      if (!mounted) return;
      MealLog? applyTo;
      if (mealId.isNotEmpty) {
        for (final meal in widget.storage.meals) {
          if (meal.id == mealId) {
            applyTo = meal;
            break;
          }
        }
      }
      BridgeSnackSheet.show(context, widget.storage, applyTo: applyTo);
    });
  }

  void _openReminder(Object? arguments) {
    if (!mounted || arguments is! Map) return;
    final payload = arguments['payload'];
    Map<String, dynamic>? data;
    try {
      if (payload is String) {
        data = Map<String, dynamic>.from(jsonDecode(payload) as Map);
      }
    } catch (_) {
      return;
    }
    final action = arguments['action'] as String?;
    widget.oneSignal?.handleNotificationAction(action, data);
    if (action == 'action_steady' || action == 'action_dip') return;
    switch (data?['campaign']) {
      case 'post_meal_checkin':
        final mealId = data?['meal_id'];
        final meal = widget.storage.meals
            .where((meal) => meal.id == mealId)
            .firstOrNull;
        if (meal == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('This meal is no longer available.')),
          );
          return;
        }
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) => SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: SatietyCheckinCard(meal: meal, storage: widget.storage),
            ),
          ),
        );
      case 'pre_meal_anchor':
        _openScanScreen();
      case 'sunday_recap':
        _openInsights();
      case 'trial_trust':
        _onDestTapped(_NavDest.profile);
      default:
        _onDestTapped(_NavDest.home);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (prefersReducedMotion(context)) {
      _scanPulse.stop();
      _scanPulse.value = 0.5;
    }
  }

  @override
  void dispose() {
    _reminders.setMethodCallHandler(null);
    widget.oneSignal?.onNotificationTap = null;
    _bridgeSnackSub?.cancel();
    _scanPulse.dispose();
    super.dispose();
  }

  void _openScanScreen() {
    if (_scanRoute?.isActive ?? false) return;
    SensoryFeedback.gentleTap();
    final route = PageRouteBuilder<void>(
      pageBuilder: (_, animation, secondaryAnimation) => ScanPlateScreen(
        storage: widget.storage,
        visionService: _visionService,
        revenueCat: widget.revenueCat,
        refreshQuota: widget.supabase == null
            ? null
            : () async {
                await widget.supabase!.pullProfileQuota();
              },
      ),
      transitionsBuilder: (_, animation, secondaryAnimation, child) {
        return SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
              .animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
          child: child,
        );
      },
      transitionDuration: const Duration(milliseconds: 420),
    );
    _scanRoute = route;
    Navigator.of(context).push(route).whenComplete(() {
      if (identical(_scanRoute, route)) _scanRoute = null;
    });
  }

  void _openInsights() {
    SensoryFeedback.gentleTap();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => InsightsScreen(
          storage: widget.storage,
          onScanPressed: () {
            Navigator.of(context).pop();
            _openScanScreen();
          },
        ),
      ),
    );
  }

  void _onDestTapped(_NavDest dest) {
    if (_dest == dest) return;
    SensoryFeedback.gentleTap();
    setState(() => _dest = dest);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      extendBody: true,
      backgroundColor: EvenColors.darkBackground,
      body: IndexedStack(
        key: const ValueKey('nav_body_stack'),
        index: _dest.index,
        children: [
          TodayScreen(
            storage: widget.storage,
            revenueCat: widget.revenueCat,
            onScanPressed: _openScanScreen,
            onInsightsPressed: _openInsights,
            onOpenSettings: () => _onDestTapped(_NavDest.profile),
          ),
          SettingsScreen(
            storage: widget.storage,
            oneSignal: widget.oneSignal,
            supabase: widget.supabase,
            revenueCat: widget.revenueCat,
          ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.only(
          left: 40,
          right: 40,
          bottom: bottomInset > 0 ? bottomInset + 8 : 20,
        ),
        child: _FloatingDock(
          currentDest: _dest,
          scanAura: _scanAura,
          onDestTapped: _onDestTapped,
          onScanTapped: _openScanScreen,
        ),
      ),
    );
  }
}

// Floating 3-icon dock

class _FloatingDock extends StatelessWidget {
  final _NavDest currentDest;
  final Animation<double> scanAura;
  final ValueChanged<_NavDest> onDestTapped;
  final VoidCallback onScanTapped;

  const _FloatingDock({
    required this.currentDest,
    required this.scanAura,
    required this.onDestTapped,
    required this.onScanTapped,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(36),
      child: _dockSurface(
        context: context,
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            color: isDark
                ? EvenColors.darkSurface.withValues(alpha: 0.94)
                : EvenColors.lightSurface.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(36),
            border: Border.all(
              color: isDark
                  ? EvenColors.darkGlassBorder
                  : EvenColors.lightGlassBorder,
              width: 1,
            ),
            boxShadow: safeBoxShadows([
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ]),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _DockItem(
                key: const ValueKey('nav_home_tab'),
                icon: Icons.grid_view_rounded,
                label: 'Home',
                isActive: currentDest == _NavDest.home,
                onTap: () => onDestTapped(_NavDest.home),
              ),
              _ScanFab(
                key: const ValueKey('nav_scan_button'),
                aura: scanAura,
                onTap: onScanTapped,
              ),
              _DockItem(
                key: const ValueKey('nav_profile_tab'),
                icon: Icons.person_outline_rounded,
                label: 'Profile',
                isActive: currentDest == _NavDest.profile,
                onTap: () => onDestTapped(_NavDest.profile),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _dockSurface({required BuildContext context, required Widget child}) {
  if (!useBackdropBlur(context)) return child;
  return BackdropFilter(
    filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
    child: child,
  );
}

class _DockItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _DockItem({
    super.key,
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = EvenColors.primaryGreen;
    final inactiveColor = isDark
        ? EvenColors.textDarkMuted
        : EvenColors.textLightMuted;

    return Semantics(
      label: label,
      selected: isActive,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 64,
          height: 64,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isActive
                    ? activeColor.withValues(alpha: 0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                icon,
                size: 24,
                color: isActive ? activeColor : inactiveColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScanFab extends StatelessWidget {
  final Animation<double> aura;
  final VoidCallback onTap;

  const _ScanFab({super.key, required this.aura, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Semantics(
      label: 'Scan Plate',
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedBuilder(
          animation: aura,
          builder: (context, _) {
            final glow = aura.value;
            return Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: isDark
                    ? EvenColors.primaryGreen
                    : EvenColors.primaryCharcoal,
                boxShadow: safeBoxShadows([
                  BoxShadow(
                    color: (isDark ? EvenColors.primaryGreen : Colors.black)
                        .withValues(alpha: 0.2 + 0.15 * glow),
                    blurRadius: 12 + 6 * glow,
                    offset: const Offset(0, 4),
                  ),
                ]),
              ),
              child: const Center(
                child: Icon(
                  Icons.document_scanner_outlined,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
