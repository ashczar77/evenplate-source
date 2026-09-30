import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../core/billing/scan_allowance.dart';
import '../core/json/json_map.dart';
import '../core/security/hive_key_store.dart';
import '../models/meal_log.dart';
import '../models/user_profile.dart';
import 'gemini_vision_service.dart';
import 'meal_diary_sync.dart';
import 'meal_photo_store.dart';

/// Local storage. Boxes are AES-256 encrypted; the key lives in
/// flutter_secure_storage (Keychain / Keystore), not next to the files.
class LocalStorageService extends ChangeNotifier {
  static const String _userBoxName = 'evenplate_user_box_aes';
  static const String _mealsBoxName = 'evenplate_meals_box_aes';
  static const String _legacyUserBoxName = 'evenplate_user_box';
  static const String _legacyMealsBoxName = 'evenplate_meals_box';

  static const String _activeProfileKey = 'profile';

  static String _profileKeyFor(String userId) => 'profile|$userId';

  static String _mealKey(String userId, String mealId) => '$userId|$mealId';

  final HiveKeyStore _keyStore;
  final MealPhotoStore _photoStore;

  late Box<String> _userBox;
  late Box<String> _mealsBox;

  UserProfile _userProfile = UserProfile(lastQuotaReset: DateTime.now());
  List<MealLog> _meals = [];

  UserProfile get userProfile => _userProfile;
  List<MealLog> get meals => List.unmodifiable(_meals);

  /// Finished questionnaire, or a diary that already has plates.
  /// Signing out must not send that account through the questions again.
  bool get questionnaireDone {
    if (_userProfile.hasCompletedOnboarding) return true;
    if (!_isInitialized) return false;
    if (_questionnaireMarked(_userProfile)) return true;
    return _meals.isNotEmpty;
  }

  /// Quota and profile. Meal lists should listen to [mealChanges].
  final ChangeNotifier profileChanges = _StorageHub();

  /// Diary rows only.
  final ChangeNotifier mealChanges = _StorageHub();
  int get balancedMealCount =>
      _meals.where((m) => m.satietyResult.pillars.isFullMatrix).length;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  static const String _deletedIdsKey = 'deleted_ids';
  static const String _deletedPrintsKey = 'deleted_prints';
  static const String _storeEntitledKey = 'store_entitled';
  static const String _promoUntilKey = 'promo_until';

  /// Cloud diary hooks. Merge-from-server must not fire these.
  void Function(MealLog meal)? onMealWritten;
  void Function(MealLog meal)? onMealRemoved;

  final Set<String> _deletedIds = {};
  final Set<String> _deletedPrints = {};

  LocalStorageService({HiveKeyStore? keyStore, MealPhotoStore? photoStore})
    : _keyStore = keyStore ?? SecureHiveKeyStore(),
      _photoStore = photoStore ?? MealPhotoStore();

  /// [hivePath] is a test seam. Production calls Hive.initFlutter so the
  /// boxes land in the app documents directory.
  Future<void> init({String? hivePath}) async {
    if (_isInitialized) return;

    if (hivePath != null) {
      Hive.init(hivePath);
    } else {
      await Hive.initFlutter();
    }

    final keyBytes = await _keyStore.loadOrCreateKey();
    MealPhotoStore.bindCipherKey(keyBytes);
    final cipher = HiveAesCipher(keyBytes);
    _userBox = await _openEncryptedBox(
      _userBoxName,
      _legacyUserBoxName,
      cipher,
    );
    _mealsBox = await _openEncryptedBox(
      _mealsBoxName,
      _legacyMealsBoxName,
      cipher,
    );

    // Load Profile
    var persistReconciled = false;
    final profileRaw = _userBox.get(_activeProfileKey);
    if (profileRaw != null) {
      try {
        final profileJson = asStringKeyedMap(jsonDecode(profileRaw));
        if (profileJson != null) {
          final loaded = UserProfile.fromJson(profileJson);
          _userProfile = loaded;
          _loadStoreFlag();
          _userProfile = _reconcile(loaded);
          persistReconciled =
              _userProfile.isPro != loaded.isPro ||
              _userProfile.freeScansRemaining != loaded.freeScansRemaining ||
              _userProfile.textRemaining != loaded.textRemaining;
        }
      } catch (e) {
        debugPrint('Error decoding user profile: $e');
      }
    }

    _loadTombstones();
    await _scopeLegacyMeals();
    _isInitialized = true;
    if (persistReconciled) {
      final encoded = jsonEncode(_userProfile.toJson());
      await _userBox.put(_activeProfileKey, encoded);
      await _userBox.put(_profileKeyFor(_userProfile.id), encoded);
    }
    await _replayMealOutbox();
    await _reloadVisibleMeals();
    // History is retained until the customer deletes it.
    await _adoptReadablePhotos();
    await _ensureQuestionnaireSticky();
    _checkWeeklyQuotaReset();
    _emitAll();
  }

