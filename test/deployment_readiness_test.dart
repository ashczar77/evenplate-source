import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Deployment & Store Readiness Verification Tests', () {
    test(
      'iOS Info.plist contains all required App Store privacy descriptions',
      () {
        final file = File('ios/Runner/Info.plist');
        expect(
          file.existsSync(),
          isTrue,
          reason: 'ios/Runner/Info.plist must exist',
        );

        final content = file.readAsStringSync();
        expect(
          content.contains('NSCameraUsageDescription'),
          isTrue,
          reason: 'App Store submission requires NSCameraUsageDescription',
        );
        expect(
          content.contains('NSPhotoLibraryUsageDescription'),
          isTrue,
          reason:
              'App Store submission requires NSPhotoLibraryUsageDescription',
        );
        expect(content.contains('CFBundleDisplayName'), isTrue);
        expect(content.contains('CFBundleIdentifier'), isTrue);
      },
    );

    test('Android Manifest declares necessary production permissions', () {
      final file = File('android/app/src/main/AndroidManifest.xml');
      expect(
        file.existsSync(),
        isTrue,
        reason: 'AndroidManifest.xml must exist',
      );

      final content = file.readAsStringSync();
      expect(
        content.contains('android.permission.CAMERA'),
        isTrue,
        reason: 'Camera permission required for plate scanning',
      );
      expect(
        content.contains('android.permission.INTERNET'),
        isTrue,
        reason: 'Internet permission required for vision and monetization',
      );
      expect(
        content.contains('android.permission.POST_NOTIFICATIONS'),
        isTrue,
        reason: 'Notification permission required for OneSignal retention',
      );
    });

    test('iOS privacy manifest is bundled and declares no tracking', () {
      final file = File('ios/Runner/PrivacyInfo.xcprivacy');
      expect(
        file.existsSync(),
        isTrue,
        reason: 'App Store requires PrivacyInfo.xcprivacy',
      );

      final content = file.readAsStringSync();
      expect(content.contains('NSPrivacyTracking'), isTrue);
      expect(content.contains('<false/>'), isTrue);
      expect(
        content.contains('NSPrivacyCollectedDataTypeEmailAddress'),
        isTrue,
      );
      expect(
        content.contains('NSPrivacyCollectedDataTypePhotosorVideos'),
        isTrue,
      );
    });

    test(
      'Android release builds minify with R8 and can pick up a keystore later',
      () {
        final gradle = File('android/app/build.gradle.kts').readAsStringSync();
        expect(gradle.contains('isMinifyEnabled = true'), isTrue);
        expect(gradle.contains('proguard-rules.pro'), isTrue);
        expect(File('android/app/proguard-rules.pro').existsSync(), isTrue);
        expect(File('android/key.properties.example').existsSync(), isTrue);

        final manifest = File(
          'android/app/src/main/AndroidManifest.xml',
        ).readAsStringSync();
        expect(manifest.contains('android:allowBackup="false"'), isTrue);
      },
    );

    test(
      'pubspec.yaml has valid version code and build number for store submission',
      () {
        final file = File('pubspec.yaml');
        expect(file.existsSync(), isTrue);

        final content = file.readAsStringSync();
        final versionRegex = RegExp(r'version:\s*(\d+\.\d+\.\d+\+\d+)');
        expect(
          versionRegex.hasMatch(content),
          isTrue,
          reason:
              'pubspec.yaml must have semantic version + build number (e.g. 1.0.0+1)',
        );
      },
    );

    test(
      'Zero hardcoded live secrets or tokens committed in repository source files',
      () {
        final dir = Directory('lib');
        expect(dir.existsSync(), isTrue);

        final files = dir.listSync(recursive: true).whereType<File>();
        for (final file in files) {
          if (!file.path.endsWith('.dart')) continue;
          final content = file.readAsStringSync();

          // Check for common real API key prefixes
          expect(
            content.contains('AIzaSy'),
            isFalse,
            reason: 'Found live Google Gemini API key in ${file.path}',
          );
          expect(
            content.contains('appl_prod_'),
            isFalse,
            reason: 'Found live RevenueCat production key in ${file.path}',
          );
          expect(
            content.contains('goog_prod_'),
            isFalse,
            reason: 'Found live RevenueCat Google key in ${file.path}',
          );
        }
      },
    );

    test(
      'Zero Unicode em dashes (\u2014) exist in any source or test file',
      () {
        final dirs = [
          Directory('lib'),
          Directory('test'),
          Directory('integration_test'),
        ];
        final emDashChar = String.fromCharCode(0x2014);

        for (final dir in dirs) {
          if (!dir.existsSync()) continue;
          final files = dir.listSync(recursive: true).whereType<File>();
          for (final file in files) {
            if (!file.path.endsWith('.dart')) continue;
            final content = file.readAsStringSync();
            expect(
              content.contains(emDashChar),
              isFalse,
              reason: 'Found prohibited em dash in ${file.path}',
            );
          }
        }
      },
    );
  });
}
