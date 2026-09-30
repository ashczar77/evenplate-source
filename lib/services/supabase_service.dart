import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/errors/telemetry.dart';
import '../core/security/app_secrets.dart';
import '../core/security/auth_user_messages.dart';
import '../models/meal_log.dart';
import 'local_storage_service.dart';
import 'meal_diary_sync.dart';
import 'onesignal_service.dart';
import 'revenuecat_service.dart';
import 'food_list_scorer.dart';
import 'device_check_service.dart';

enum EmailAuthOutcome { authenticated, confirmEmail, accountExists, failed }

/// Confirm-email Auth answers a repeat signup with a user and an empty
/// identities list, instead of an "already registered" error.
bool signupIsExistingAccount(User? user) {
  final identities = user?.identities;
  return identities != null && identities.isEmpty;
}

/// Supabase Authentication & Backend Service
class SupabaseService extends ChangeNotifier with WidgetsBindingObserver {
  final LocalStorageService _storage;
  RevenueCatService? _revenueCat;
  OneSignalService? _oneSignal;
  bool _isInitialized = false;
  bool needsPasswordRecovery = false;
  static const authRedirect = 'evenplate://auth-callback';
  bool _isLoading = false;
  String? _errorMessage;

  /// Local simulation lets the UI be developed without a backend. It is a debug
  /// convenience only: a release build must never treat an unconfigured backend
  /// as a successful sign in, because that accepts any password.
  final bool _allowSimulatedAuth;

  SupabaseService(this._storage, {bool? allowSimulatedAuth})
    : _allowSimulatedAuth = allowSimulatedAuth ?? kDebugMode {
    _storage.onPreferencesWritten = () => unawaited(flushMealSync());
    _storage.onMealWritten = (_) => unawaited(flushMealSync());
    _storage.onMealRemoved = (_) => unawaited(flushMealSync());
  }

  String get dietaryPreference => _storage.userProfile.dietaryPreference;

  bool get hasAnalysisConsent => _storage.analysisConsentGranted;

