/// Empty-field long-press in Flutter can throw in RenderEditable.selectWord.
/// Store builds usually keep running; do not page this as a crash.
bool isFrameworkTextSelectionFault(
  Object? error, [
  StackTrace? stack,
  String extra = '',
]) {
  final haystack = '${error ?? ''}\n${stack ?? ''}\n$extra';
  final nullCheck =
      error is TypeError ||
      haystack.contains('Null check operator used on a null value');
  if (!nullCheck) return false;
  return haystack.contains('RenderEditable.selectWord') ||
      haystack.contains('selectWordsInRange') ||
      haystack.contains('selectWord') ||
      haystack.contains('TextSelectionGestureDetector');
}
