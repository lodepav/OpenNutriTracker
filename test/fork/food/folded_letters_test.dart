// The table's search folds letters with marks on both sides: "sasliks"
// typed on an English keyboard found nothing, though a dish is named
// "Shashlik, chicken (vistas šašliks, ...)".
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/food/local_food_data_source.dart';

void main() {
  late LocalFoodDataSource foods;

  setUpAll(() async {
    final table = LocalFoodTable.fromGzip(
      await File(LocalFoodDataSource.assetPath).readAsBytes(),
    );
    foods = LocalFoodDataSource(
      loadTable: () async => table,
      readToggles: () async => null,
    );
  });

  test('letters with marks are plain ones', () {
    expect(
      foldLetters('Šašliks ĶIRBIS Ģērbe ņūļčž'),
      'sasliks kirbis gerbe nulcz',
    );
    expect(nameWords('vistas šašliks'), ['vistas', 'sasliks']);
  });

  test('"sasliks" lists the shashlik first on the Food tab', () async {
    final tab = await foods.fetchSearchWordResults('sasliks');
    expect(tab.first.name, startsWith('Shashlik'));
    final chicken = await foods.fetchSearchWordResults('vistas sasliks');
    expect(chicken.first.name, startsWith('Shashlik, chicken'));
  });

  for (final typed in ['sasliks', 'šašliks', 'vistas sasliks']) {
    test('"$typed" finds the shashlik', () async {
      final tab = await foods.fetchSearchWordResults(typed);
      expect(tab.map((r) => r.name), contains(startsWith('Shashlik')));
      final resolved = await foods.fetchSearchWordResults(
        typed,
        forResolution: true,
      );
      expect(resolved.map((r) => r.name), contains(startsWith('Shashlik')));
    });
  }
}
