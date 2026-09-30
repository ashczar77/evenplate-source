import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Supplies the 32-byte AES key used to encrypt Hive boxes.
abstract class HiveKeyStore {
  Future<List<int>> loadOrCreateKey();
}

/// Keychain was too slow or failed. Do not mint a replacement key, because
/// that would decrypt as empty and look like a fresh install.
class HiveKeyUnavailable implements Exception {
  final Object? cause;

  const HiveKeyUnavailable([this.cause]);

  @override
  String toString() => 'HiveKeyUnavailable: $cause';
}

/// Production store: Keychain on Apple, Keystore-backed cipher on Android.
class SecureHiveKeyStore implements HiveKeyStore {
  static const _keyName = 'evenplate_hive_aes_key';

  static const _appleOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
    synchronizable: false,
  );

  static const _macOptions = MacOsOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
    synchronizable: false,
  );

  final Future<String?> Function() _read;
  final Future<void> Function(String value) _write;
  final Duration? readTimeout;
  final int readAttempts;
  final Random _random;

  SecureHiveKeyStore({
    FlutterSecureStorage? storage,
    Future<String?> Function()? read,
    Future<void> Function(String value)? write,
    this.readTimeout,
    this.readAttempts = 3,
    Random? random,
  }) : _read = read ?? _reader(storage ?? _defaultStorage()),
       _write = write ?? _writer(storage ?? _defaultStorage()),
       _random = random ?? Random();

  static FlutterSecureStorage _defaultStorage() {
    return const FlutterSecureStorage(
      iOptions: _appleOptions,
      mOptions: _macOptions,
    );
  }

  static Future<String?> Function() _reader(FlutterSecureStorage storage) {
    return () => storage.read(key: _keyName);
  }

  static Future<void> Function(String value) _writer(
    FlutterSecureStorage storage,
  ) {
    return (value) => storage.write(key: _keyName, value: value);
  }

  @override
  Future<List<int>> loadOrCreateKey() async {
    Object? lastError;
    for (var attempt = 1; attempt <= readAttempts; attempt++) {
      try {
        final existing = await _read().timeout(_timeoutFor(attempt));
        if (existing != null && existing.isNotEmpty) {
          final decoded = base64Decode(existing);
          if (decoded.length == 32) return decoded;
        }
        return await _createAndPersist();
      } on HiveKeyUnavailable {
        rethrow;
      } catch (e) {
        lastError = e;
        debugPrint('Hive key read failed (attempt $attempt/$readAttempts): $e');
        if (attempt < readAttempts) {
          await Future<void>.delayed(_backoffFor(attempt));
        }
      }
    }
    throw HiveKeyUnavailable(lastError);
  }

  Duration _timeoutFor(int attempt) {
    if (readTimeout != null) return readTimeout!;
    switch (attempt) {
      case 1:
        return const Duration(milliseconds: 1500);
      case 2:
        return const Duration(seconds: 3);
      default:
        return const Duration(seconds: 5);
    }
  }

  /// Full jitter: wait random(0, base) so stacked launches do not retry in lockstep.
  Duration _backoffFor(int failedAttempt) {
    final capMs = 150 * (1 << (failedAttempt - 1));
    return Duration(milliseconds: _random.nextInt(capMs + 1));
  }

  Future<List<int>> _createAndPersist() async {
    final key = Hive.generateSecureKey();
    try {
      await _write(
        base64Encode(key),
      ).timeout(readTimeout ?? const Duration(seconds: 5));
    } catch (e) {
      throw HiveKeyUnavailable(e);
    }
    return key;
  }
}

/// In-memory key for tests. A missing persist path must never be used in
/// a release build as a silent fallback, because the next launch would
/// rotate the key and wipe readable history.
class MemoryHiveKeyStore implements HiveKeyStore {
  List<int>? stored;

  MemoryHiveKeyStore({this.stored});

  @override
  Future<List<int>> loadOrCreateKey() async {
    return stored ??= Hive.generateSecureKey();
  }
}