  bool get isInitialized => _isInitialized;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  SupabaseClient? get client {
    if (!_isInitialized) return null;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  static const _authTimeout = Duration(seconds: 20);

  bool _isMockAuthenticated = false;
  String? _mockUserId;
  String? _mockUserEmail;
  String? _syncedUserId;
  Future<void>? _accountRestore;
  StreamSubscription<AuthState>? _authChanges;

  User? get currentUser => client?.auth.currentUser;

  /// Opaque auth id for crash reports. Never an email.
  String? get telemetryUserId => currentUser?.id ?? _mockUserId;
  bool get isAuthenticated => currentUser != null || _isMockAuthenticated;
  bool get isAnonymous =>
      currentUser?.isAnonymous ??
      (_isMockAuthenticated &&
          (_mockUserEmail == null || _mockUserEmail!.isEmpty));
  String? get currentAccessToken =>
      client?.auth.currentSession?.accessToken ??
      (_isMockAuthenticated
          ? 'mock_jwt_token_${_mockUserId ?? "guest"}'
          : null);

  void setRevenueCatService(RevenueCatService revenueCat) {
    _revenueCat = revenueCat;
    revenueCat.onPurchaseCompleted = ({required bool subscription}) async {
      final owner = currentUser?.id;
      final accessToken = currentAccessToken;
      if (owner == null || accessToken == null) return;
      final photoBefore = _storage.userProfile.photoPurchased;
      final textBefore = _storage.userProfile.textPurchased;
      try {
        await client?.functions
            .invoke(
              'reconcile-billing',
              body: {},
              headers: {'Authorization': 'Bearer $accessToken'},
            )
            .timeout(_authTimeout);
      } catch (e, st) {
        Telemetry.report(name: 'billing.reconcile_failed', error: e, stack: st);
      }
      for (var attempt = 0; attempt < 6; attempt++) {
        if (currentUser?.id != owner || _storage.userProfile.id != owner) {
          return;
        }
        final synced = await pullProfileQuota();
        if (currentUser?.id != owner || _storage.userProfile.id != owner) {
          return;
        }
        if (synced &&
            (_storage.userProfile.photoPurchased > photoBefore ||
                _storage.userProfile.textPurchased > textBefore ||
                (subscription && _storage.userProfile.isPro))) {
          return;
        }
        if (attempt == 5) break;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      Telemetry.report(name: 'billing.sync_incomplete');
    };
  }

  void setOneSignalService(OneSignalService oneSignal) {
    _oneSignal = oneSignal;
  }

  Future<void> init() async {
    if (_isInitialized) return;

    WidgetsBinding.instance.addObserver(this);
    final url = AppSecrets.supabaseUrl;
    final anonKey = AppSecrets.supabaseAnonKey;

    if (url.isEmpty || anonKey.isEmpty || url.contains('mock.supabase.co')) {
      debugPrint(
        'Supabase credentials unconfigured or using mock placeholder.',
      );
      _isInitialized = true;
      notifyListeners();
      return;
    }

    try {
      await Supabase.initialize(
        url: url,
        // ignore: deprecated_member_use
        anonKey: anonKey,
        authOptions: const FlutterAuthClientOptions(
          authFlowType: AuthFlowType.pkce,
        ),
      ).timeout(const Duration(seconds: 15));

      _isInitialized = true;

      // Listen to Auth State Changes. Never await RevenueCat here: a hung
      // logIn used to freeze the sign-in spinner forever.
      _authChanges = client?.auth.onAuthStateChange.listen((data) {
        final session = data.session;
        final event = data.event;
        if (event == AuthChangeEvent.passwordRecovery) {
          needsPasswordRecovery = true;
          notifyListeners();
          return;
        }

        if (event == AuthChangeEvent.signedIn && session != null) {
          debugPrint('Supabase Auth: Signed in as ${session.user.id}');
          // Restore the diary before the gate paints. Notifying first showed
          // the questionnaire for an account that already had plates.
          unawaited(() async {
            await _onUserAuthenticated(session.user);
            notifyListeners();
          }());
          return;
        } else if (event == AuthChangeEvent.signedOut) {
          debugPrint('Supabase Auth: Signed out');
          _syncedUserId = null;
          final rc = _revenueCat;
          if (rc != null) unawaited(rc.logOut());
          final push = _oneSignal;
          if (push != null) unawaited(push.logOut());
        }
        notifyListeners();
      });

      // Adopt the saved account before the first frame of the gate.
      // Cloud quota and diary pull stay off this path so boot is not
      // stuck on the network.
      final activeSession = client?.auth.currentSession;
      if (activeSession != null) {
        await _onUserAuthenticated(activeSession.user);
      }
    } catch (e) {
      debugPrint('Supabase initialization notice: $e');
      _isInitialized = true;
    }

    notifyListeners();
  }

  bool _refuseUnconfiguredAuth() {
    _errorMessage =
        'Sign in is unavailable because the app is not configured correctly.';
    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<void> _onUserAuthenticated(User user) {
    final pending = _accountRestore ?? Future<void>.value();
    final next = pending.then((_) => _restoreAccount(user));
    _accountRestore = next.catchError((Object error) {
      debugPrint('Account restore failed: $error');
      return Future<void>.value();
    });
    return next;
  }

  Future<void> _restoreAccount(User user) async {
    if (currentUser?.id != user.id) return;
    await _storage.adoptAccount(userId: user.id, email: user.email);
    if (currentUser?.id != user.id) return;
    if (_syncedUserId == user.id) return;
    _syncedUserId = user.id;
    unawaited(_oneSignal?.identify(user.id));
    unawaited(_syncSignedInCloud(user.id));
  }

  /// Store first, then the profile ledger. Pulling leftover Pro meters
  /// before RevenueCat has spoken used to resurrect an expired week.
  Future<void> _syncSignedInCloud(String userId) async {
    final rc = _revenueCat;
    if (rc != null) await rc.logIn(userId);
    if (currentUser?.id != userId) return;
    try {
      await client?.functions
          .invoke('reconcile-billing', body: {})
          .timeout(_authTimeout);
    } catch (e) {
      Telemetry.report(name: 'billing.reconcile_failed', error: e);
    }
    unawaited(verifyDeviceInstallation());
    await pullProfileQuota();
    if (currentUser?.id != userId) return;
    await flushMealSync();
    await pullMealDiary();
  }

  String? _deviceEligibleOwner;
  DateTime? _deviceEligibleUntil;
  Future<void>? _deviceAccessPending;
  String? _deviceAccessPendingKey;

  void invalidateDeviceAccess() {
    _deviceEligibleOwner = null;
    _deviceEligibleUntil = null;
  }

  Future<void> ensureDeviceAccess(String kind) async {
    final live = client;
    final owner = currentUser?.id;
    if (live == null || owner == null) return;
    if (_deviceEligibleOwner == owner &&
        (_deviceEligibleUntil?.isAfter(DateTime.now()) ?? false)) {
      return;
    }
    final key = '$owner:$kind';
    if (_deviceAccessPendingKey == key && _deviceAccessPending != null) {
      return _deviceAccessPending!;
    }
    final pending = _verifyFreeAccess(live, owner, kind);
    _deviceAccessPendingKey = key;
    _deviceAccessPending = pending;
    try {
      await pending;
    } finally {
      if (_deviceAccessPendingKey == key && _deviceAccessPending == pending) {
        _deviceAccessPendingKey = null;
        _deviceAccessPending = null;
      }
    }
  }

  Future<void> _verifyFreeAccess(
    SupabaseClient live,
    String owner,
    String kind,
  ) async {
    final tokenForOwner = live.auth.currentSession?.accessToken;
    if (tokenForOwner == null) {
      throw const DeviceCheckUnavailable('account_changed');
    }
    final authHeaders = {'Authorization': 'Bearer $tokenForOwner'};
    try {
      final response = await live.functions
          .invoke(
            'device-access',
            body: {'action': 'status'},
            headers: authHeaders,
          )
          .timeout(_authTimeout);
      final state = _asStringKeyedMap(response.data);
      if (currentUser?.id != owner) {
        throw const DeviceCheckUnavailable('account_changed');
      }
      if (response.status != 200 || state == null) {
        throw const DeviceCheckUnavailable('unavailable');
      }
      if (state['enabled'] != true) return;
      if (state['eligible'] != true) {
        if (state['paid'] == true ||
            ((state[kind == 'photo' ? 'photo_purchased' : 'text_purchased']
                            as num?)
                        ?.toInt() ??
                    0) >
                0) {
          return;
        }
        final token = await DeviceCheckService().generateToken();
        if (currentUser?.id != owner) {
          throw const DeviceCheckUnavailable('account_changed');
        }
        final result = await live.functions
            .invoke(
              'device-access',
              body: {'action': 'claim', 'token': token},
              headers: authHeaders,
            )
            .timeout(const Duration(seconds: 30));
        final data = _asStringKeyedMap(result.data);
        if (result.status != 200 || data?['eligible'] != true) {
          throw DeviceCheckUnavailable(
            data?['code']?.toString() ?? 'unavailable',
          );
        }
      }
      if (currentUser?.id != owner) {
        throw const DeviceCheckUnavailable('account_changed');
      }
      _deviceEligibleOwner = owner;
      _deviceEligibleUntil = DateTime.now().add(const Duration(minutes: 20));
    } on FunctionException catch (error) {
      final data = _asStringKeyedMap(error.details);
      throw DeviceCheckUnavailable(data?['code']?.toString() ?? 'unavailable');
    } on DeviceCheckUnavailable {
      rethrow;
    } catch (_) {
      throw const DeviceCheckUnavailable('unavailable');
    }
  }

  Future<void> verifyDeviceInstallation() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    final live = client;
    final owner = currentUser?.id;
    if (live == null || owner == null) return;
    final tokenForOwner = live.auth.currentSession?.accessToken;
    if (tokenForOwner == null) return;
    try {
      final token = await DeviceCheckService().generateToken();
      if (currentUser?.id != owner) return;
      await live.functions
          .invoke(
            'device-access',
            body: {'action': 'verify', 'token': token},
            headers: {'Authorization': 'Bearer $tokenForOwner'},
          )
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      // Verification does not block account restoration or expose token details.
      debugPrint('Device verification pending.');
    }
  }

  /// Adopts the weekly meters stored on the profile ledger.
  Future<bool> pullProfileQuota() async {
    final live = client;
    final user = live?.auth.currentUser;
    if (live == null || user == null) return false;
    try {
      final map = _asStringKeyedMap(
        await live.rpc('get_my_quota').timeout(_authTimeout),
      );
      if (map == null ||
          currentUser?.id != user.id ||
          _storage.userProfile.id != user.id) {
        return false;
      }
      await _adoptProfileLedger(map);
      return true;
    } catch (e) {
      debugPrint('Profile quota pull failed: $e');
      return false;
    }
  }

  Future<void> _adoptProfileLedger(Map<String, dynamic> map) async {
    int asInt(String key, int fallback) {
      final value = map[key];
      if (value is num) return value.toInt();
      return fallback;
    }

    final promoUntil = DateTime.tryParse(
      map['promo_pro_until']?.toString() ?? '',
    );
    final promoLive =
        map['promo_live'] == true ||
        (promoUntil != null && promoUntil.isAfter(DateTime.now().toUtc()));
    final entitled = promoLive || map['is_pro'] == true;
    await _storage.applyPromoGrant(promoUntil);
    await _storage.applyStoreEntitlement(map['is_pro'] == true);
    await _storage.applyServerQuota(
      isPro: entitled,
      freeScansRemaining: asInt(
        'free_scans_remaining',
        _storage.userProfile.freeScansRemaining,
      ),
      photoPurchased: asInt(
        'photo_purchased',
        _storage.userProfile.photoPurchased,
      ),
      textRemaining: asInt(
        'text_included_remaining',
        _storage.userProfile.textRemaining,
      ),
      textPurchased: asInt(
        'text_purchased',
        _storage.userProfile.textPurchased,
      ),
    );
  }

  /// Signed-in plates from the account, merged into the phone diary.
  Future<void> pullMealDiary() async {
    final live = client;
    final user = live?.auth.currentUser;
    if (live == null || user == null) return;
    try {
      final rows = <dynamic>[];
      for (var offset = 0; ; offset += 250) {
        if (currentUser?.id != user.id) return;
        final page = await live
            .from('meals')
            .select()
            .eq('user_id', user.id)
            .order('created_at')
            .order('id')
            .range(offset, offset + 249)
            .timeout(_authTimeout);
        rows.addAll(page);
        if (page.length < 250) break;
      }
      final meals = <MealLog>[];
      for (final raw in rows) {
        final map = _asStringKeyedMap(raw);
        if (map == null) continue;
        final meal = MealDiarySync.fromServerRow(map);
        if (meal == null) continue;
        meals.add(meal);
      }
      if (currentUser?.id != user.id || _storage.userProfile.id != user.id) {
        return;
      }
      await _storage.mergeRemoteMeals(meals);
    } catch (e, st) {
      Telemetry.report(name: 'sync.pull_failed', error: e, stack: st);
      if (currentUser?.id == user.id) {
        _syncIssue =
            'Could not refresh your cloud diary. Your plates on this phone are still available.';
        notifyListeners();
      }
    }
  }

  bool _flushing = false;
  bool _flushQueued = false;
  Timer? _syncRetry;
  int _retrySeconds = 2;
  int _consecutiveSyncTimeouts = 0;
  String? _syncIssue;
  String? get syncIssue => _syncIssue;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refreshAccount());
  }

