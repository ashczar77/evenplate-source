import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:evenplate/services/meal_photo_store.dart';

void main() {
  late Directory root;
  late MealPhotoStore store;

  setUp(() async {
    MealPhotoStore.unbindCipherKey();
    root = await Directory.systemTemp.createTemp('evenplate_photos_');
    store = MealPhotoStore(root: root);
  });

  tearDown(() async {
    MealPhotoStore.unbindCipherKey();
    if (root.existsSync()) {
      await root.delete(recursive: true);
    }
  });

  test('persists a copy from a source file', () async {
    final source = File('${root.path}/source.png');
    await source.writeAsBytes(const [1, 2, 3, 4]);

    final path = await store.persist(mealId: 'meal-1', sourcePath: source.path);

    expect(path, '${root.path}/meal-1.jpg');
    expect(File(path!).readAsBytesSync(), [1, 2, 3, 4]);
    expect(MealPhotoStore.isReadable(path), isTrue);
  });

  test('persists raw bytes when the temp file is already gone', () async {
    final path = await store.persist(
      mealId: 'meal-2',
      bytes: Uint8List.fromList(const [9, 8, 7]),
    );

    expect(File(path!).readAsBytesSync(), [9, 8, 7]);
  });

  test('prefers bytes when a source path is also passed', () async {
    final source = File('${root.path}/source.jpg');
    await source.writeAsBytes(const [1, 2, 3]);

    final path = await store.persist(
      mealId: 'meal-bytes',
      sourcePath: source.path,
      bytes: Uint8List.fromList(const [9, 8, 7]),
    );

    expect(File(path!).readAsBytesSync(), [9, 8, 7]);
  });

  test('resolves a stale container path by meal id', () async {
    final path = await store.persist(
      mealId: 'meal-stale',
      bytes: Uint8List.fromList(const [4, 5, 6]),
    );

    final resolved = await store.resolve(
      mealId: 'meal-stale',
      storedPath: '/old/container/meal_photos/meal-stale.jpg',
    );

    expect(resolved, path);
    expect(File(resolved!).readAsBytesSync(), [4, 5, 6]);
  });

  test('deletes only photos it owns', () async {
    final owned = await store.persist(
      mealId: 'meal-3',
      bytes: Uint8List.fromList(const [1]),
    );
    final outsider = File('${Directory.systemTemp.path}/other.jpg');
    await outsider.writeAsBytes(const [2]);

    await store.deleteIfOwned(owned);
    await store.deleteIfOwned(outsider.path);

    expect(File(owned!).existsSync(), isFalse);
    expect(outsider.existsSync(), isTrue);
    await outsider.delete();
  });

  test('Two accounts keep photos in separate folders', () async {
    final a = await store.persist(
      mealId: 'meal-1',
      ownerId: 'user-a',
      bytes: Uint8List.fromList(const [1]),
    );
    final b = await store.persist(
      mealId: 'meal-1',
      ownerId: 'user-b',
      bytes: Uint8List.fromList(const [2]),
    );

    expect(a, '${root.path}/user-a/meal-1.jpg');
    expect(b, '${root.path}/user-b/meal-1.jpg');
    expect(File(a!).readAsBytesSync(), [1]);
    expect(File(b!).readAsBytesSync(), [2]);
  });

  test('A bound Hive key stores ciphertext, not the JPEG bytes', () async {
    MealPhotoStore.bindCipherKey(List<int>.generate(32, (i) => i + 1));
    store = MealPhotoStore(root: root);
    const canary = [0xFF, 0xD8, 0xFF, 1, 2, 3, 4, 5];

    final path = await store.persist(
      mealId: 'meal-sealed',
      bytes: Uint8List.fromList(canary),
    );

    expect(path!.endsWith('.ep'), isTrue);
    expect(File(path).readAsBytesSync(), isNot(canary));
    expect(await MealPhotoStore.readDisplayBytes(path), canary);
  });

  test('Ciphertext stored as .jpg still decrypts for display', () async {
    MealPhotoStore.bindCipherKey(List<int>.generate(32, (i) => i + 1));
    const canary = [0xFF, 0xD8, 0xFF, 9, 8, 7];
    final sealed = await store.persist(
      mealId: 'meal-misnamed',
      bytes: Uint8List.fromList(canary),
    );
    final disguised = File('${root.path}/looks-like.jpg');
    await disguised.writeAsBytes(File(sealed!).readAsBytesSync());

    expect(MealPhotoStore.looksLikeImage(canary), isTrue);
    expect(MealPhotoStore.looksLikeImage(disguised.readAsBytesSync()), isFalse);
    expect(await MealPhotoStore.readDisplayBytes(disguised.path), canary);
  });

  test('Missing photos never resolve from another account folder', () async {
    await store.persist(
      mealId: 'plate-1',
      ownerId: 'user-a',
      bytes: Uint8List.fromList(const [1, 2, 3, 4]),
    );

    final resolved = await store.resolve(
      mealId: 'plate-1',
      ownerId: 'user-b',
      storedPath: null,
    );

    expect(resolved, isNull);
  });

  test(
    'Account deletion removes orphan photos and preserves other owners',
    () async {
      final deleted = await store.persist(
        mealId: 'orphan',
        ownerId: 'user-a',
        bytes: Uint8List.fromList([1]),
      );
      final retained = await store.persist(
        mealId: 'other',
        ownerId: 'user-b',
        bytes: Uint8List.fromList([2]),
      );
      await store.deleteOwnerFiles('user-a');
      expect(File(deleted!).existsSync(), isFalse);
      expect(File(retained!).existsSync(), isTrue);
    },
  );
}
