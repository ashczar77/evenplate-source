import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// True when the user (or a test) asked for reduced motion.
bool prefersReducedMotion(BuildContext context) {
  return MediaQuery.disableAnimationsOf(context);
}

/// Caps system text scaling so dense screens stay usable without ignoring
/// accessibility entirely. 1.5 covers large-text settings on iOS and Android.
TextScaler clampedTextScaler(TextScaler raw) {
  return raw.clamp(minScaleFactor: 1.0, maxScaleFactor: 1.5);
}

/// The iOS Simulator on recent macOS drops SimMetalHost; Impeller then
/// SIGABRTs or composites a black frame. HOME is often empty inside the
/// simulated app, so also check TMPDIR, the binary path, and SIMULATOR_*.
bool get isIosSimulator {
  if (kIsWeb) return false;
  try {
    if (!Platform.isIOS) return false;
  } catch (_) {
    return false;
  }
  final env = Platform.environment;
  if ((env['SIMULATOR_UDID'] ?? '').isNotEmpty) return true;
  if ((env['SIMULATOR_DEVICE_NAME'] ?? '').isNotEmpty) return true;
  bool looksLikeSim(String value) => value.contains('CoreSimulator');
  if (looksLikeSim(env['HOME'] ?? '')) return true;
  if (looksLikeSim(env['TMPDIR'] ?? '')) return true;
  if (looksLikeSim(env['CFFIXED_USER_HOME'] ?? '')) return true;
  try {
    if (looksLikeSim(Platform.resolvedExecutable)) return true;
  } catch (_) {}
  return false;
}

/// Live backdrop blur is expensive. Skip it when motion is reduced or when
/// the iOS Simulator Metal host would abort the process.
bool useBackdropBlur(BuildContext context) {
  if (prefersReducedMotion(context)) return false;
  if (isIosSimulator) return false;
  return true;
}

/// Box shadows compile to Impeller blurs. On the iOS Simulator that path
/// SIGABRTs when SimMetalHost drops (DrawCircle + AttemptDrawBlur).
List<BoxShadow> safeBoxShadows(List<BoxShadow> shadows) {
  if (isIosSimulator) return const [];
  return shadows;
}

/// Canvas glow. Same Impeller blur trap as [safeBoxShadows].
MaskFilter? safeMaskBlur(double sigma, {BlurStyle style = BlurStyle.normal}) {
  if (isIosSimulator) return null;
  return MaskFilter.blur(style, sigma);
}
