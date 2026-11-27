import 'dart:io';

import 'package:opennutritracker/fork/food/local_food_data_source.dart';

Future<LocalFoodTable>? _table;

/// The bundled food table, parsed once per process so the files of one test
/// bundle share a parse. No test may change it.
Future<LocalFoodTable> sharedFoodTable() => _table ??= File(
  LocalFoodDataSource.assetPath,
).readAsBytes().then(LocalFoodTable.fromGzip);
