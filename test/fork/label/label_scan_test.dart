import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'package:opennutritracker/fork/label/label_scan.dart';

LabelReading _read(List<String> queries) => LabelReading.fromItems([
  for (final query in queries) ParsedMealItem(query: query),
]);

void main() {
  test('reads identity and per-100 values, zeros included', () {
    final reading = _read([
      'name=Rye crispbread',
      'brand = Finn Crisp',
      'barcode=6410500090014',
      'serving=10',
      'energyKcal=350',
      'fat=2,5',
      'sodium=480',
      'vitaminD=0',
    ]);

    expect(reading.name, 'Rye crispbread');
    expect(reading.brand, 'Finn Crisp');
    expect(reading.barcode, '6410500090014');
    expect(reading.servingGrams, 10);
    expect(reading.per100, {
      'energyKcal': 350,
      'fat': 2.5,
      'sodium': 480,
      'vitaminD': 0,
    });
  });

  test('drops what no label prints', () {
    final reading = _read([
      'fat=120',
      'energyKcal=1500',
      'caffeine=40',
      'protein=n/a',
      'barcode=12ab',
      'serving=0',
      'carbs',
      'name=',
    ]);

    expect(reading.isEmpty, isTrue);
    expect(reading.servingGrams, isNull);
  });

  test('the prompt names every key the form takes', () {
    for (final key in labelNutrientUnits.keys) {
      expect(labelSystemPrompt, contains('- $key:'));
    }
    expect(labelSystemPrompt, startsWith(labelPromptStart));
  });
}
