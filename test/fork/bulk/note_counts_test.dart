import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/data/model_meal_photo_interpreter.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_items_api.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_photo_interpreter.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'package:opennutritracker/fork/bulk/note_counts.dart';

class _Api implements MealItemsApi {
  final List<ParsedMealItem> reply;

  _Api(this.reply);

  @override
  Future<MealTextParseResult> requestItems({
    required MealContent content,
    required String system,
  }) async => MealTextParseResult(items: reply, errors: const []);
}

void main() {
  group('noteStatesCount', () {
    test('a part count written as a number, a sign or a word', () {
      for (final (note, count) in [
        ('1.5 cabbage rolls', 1.5),
        ('1,5 cabbage rolls', 1.5),
        ('half a pork chop', 0.5),
        ('½ pizza', 0.5),
        ('1½ pancakes', 1.5),
        ('a quarter of the pizza', 0.25),
        ('one and a half cutlets', 1.5),
        ('2 and a half pancakes', 2.5),
        ('⅓ of the cake', 0.33),
      ]) {
        expect(noteStatesCount(note, count), isTrue, reason: note);
      }
    });

    test('a count the note does not state, or no note', () {
      expect(noteStatesCount('2 pancakes', 1.5), isFalse);
      expect(noteStatesCount('halves of peaches', 0.5), isFalse);
      expect(noteStatesCount(null, 0.5), isFalse);
      expect(noteStatesCount('half a pizza', null), isFalse);
    });
  });

  group('the photo path (S170)', () {
    final photo = MealPhoto(bytes: Uint8List(1), mediaType: 'image/webp');
    Future<double?> countFor(double quantity, String? note) async {
      final result = await ModelMealPhotoInterpreter(
        _Api([ParsedMealItem(query: 'pork chop', quantity: quantity)]),
      ).interpret(photo, note: note);
      return result.items.single.quantity;
    }

    test('keeps a part count the note states', () async {
      expect(await countFor(0.5, 'half a pork chop'), 0.5);
      expect(await countFor(1.5, '1.5 pork chops'), 1.5);
    });

    test('still drops one the model made up', () async {
      expect(await countFor(1.5, null), isNull);
      expect(await countFor(1.5, '2 pork chops'), isNull);
    });
  });
}
