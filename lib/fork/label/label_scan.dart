import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/core/utils/barcode_validator.dart';
import 'package:opennutritracker/features/add_meal/data/meal_items_api_factory.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_items_api.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_photo_interpreter.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';

/// Marks the request, for the fake AI.
const labelPromptStart = 'You transcribe a packaged-food nutrition label';

/// What the custom-meal form takes per 100 g, with the unit each is asked
/// in: the form's own units.
const labelNutrientUnits = {
  'energyKcal': 'kcal',
  'carbs': 'g',
  'fat': 'g',
  'protein': 'g',
  'fiber': 'g',
  'saturatedFat': 'g',
  'sugars': 'g',
  'sodium': 'mg',
  'calcium': 'mg',
  'iron': 'mg',
  'potassium': 'mg',
  'magnesium': 'mg',
  'vitaminD': 'µg',
  'vitaminB12': 'µg',
};

/// The most of each per 100 g a real label can print; a larger value is a
/// misread and is dropped.
const _maxPer100 = {'energyKcal': 900.0, 'sodium': 40000.0};
const _gramsMax = 100.0;
const _otherMax = 100000.0;

/// The rules for reading a label photo. The answer rides on upstream's
/// meal-items tool, as the leftovers photo does (D14): one item per value,
/// written into the item's text as `key=value`, because the tool's amount
/// field refuses the zeros a label prints.
final labelSystemPrompt =
    '$labelPromptStart from a photo, so the values can be typed into a '
    'nutrition tracker. You transcribe; you never estimate.\n'
    'Record one item per value you can read, and nothing else. Its query is '
    '`key=value`; leave quantity and unit out.\n'
    'Keys:\n'
    '- name: the product name as printed\n'
    '- brand: the brand as printed (not the shop)\n'
    '- barcode: the barcode digits, only when they are legible\n'
    '- serving: one stated portion in g (ml for drinks)\n'
    '${[for (final MapEntry(:key, :value) in labelNutrientUnits.entries) '- $key: per 100 g (or 100 ml), in $value'].join('\n')}\n'
    'Rules:\n'
    '- Read the per-100 g / per-100 ml column. When only per-serving values '
    'are printed, convert them to per 100 g using the stated serving size.\n'
    '- Convert printed units to the ones named (g, mg, µg; kJ to kcal with '
    '1 kcal = 4.184 kJ). Prefer a printed kcal over a converted kJ.\n'
    '- Sodium: when only salt is printed, sodium (mg) = salt (g) x 400.\n'
    '- A value printed as 0 is 0. A value you cannot read is left out, never '
    'guessed.\n'
    '- Numbers use a dot for decimals: fat=3.2, not fat=3,2.';

/// What was read off a label. [per100] holds the [labelNutrientUnits] keys
/// it printed.
class LabelReading {
  final String? name;
  final String? brand;
  final String? barcode;
  final double? servingGrams;
  final Map<String, double> per100;

  const LabelReading({
    this.name,
    this.brand,
    this.barcode,
    this.servingGrams,
    this.per100 = const {},
  });

  bool get isEmpty =>
      name == null && brand == null && barcode == null && per100.isEmpty;

  /// From the model's items: unknown keys, unreadable numbers, values no
  /// label prints and a barcode of the wrong shape are dropped.
  static LabelReading fromItems(List<ParsedMealItem> items) {
    String? name, brand, barcode;
    double? serving;
    final per100 = <String, double>{};
    for (final item in items) {
      final at = item.query.indexOf('=');
      if (at < 0) continue;
      final key = item.query.substring(0, at).trim();
      final raw = item.query.substring(at + 1).trim();
      if (raw.isEmpty) continue;
      switch (key) {
        case 'name':
          name = raw;
        case 'brand':
          brand = raw;
        case 'barcode':
          final digits = raw.replaceAll(RegExp(r'\D'), '');
          if (isBarcodeFormatValid(digits)) barcode = digits;
        case 'serving':
          final grams = _number(raw);
          if (grams != null && grams > 0 && grams <= 5000) serving = grams;
        default:
          final unit = labelNutrientUnits[key];
          final value = _number(raw);
          if (unit == null || value == null) continue;
          final max = _maxPer100[key] ?? (unit == 'g' ? _gramsMax : _otherMax);
          if (value <= max) per100[key] = value;
      }
    }
    return LabelReading(
      name: name,
      brand: brand,
      barcode: barcode,
      servingGrams: serving,
      per100: per100,
    );
  }

  static double? _number(String raw) {
    final match = RegExp(r'\d+(?:[.,]\d+)?').firstMatch(raw);
    final value = double.tryParse(match?[0]?.replaceAll(',', '.') ?? '');
    return value != null && value.isFinite ? value : null;
  }
}

/// Reads a label photo with the chosen model. Ported after
/// review from the label step of cattosmile/OpenNutriTrackerPlus's AI meal
/// scan (its prompt rules), without its research, web search and estimating
/// merge: only what the label prints reaches the form, which is also all
/// that may go to Open Food Facts.
class ReadLabelUseCase {
  final AiCredentialStorage _credentials;
  final http.Client _client;

  ReadLabelUseCase(this._credentials, this._client);

  Future<AiSelection?> get selection => _credentials.readSelection();

  /// Null when no model is set up; raises [MealInterpreterException] when
  /// the call fails.
  Future<LabelReading?> read(MealPhoto photo) async {
    final selection = await _credentials.readSelection();
    if (selection == null) return null;
    final result = await mealItemsApiFor(_client, selection).requestItems(
      content: MealPhotoContent(
        mediaType: photo.mediaType,
        base64Data: base64Encode(photo.bytes),
      ),
      system: labelSystemPrompt,
    );
    return LabelReading.fromItems(result.items);
  }
}