  void _emitProfile() {
    (profileChanges as _StorageHub).bump();
  }

  void _emitMeals() {
    (mealChanges as _StorageHub).bump();
  }

  void _emitAll() {
    _emitProfile();
    _emitMeals();
    notifyListeners();
  }

  bool _ownedBy(MealLog meal, String userId) {
    if (meal.userId.isEmpty) return userId == 'default_user';
    return meal.userId == userId;
  }

  bool? _storeEntitled;
  DateTime? _promoProUntil;
  bool get _hasLivePromo => _promoProUntil?.isAfter(DateTime.now()) ?? false;

  /// True after RevenueCat has said yes or no this install.
  bool get storeHasSpoken => _storeEntitled != null;

  /// True when the store said the entitlement is gone.
  bool get storeEntitlementDenied => _storeEntitled == false && !_hasLivePromo;

  bool get hasPro {
    if (_hasLivePromo) return true;
    if (_storeEntitled == false) return false;
    return ScanAllowance.hasProAccess(
      isPro: _userProfile.isPro,
      weeklyPhotoRemaining: _userProfile.freeScansRemaining,
      weeklyTextRemaining: _userProfile.textRemaining,
    );
  }

  /// RevenueCat (or a live promo) is the membership source.
  Future<void> applyStoreEntitlement(bool entitled) async {
    _storeEntitled = entitled;
    await _persistStoreFlag();
    if (entitled || _hasLivePromo) {
      await saveUserProfile(_userProfile.copyWith(isPro: true));
    } else {
      await setProStatus(false);
    }
  }

  UserProfile _reconcile(UserProfile profile) {
    if (storeEntitlementDenied) {
      return profile.copyWith(
        isPro: false,
        freeScansRemaining: ScanAllowance.clampIncluded(
          profile.freeScansRemaining,
          ScanAllowance.freePhotoWeekly,
        ),
        textRemaining: ScanAllowance.clampIncluded(
          profile.textRemaining,
          ScanAllowance.freeTextWeekly,
        ),
      );
    }
    if (_hasLivePromo) return profile.copyWith(isPro: true);
    if (profile.isPro) return profile;
    if (ScanAllowance.weeklyMetersImplyPro(
      weeklyPhotoRemaining: profile.freeScansRemaining,
      weeklyTextRemaining: profile.textRemaining,
    )) {
      return profile.copyWith(isPro: true);
    }
    return profile;
  }

  void _loadTombstones() {
    _deletedIds
      ..clear()
      ..addAll(_stringSet(_userBox.get(_deletedKey(_deletedIdsKey))));
    _deletedPrints
      ..clear()
      ..addAll(_stringSet(_userBox.get(_deletedKey(_deletedPrintsKey))));
  }

  String _deletedKey(String kind) => '$kind|${_userProfile.id}';

  String _storeKey() => '$_storeEntitledKey|${_userProfile.id}';

  void _loadStoreFlag() {
    _promoProUntil = DateTime.tryParse(
      _userBox.get('$_promoUntilKey|${_userProfile.id}') ?? '',
    );
    final raw = _userBox.get(_storeKey());
    if (raw == '1') {
      _storeEntitled = true;
    } else if (raw == '0') {
      _storeEntitled = false;
    } else {
      _storeEntitled = null;
    }
  }

  Future<void> applyPromoGrant(DateTime? until) async {
    _promoProUntil = until;
    if (_isInitialized) {
      final key = '$_promoUntilKey|${_userProfile.id}';
      if (until == null) {
        await _userBox.delete(key);
      } else {
        await _userBox.put(key, until.toUtc().toIso8601String());
      }
    }
    await saveUserProfile(_reconcile(_userProfile));
  }

  Future<void> _persistStoreFlag() async {
    if (!_isInitialized) return;
    if (_storeEntitled == null) {
      await _userBox.delete(_storeKey());
      return;
    }
    await _userBox.put(_storeKey(), _storeEntitled! ? '1' : '0');
  }

