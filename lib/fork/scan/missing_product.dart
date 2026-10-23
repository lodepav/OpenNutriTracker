import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/edit_meal/presentation/edit_meal_screen.dart';

/// A new custom food carrying the barcode no database knew.
MealEntity missingProduct(String barcode) {
  final empty = MealEntity.empty();
  return MealEntity(
    code: barcode,
    name: empty.name,
    url: empty.url,
    mealQuantity: empty.mealQuantity,
    mealUnit: empty.mealUnit,
    servingQuantity: empty.servingQuantity,
    servingUnit: empty.servingUnit,
    servingSize: empty.servingSize,
    nutriments: empty.nutriments,
    source: MealSourceEntity.custom,
  );
}

/// Under the scanner's "product not found" (seam S36): makes the product a
/// custom food with its barcode, in place of the scanner. The form's label
/// scan (S29) fills it, and saving offers it to Open Food Facts (S33).
class AddMissingProductButton extends StatelessWidget {
  final String barcode;
  final IntakeTypeEntity intakeType;
  final DateTime day;

  const AddMissingProductButton({
    super.key,
    required this.barcode,
    required this.intakeType,
    required this.day,
  });

  Future<void> _open(BuildContext context) async {
    final config = await locator<GetConfigUsecase>().getConfig();
    if (!context.mounted) return;
    await Navigator.of(context).pushReplacementNamed(
      NavigationOptions.editMealRoute,
      arguments: EditMealScreenArguments(
        day,
        missingProduct(barcode),
        intakeType,
        config.usesImperialFoodUnits,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(32, 24, 32, 0),
    child: Column(
      children: [
        OutlinedButton.icon(
          key: const Key('fork-add-missing-product'),
          icon: const Icon(Icons.document_scanner_outlined),
          label: const Text('Add it from its label'),
          onPressed: () => _open(context),
        ),
        const SizedBox(height: 8),
        Text(
          'Save it as your own food with barcode $barcode. You can read the '
          'nutrition label with a photo, and then offer it to Open Food '
          'Facts.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}
