import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:evenplate/core/security/hive_key_store.dart';

void main() {
  test('retries a timed-out read and returns the existing key', () async {
    var reads = 0;
    var writes = 0;
    final existing = base64Encode(Hive.generateSecureKey());

    final store = SecureHiveKeyStore(
      readTimeout: const Duration(milliseconds: 20),
      readAttempts: 3,
      read: () async {
        reads++;
        if (reads == 1) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return existing;
        }
        return existing;
      },
      write: (_) async {
        writes++;
      },
    );

    final key = await store.loadOrCreateKey();

    expect(reads, 2);
    expect(writes, 0);
    expect(key, base64Decode(existing));
  });

  test('does not mint a new key when every read fails', () async {
    var writes = 0;
    final store = SecureHiveKeyStore(
      readTimeout: const Duration(milliseconds: 10),
      readAttempts: 2,
      read: () async {
        throw TimeoutException('slow keychain');
      },
      write: (_) async {
        writes++;
      },
    );

    await expectLater(
      store.loadOrCreateKey(),
      throwsA(isA<HiveKeyUnavailable>()),
    );
    expect(writes, 0);
  });

  test('mints only after a successful empty read', () async {
    var writes = 0;
    String? persisted;
    final store = SecureHiveKeyStore(
      read: () async => persisted,
      write: (value) async {
        writes++;
        persisted = value;
      },
    );

    final first = await store.loadOrCreateKey();
    final second = await store.loadOrCreateKey();

    expect(writes, 1);
    expect(first, second);
    expect(persisted, isNotNull);
  });

  test('does not keep an unpersisted minted key', () async {
    final store = SecureHiveKeyStore(
      read: () async => null,
      write: (_) async {
        throw TimeoutException('keychain write');
      },
    );

    await expectLater(
      store.loadOrCreateKey(),
      throwsA(isA<HiveKeyUnavailable>()),
    );
  });
}