  Set<String> _stringSet(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return {};
      return decoded
          .map((e) => e.toString())
          .where((e) => e.isNotEmpty)
          .toSet();
    } catch (_) {
      return {};
    }
  }

  Future<void> _persistTombstones() async {
    if (!_isInitialized) return;
    await _userBox.put(
      _deletedKey(_deletedIdsKey),
      jsonEncode(_deletedIds.toList()),
    );
    await _userBox.put(
      _deletedKey(_deletedPrintsKey),
      jsonEncode(_deletedPrints.toList()),
    );
  }

  bool _isTombstoned(MealLog meal) {
    return _deletedIds.contains(meal.id) ||
        _deletedPrints.contains(MealDiarySync.fingerprint(meal));
  }

  Future<void> _rememberDeleted(MealLog meal) async {
    _deletedIds.add(meal.id);
    _deletedPrints.add(MealDiarySync.fingerprint(meal));
    await _persistTombstones();
  }

  Future<void> _scopeLegacyMeals() async {
    final owner = _userProfile.id;
    for (final key in _mealsBox.keys.toList()) {
      final keyStr = key.toString();
      final meal = MealLog.tryParse(_mealsBox.get(key));
      if (meal == null) continue;
      final ownerId = meal.userId.isNotEmpty ? meal.userId : owner;
      final stamped = meal.userId == ownerId
          ? meal
          : meal.copyWith(userId: ownerId);
      final nextKey = _mealKey(ownerId, stamped.id);
      if (keyStr == nextKey && meal.userId == ownerId) continue;
      await _mealsBox.put(nextKey, jsonEncode(stamped.toJson()));
      if (keyStr != nextKey) await _mealsBox.delete(key);
    }
  }

  Future<int> _reloadVisibleMeals() async {
    _meals = [];
    var skippedMeals = 0;
    for (final raw in _mealsBox.values) {
      final meal = MealLog.tryParse(raw);
      if (meal == null) {
        skippedMeals++;
        continue;
      }
      if (!_ownedBy(meal, _userProfile.id)) continue;
      if (_isTombstoned(meal)) continue;
      _meals.add(meal);
    }
    _meals.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    if (skippedMeals > 0) {
      debugPrint('Skipped $skippedMeals unreadable meal log(s)');
    }
    return skippedMeals;
  }

  Future<void> _rekeyMeals({required String from, required String to}) async {
    for (final key in _mealsBox.keys.toList()) {
      final meal = MealLog.tryParse(_mealsBox.get(key));
      if (meal == null) continue;
      final owner = meal.userId.isEmpty ? from : meal.userId;
      if (owner != from) continue;
      final stamped = meal.copyWith(userId: to);
      await _mealsBox.put(
        _mealKey(to, stamped.id),
        jsonEncode(stamped.toJson()),
      );
      if (key.toString() != _mealKey(to, stamped.id)) {
        await _mealsBox.delete(key);
      }
    }
  }

  /// Drops plates older than the Insights month window, including photos.
  Future<int> pruneStaleMeals({DateTime? now}) async {
    var removed = 0;
    for (final key in _mealsBox.keys.toList()) {
      final meal = MealLog.tryParse(_mealsBox.get(key));
      if (meal == null) continue;
      if (MealDiarySync.withinKeepWindow(meal.timestamp, now: now)) continue;
      await _mealsBox.delete(key);
      await MealPhotoStore().deleteIfOwned(meal.imagePath);
      _meals.removeWhere((m) => m.id == meal.id && m.userId == meal.userId);
      removed++;
    }
    if (removed > 0) _emitMeals();
    return removed;
  }

  /// Copies leftover camera/gallery temp files into app documents, and
  /// rewrites stale iOS container paths so a thumbnail still opens.
  Future<void> _adoptReadablePhotos() async {
    try {
      final _ = WidgetsBinding.instance;
    } catch (_) {
      return;
    }
    try {
      final store = MealPhotoStore();
      for (var i = 0; i < _meals.length; i++) {
        final meal = _meals[i];
        final next = await store.resolve(
          mealId: meal.id,
          ownerId: meal.userId.isNotEmpty ? meal.userId : _userProfile.id,
          storedPath: meal.imagePath,
        );
        if (next == null || next == meal.imagePath) continue;
        final updated = meal.copyWith(imagePath: next);
        _meals[i] = updated;
        await _mealsBox.put(
          _mealKey(updated.userId, updated.id),
          jsonEncode(updated.toJson()),
        );
      }
    } catch (e) {
      debugPrint('Meal photo adopt failed: $e');
    }
  }

  /// Opens the encrypted box, then copies any leftover plaintext box from
  /// before AES was added. Hive does not throw on a cipher mismatch: it
  /// reports the file as corrupt and empties it, so the old names must
  /// never be opened with the cipher.
  Future<Box<String>> _openEncryptedBox(
    String name,
    String legacyName,
    HiveAesCipher cipher,
  ) async {
    if (Hive.isBoxOpen(name)) {
      await Hive.box(name).close();
    }

    final box = await Hive.openBox<String>(name, encryptionCipher: cipher);
    await _migrateLegacyBox(legacyName, box);
    return box;
  }

  Future<void> _migrateLegacyBox(String legacyName, Box<String> target) async {
    if (!await Hive.boxExists(legacyName)) return;

    try {
      if (Hive.isBoxOpen(legacyName)) {
        await Hive.box(legacyName).close();
      }
      final legacy = await Hive.openBox<String>(legacyName);
      for (final key in legacy.keys) {
        final value = legacy.get(key);
        if (value != null && !target.containsKey(key)) {
          await target.put(key, value);
        }
      }
      await legacy.close();
      await Hive.deleteBoxFromDisk(legacyName);
    } catch (e) {
      debugPrint('Legacy Hive migrate of $legacyName failed: $e');
    }
  }

  void _checkWeeklyQuotaReset() {
    final now = DateTime.now().toUtc();
    final previous = _userProfile.lastQuotaReset.toUtc();
    DateTime monday(DateTime date) => DateTime.utc(
      date.year,
      date.month,
      date.day,
    ).subtract(Duration(days: date.weekday - 1));
    if (monday(previous).isBefore(monday(now))) {
      _userProfile = _userProfile.copyWith(
        freeScansRemaining: ScanAllowance.includedPhotoWeekly(
          isPro: _userProfile.isPro,
        ),
        textRemaining: ScanAllowance.includedTextWeekly(
          isPro: _userProfile.isPro,
        ),
        lastQuotaReset: now,
      );
      saveUserProfile(_userProfile);
    }
  }

  String _onboardedKey(String userId) => 'onboarded|$userId';

  bool _sameEmail(String? a, String? b) {
    if (a == null || b == null) return false;
    final left = a.trim().toLowerCase();
    final right = b.trim().toLowerCase();
    return left.isNotEmpty && left == right;
  }

  String? _onboardedEmailKey(String? email) {
    if (email == null) return null;
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    return 'onboarded-email|$normalized';
  }

  bool _emailMarked(String? email) {
    if (!_isInitialized) return false;
    final key = _onboardedEmailKey(email);
    if (key == null) return false;
    return _userBox.get(key) == '1';
  }

  bool _questionnaireMarked(UserProfile profile) {
    if (!_isInitialized) return false;
    if (_userBox.get(_onboardedKey(profile.id)) == '1') return true;
    return _emailMarked(profile.email);
  }

  /// A later profile write must not clear a questionnaire this phone
  /// already finished for the same account.
  UserProfile _rememberQuestionnaire(UserProfile profile, {UserProfile? also}) {
    var completed = profile.hasCompletedOnboarding;
    if (also != null &&
        also.hasCompletedOnboarding &&
        (also.id == profile.id || _sameEmail(also.email, profile.email))) {
      completed = true;
    }
    if (!completed && _questionnaireMarked(profile)) completed = true;
    if (!completed && profile.id == _userProfile.id && _meals.isNotEmpty) {
      completed = true;
    }
    if (!completed) return profile;
    return profile.hasCompletedOnboarding
        ? profile
        : profile.copyWith(hasCompletedOnboarding: true);
  }

  Future<void> _writeQuestionnaireMarkers(UserProfile profile) async {
    if (!_isInitialized || !profile.hasCompletedOnboarding) return;
    await _userBox.put(_onboardedKey(profile.id), '1');
    final emailKey = _onboardedEmailKey(profile.email);
    if (emailKey != null) {
      await _userBox.put(emailKey, '1');
    }
  }

  /// Plates on this phone mean the account already finished setup.
  Future<void> _ensureQuestionnaireSticky() async {
    var next = _rememberQuestionnaire(_userProfile);
    if (_meals.isNotEmpty && !next.hasCompletedOnboarding) {
      next = next.copyWith(hasCompletedOnboarding: true);
    }
    final missingMarker =
        next.hasCompletedOnboarding && !_questionnaireMarked(next);
    if (next.hasCompletedOnboarding == _userProfile.hasCompletedOnboarding &&
        !missingMarker) {
      return;
    }
    await saveUserProfile(next);
  }

  static const preferenceKeys = {
    'primaryGoal',
    'eatingStyle',
    'crashPattern',
    'dietaryPreference',
    'mealSchedule',
    'coachingStyle',
    'targetMealsPerDay',
    'targetSatietyHoursDaily',
    'hasCompletedOnboarding',
    'wakeTime',
    'sleepTime',
  };
  VoidCallback? onPreferencesWritten;
  Map<String, dynamic> preferencesFor(UserProfile profile) => {
    for (final entry in profile.toJson().entries)
      if (preferenceKeys.contains(entry.key)) entry.key: entry.value,
  };
  Map<String, dynamic>? pendingPreferences(String owner) {
    if (!_isInitialized) return null;
    final raw = _userBox.get('preferences_pending|$owner');
    return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> acknowledgePreferences(String owner, String revision) async {
    if (pendingPreferences(owner)?['revision'] == revision) {
      await _userBox.delete('preferences_pending|$owner');
    }
  }

  Future<void> adoptRemotePreferences(
    String owner,
    Map<String, dynamic> preferences,
  ) async {
    if (_userProfile.id != owner || pendingPreferences(owner) != null) return;
    final merged = {
      ..._userProfile.toJson(),
      for (final entry in preferences.entries)
        if (preferenceKeys.contains(entry.key)) entry.key: entry.value,
    };
    final next = UserProfile.fromJson(merged);
    _userProfile = _reconcile(next);
    if (_isInitialized) {
      final encoded = jsonEncode(_userProfile.toJson());
      await _userBox.put(_activeProfileKey, encoded);
      await _userBox.put(_profileKeyFor(owner), encoded);
    }
    _emitProfile();
  }

  Future<void> saveUserProfile(UserProfile profile) async {
    final beforePreferences = jsonEncode(preferencesFor(_userProfile));
    final next = _rememberQuestionnaire(profile, also: _userProfile);
    _userProfile = _reconcile(next);
    if (_isInitialized) {
      final encoded = jsonEncode(_userProfile.toJson());
      await _userBox.put(_activeProfileKey, encoded);
      await _userBox.put(_profileKeyFor(_userProfile.id), encoded);
      await _writeQuestionnaireMarkers(_userProfile);
    }
    if (beforePreferences != jsonEncode(preferencesFor(_userProfile)) &&
        _isInitialized) {
      await _userBox.put(
        'preferences_pending|${_userProfile.id}',
        jsonEncode({
          'preferences': preferencesFor(_userProfile),
          'revision': DateTime.now().microsecondsSinceEpoch.toString(),
        }),
      );
      onPreferencesWritten?.call();
    }
    _emitProfile();
  }

  MealLog _stamp(MealLog log) {
    if (log.userId.isNotEmpty) return log;
    return log.copyWith(userId: _userProfile.id);
  }

  Future<void> addMealLog(MealLog log) async {
    final stamped = _stamp(log);
    _deletedIds.remove(stamped.id);
    _deletedPrints.remove(MealDiarySync.fingerprint(stamped));
    await _persistTombstones();
    await queueMealSync(stamped, 'upsert');
    _meals.removeWhere((m) => m.id == stamped.id && m.userId == stamped.userId);
    _meals.insert(0, stamped);
    if (_isInitialized) {
      await _mealsBox.put(
        _mealKey(stamped.userId, stamped.id),
        jsonEncode(stamped.toJson()),
      );
    }
    _emitMeals();
    onMealWritten?.call(stamped);
  }

  Future<void> deleteMeal(String mealId) async {
    final index = _meals.indexWhere((m) => m.id == mealId);
    if (index == -1) return;
    final removed = _meals[index];
    await queueMealSync(removed, 'delete');
    _meals.removeAt(index);
    if (_isInitialized) {
      await _mealsBox.delete(_mealKey(removed.userId, mealId));
    }
    await MealPhotoStore().deleteIfOwned(removed.imagePath);

    // Removing a bridge snack restores the parent check-in card.
    if (removed.isBridgeFix &&
        removed.bridgedFromId != null &&
        !_meals.any(
          (m) => m.isBridgeFix && m.bridgedFromId == removed.bridgedFromId,
        )) {
      final parentIndex = _meals.indexWhere(
        (m) => m.id == removed.bridgedFromId,
      );
      if (parentIndex != -1) {
        final cleared = _meals[parentIndex].copyWith(energyCheckIn: null);
        await queueMealSync(cleared, 'upsert');
        _meals[parentIndex] = cleared;
        if (_isInitialized) {
          await _mealsBox.put(
            _mealKey(cleared.userId, removed.bridgedFromId!),
            jsonEncode(cleared.toJson()),
          );
        }
      }
    }
    await _rememberDeleted(removed);
    _emitMeals();
    onMealRemoved?.call(removed);
  }

  Future<void> updateMealLog(MealLog log) async {
    final index = _meals.indexWhere((m) => m.id == log.id);
    if (index == -1) return;
    final stamped = _stamp(log);
    await queueMealSync(stamped, 'upsert');
    _meals[index] = stamped;
    if (_isInitialized) {
      await _mealsBox.put(
        _mealKey(stamped.userId, stamped.id),
        jsonEncode(stamped.toJson()),
      );
    }
    _emitMeals();
    onMealWritten?.call(stamped);
  }

  Future<void> resetMealCheckIn(String mealId) async {
    final snackIds = _meals
        .where((m) => m.isBridgeFix && m.bridgedFromId == mealId)
        .map((m) => m.id)
        .toList();
    for (final id in snackIds) {
      MealLog? snack;
      for (final meal in _meals) {
        if (meal.id == id) {
          snack = meal;
          break;
        }
      }
      _meals.removeWhere((m) => m.id == id);
      if (_isInitialized) {
        await _mealsBox.delete(_mealKey(snack?.userId ?? _userProfile.id, id));
      }
      if (snack != null) {
        await _rememberDeleted(snack);
        await queueMealSync(snack, 'delete');
        onMealRemoved?.call(snack);
      }
    }
    await updateMealEnergyCheckIn(mealId, null);
  }

  Future<void> updateMealEnergyCheckIn(
    String mealId,
    String? energyState,
  ) async {
    final index = _meals.indexWhere((m) => m.id == mealId);
    if (index != -1) {
      final updated = _meals[index].copyWith(energyCheckIn: energyState);
      await queueMealSync(updated, 'upsert');
      _meals[index] = updated;
      if (_isInitialized) {
        await _mealsBox.put(
          _mealKey(updated.userId, mealId),
          jsonEncode(updated.toJson()),
        );
      }
      _emitMeals();
      onMealWritten?.call(updated);
    }
  }

  int get photoLeft =>
      _userProfile.freeScansRemaining + _userProfile.photoPurchased;

  int get textLeft => _userProfile.textRemaining + _userProfile.textPurchased;

  bool hasFreeScans() {
    return photoLeft > 0;
  }

  Future<void> consumeScanCredit() async {
    if (_userProfile.freeScansRemaining > 0) {
      await saveUserProfile(
        _userProfile.copyWith(
          freeScansRemaining: _userProfile.freeScansRemaining - 1,
        ),
      );
      return;
    }
    if (_userProfile.photoPurchased > 0) {
      await saveUserProfile(
        _userProfile.copyWith(photoPurchased: _userProfile.photoPurchased - 1),
      );
    }
  }

  Future<void> setFreeScansRemaining(int count) async {
    final updated = _userProfile.copyWith(freeScansRemaining: count);
    await saveUserProfile(updated);
  }

  Future<void> setProStatus(bool isPro) async {
    if (!isPro) {
      final photo = _userProfile.freeScansRemaining;
      final text = _userProfile.textRemaining;
      await saveUserProfile(
        _userProfile.copyWith(
          isPro: false,
          freeScansRemaining: ScanAllowance.clampIncluded(
            photo,
            ScanAllowance.freePhotoWeekly,
          ),
          textRemaining: ScanAllowance.clampIncluded(
            text,
            ScanAllowance.freeTextWeekly,
          ),
        ),
      );
      return;
    }
    final photoCap = ScanAllowance.includedPhotoWeekly(isPro: true);
    final textCap = ScanAllowance.includedTextWeekly(isPro: true);
    final photo = _userProfile.freeScansRemaining;
    final text = _userProfile.textRemaining;
    final liftPhoto =
        !_userProfile.isPro ||
        (photo > 0 && photo <= ScanAllowance.freePhotoWeekly);
    final liftText =
        !_userProfile.isPro ||
        (text > 0 && text <= ScanAllowance.freeTextWeekly);
    await saveUserProfile(
      _userProfile.copyWith(
        isPro: true,
        freeScansRemaining: liftPhoto ? photoCap : photo,
        textRemaining: liftText ? textCap : text,
      ),
    );
  }

  /// Adopts the meters the profile ledger reported. Omitted fields stay.
  Future<void> applyServerQuota({
    required bool isPro,
    required int freeScansRemaining,
    int? photoPurchased,
    int? textRemaining,
    int? textPurchased,
  }) async {
    final remaining = freeScansRemaining < 0 ? 0 : freeScansRemaining;
    final updated = _userProfile.copyWith(
      isPro: isPro,
      freeScansRemaining: remaining,
      photoPurchased: photoPurchased == null
          ? _userProfile.photoPurchased
          : (photoPurchased < 0 ? 0 : photoPurchased),
      textRemaining: textRemaining == null
          ? _userProfile.textRemaining
          : (textRemaining < 0 ? 0 : textRemaining),
      textPurchased: textPurchased == null
          ? _userProfile.textPurchased
          : (textPurchased < 0 ? 0 : textPurchased),
    );
    await saveUserProfile(updated);
  }

  // Server remaining is adopted via applyServerQuota. Zero means stop.
  bool canScanPlate() {
    return hasFreeScans();
  }

  bool canScoreFoods() {
    return textLeft > 0;
  }

  Future<void> applyFoodsQuota(ScanQuota? quota) async {
    if (quota == null) return;
    await applyServerQuota(
      isPro: quota.isPro,
      freeScansRemaining: _userProfile.freeScansRemaining,
      textRemaining: quota.textRemaining,
      textPurchased: quota.textPurchased,
    );
  }

  String? _keptPhotoPath(String? current, String? incoming) {
    if (current != null && current.isNotEmpty) return current;
    if (incoming != null && incoming.isNotEmpty) return incoming;
    return null;
  }

  Future<MealLog> _withResolvedPhoto(MealLog meal) async {
    try {
      WidgetsBinding.instance;
    } catch (_) {
      return meal;
    }
    final stored = meal.imagePath;
    String? resolved;
    try {
      resolved = await MealPhotoStore().resolve(
        mealId: meal.id,
        ownerId: meal.userId.isNotEmpty ? meal.userId : _userProfile.id,
        storedPath: stored,
      );
    } catch (e) {
      debugPrint('Meal photo resolve failed: $e');
    }
    final path = resolved ?? stored;
    if (path == stored) return meal;
    if (path == null || path.isEmpty) return meal;
    return meal.copyWith(imagePath: path);
  }

  Future<void> _putMeal(MealLog meal) async {
    if (!_isInitialized) return;
    await _mealsBox.put(
      _mealKey(meal.userId, meal.id),
      jsonEncode(meal.toJson()),
    );
  }

  /// Adds remote plates that are not already on this phone.
  /// A cloud row has no photo file. The phone copy keeps its image.
  Future<int> mergeRemoteMeals(Iterable<MealLog> remote) async {
    var added = 0;
    var changed = false;
    for (final incoming in remote) {
      final meal = _stamp(incoming);
      if (_isTombstoned(meal)) continue;
      final index = _meals.indexWhere(
        (local) =>
            local.id == meal.id || MealDiarySync.isSamePlate(local, meal),
      );
      if (index != -1) {
        final path = _keptPhotoPath(_meals[index].imagePath, meal.imagePath);
        final pending = pendingMealSync(
          _userProfile.id,
        ).any((entry) => (entry['meal'] as Map)['id'] == meal.id);
        var kept = (pending ? _meals[index] : meal).copyWith(imagePath: path);
        kept = await _withResolvedPhoto(kept);
        if (!pending || kept.imagePath != _meals[index].imagePath) {
          _meals[index] = kept;
          await _putMeal(kept);
          changed = true;
        }
        continue;
      }
      final stored = await _withResolvedPhoto(meal);
      _meals.add(stored);
      await _putMeal(stored);
      added++;
    }
    if (added > 0) {
      _meals.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    }
    if (added > 0 || changed) _emitMeals();
    if (added > 0) await _ensureQuestionnaireSticky();
    return added;
  }

  /// Switches the visible diary. Other accounts stay on disk.
  Future<void> adoptAccount({required String userId, String? email}) async {
    final previousProfile = _userProfile;
    final previous = previousProfile.id;
    final samePerson =
        previous == userId ||
        previous == 'default_user' ||
        _sameEmail(previousProfile.email, email);

    if (previous == userId) {
      final kept = _rememberQuestionnaire(
        previousProfile.copyWith(email: email ?? previousProfile.email),
      );
      _userProfile = kept.hasCompletedOnboarding || _meals.isEmpty
          ? kept
          : kept.copyWith(hasCompletedOnboarding: true);
      _emitProfile();
      await saveUserProfile(_userProfile);
      await _adoptReadablePhotos();
      return;
    }

    if (_isInitialized) {
      final encoded = jsonEncode(previousProfile.toJson());
      await _userBox.put(_profileKeyFor(previous), encoded);
    }

    if (samePerson) {
      await _rekeyMeals(from: previous, to: userId);
    }

    UserProfile next;
    final stored = _isInitialized ? _userBox.get(_profileKeyFor(userId)) : null;
    if (stored != null) {
      final json = asStringKeyedMap(jsonDecode(stored));
      next = json != null
          ? UserProfile.fromJson(json)
          : UserProfile(id: userId, lastQuotaReset: DateTime.now());
      if (previous == 'default_user' ||
          _sameEmail(previousProfile.email, email)) {
        next = next.mergedWithLiveSession(previousProfile);
      }
      if (email != null && email.isNotEmpty) {
        next = next.copyWith(email: email);
      }
    } else if (previous == 'default_user' ||
        _sameEmail(previousProfile.email, email)) {
      next = previousProfile.copyWith(
        id: userId,
        email: email ?? previousProfile.email,
      );
    } else {
      next = UserProfile(
        id: userId,
        email: email,
        lastQuotaReset: DateTime.now(),
      );
    }
    next = _rememberQuestionnaire(
      next,
      also: samePerson ? previousProfile : null,
    );

    _userProfile = next;
    _loadStoreFlag();
    _userProfile = _reconcile(next);
    _loadTombstones();
    await _replayMealOutbox();
    await _reloadVisibleMeals();
    // History is retained until the customer deletes it.
    await _adoptReadablePhotos();
    if (_meals.isNotEmpty && !_userProfile.hasCompletedOnboarding) {
      _userProfile = _userProfile.copyWith(hasCompletedOnboarding: true);
    }
    if (_isInitialized) {
      final encoded = jsonEncode(_userProfile.toJson());
      await _userBox.put(_activeProfileKey, encoded);
      await _userBox.put(_profileKeyFor(_userProfile.id), encoded);
      await _writeQuestionnaireMarkers(_userProfile);
    }
    _emitAll();
  }

  Future<void> clearMeals() async {
    await _replayMealOutbox();
    await _reloadVisibleMeals();
    for (final meal in List<MealLog>.from(_meals)) {
      if (_isInitialized) {
        await _mealsBox.delete(_mealKey(meal.userId, meal.id));
      }
      await MealPhotoStore().deleteIfOwned(meal.imagePath);
    }
    _meals = [];
    _emitMeals();
  }

  final Set<String> _analysisConsents = {};
  bool get analysisConsentGranted =>
      _analysisConsents.contains(_userProfile.id) ||
      (_isInitialized &&
          _userBox.get('analysis_consent|${_userProfile.id}') == '1');

  Future<void> setAnalysisConsent(bool granted) async {
    if (granted) {
      _analysisConsents.add(_userProfile.id);
    } else {
      _analysisConsents.remove(_userProfile.id);
    }
    if (_isInitialized) {
      await _userBox.put(
        'analysis_consent|${_userProfile.id}',
        granted ? '1' : '0',
      );
    }
    _emitProfile();
  }

  Future<void> _replayMealOutbox() async {
    if (!_isInitialized) return;
    for (final entry in pendingMealSync(_userProfile.id)) {
      final meal = MealLog.fromJson(
        Map<String, dynamic>.from(entry['meal'] as Map),
      );
      if (entry['operation'] == 'delete') {
        await _mealsBox.delete(_mealKey(meal.userId, meal.id));
        await _rememberDeleted(meal);
      } else {
        await _putMeal(meal);
      }
    }
  }

  Future<void> queueMealSync(MealLog meal, String operation) async {
    if (!_isInitialized) return;
    await _userBox.put(
      'outbox|${meal.userId}|${meal.id}',
      jsonEncode({
        'operation': operation,
        'meal': meal.toJson(),
        'revision': DateTime.now().microsecondsSinceEpoch.toString(),
      }),
    );
  }

  List<Map<String, dynamic>> pendingMealSync(String owner) {
    if (!_isInitialized) return [];
    return [
      for (final key in _userBox.keys)
        if (key.toString().startsWith('outbox|$owner|'))
          {
            ...jsonDecode(_userBox.get(key)!) as Map<String, dynamic>,
            'key': key.toString(),
          },
    ];
  }

  Future<void> acknowledgeMealSync(String key, String revision) async {
    final raw = _userBox.get(key);
    if (raw != null && (jsonDecode(raw) as Map)['revision'] == revision) {
      await _userBox.delete(key);
    }
  }

  Future<void> clearAll() => clearAccountData(_userProfile.id);

  Future<void> clearAccountData(String id) async {
    String? email = _userProfile.id == id ? _userProfile.email : null;
    if (_isInitialized && email == null) {
      final saved = _userBox.get(_profileKeyFor(id));
      if (saved != null) {
        try {
          email = (jsonDecode(saved) as Map)['email'] as String?;
        } catch (_) {}
      }
    }
    _analysisConsents.remove(id);
    if (_isInitialized) {
      for (final key in _mealsBox.keys.toList()) {
        final meal = MealLog.tryParse(_mealsBox.get(key));
        if (meal == null) continue;
        if (meal.userId.isEmpty ? _userProfile.id != id : meal.userId != id) {
          continue;
        }
        await MealPhotoStore().deleteIfOwned(meal.imagePath);
        await _mealsBox.delete(key);
      }
      await _photoStore.deleteOwnerFiles(id);
      await _userBox.delete('$_deletedIdsKey|$id');
      await _userBox.delete('$_deletedPrintsKey|$id');
      await _userBox.delete('reviewer_free|$id');
      await _userBox.delete('$_storeEntitledKey|$id');
      await _userBox.delete('$_promoUntilKey|$id');
      await _userBox.delete(_profileKeyFor(id));
      await _userBox.delete('preferences_pending|$id');
      await _userBox.delete(_onboardedKey(id));
      final emailKey = _onboardedEmailKey(email);
      if (emailKey != null) await _userBox.delete(emailKey);
      for (final key in _userBox.keys.toList()) {
        if (key.toString().startsWith('outbox|$id|')) {
          await _userBox.delete(key);
        }
      }
      await _userBox.delete('analysis_consent|$id');
      if (_userProfile.id == id) await _userBox.delete(_activeProfileKey);
    }
    if (_userProfile.id != id) return;
    _deletedIds.clear();
    _deletedPrints.clear();
    _userProfile = UserProfile(lastQuotaReset: DateTime.now());
    _meals = [];
    _storeEntitled = null;
    _promoProUntil = null;
    _emitAll();
  }
}

class _StorageHub extends ChangeNotifier {
  void bump() => notifyListeners();
}
