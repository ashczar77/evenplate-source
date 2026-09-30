import 'package:flutter/foundation.dart';

import 'image_codec_fault.dart';
import 'telemetry.dart';
import 'text_selection_fault.dart';

/// Records uncaught Flutter and zone errors, then forwards them to [Telemetry]
/// when a Sentry DSN is configured.
class ErrorReporter {
  ErrorReporter._();

  static const int _maxRecent = 20;
  static final List<String> _recent = [];

  static List<String> get recent => List.unmodifiable(_recent);

  static void install() {
    FlutterError.onError = (details) {
      record(details.exception, details.stack);
      FlutterError.presentError(details);
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      record(error, stack);
      return kReleaseMode;
    };
  }

  static void record(Object error, [StackTrace? stack]) {
    debugPrint('EvenPlate error: $error');
    if (stack != null) debugPrint('$stack');
    _recent.add(error.toString());
    if (_recent.length > _maxRecent) {
      _recent.removeAt(0);
    }
    if (isFrameworkTextSelectionFault(error, stack)) {
      Telemetry.report(
        name: 'ui.text_select',
        alert: false,
        error: error,
        stack: stack,
      );
      return;
    }
    if (isImageCodecFault(error, stack)) {
      Telemetry.report(
        name: 'ui.image_codec',
        alert: false,
        error: error,
        stack: stack,
      );
      return;
    }
    Telemetry.report(name: 'crash.uncaught', error: error, stack: stack);
  }

  /// Test seam so the ring buffer does not leak across cases.
  static void resetForTest() {
    _recent.clear();
    Telemetry.resetForTest();
  }
}
