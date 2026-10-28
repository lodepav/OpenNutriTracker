import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/data/model_meal_photo_interpreter.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_items_api.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_photo_interpreter.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'package:opennutritracker/fork/bulk/saved_dishes.dart';

class _Api implements MealItemsApi {
  String? system;

  @override
  Future<MealTextParseResult> requestItems({
    required MealContent content,
    required String system,
  }) async {
    this.system = system;
    return const MealTextParseResult(items: [], errors: []);
  }
}

void main() {
  test('the names quoted once each, the latest first, up to the limit', () {
    final prompt = savedDishesPrompt([
      'Sklandu rauši (sklandrausis)',
      ' pelmeni ',
      'Pelmeni',
      '',
      'Grey peas "with bacon"',
    ])!;
    expect(
      prompt,
      startsWith(
        'The user has saved these dishes: "Sklandu rauši (sklandrausis)", '
        '"pelmeni", "Grey peas \\"with bacon\\"". ',
      ),
    );
    final many = savedDishesPrompt([for (var i = 0; i < 100; i++) 'dish $i'])!;
    expect(many, contains('"dish ${savedDishesLimit - 1}"'));
    expect(many, isNot(contains('"dish $savedDishesLimit"')));
  });

  test('no saved dishes: no line', () {
    expect(savedDishesPrompt(const []), isNull);
    expect(savedDishesPrompt(const [' ']), isNull);
  });

  test('the photo prompt carries them, after the language (S172)', () async {
    final photo = MealPhoto(bytes: Uint8List(1), mediaType: 'image/webp');
    final api = _Api();
    await ModelMealPhotoInterpreter(
      api,
      savedDishes: () => ['Pelmeni'],
    ).interpret(photo, localeCode: 'en');
    expect(
      api.system,
      endsWith(
        'The user\'s app language is "en".\n'
        '${savedDishesPrompt(['Pelmeni'])}',
      ),
    );

    final plain = _Api();
    await ModelMealPhotoInterpreter(plain).interpret(photo, localeCode: 'en');
    expect(plain.system, endsWith('The user\'s app language is "en".'));
  });
}