  Future<void> refreshAccount() async {
    await flushMealSync();
    await pullProfileQuota();
    await pullMealDiary();
  }

  Future<void> flushMealSync() async {
    final live = client;
    final owner = currentUser?.id;
    if (_flushing) {
      _flushQueued = true;
      return;
    }
    if (live == null || owner == null || owner != _storage.userProfile.id) {
      return;
    }
    _flushing = true;
    try {
      for (final entry in _storage.pendingMealSync(owner)) {
        if (currentUser?.id != owner || _storage.userProfile.id != owner) {
          return;
        }
        final meal = MealLog.fromJson(
          Map<String, dynamic>.from(entry['meal'] as Map),
        );
        if (meal.userId != owner) continue;
        if (entry['operation'] == 'delete') {
          await live
              .from('meals')
              .delete()
              .eq('user_id', owner)
              .eq('local_id', meal.id)
              .timeout(_authTimeout);
        } else {
          await live
              .from('meals')
              .upsert({
                'user_id': owner,
                'local_id': meal.id,
                'meal_name': meal.mealName,
                'satiety_score': meal.satietyResult.satietyScore,
                'duration_hours': meal.satietyResult.durationHours,
                'satiety_result': MealDiarySync.satietyPayload(meal),
                'created_at': meal.timestamp.toUtc().toIso8601String(),
              }, onConflict: 'user_id,local_id')
              .timeout(_authTimeout);
        }
        if (currentUser?.id != owner) return;
        await _storage.acknowledgeMealSync(
          entry['key'] as String,
          entry['revision'] as String,
        );
      }
      await syncPreferences();
      _syncIssue = null;
      _retrySeconds = 2;
      _consecutiveSyncTimeouts = 0;
    } catch (e, st) {
      _syncIssue =
          'Your changes are saved on this phone. Cloud sync will retry.';
      _consecutiveSyncTimeouts = e is TimeoutException
          ? _consecutiveSyncTimeouts + 1
          : 0;
      Telemetry.report(
        name: 'sync.failed',
        error: e,
        stack: st,
        diagnosticOnly: e is TimeoutException && _consecutiveSyncTimeouts < 3,
      );
      _syncRetry?.cancel();
      _syncRetry = Timer(
        Duration(seconds: _retrySeconds),
        () => unawaited(flushMealSync()),
      );
      _retrySeconds = (_retrySeconds * 2).clamp(2, 60);
    } finally {
      _flushing = false;
      notifyListeners();
      if (_flushQueued) {
        _flushQueued = false;
        unawaited(flushMealSync());
      }
    }
  }

