import '../core/json/json_map.dart';
import '../models/meal_log.dart';
import '../models/satiety_matrix.dart';

/// Packs a local meal into the existing `meals.satiety_result` jsonb so the
/// diary can come back after sign-in without a schema change.
class MealDiarySync {
  static const diaryKey = '_evenplate';

  /// Insights month is 30 calendar days. Stored history is retained.
  static const keepDays = 30;

  static DateTime keepAfter({DateTime? now}) {
    final moment = now ?? DateTime.now();
    final day = DateTime(moment.year, moment.month, moment.day);
    return day.subtract(const Duration(days: keepDays - 1));
  }

  static bool withinKeepWindow(DateTime stamp, {DateTime? now}) {
    final stampDay = DateTime(stamp.year, stamp.month, stamp.day);
    return !stampDay.isBefore(keepAfter(now: now));
  }

  static Map<String, dynamic> satietyPayload(MealLog meal) {
    return {
      ...meal.satietyResult.toJson(),
      diaryKey: {
        'id': meal.id,
        'timestamp': meal.timestamp.toIso8601String(),
        'energyCheckIn': meal.energyCheckIn,
        'isBridgeFix': meal.isBridgeFix,
        if (meal.bridgedFromId != null) 'bridgedFromId': meal.bridgedFromId,
      },
    };
  }

  static MealLog? fromServerRow(Map<String, dynamic> row) {
    final satietyRaw = asStringKeyedMap(row['satiety_result']);
    if (satietyRaw == null) return null;
    final diary = asStringKeyedMap(satietyRaw[diaryKey]);
    final analysis = Map<String, dynamic>.from(satietyRaw)..remove(diaryKey);
    final result = SatietyResult.fromJson(analysis);
    final id = diary?['id']?.toString() ?? row['id']?.toString();
    final timestamp =
        DateTime.tryParse(diary?['timestamp']?.toString() ?? '') ??
        DateTime.tryParse(row['created_at']?.toString() ?? '');
    final mealName = row['meal_name']?.toString();
    if (id == null ||
        id.isEmpty ||
        timestamp == null ||
        mealName == null ||
        mealName.isEmpty) {
      return null;
    }
    final energy = diary?['energyCheckIn'];
    final bridged = diary?['bridgedFromId'];
    final userId = row['user_id']?.toString() ?? '';
    return MealLog(
      id: id,
      userId: userId,
      mealName: mealName,
      timestamp: timestamp,
      imagePath: null,
      satietyResult: result,
      energyCheckIn: energy is String ? energy : null,
      isBridgeFix: diary?['isBridgeFix'] == true,
      bridgedFromId: bridged is String ? bridged : null,
    );
  }

  static String fingerprint(MealLog meal) {
    return '${meal.userId}|${meal.id}';
  }

  static bool isSamePlate(MealLog a, MealLog b) {
    if (a.userId.isNotEmpty && b.userId.isNotEmpty && a.userId != b.userId) {
      return false;
    }
    return a.id == b.id;
  }
}
