import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Produces ephemeral Apple tokens without storing or reporting their contents.
class DeviceCheckService {
  static const _channel = MethodChannel('evenplate/devicecheck');
  final MethodChannel channel;
  final TargetPlatform platform;
  final Duration timeout;

  DeviceCheckService({
    this.channel = _channel,
    TargetPlatform? platform,
    this.timeout = const Duration(seconds: 10),
  }) : platform = platform ?? defaultTargetPlatform;

  Future<String> generateToken() async {
    if (kIsWeb || platform != TargetPlatform.iOS) {
      throw const DeviceCheckUnavailable('unsupported');
    }
    try {
      final token = await channel
          .invokeMethod<String>('generateToken')
          .timeout(timeout);
      if (token == null ||
          token.isEmpty ||
          token.length > 16384 ||
          !RegExp(r'^[A-Za-z0-9+/]+={0,2}$').hasMatch(token)) {
        throw const DeviceCheckUnavailable('unavailable');
      }
      return token;
    } on TimeoutException {
      throw const DeviceCheckUnavailable('timeout');
    } on MissingPluginException {
      throw const DeviceCheckUnavailable('unsupported');
    } on PlatformException catch (error) {
      throw DeviceCheckUnavailable(
        error.code == 'unsupported' ? 'unsupported' : 'unavailable',
      );
    }
  }
}

class DeviceCheckUnavailable implements Exception {
  final String code;
  const DeviceCheckUnavailable(this.code);

  @override
  String toString() => 'Device verification $code';
}
