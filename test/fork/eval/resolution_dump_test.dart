// The resolution audit's first half: each query in FORK_EVAL_AUDIT_QUERIES
// (a JSON list of strings, or of {query, quantity} for a counted name)
// resolved as a model's read is (S196, S204): the table, and Open Food
// Facts too under FORK_EVAL_ONLINE=1, as the live eval searches, as
// staple_foods_test.dart does, and written beside it as
// <file>.resolved.json with the row's name, kcal per 100 and serving, for
// a judge to read. Skipped without the variable.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/data/data_sources/off_data_source.dart';
import 'package:opennutritracker/features/add_meal/data/repository/products_repository.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/resolve_parsed_meals_usecase.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'package:opennutritracker/fork/food/local_food_data_source.dart';

import 'eval_model.dart';

void main() {
  final path = Platform.environment['FORK_EVAL_AUDIT_QUERIES'];
  test('resolution dump', skip: path == null, () async {
    final table = LocalFoodTable.fromGzip(
      await File(LocalFoodDataSource.assetPath).readAsBytes(),
    );
    final resolver = ResolveParsedMealsUseCase(
      TableOnlySearch(
        ProductsRepository(
          OFFDataSource(),
          LocalFoodDataSource(
            loadTable: () async => table,
            readToggles: () async => null,
          ),
        ),
      ),
    );
    final queries = jsonDecode(File(path!).readAsStringSync()) as List;
    final out = <Map<String, Object?>>[];
    for (final entry in queries) {
      final query = entry is Map ? entry['query'] as String : entry as String;
      final quantity = entry is Map ? entry['quantity'] as num? : null;
      final item = (await resolver.resolve([
        ParsedMealItem(query: query, quantity: quantity?.toDouble()),
      ], fromPhoto: true)).single;
      final meal = item.candidates.isEmpty
          ? null
          : item.candidates[item.selectedIndex];
      out.add({
        'query': query,
        'row': meal?.name,
        'brand': meal?.brands ?? meal?.source.name,
        'kcal100': meal?.nutriments.energyKcal100,
        'serving': meal == null
            ? null
            : '${meal.servingQuantity ?? ''} ${meal.servingUnit ?? ''} '
                      '${meal.servingSize ?? ''}'
                  .trim(),
        'confidence': item.confidence,
        'next': [
          for (final c in item.candidates.skip(1).take(2))
            '${c.name} [${c.brands ?? c.source.name}] '
                '(${c.servingQuantity ?? '-'})',
        ],
      });
    }
    File(
      '$path.resolved.json',
    ).writeAsStringSync(const JsonEncoder.withIndent(' ').convert(out));
  });
}
