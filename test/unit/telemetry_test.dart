import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evenplate/core/errors/error_reporter.dart';
import 'package:evenplate/core/errors/telemetry.dart';
import 'package:evenplate/core/errors/image_codec_fault.dart';
import 'package:evenplate/core/errors/text_selection_fault.dart';
import 'package:evenplate/core/security/app_secrets.dart';
import 'package:evenplate/services/gemini_vision_service.dart';

void main() {
  setUp(Telemetry.resetForTest);

  test(
    'handled offline failures are diagnostic, server failures still alert',
    () {
      final seen = <TelemetryEvent>[];
      Telemetry.debugSink(seen.add);
      final failures = <Object>[
        const SocketException('Failed host lookup'),
        http.ClientException('SocketException: Failed host lookup'),
        PlatformException(
          code: '35',
          details: {'readable_error_code': 'OFFLINE_CONNECTION_ERROR'},
        ),
        const FunctionException(status: 0, details: 'SocketException: offline'),
        FunctionException(
          status: 0,
          details: Exception(
            'ClientException with SocketException: Failed host lookup',
          ),
        ),
      ];
      for (final failure in failures) {
        Telemetry.report(name: 'sync.failed', error: failure);
      }
      expect(seen.every((event) => !event.alert), isTrue);
      seen.clear();
      for (final failure in <Object>[
        const FunctionException(status: 503, details: 'server unavailable'),
        const FunctionException(status: 401, details: 'unauthorized'),
        FormatException('invalid response'),
        TimeoutException('persistent timeout'),
      ]) {
        Telemetry.report(name: 'sync.failed', error: failure);
      }
      Telemetry.report(name: 'crash.uncaught', error: failures.first);
      expect(seen.every((event) => event.alert), isTrue);
    },
  );

  test('initial sync timeout can be retained as a breadcrumb', () {
    final seen = <TelemetryEvent>[];
    Telemetry.debugSink(seen.add);
    Telemetry.report(
      name: 'sync.failed',
      error: TimeoutException('retry pending'),
      diagnosticOnly: true,
    );
    expect(seen.single.alert, isFalse);
  });

  test('SENTRY_DSN is optional and empty in tests', () {
    expect(AppSecrets.sentryDsn, isEmpty);
    expect(AppSecrets.placeholders(), isNot(contains('SENTRY_DSN')));
  });

  test('report records on the debug sink without a DSN', () {
    final seen = <TelemetryEvent>[];
    Telemetry.debugSink(seen.add);

    Telemetry.report(name: 'scan.timeout', error: StateError('late'));
    Telemetry.report(name: 'scan.quota', alert: false);

    expect(seen.map((e) => e.name), ['scan.timeout', 'scan.quota']);
    expect(seen[0].alert, isTrue);
    expect(seen[1].alert, isFalse);
  });

  test('uncaught errors also emit crash.uncaught', () {
    final seen = <TelemetryEvent>[];
    ErrorReporter.resetForTest();
    Telemetry.debugSink(seen.add);

    ErrorReporter.record(StateError('boom'));

    expect(seen.map((e) => e.name), contains('crash.uncaught'));
    expect(ErrorReporter.recent, contains('Bad state: boom'));
  });

  test('text selection nulls are not crash.uncaught', () {
    final seen = <TelemetryEvent>[];
    ErrorReporter.resetForTest();
    Telemetry.debugSink(seen.add);
    final stack = StackTrace.fromString(
      '#0      RenderEditable.selectWord (package:flutter/src/rendering/editable.dart:1:1)\n',
    );

    ErrorReporter.record(
      Exception('Null check operator used on a null value'),
      stack,
    );

    expect(seen.map((e) => e.name), ['ui.text_select']);
    expect(seen.single.alert, isFalse);
  });

  test('Sentry-shaped selectWord payloads are dropped as text selection', () {
    const extra =
        'TypeErrorNull check operator used on a null value'
        'RenderEditable.selectWord'
        'package:flutter/src/rendering/editable.dart';
    expect(isFrameworkTextSelectionFault(null, null, extra), isTrue);
    expect(isFrameworkTextSelectionFault(StateError('boom')), isFalse);
  });

  test('Invalid plate photo data is not paged as a crash', () {
    ErrorReporter.resetForTest();
    final seen = <TelemetryEvent>[];
    Telemetry.debugSink(seen.add);

    ErrorReporter.record(
      Exception('Invalid image data'),
      StackTrace.fromString('#4      FileImage._loadAsync'),
    );

    expect(seen.map((e) => e.name), ['ui.image_codec']);
    expect(seen.single.alert, isFalse);
    expect(
      isImageCodecFault(
        Exception('Invalid image data'),
        StackTrace.fromString('instantiateImageCodecWithSize'),
      ),
      isTrue,
    );
  });

  test('PlateAnalysisException names map to scan events', () {
    expect(
      const PlateAnalysisException(
        'late',
        kind: PlateAnalysisFailureKind.timeout,
      ).telemetryName,
      'scan.timeout',
    );
    expect(
      const PlateAnalysisException(
        'offline',
        kind: PlateAnalysisFailureKind.network,
      ).telemetryName,
      'scan.network',
    );
    expect(
      const PlateAnalysisException(
        'bad json',
        kind: PlateAnalysisFailureKind.unreadable,
      ).telemetryName,
      'scan.unreadable',
    );
    expect(
      const PlateAnalysisException(
        'busy',
        kind: PlateAnalysisFailureKind.http,
        statusCode: 502,
      ).telemetryName,
      'scan.http_5xx',
    );
    expect(
      const PlateAnalysisException(
        'no',
        kind: PlateAnalysisFailureKind.http,
        statusCode: 401,
      ).telemetryName,
      'scan.http_4xx',
    );
    expect(
      const PlateAnalysisException(
        'empty',
        statusCode: 502,
        code: 'GEMINI_EMPTY',
      ).telemetryName,
      'scan.empty',
    );
    expect(
      const PlateAnalysisException(
        'empty',
        statusCode: 502,
        code: 'GEMINI_EMPTY',
      ).alert,
      isTrue,
    );
    expect(
      const PlateAnalysisException(
        'blocked leftover',
        statusCode: 422,
        code: 'GEMINI_BLOCKED',
      ).telemetryName,
      'scan.not_food',
    );
    expect(
      const PlateAnalysisException(
        'blocked leftover',
        statusCode: 422,
        code: 'GEMINI_BLOCKED',
      ).alert,
      isFalse,
    );
    expect(
      const PlateAnalysisException(
        'late',
        kind: PlateAnalysisFailureKind.timeout,
      ).telemetryNameFor('foods'),
      'foods.timeout',
    );
    expect(
      const PlateAnalysisException(
        'empty',
        statusCode: 502,
        code: 'GEMINI_EMPTY',
      ).telemetryNameFor('foods'),
      'foods.empty',
    );
    expect(
      const PlateAnalysisException(
        'unknown',
        statusCode: 502,
        code: 'GEMINI_UNKNOWN',
      ).telemetryNameFor('foods'),
      'foods.unknown',
    );
    expect(
      const PlateAnalysisException(
        'busy',
        statusCode: 429,
        code: 'GEMINI_BUSY',
      ).telemetryNameFor('foods'),
      'foods.busy',
    );
    expect(
      const PlateAnalysisException(
        'unpaid',
        statusCode: 402,
        code: 'GEMINI_UNPAID',
      ).telemetryNameFor('foods'),
      'foods.busy',
    );
  });
}
