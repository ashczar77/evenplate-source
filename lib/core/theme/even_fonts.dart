import 'package:flutter/material.dart';

/// App type styles that paint on the first frame.
///
/// GoogleFonts.poppins/inter point at faces that are not bundled. Until a
/// network fetch completes (and if it never does), those styles can render
/// with zero glyphs on a dark scaffold, which looks like a blank app.
TextStyle evenPoppins({
  double? fontSize,
  FontWeight? fontWeight,
  Color? color,
  double? letterSpacing,
  double? height,
}) {
  return TextStyle(
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    letterSpacing: letterSpacing,
    height: height,
    fontFamilyFallback: const ['Helvetica Neue', 'Arial', 'sans-serif'],
  );
}
