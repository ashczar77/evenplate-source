import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../security/app_secrets.dart';
import 'image_codec_fault.dart';
import 'text_selection_fault.dart';
import 'handled_network_fault.dart';

/// One place for crashes and handled feature failures.
///
/// Blank [AppSecrets.sentryDsn] leaves this a no-op so simulator work stays
/// local. Never pass photos, food lists, or email into [report].
class TelemetryEvent {
  final String name;
  final bool alert;
  final Map<String, String> tags;
  final Object? error;

  const TelemetryEvent({
    required this.name,
    required this.alert,
    this.tags = const {},
    this.error,
  });
}

typedef TelemetrySink = void Function(TelemetryEvent event);

class Telemetry {
  Telemetry._();

  static bool _ready = false;
  static String? _boundUserId;
  static TelemetrySink? _sink;

  static bool get isEnabled => _ready;

  static void assessmentBreadcrumb(String name, Map<String, Object?> data) {
    if (!_ready) return;
    Sentry.addBreadcrumb(
      Breadcrumb(category: 'meal_assessment', message: name, data: data),
    );
  }

  /// Test seam. Production never sets this.
  @visibleForTesting
  static void debugSink(TelemetrySink? sink) => _sink = sink;

  static void resetForTest() {
    _ready = false;
    _boundUserId = null;
    _sink = null;
  }

  /// Safe to call with an empty DSN. Does not delay the first frame; boot
  /// starts this after splash is on screen.
  static Future<void> init() async {
    final dsn = AppSecrets.sentryDsn.trim();
    if (dsn.isEmpty) return;
    if (_ready) return;

    await SentryFlutter.init((options) {
      options.dsn = dsn;
      options.environment = kReleaseMode ? 'release' : 'debug';
      options.sendDefaultPii = false;
      options.attachScreenshot = false;
      options.captureFailedRequests = false;
      options.tracesSampleRate = kReleaseMode ? 0.1 : 1.0;
      options.beforeSend = _dropFrameworkTextSelection;
    });
    _ready = true;
  }

  /// SentryFlutter.init installs its own FlutterError hook. Drop the known
  /// empty-field long-press null so it is not filed as a crash.
  static SentryEvent? _dropFrameworkTextSelection(
    SentryEvent event,
    Hint hint,
  ) {
    final extra = StringBuffer(event.message?.formatted ?? '');
    for (final exception in event.exceptions ?? const <SentryException>[]) {
      extra.write(exception.type);
      extra.write(exception.value);
      final frames = exception.stackTrace?.frames ?? const <SentryStackFrame>[];
      for (final frame in frames) {
        extra.write(frame.function);
        extra.write(frame.absPath);
        extra.write(frame.fileName);
      }
    }
    final blob = extra.toString();
    if (isFrameworkTextSelectionFault(event.throwable, null, blob)) {
      return null;
    }
    if (isImageCodecFault(event.throwable, null, blob)) {
      return null;
    }
    return event;
  }

  static void setUser({String? id, bool guest = false}) {
    if (id == null || id.isEmpty) {
      _boundUserId = null;
      if (_ready) {
        Sentry.configureScope((scope) => scope.setUser(null));
      }
      return;
    }
    if (_boundUserId == id) return;
    _boundUserId = id;
    if (!_ready) return;
    Sentry.configureScope((scope) {
      scope.setUser(SentryUser(id: id));
      scope.setTag('guest', guest ? 'true' : 'false');
    });
  }

  /// [alert] true: grouped as an issue we should page on (timeout, 5xx,
  /// purchase fail, crash). False: expected product outcomes (not food,
  /// quota, user cancelled pay).
  static void report({
    required String name,
    bool alert = true,
    Map<String, String> tags = const {},
    Object? error,
    StackTrace? stack,
    bool diagnosticOnly = false,
  }) {
    final breadcrumbOnly = diagnosticOnly || isHandledNetworkFault(name, error);
    if (breadcrumbOnly) alert = false;
    _sink?.call(
      TelemetryEvent(name: name, alert: alert, tags: tags, error: error),
    );
    debugPrint('EvenPlate telemetry: $name alert=$alert');

    if (!_ready) return;

    if (breadcrumbOnly) {
      Sentry.addBreadcrumb(
        Breadcrumb(
          category: 'network.retry',
          message: name,
          level: SentryLevel.info,
          data: tags,
        ),
      );
      return;
    }

    final level = alert ? SentryLevel.error : SentryLevel.info;
    if (alert && error != null) {
      Sentry.captureException(
        error,
        stackTrace: stack,
        withScope: (scope) {
          scope.level = level;
          scope.fingerprint = [name];
          scope.setTag('feature', name);
          tags.forEach(scope.setTag);
        },
      );
      return;
    }

    Sentry.captureMessage(
      name,
      level: level,
      withScope: (scope) {
        scope.fingerprint = [name];
        scope.setTag('feature', name);
        tags.forEach(scope.setTag);
      },
    );
  }

  static Future<T> traceScan<T>(
    Future<T> Function() body, {
    String Function(T value)? outcomeOf,
  }) async {
    if (!_ready) return body();

    final transaction = Sentry.startTransaction('scan.analyze', 'http.client');
    try {
      final result = await body();
      transaction.setTag('outcome', outcomeOf?.call(result) ?? 'ok');
      transaction.status = const SpanStatus.ok();
      return result;
    } catch (e) {
      transaction.setTag('outcome', 'error');
      transaction.throwable = e;
      transaction.status = const SpanStatus.internalError();
      rethrow;
    } finally {
      await transaction.finish();
    }
  }
}
