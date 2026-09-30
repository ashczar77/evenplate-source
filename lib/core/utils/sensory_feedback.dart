import 'package:flutter/services.dart';

/// EvenPlate: Tactile Haptic System
/// Clean, subtle physical cues inspired by Apple Health and high-end wearables.
class SensoryFeedback {
  SensoryFeedback._();

  /// Triggered when the 4 nodes of the Satiety Matrix lock together into a seal
  static Future<void> resonanceSnap() async {
    try {
      HapticFeedback.lightImpact();
    } catch (_) {}
  }

  /// Triggered upon completing a balanced meal scan or ring close
  static Future<void> zenBloomPulse() async {
    try {
      HapticFeedback.mediumImpact();
    } catch (_) {}
  }

  /// Triggered on light tab / chip selection
  static Future<void> gentleTap() async {
    try {
      HapticFeedback.selectionClick();
    } catch (_) {}
  }

  /// Subtle warning haptic when a scan cannot identify food
  static Future<void> softWarning() async {
    try {
      HapticFeedback.selectionClick();
    } catch (_) {}
  }
}
