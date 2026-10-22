import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/food/food_table_licenses.dart';

void main() {
  test('the licence page credits BLS (CC BY 4.0, MRI) and USDA FDC', () async {
    registerFoodTableLicenses();
    final entries = await LicenseRegistry.licenses.toList();
    String textOf(String package) => entries
        .firstWhere((e) => e.packages.contains(package))
        .paragraphs
        .map((p) => p.text)
        .join('\n');

    final bls = textOf('Bundeslebensmittelschlüssel (BLS) 4.0');
    expect(bls, contains('Max Rubner-Institut'));
    expect(bls, contains('CC BY 4.0'));
    expect(bls, contains('Changes:'));
    expect(textOf('USDA FoodData Central'), contains('Public domain'));
  });
}
