import 'package:flutter/foundation.dart';

/// Credits for the bundled food table (D11), shown under Settings → About →
/// View licenses. Settings → Food databases already names each table and
/// links to it; this adds what CC BY 4.0 asks for on top: the creator, the
/// licence and what was changed.
void registerFoodTableLicenses() {
  LicenseRegistry.addLicense(
    () => Stream.fromIterable(const [
      LicenseEntryWithLineBreaks(
        ['Bundeslebensmittelschlüssel (BLS) 4.0'],
        'Bundeslebensmittelschlüssel (BLS), version 4.0, '
        '© Max Rubner-Institut (MRI), https://www.blsdb.de\n\n'
        'Licensed under the Creative Commons Attribution 4.0 International '
        'licence (CC BY 4.0): https://creativecommons.org/licenses/by/4.0/\n\n'
        'Changes: a subset of the nutrients is converted to per 100 g in the '
        "app's units, and a comma is inserted after the food in each English "
        'name ("Herring smoked" becomes "Herring, smoked"). The values '
        'themselves are not changed.',
      ),
      LicenseEntryWithLineBreaks(
        ['USDA FoodData Central'],
        'U.S. Department of Agriculture, Agricultural Research Service. '
        'FoodData Central: SR Legacy, Foundation Foods and the Food and '
        'Nutrient Database for Dietary Studies (FNDDS). '
        'https://fdc.nal.usda.gov\n\n'
        'Public domain (CC0 1.0).',
      ),
    ]),
  );
}
