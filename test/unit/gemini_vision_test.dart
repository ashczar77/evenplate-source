import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:evenplate/services/gemini_vision_service.dart';

void main() {
  group('Gemini Flash Vision Service: Diverse Meal Parsing Tests', () {
    test('Correctly parses Salad: Mediterranean Chickpea & Arugula Salad', () {
      const rawJson = '''
      ```json
      {
        "mealName": "Mediterranean Chickpea & Arugula Salad",
        "components": ["Chickpeas", "Baby Arugula", "Kalamata Olives", "Feta Cheese", "Cucumber", "Extra Virgin Olive Oil"],
        "pillars": {
          "anchor": { "detected": true, "items": ["Chickpeas", "Feta Cheese"], "quality": "medium" },
          "net": { "detected": true, "items": ["Chickpeas", "Arugula", "Cucumber"], "quality": "high" },
          "buffer": { "detected": true, "items": ["Olive Oil", "Olives", "Feta"], "quality": "high" },
          "spark": { "detected": true, "items": ["Arugula", "Cucumber", "Lemon Zest"], "quality": "high" }
        },
        "satietyScore": 89,
        "durationHours": 4.0,
        "crashRisk": "low",
        "hybridUpgrade": {
          "instantAdd": "Top with 2 tbsp pumpkin seeds for zinc and additional protein anchor.",
          "smartSwap": "Add a scoop of hemp hearts to boost complete plant protein.",
          "digestiveCatalyst": "Dress with unpasteurized apple cider vinegar to support digestion."
        }
      }
      ```
      ''';

      final result = GeminiVisionService.parseVisionResponse(rawJson);

      expect(result.mealName, 'Mediterranean Chickpea & Arugula Salad');
      expect(result.components.length, 6);
      expect(result.pillars.isFullMatrix, isTrue);
      expect(result.pillars.completedCount, 4);
      expect(result.pillars.anchor.detected, isTrue);
      expect(result.pillars.net.quality, 'high');
      expect(result.satietyScore, 0);
      expect(result.durationHours, 0);
      expect(result.crashRisk, 'moderate');
      expect(result.hybridUpgrade.instantAdd, contains('pumpkin seeds'));
    });

    test('Correctly parses Bowl: Wild Salmon & Quinoa Bowl', () {
      const rawJson = '''
      {
        "mealName": "Wild Salmon & Quinoa Harvest Bowl",
        "components": ["Wild Sockeye Salmon", "Tricolor Quinoa", "Hass Avocado", "Steamed Broccoli"],
        "pillars": {
          "anchor": { "detected": true, "items": ["Wild Sockeye Salmon"], "quality": "high" },
          "net": { "detected": true, "items": ["Tricolor Quinoa", "Steamed Broccoli"], "quality": "high" },
          "buffer": { "detected": true, "items": ["Hass Avocado", "Omega-3s"], "quality": "high" },
          "spark": { "detected": true, "items": ["Lemon Herb Dressing"], "quality": "medium" }
        },
        "satietyScore": 96,
        "durationHours": 5.0,
        "crashRisk": "low",
        "hybridUpgrade": {
          "instantAdd": "Plate is already in near-perfect harmony.",
          "smartSwap": "No ingredient swap necessary.",
          "digestiveCatalyst": "Take 3 calming belly breaths before eating to stimulate vagus nerve."
        }
      }
      ''';

      final result = GeminiVisionService.parseVisionResponse(rawJson);

      expect(result.mealName, 'Wild Salmon & Quinoa Harvest Bowl');
      expect(result.pillars.anchor.items, contains('Wild Sockeye Salmon'));
      expect(result.satietyScore, 0);
      expect(result.durationHours, 0);
      expect(result.crashRisk, 'moderate');
    });

    test(
      'Correctly parses Comfort Food: Margherita Sourdough Pizza (Partial Combo)',
      () {
        const rawJson = '''
      ```json
      {
        "mealName": "Wood-Fired Margherita Pizza",
        "components": ["Sourdough Crust", "Tomato Sugo", "Fresh Mozzarella", "Basil"],
        "pillars": {
          "anchor": { "detected": true, "items": ["Mozzarella Cheese"], "quality": "low" },
          "net": { "detected": false, "items": [], "quality": "low" },
          "buffer": { "detected": true, "items": ["Olive Oil", "Cheese Fat"], "quality": "medium" },
          "spark": { "detected": false, "items": [], "quality": "low" }
        },
        "satietyScore": 62,
        "durationHours": 2.5,
        "crashRisk": "moderate",
        "hybridUpgrade": {
          "instantAdd": "Toss a side salad with mixed greens and balsamic to add a prebiotic net.",
          "smartSwap": "Opt for seeded thin-crust or top with grilled chicken next time.",
          "digestiveCatalyst": "Drink a glass of water with lemon to help digestive enzymes."
        }
      }
      ```
      ''';

        final result = GeminiVisionService.parseVisionResponse(rawJson);

        expect(result.mealName, 'Wood-Fired Margherita Pizza');
        expect(result.pillars.net.detected, isFalse);
        expect(result.pillars.spark.detected, isFalse);
        expect(result.pillars.completedCount, 1);
        expect(result.pillars.isFullMatrix, isFalse);
        expect(result.crashRisk, 'moderate');
        expect(result.durationHours, 0);
      },
    );

    test('Correctly parses Smoothie: Green Protein Boost Smoothie', () {
      const rawJson = '''
      {
        "mealName": "Green Goddess Protein Smoothie",
        "components": ["Plant Protein Powder", "Baby Spinach", "Chia Seeds", "Almond Milk", "Frozen Banana"],
        "pillars": {
          "anchor": { "detected": true, "items": ["Plant Protein Powder"], "quality": "high" },
          "net": { "detected": true, "items": ["Baby Spinach", "Chia Seeds"], "quality": "high" },
          "buffer": { "detected": true, "items": ["Chia Seeds", "Almond Milk"], "quality": "medium" },
          "spark": { "detected": true, "items": ["Spinach", "Spirulina"], "quality": "medium" }
        },
        "satietyScore": 86,
        "durationHours": 3.8,
        "crashRisk": "low",
        "hybridUpgrade": {
          "instantAdd": "Stir in 1 tbsp hemp hearts on top for chewing texture.",
          "smartSwap": "Swap whole banana for half banana + avocado to lower glycemic load.",
          "digestiveCatalyst": "Sip slowly over 15 minutes rather than gulping."
        }
      }
      ''';

      final result = GeminiVisionService.parseVisionResponse(rawJson);

      expect(result.mealName, 'Green Goddess Protein Smoothie');
      expect(result.pillars.isFullMatrix, isTrue);
      expect(result.satietyScore, 0);
      expect(result.durationHours, 0);
    });

    test('Correctly parses Snack: Apple with Almond Butter & Hemp Seeds', () {
      const rawJson = '''
      {
        "mealName": "Honeycrisp Apple with Almond Butter",
        "components": ["Sliced Apple", "Creamy Almond Butter", "Raw Hemp Seeds"],
        "pillars": {
          "anchor": { "detected": true, "items": ["Hemp Seeds"], "quality": "medium" },
          "net": { "detected": true, "items": ["Apple Skin & Flesh"], "quality": "high" },
          "buffer": { "detected": true, "items": ["Almond Butter"], "quality": "high" },
          "spark": { "detected": true, "items": ["Crisp Apple Crunch"], "quality": "high" }
        },
        "satietyScore": 82,
        "durationHours": 3.0,
        "crashRisk": "low",
        "hybridUpgrade": {
          "instantAdd": "Dust with ground cinnamon to support glucose sensitivity.",
          "smartSwap": "Keep the apple peel on for 4x more insoluble fiber.",
          "digestiveCatalyst": "Chew each bite thoroughly to stimulate saliva amylase."
        }
      }
      ''';

      final result = GeminiVisionService.parseVisionResponse(rawJson);

      expect(result.mealName, 'Honeycrisp Apple with Almond Butter');
      expect(result.pillars.spark.detected, isTrue);
      expect(result.satietyScore, 0);
    });

    test(
      'Correctly parses Unbalanced Sugar Spike: Frosted Donut (High Crash Risk)',
      () {
        const rawJson = '''
      {
        "mealName": "Glazed Cinnamon Donut",
        "components": ["Enriched Flour", "Sugar Glaze", "Palm Oil"],
        "pillars": {
          "anchor": { "detected": false, "items": [], "quality": "low" },
          "net": { "detected": false, "items": [], "quality": "low" },
          "buffer": { "detected": true, "items": ["Frying Fat"], "quality": "low" },
          "spark": { "detected": false, "items": [], "quality": "low" }
        },
        "satietyScore": 32,
        "durationHours": 1.2,
        "crashRisk": "high",
        "hybridUpgrade": {
          "instantAdd": "Pair immediately with a handful of raw walnuts or a hardboiled egg.",
          "smartSwap": "Next time, choose sourdough toast with almond butter and cinnamon.",
          "digestiveCatalyst": "Go for a light 10-minute walk after eating to clear glucose spike."
        }
      }
      ''';

        final result = GeminiVisionService.parseVisionResponse(rawJson);

        expect(result.mealName, 'Glazed Cinnamon Donut');
        expect(result.pillars.isFullMatrix, isFalse);
        expect(result.pillars.completedCount, 0);
        expect(result.crashRisk, 'moderate');
        expect(result.durationHours, 0);
        expect(result.satietyScore, 0);
      },
    );

    test(
      'Resiliently parses string numbers and conversational commentary from Gemini',
      () {
        const rawJson = '''
      Here is the Satiety Matrix analysis for your meal:
      ```json
      {
        "mealName": "Tofu Vegetable Stir Fry",
        "components": ["Crispy Tofu", "Snap Peas", "Carrots", "Sesame Oil"],
        "pillars": {
          "anchor": { "detected": "true", "items": ["Crispy Tofu"], "quality": "high" },
          "net": { "detected": "true", "items": ["Snap Peas", "Carrots"], "quality": "high" },
          "buffer": { "detected": "true", "items": ["Sesame Oil"], "quality": "high" },
          "spark": { "detected": "true", "items": ["Crunchy Vegetables"], "quality": "high" }
        },
        "satietyScore": "94",
        "durationHours": "4.6",
        "crashRisk": "low",
        "hybridUpgrade": {
          "instantAdd": "Sprinkle sesame seeds for extra zinc.",
          "smartSwap": "Pair with edamame for extra plant protein.",
          "digestiveCatalyst": "Enjoy warm ginger tea post-meal."
        }
      }
      ```
      Hope this helps your daily harmony!
      ''';

        final result = GeminiVisionService.parseVisionResponse(rawJson);

        expect(result.mealName, 'Tofu Vegetable Stir Fry');
        expect(result.pillars.anchor.detected, isTrue);
        expect(result.pillars.net.detected, isTrue);
        expect(result.satietyScore, 0);
        expect(result.durationHours, 0);
        expect(result.crashRisk, 'moderate');
      },
    );

    test('Throws FormatException on commentary with no JSON object', () {
      expect(
        () => GeminiVisionService.parseVisionResponse('sorry, no plate found'),
        throwsA(isA<FormatException>()),
      );
    });

    test('Throws FormatException when the payload is a JSON array', () {
      expect(
        () => GeminiVisionService.parseVisionResponse('[1, 2, 3]'),
        throwsA(isA<FormatException>()),
      );
    });

    test('Reads captureIssue from a valid vision payload', () {
      const rawJson = '''
      {
        "mealName": "Houseplant",
        "components": [],
        "pillars": {},
        "satietyScore": 0,
        "durationHours": 0.5,
        "crashRisk": "low",
        "captureIssue": "not_food"
      }
      ''';
      final result = GeminiVisionService.parseVisionResponse(rawJson);
      expect(result.captureIssue, 'not_food');
    });

    test('Sniffs jpeg and png magic bytes', () {
      expect(
        sniffImageMimeType(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0x00])),
        'image/jpeg',
      );
      expect(
        sniffImageMimeType(
          Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0, 0, 0, 0]),
        ),
        'image/png',
      );
    });
  });
}
