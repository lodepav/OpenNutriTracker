import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/data/model_meal_text_interpreter.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_items_api.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'package:opennutritracker/fork/bulk/typed_query_language.dart';

class _CapturingApi implements MealItemsApi {
  final systems = <String>[];

  @override
  Future<MealTextParseResult> requestItems({
    required MealContent content,
    required String system,
  }) async {
    systems.add(system);
    return const MealTextParseResult(items: [], errors: []);
  }
}

Future<String> _sentPrompt({String? localeCode}) async {
  final api = _CapturingApi();
  await ModelMealTextInterpreter(
    api,
  ).interpret('3 Scheiben Brot', localeCode: localeCode);
  return api.systems.single;
}

int _count(String text, String part) => part.allMatches(text).length;

void main() {
  group('the typed prompt holds one rule for "query" (D51)', () {
    for (final locale in [null, 'lv']) {
      test('as sent, app language ${locale ?? 'unset'}', () async {
        final system = await _sentPrompt(localeCode: locale);

        expect(system, isNot(contains('in the same language')));
        expect(system, isNot(contains('the user wrote. Keep a brand')));
        expect(system, isNot(contains('query "Brot"')));
        expect(system, contains('-> query "bread", quantity 3'));
        expect(system, isNot(contains('replaces')));
        expect(_count(system, '"query" is'), 1);
        expect(_count(system, 'nearest generic food in English'), 1);
        expect(system, contains('Keep a brand as written.'));
        expect(system, contains('with no amount in it'));
        if (locale != null) {
          expect(system, endsWith('The user\'s app language is "lv".'));
        }
      });
    }

    test('the fork rules stand where upstream\'s rule stood', () async {
      final system = await _sentPrompt();
      final query = system.indexOf(typedQueryLanguageRule);
      expect(query, greaterThan(system.indexOf('- One entry per distinct')));
      expect(query, lessThan(system.indexOf('- Only include "quantity"')));
      expect(system, contains('- A dish known by its name is one entry'));
      expect(system, contains('- Foods only served together are separate'));
    });

    test('a reworded upstream prompt fails rather than going out', () {
      expect(
        () => typedQueryPrompt('- "query" is the food name, in any language.'),
        throwsStateError,
      );
      expect(
        () => typedQueryPrompt('$upstreamQueryRule"Brot" -> query "Brot"'),
        returnsNormally,
      );
      expect(
        () => typedQueryPrompt('$upstreamQueryRule no example'),
        throwsStateError,
      );
    });
  });
}
