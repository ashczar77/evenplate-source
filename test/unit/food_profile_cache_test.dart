import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:evenplate/models/satiety_matrix.dart';
import 'package:evenplate/services/food_list_scorer.dart';
import 'package:evenplate/services/gemini_vision_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'a cached single food is not a result for a novel mixed plate',
    () async {
      var calls = 0;
      final scorer = FoodListScorer.instance;
      scorer.resetForTest(
        vision: GeminiVisionService(
          null,
          MockClient((req) async {
            calls++;
            final foods = List<String>.from(jsonDecode(req.body)['foods']);
            return http.Response(
              jsonEncode({
                ...SatietyResult.fromFoods(mealName: 'Plate', components: foods)
                    .copyWith(
                      assessmentMethod: SatietyResult.modelMethod,
                      satietyScore: 60,
                    )
                    .toJson(),
                'captureIssue': 'none',
                'rejected': [],
              }),
              200,
            );
          }),
        ),
      );
      for (final foods in [
        ['cake'],
        ['cake', 'Eggs'],
        ['cake', 'Eggs', 'Side salad'],
      ]) {
        expect(
          (await scorer.score(mealName: 'Plate', foods: foods)).settled,
          isTrue,
        );
      }
      expect(calls, 3);
      await scorer.score(mealName: 'Plate', foods: ['Eggs', 'cake']);
      expect(calls, 3);
    },
  );
  test(
    'scan restoration never invents an assessment for unseen added foods',
    () {
      final scorer = FoodListScorer.instance;
      scorer.resetForTest();
      final original = SatietyResult.fromFoods(
        mealName: 'Sushi',
        components: ['Sushi platter'],
      ).copyWith(assessmentMethod: SatietyResult.modelMethod, satietyScore: 65);
      scorer.rememberScan(original);
      expect(
        scorer.cachedPlate(
          mealName: 'Sushi',
          foods: ['Sushi platter', 'Edamame'],
          original: original,
        ),
        isNull,
      );
      expect(
        scorer
            .cachedPlate(
              mealName: 'Sushi',
              foods: original.components,
              original: original,
            )!
            .satietyScore,
        65,
      );
    },
  );
}
