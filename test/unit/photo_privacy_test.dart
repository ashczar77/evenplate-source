import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:evenplate/services/photo_privacy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Uploaded photo removes GPS and EXIF metadata while retaining pixels',
    () async {
      final source = await File(
        'test/fixtures/photo_with_metadata.jpg',
      ).readAsBytes();
      expect(latin1.decode(source), contains('EXIF_PRIVACY_CANARY'));
      final clean = await stripPhotoMetadata(source);
      expect(clean.take(4), [137, 80, 78, 71]);
      expect(latin1.decode(clean), isNot(contains('EXIF_PRIVACY_CANARY')));
      expect(latin1.decode(clean), isNot(contains('Exif')));
    },
  );
}
