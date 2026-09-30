/// Best-effort conversion of decoded JSON into a string-keyed map.
///
/// `jsonDecode` usually yields `Map<String, dynamic>`, but Hive leftovers and
/// nested values can arrive as `Map<dynamic, dynamic>`. A hard `as` cast
/// throws and used to take down startup when a single meal row was corrupt.
Map<String, dynamic>? asStringKeyedMap(Object? raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) {
    return raw.map((key, value) => MapEntry(key.toString(), value));
  }
  return null;
}
