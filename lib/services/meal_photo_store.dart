import 'package:flutter/foundation.dart';
import 'dart:io';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

/// Keeps scan photos in app documents so list thumbnails survive after
/// the camera or gallery temp file is cleaned up. When a Hive AES key is
/// bound, new files are ciphertext (`.ep`), not raw JPEGs.
class MealPhotoStore {
  MealPhotoStore({Directory? root}) : _rootOverride = root;

  final Directory? _rootOverride;

  static const folderName = 'meal_photos';
  static const encryptedSuffix = '.ep';

  static List<int>? _cipherKey;

  static void bindCipherKey(List<int> key) {
    _cipherKey = List<int>.from(key);
  }

  static void unbindCipherKey() {
    _cipherKey = null;
  }

  static bool get encryptsWrites => _cipherKey != null;

  static bool isEncryptedPath(String? path) {
    return path != null && path.endsWith(encryptedSuffix);
  }

  Future<Directory> _dir({String? ownerId}) async {
    final override = _rootOverride;
    Directory base;
    if (override != null) {
      if (!override.existsSync()) {
        await override.create(recursive: true);
      }
      base = override;
    } else {
      final docs = await getApplicationDocumentsDirectory();
      base = Directory('${docs.path}/$folderName');
      if (!base.existsSync()) {
        await base.create(recursive: true);
      }
    }
    if (ownerId == null || ownerId.isEmpty) return base;
    final dir = Directory('${base.path}/$ownerId');
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String _fileName(String mealId) {
    return encryptsWrites ? '$mealId$encryptedSuffix' : '$mealId.jpg';
  }

  Future<File> ownedFile(String mealId, {String? ownerId}) async {
    return File('${(await _dir(ownerId: ownerId)).path}/${_fileName(mealId)}');
  }

  /// Writes into app documents. Prefers in-memory bytes so an iOS temp
  /// camera path that later vanishes is not the only copy.
  Future<String?> persist({
    required String mealId,
    String? ownerId,
    String? sourcePath,
    Uint8List? bytes,
  }) async {
    final hasBytes = bytes != null && bytes.isNotEmpty;
    final source = sourcePath != null && sourcePath.isNotEmpty
        ? File(sourcePath)
        : null;
    final hasSource = source != null && source.existsSync();
    if (!hasSource && !hasBytes) return null;

    final dest = await ownedFile(mealId, ownerId: ownerId);
    final plain = hasBytes
        ? bytes
        : Uint8List.fromList(await source!.readAsBytes());
    final key = _cipherKey;
    final packed = key == null
        ? plain
        : await compute(_sealWithKey, (plain, key));
    await dest.writeAsBytes(packed, flush: true);
    return dest.path;
  }

  /// Stored paths are absolute. An iOS reinstall can move Documents to a
  /// new container while the jpg is still there under the meal id.
  Future<String?> resolve({
    required String mealId,
    String? ownerId,
    String? storedPath,
  }) async {
    if (isReadable(storedPath)) {
      if (storedPath!.contains('/$folderName/')) return storedPath;
      final adopted = await persist(
        mealId: mealId,
        ownerId: ownerId,
        sourcePath: storedPath,
      );
      return adopted ?? storedPath;
    }
    final owned = await ownedFile(mealId, ownerId: ownerId);
    if (owned.existsSync()) return owned.path;
    final legacyJpg = File(
      '${(await _dir(ownerId: ownerId)).path}/$mealId.jpg',
    );
    if (legacyJpg.existsSync()) return legacyJpg.path;
    final legacy = await ownedFile(mealId);
    if (legacy.existsSync()) return legacy.path;
    if (storedPath != null && storedPath.isNotEmpty) {
      final name = storedPath.split('/').last;
      if (name.isNotEmpty) {
        final byName = File('${(await _dir(ownerId: ownerId)).path}/$name');
        if (byName.existsSync()) return byName.path;
      }
    }
    return null;
  }

  Future<void> deleteOwnerFiles(String ownerId) async {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(ownerId)) {
      throw ArgumentError.value(ownerId, 'ownerId');
    }
    final dir = await _dir(ownerId: ownerId);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  Future<void> deleteIfOwned(String? path) async {
    if (path == null || path.isEmpty) return;
    var owned = false;
    try {
      owned = path.startsWith((await _dir()).path);
    } catch (_) {
      owned = path.contains('/$folderName/');
    }
    if (!owned) return;
    final file = File(path);
    if (file.existsSync()) {
      await file.delete();
    }
  }

  static bool isReadable(String? path) {
    return path != null && path.isNotEmpty && File(path).existsSync();
  }

  static bool looksLikeImage(List<int> bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return true;
    }
    if (bytes.length < 12) return false;
    if (bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return true;
    }
    if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) {
      return true;
    }
    if (bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return true;
    }
    return bytes[4] == 0x66 &&
        bytes[5] == 0x74 &&
        bytes[6] == 0x79 &&
        bytes[7] == 0x70;
  }

  static Future<Uint8List?> readDisplayBytes(String? path) async {
    if (!isReadable(path)) return null;
    final raw = Uint8List.fromList(await File(path!).readAsBytes());
    if (looksLikeImage(raw)) return raw;
    if (_cipherKey == null) return null;
    try {
      final plain = await compute(_openWithKey, (raw, _cipherKey!));
      if (looksLikeImage(plain)) return plain;
    } catch (_) {}
    return null;
  }

  static Uint8List _sealWithKey((Uint8List, List<int>) input) {
    final plain = input.$1;
    final cipher = HiveAesCipher(input.$2);
    final out = Uint8List(cipher.maxEncryptedSize(plain));
    final n = cipher.encrypt(plain, 0, plain.length, out, 0);
    return Uint8List.sublistView(out, 0, n);
  }

  static Uint8List _openWithKey((Uint8List, List<int>) input) {
    final packed = input.$1;
    final cipher = HiveAesCipher(input.$2);
    final out = Uint8List(packed.length);
    final n = cipher.decrypt(packed, 0, packed.length, out, 0);
    return Uint8List.sublistView(out, 0, n);
  }
}
