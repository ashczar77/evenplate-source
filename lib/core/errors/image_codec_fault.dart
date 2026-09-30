/// A missing or encrypted plate file is not a crash. Show the fallback mark.
bool isImageCodecFault(Object? error, [StackTrace? stack, String extra = '']) {
  final haystack = '${error ?? ''}\n${stack ?? ''}\n$extra';
  if (!haystack.contains('Invalid image data')) return false;
  return haystack.contains('FileImage') ||
      haystack.contains('instantiateImageCodec') ||
      haystack.contains('ImageDescriptor') ||
      haystack.contains('image_provider');
}
