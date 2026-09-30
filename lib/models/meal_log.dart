import 'dart:convert';

import '../core/json/json_map.dart';
import 'satiety_matrix.dart';

const _keepEnergy = Object();
const _keepImage = Object();

/// Represents a logged meal in the user's local diary
class MealLog {
  final String id;
  final String userId;
  final String mealName;
  final DateTime timestamp;
  final String? imagePath;
  final SatietyResult satietyResult;
  final String? energyCheckIn; // 'steady', 'dip', null
  final bool isBridgeFix;
  final String? bridgedFromId;

  const MealLog({
    required this.id,
    this.userId = '',
    required this.mealName,
    required this.timestamp,
    this.imagePath,
    required this.satietyResult,
    this.energyCheckIn,
    this.isBridgeFix = false,
    this.bridgedFromId,
  });

  MealLog copyWith({
    String? userId,
    String? mealName,
    Object? energyCheckIn = _keepEnergy,
    SatietyResult? satietyResult,
    bool? isBridgeFix,
    String? bridgedFromId,
    Object? imagePath = _keepImage,
  }) {
    return MealLog(
      id: id,
      userId: userId ?? this.userId,
      mealName: mealName ?? this.mealName,
      timestamp: timestamp,
      imagePath: identical(imagePath, _keepImage)
          ? this.imagePath
          : imagePath as String?,
      satietyResult: satietyResult ?? this.satietyResult,
      energyCheckIn: identical(energyCheckIn, _keepEnergy)
          ? this.energyCheckIn
          : energyCheckIn as String?,
      isBridgeFix: isBridgeFix ?? this.isBridgeFix,
      bridgedFromId: bridgedFromId ?? this.bridgedFromId,
    );
  }

  /// Returns null when a Hive row cannot be read, so one corrupt meal cannot
  /// take down app startup.
  static MealLog? tryParse(Object? raw) {
    try {
      Object? decoded = raw;
      if (raw is String) {
        decoded = jsonDecode(raw);
      }
      final json = asStringKeyedMap(decoded);
      if (json == null) return null;

      final id = json['id']?.toString();
      final mealName = json['mealName']?.toString();
      final timestamp = DateTime.tryParse(json['timestamp']?.toString() ?? '');
      if (id == null ||
          id.isEmpty ||
          mealName == null ||
          mealName.isEmpty ||
          timestamp == null) {
        return null;
      }

      final satiety = asStringKeyedMap(json['satietyResult']);
      if (satiety == null) return null;

      final imagePath = json['imagePath'];
      final energyCheckIn = json['energyCheckIn'];
      final bridgedFromId = json['bridgedFromId'];

      final userId = json['userId']?.toString() ?? '';

      return MealLog(
        id: id,
        userId: userId,
        mealName: mealName,
        timestamp: timestamp,
        imagePath: imagePath is String ? imagePath : null,
        satietyResult: SatietyResult.fromJson(satiety),
        energyCheckIn: energyCheckIn is String ? energyCheckIn : null,
        isBridgeFix: json['isBridgeFix'] == true,
        bridgedFromId: bridgedFromId is String ? bridgedFromId : null,
      );
    } catch (_) {
      return null;
    }
  }

  factory MealLog.fromJson(Map<String, dynamic> json) {
    final parsed = tryParse(json);
    if (parsed == null) {
      throw const FormatException('Invalid MealLog JSON');
    }
    return parsed;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    if (userId.isNotEmpty) 'userId': userId,
    'mealName': mealName,
    'timestamp': timestamp.toIso8601String(),
    'imagePath': imagePath,
    'satietyResult': satietyResult.toJson(),
    'energyCheckIn': energyCheckIn,
    'isBridgeFix': isBridgeFix,
    if (bridgedFromId != null) 'bridgedFromId': bridgedFromId,
  };
}