  @override
  void dispose() {
    _syncRetry?.cancel();
    _authChanges?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> syncPreferences() async {
    final live = client;
    final owner = currentUser?.id;
    if (live == null || owner == null || _storage.userProfile.id != owner) {
      return;
    }
    final pending = _storage.pendingPreferences(owner);
    if (pending != null) {
      await live
          .from('user_preferences')
          .upsert({
            'user_id': owner,
            'preferences': pending['preferences'],
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .timeout(_authTimeout);
      if (currentUser?.id != owner) return;
      await _storage.acknowledgePreferences(
        owner,
        pending['revision'] as String,
      );
    }
    final row = await live
        .from('user_preferences')
        .select('preferences')
        .eq('user_id', owner)
        .maybeSingle()
        .timeout(_authTimeout);
    if (currentUser?.id != owner || row == null) return;
    await _storage.adoptRemotePreferences(
      owner,
      Map<String, dynamic>.from(row['preferences'] as Map),
    );
  }

  Future<void> eraseAccountData() async {
    final live = client;
    final owner = live?.auth.currentUser?.id ?? _storage.userProfile.id;
    if (live == null || live.auth.currentUser == null) {
      if (!_isMockAuthenticated) {
        throw StateError('Sign in to delete your account.');
      }
    } else {
      final response = await live.functions
          .invoke('delete-account', body: {})
          .timeout(const Duration(seconds: 45));
      if (response.status != 200 ||
          response.data is! Map ||
          response.data['deleted'] != true) {
        throw StateError(
          'Account deletion could not finish. Please try again.',
        );
      }
    }
    final wasActive = _storage.userProfile.id == owner;
    await _storage.clearAccountData(owner);
    if (!wasActive || (live != null && live.auth.currentUser?.id != owner)) {
      return;
    }
    await FoodListScorer.instance.cache.clear();
    if (live != null && live.auth.currentUser?.id != owner) return;
    await _oneSignal?.logOut();
    if (live != null && live.auth.currentUser?.id != owner) return;
    await signOut();
  }

  Future<void> _simulateLocalAuth({
    required String idPrefix,
    String? email,
  }) async {
    _isMockAuthenticated = true;
    _mockUserId = '${idPrefix}_${DateTime.now().millisecondsSinceEpoch}';
    _mockUserEmail = email;
    final currentProfile = _storage.userProfile;
    final updated = currentProfile.copyWith(
      id: _mockUserId,
      email: email ?? 'guest@evenplate.dev',
    );
    await _storage.saveUserProfile(updated);
    final rc = _revenueCat;
    if (rc != null) unawaited(rc.logIn(_mockUserId!));
  }

  Future<bool> _runAuthAttempt(Future<void> Function() body) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await body();
      Telemetry.setUser(id: telemetryUserId, guest: isAnonymous);
      return true;
    } on TimeoutException {
      _errorMessage =
          'Sign in is taking too long. Check your connection and try again.';
      Telemetry.report(name: 'auth.timeout');
      return false;
    } on _AuthRefused {
      return false;
    } catch (e) {
      _setFriendlyAuthError(e);
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Guest / Anonymous Authentication
  /// Creates a real cryptographic JWT session without an email wall
  Future<bool> signInAnonymously() {
    return _runAuthAttempt(() async {
      if (client != null) {
        await client!.auth.signInAnonymously().timeout(_authTimeout);
        final user = client!.auth.currentUser;
        if (user != null) await _onUserAuthenticated(user);
        return;
      }
      if (!_allowSimulatedAuth) {
        _refuseUnconfiguredAuth();
        throw const _AuthRefused();
      }
      await _simulateLocalAuth(idPrefix: 'guest');
    });
  }

  void _setFriendlyAuthError(Object error) {
    if (error is AuthException) {
      debugPrint('EvenPlate auth: ${error.code ?? "no_code"} ${error.message}');
      _errorMessage = AuthUserMessages.fromAuthFailure(
        code: error.code,
        message: error.message,
      );
      return;
    }
    debugPrint('EvenPlate auth: $error');
    _errorMessage = AuthUserMessages.fromAuthFailure(message: error.toString());
  }

  /// Email & Password Sign Up
  Future<EmailAuthOutcome> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      if (client != null) {
        final response = await client!.auth
            .signUp(
              email: email.trim(),
              password: password,
              emailRedirectTo: authRedirect,
            )
            .timeout(_authTimeout);
        final signedInUser = response.session?.user;
        if (signedInUser != null) {
          await _onUserAuthenticated(signedInUser);
          Telemetry.setUser(id: telemetryUserId, guest: isAnonymous);
          return EmailAuthOutcome.authenticated;
        }
        if (signupIsExistingAccount(response.user)) {
          _errorMessage = AuthUserMessages.accountExists;
          return EmailAuthOutcome.accountExists;
        }
        // Confirm-email projects mint the user and send a link, but no session.
        return EmailAuthOutcome.confirmEmail;
      }
      if (!_allowSimulatedAuth) {
        _refuseUnconfiguredAuth();
        return EmailAuthOutcome.failed;
      }
      await _simulateLocalAuth(idPrefix: 'user', email: email.trim());
      Telemetry.setUser(id: telemetryUserId, guest: isAnonymous);
      return EmailAuthOutcome.authenticated;
    } on TimeoutException {
      _errorMessage =
          'Sign in is taking too long. Check your connection and try again.';
      Telemetry.report(name: 'auth.timeout');
      return EmailAuthOutcome.failed;
    } catch (e) {
      _setFriendlyAuthError(e);
      if (_errorMessage == AuthUserMessages.accountExists) {
        return EmailAuthOutcome.accountExists;
      }
      return EmailAuthOutcome.failed;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Email & Password Sign In
  Future<bool> signInWithEmail({
    required String email,
    required String password,
  }) {
    return _runAuthAttempt(() async {
      if (client != null) {
        await client!.auth
            .signInWithPassword(email: email.trim(), password: password)
            .timeout(_authTimeout);
        final user = client!.auth.currentUser;
        if (user != null) await _onUserAuthenticated(user);
        return;
      }
      if (!_allowSimulatedAuth) {
        _refuseUnconfiguredAuth();
        throw const _AuthRefused();
      }
      await _simulateLocalAuth(idPrefix: 'user', email: email.trim());
    });
  }

  Future<void> sendRecoveryEmail(
    String email, {
    bool confirmation = false,
  }) async {
    final live = client;
    if (live == null) throw StateError('Sign in service is unavailable.');
    if (confirmation) {
      await live.auth
          .resend(
            type: OtpType.signup,
            email: email.trim(),
            emailRedirectTo: authRedirect,
          )
          .timeout(_authTimeout);
    } else {
      await live.auth
          .resetPasswordForEmail(email.trim(), redirectTo: authRedirect)
          .timeout(_authTimeout);
    }
  }

  Future<void>? _passwordRecoverySave;

  Future<void> completePasswordRecovery(String password) {
    final save = _passwordRecoverySave ??= _saveRecoveryPassword(
      password,
    ).whenComplete(() => _passwordRecoverySave = null);
    return save.timeout(_authTimeout);
  }

  Future<void> _saveRecoveryPassword(String password) async {
    final live = client;
    if (!needsPasswordRecovery || live == null) {
      throw StateError('Open a new password reset link.');
    }
    final owner = live.auth.currentUser?.id;
    // A timed-out waiter does not cancel the server request.
    await live.auth.updateUser(UserAttributes(password: password));
    if (owner != null && live.auth.currentUser?.id == owner) {
      needsPasswordRecovery = false;
      notifyListeners();
    }
  }

  /// Sign Out
  Future<void> signOut() async {
    _isLoading = true;
    notifyListeners();

    try {
      _isMockAuthenticated = false;
      _mockUserId = null;
      _mockUserEmail = null;
      _syncedUserId = null;
      needsPasswordRecovery = false;
      await _oneSignal?.logOut();
      await client?.auth.signOut();
      await _revenueCat?.logOut();
      // Keep local meals and the last account id. Sign-in matches them.
    } catch (e) {
      debugPrint('Sign out notice: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Redeems a reviewer promo code against the server.
  ///
  /// Never grants locally when the backend is missing: that was how the old
  /// hardcoded codes unlocked Pro in a release APK.
  Future<PromoRedeemResult> redeemPromoCode(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) {
      return const PromoRedeemResult(
        redeemed: false,
        message: 'Please enter a code.',
      );
    }

    final liveClient = client;
    if (liveClient == null || liveClient.auth.currentSession == null) {
      return const PromoRedeemResult(
        redeemed: false,
        message: 'Sign in to redeem a promo code.',
      );
    }

    try {
      final owner = liveClient.auth.currentUser?.id;
      final raw = await liveClient.rpc(
        'redeem_promo_code',
        params: {'p_code': trimmed},
      );
      if (owner != currentUser?.id || _storage.userProfile.id != owner) {
        return const PromoRedeemResult(
          redeemed: false,
          message: 'Sign in to redeem a promo code.',
        );
      }
      final body = _asStringKeyedMap(raw);
      if (body == null) {
        return const PromoRedeemResult(
          redeemed: false,
          message: 'That code could not be redeemed. Try again.',
        );
      }

      if (body['redeemed'] == true) {
        if (owner != currentUser?.id || _storage.userProfile.id != owner) {
          return const PromoRedeemResult(
            redeemed: false,
            message: 'Sign in to redeem a promo code.',
          );
        }
        await _storage.applyPromoGrant(
          DateTime.tryParse(body['until']?.toString() ?? ''),
        );
        await pullProfileQuota();
        _revenueCat?.notifyEntitlementChanged();
        notifyListeners();
        return const PromoRedeemResult(redeemed: true);
      }

      final reason = body['reason']?.toString();
      if (reason == 'unauthenticated') {
        return const PromoRedeemResult(
          redeemed: false,
          message: 'Sign in to redeem a promo code.',
        );
      }
      return const PromoRedeemResult(
        redeemed: false,
        message: 'That code is not valid.',
      );
    } catch (e) {
      debugPrint('Promo redeem failed: $e');
      return const PromoRedeemResult(
        redeemed: false,
        message: 'That code could not be redeemed. Try again.',
      );
    }
  }

  Map<String, dynamic>? _asStringKeyedMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return null;
  }
}

class _AuthRefused implements Exception {
  const _AuthRefused();
}

class PromoRedeemResult {
  final bool redeemed;
  final String? message;

  const PromoRedeemResult({required this.redeemed, this.message});
}
