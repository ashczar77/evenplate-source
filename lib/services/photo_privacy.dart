import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';

Future<Uint8List> stripPhotoMetadata(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(
    bytes,
    targetWidth: 1600,
    allowUpscaling: false,
  );
  try {
    final frame = await codec.getNextFrame();
    try {
      final encoded = await frame.image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (encoded == null) {
        throw const FormatException('Could not prepare photo.');
      }
      return encoded.buffer.asUint8List(
        encoded.offsetInBytes,
        encoded.lengthInBytes,
      );
    } finally {
      frame.image.dispose();
    }
  } finally {
    codec.dispose();
  }
}
