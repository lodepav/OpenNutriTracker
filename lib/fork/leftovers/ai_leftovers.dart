import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/features/add_meal/data/meal_items_api_factory.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_items_api.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_photo_interpreter.dart';
import 'package:opennutritracker/features/add_meal/util/meal_photo_encoder.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'package:opennutritracker/fork/units/amount_text.dart';

/// Marks the request, for the fake AI.
const leftoversPromptStart = 'You estimate what is left of a meal';

/// The rules for reading a leftovers photo (D14). The model answers through
/// upstream's meal-items tool, one item per entry with anything left, and
/// gives only how much is left in the entry's own unit: never a nutrient,
/// never a food that is not listed, so the numbers stay the entries' own.
String leftoversSystemPrompt(
  List<IntakeEntity> entries, {
  required bool withMealPhoto,
}) {
  final listed = [
    for (final (i, e) in entries.indexed)
      '${i + 1}. ${e.meal.name ?? ''}: ${_number(e.amount)} '
          '${shownUnit(e, false).unit}',
  ].join('\n');
  return '$leftoversPromptStart after eating, from a photo.\n'
      '${withMealPhoto ? 'The photo has two halves: on the left the meal as '
                'served, on the right what is left of it.' : 'The photo '
                'shows what is left on the plate.'}\n'
      'The meal as logged:\n$listed\n'
      'For each entry with anything left, record one item: query is the '
      "entry's name exactly as written above, quantity is how much of it is "
      "left in the entry's own unit, and unit is that unit. Count what can "
      'be counted: 2 of 5 dumplings logged as 5 serving is 2 serving. '
      'Leave out an entry with nothing left. Never record a food that is '
      'not listed.';
}

/// How much is left of each entry, by id, from the model's items. An item
/// naming no entry, in another unit, or with no amount is dropped; an
/// amount over what was logged is capped at it. Two entries of one food
/// take the model's items for it in order.
Map<String, double> leftoversFromItems(
  List<IntakeEntity> entries,
  List<ParsedMealItem> items,
) {
  final left = <String, double>{};
  for (final item in items) {
    final quantity = item.quantity;
    if (quantity == null) continue;
    final entry = entries
        .where(
          (e) =>
              !left.containsKey(e.id) &&
              (item.unit == null || item.unit == e.unit) &&
              (e.meal.name ?? '').trim().toLowerCase() ==
                  item.query.trim().toLowerCase(),
        )
        .firstOrNull;
    if (entry == null) continue;
    left[entry.id] = quantity.clamp(0, entry.amount).toDouble();
  }
  return left;
}

/// Asks the chosen model how much of each entry is left. Null when no
/// model is set up; raises [MealInterpreterException] when the call fails.
class ReadLeftoversUseCase {
  final AiCredentialStorage _credentials;
  final http.Client _client;

  ReadLeftoversUseCase(this._credentials, this._client);

  Future<AiSelection?> get selection => _credentials.readSelection();

  Future<Map<String, double>?> read(
    List<IntakeEntity> entries,
    MealPhoto leftovers, {
    MealPhoto? meal,
  }) async {
    final selection = await _credentials.readSelection();
    if (selection == null) return null;
    final photo = meal == null
        ? leftovers
        : await sideBySide(
            meal,
            leftovers,
            MealPhotoFormat.forProvider(selection.provider),
          );
    final result = await mealItemsApiFor(_client, selection).requestItems(
      content: MealPhotoContent(
        mediaType: photo.mediaType,
        base64Data: base64Encode(photo.bytes),
      ),
      system: leftoversSystemPrompt(entries, withMealPhoto: meal != null),
    );
    return leftoversFromItems(entries, result.items);
  }
}

/// [before] and [after] side by side in one image, since upstream's
/// clients carry one photo per request. Each is scaled to the same height,
/// so together they stay within the size one photo is sent at.
@visibleForTesting
Future<MealPhoto> sideBySide(
  MealPhoto before,
  MealPhoto after,
  MealPhotoFormat format,
) async {
  const height = 768;
  Future<ui.Image> decode(MealPhoto photo) async {
    final codec = await ui.instantiateImageCodec(
      photo.bytes,
      targetHeight: height,
    );
    return (await codec.getNextFrame()).image;
  }

  final left = await decode(before);
  final right = await decode(after);
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder)
    ..drawImage(left, ui.Offset.zero, ui.Paint())
    ..drawImage(right, ui.Offset(left.width.toDouble(), 0), ui.Paint());
  final image = await recorder.endRecording().toImage(
    left.width + right.width,
    height,
  );
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  final bytes = await FlutterImageCompress.compressWithList(
    png!.buffer.asUint8List(),
    minHeight: height,
    minWidth: left.width + right.width,
    quality: 80,
    format: format.compress,
  );
  return MealPhoto(bytes: bytes, mediaType: format.mediaType);
}

String _number(double value) => value == value.roundToDouble()
    ? '${value.toInt()}'
    : value.toStringAsFixed(1);
