import 'package:flutter_test/flutter_test.dart';
import 'package:evenplate/models/meal_log.dart';
import 'package:evenplate/models/satiety_matrix.dart';
import 'package:evenplate/services/meal_diary_sync.dart';

SatietyResult _result({int score = 70}) {
  return SatietyResult(
    mealName: 'Canary Bowl',
    components: const ['Canary Bean'],
    pillars: const SatietyPillars(
      anchor: PillarDetail(
        detected: true,
        items: ['Canary Bean'],
        quality: 'high',
      ),
      net: PillarDetail(detected: false, items: [], quality: 'low'),
      buffer: PillarDetail(detected: false, items: [], quality: 'low'),
      spark: PillarDetail(detected: false, items: [], quality: 'low'),
    ),
    satietyScore: score,
    durationHours: 3,
    crashRisk: 'low',
    hybridUpgrade: const HybridUpgrade(
      instantAdd: 'Add greens.',
      smartSwap: 'Keep it simple.',
      digestiveCatalyst: 'Sip water.',
    ),
  );
}

MealLog _meal({String id = 'meal-1', int score = 70, DateTime? timestamp}) {
  return MealLog(
    id: id,
    mealName: 'Canary Bowl',
    timestamp: timestamp ?? DateTime.utc(2026, 9, 25, 12),
    satietyResult: _result(score: score),
    energyCheckIn: 'steady',
  );
}

void main() {
  test('A server row round-trips the local meal id and check-in', () {
    final local = _meal();
    final row = {
      'id': '11111111-1111-1111-1111-111111111111',
      'user_id': 'user-a',
      'meal_name': local.mealName,
      'satiety_score': local.satietyResult.satietyScore,
      'duration_hours': local.satietyResult.durationHours,
      'created_at': '2026-09-25T12:00:00Z',
      'satiety_result': MealDiarySync.satietyPayload(local),
    };

    final restored = MealDiarySync.fromServerRow(row);

    expect(restored, isNotNull);
    expect(restored!.id, 'meal-1');
    expect(restored.userId, 'user-a');
    expect(restored.energyCheckIn, 'steady');
    expect(restored.satietyResult.satietyScore, 70);
    expect(restored.satietyResult.toJson().containsKey('_evenplate'), isFalse);
  });

  test('Two identical plates on the same day remain separate meals', () {
    final a = _meal(id: 'local');
    final b = _meal(id: 'server');
    expect(MealDiarySync.isSamePlate(a, b), isFalse);
    expect(
      MealDiarySync.isSamePlate(a, _meal(id: 'other', score: 40)),
      isFalse,
    );
    expect(
      MealDiarySync.isSamePlate(
        _meal(id: 'meal-1').copyWith(userId: 'user-a'),
        _meal(id: 'meal-1').copyWith(userId: 'user-b'),
      ),
      isFalse,
    );
  });

  test('Fingerprint distinguishes two meals with different identities', () {
    final local = _meal(id: 'local-uuid');
    final server = _meal(id: '11111111-1111-1111-1111-111111111111');
    expect(
      MealDiarySync.fingerprint(local),
      isNot(MealDiarySync.fingerprint(server)),
    );
    expect(MealDiarySync.isSamePlate(local, server), isFalse);
  });

  test('A server row never exposes a device photo path', () {
    final local = _meal().copyWith(imagePath: '/photos/plate-1.ep');
    final payload = MealDiarySync.satietyPayload(local);
    expect((payload['_evenplate'] as Map).containsKey('imagePath'), isFalse);
    (payload['_evenplate'] as Map)['imagePath'] = '/photos/other-owner.ep';
    final row = {
      'id': 'row-1',
      'user_id': 'user-a',
      'meal_name': local.mealName,
      'created_at': '2026-09-25T12:00:00Z',
      'satiety_result': payload,
    };

    final restored = MealDiarySync.fromServerRow(row);

    expect(restored!.imagePath, isNull);
  });

  test('The keep window matches the Insights 30 day range', () {
    final now = DateTime(2026, 9, 25);
    expect(
      MealDiarySync.withinKeepWindow(DateTime(2026, 8, 27), now: now),
      isTrue,
    );
    expect(
      MealDiarySync.withinKeepWindow(DateTime(2026, 8, 26), now: now),
      isFalse,
    );
  });
}
