import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/theme/even_colors.dart';
import '../services/meal_photo_store.dart';

/// Circular plate photo, or a centered plate mark when no file is on disk.
class MealThumb extends StatelessWidget {
  final String? imagePath;
  final double size;
  final String? semanticLabel;

  const MealThumb({
    super.key,
    this.imagePath,
    this.size = 44,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: MealPhotoImage(
          imagePath: imagePath,
          fit: BoxFit.cover,
          semanticLabel: semanticLabel,
          fallback: _FallbackMark(size: size, semanticLabel: semanticLabel),
        ),
      ),
    );
  }
}

/// Decodes a stored plate photo, including `.ep` ciphertext. Never uses
/// [Image.file], so a sealed file cannot throw Invalid image data.
class MealPhotoImage extends StatelessWidget {
  final String? imagePath;
  final BoxFit fit;
  final String? semanticLabel;
  final Widget fallback;

  const MealPhotoImage({
    super.key,
    required this.imagePath,
    required this.fallback,
    this.fit = BoxFit.cover,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    if (!MealPhotoStore.isReadable(imagePath)) return fallback;
    return FutureBuilder<Uint8List?>(
      future: MealPhotoStore.readDisplayBytes(imagePath),
      builder: (context, snap) {
        final bytes = snap.data;
        if (bytes == null || bytes.isEmpty) return fallback;
        return Image.memory(
          bytes,
          fit: fit,
          gaplessPlayback: true,
          semanticLabel: semanticLabel ?? 'Plate photo',
          errorBuilder: (context, error, stack) => fallback,
        );
      },
    );
  }
}

class _FallbackMark extends StatelessWidget {
  final double size;
  final String? semanticLabel;

  const _FallbackMark({required this.size, this.semanticLabel});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel ?? 'Plate',
      image: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [Color(0xFF1A1F3C), Color(0xFF111427)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: EvenColors.darkGlassBorderAccent),
        ),
        child: Center(
          child: Icon(
            Icons.restaurant_rounded,
            color: EvenColors.primaryGreen,
            size: size * 0.46,
          ),
        ),
      ),
    );
  }
}
