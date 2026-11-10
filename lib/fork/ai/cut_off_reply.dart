import 'dart:convert';

import 'package:opennutritracker/features/add_meal/domain/meal_items_api.dart';

/// Throws when [choice] stopped at the output limit (`finish_reason:
/// "length"`) without a whole meal in it (S209, D43).
///
/// Gemini thinks inside `max_tokens`, and at 1,024 tokens Gemini 3.8 Flash
/// ran out before its tool call on 25 of 67 photos. Google's reply then
/// carries no tool call, which the client read as a model that will not call
/// the tool: `unsupported`, the one failure that hides the camera and fails
/// the setup check for good (#782). A cut-off reply says nothing about what
/// the model can do, so it is `transient`, retryable, as a reply that did not
/// parse is. A tool call that is there and holds items is kept: it was
/// finished before the limit.
void throwIfCutOff(Map<dynamic, dynamic> choice) {
  if (choice['finish_reason'] != 'length') return;
  if (_holdsItems(choice['message'])) return;
  throw const MealInterpreterException('reply cut off at the output limit');
}

bool _holdsItems(Object? message) {
  final calls = message is Map ? message['tool_calls'] : null;
  if (calls is! List) return false;
  for (final call in calls) {
    final function = call is Map ? call['function'] : null;
    if (function is! Map || function['name'] != mealItemsToolName) continue;
    Object? arguments = function['arguments'];
    if (arguments is String) {
      try {
        arguments = jsonDecode(arguments);
      } catch (_) {
        return false;
      }
    }
    final items = arguments is Map ? arguments['items'] : null;
    return items is List && items.isNotEmpty;
  }
  return false;
}
