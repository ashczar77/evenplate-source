import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evenplate/services/device_check_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('evenplate/devicecheck-test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final service = DeviceCheckService(
    channel: channel,
    platform: TargetPlatform.iOS,
  );
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('unsupported platforms never invoke the native channel', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (_) async {
      calls++;
      return 'dG9rZW4=';
    });
    await expectLater(
      DeviceCheckService(
        channel: channel,
        platform: TargetPlatform.android,
      ).generateToken(),
      throwsA(isA<DeviceCheckUnavailable>()),
    );
    expect(calls, 0);
  });

  test('each request generates a fresh token, without caching', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'generateToken');
      calls++;
      return calls == 1 ? 'dG9rZW4=' : 'ZnJlc2g=';
    });
    expect(await service.generateToken(), 'dG9rZW4=');
    expect(await service.generateToken(), 'ZnJlc2g=');
    expect(calls, 2);
  });

  test('invalid native response fails without exposing its contents', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => 'private token\n');
    try {
      await service.generateToken();
      fail('must reject invalid tokens');
    } on DeviceCheckUnavailable catch (error) {
      expect(error.toString(), 'Device verification unavailable');
    }
  });

  test('provider errors do not expose native details', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(
        code: 'provider',
        message: 'sensitive details',
      ),
    );
    await expectLater(
      service.generateToken(),
      throwsA(
        isA<DeviceCheckUnavailable>().having(
          (error) => error.toString(),
          'safe message',
          'Device verification unavailable',
        ),
      ),
    );
  });
}
