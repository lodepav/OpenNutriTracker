import 'dart:convert';

import 'package:http/http.dart' as http;

/// What a recipe page says about itself in its schema.org Recipe data.
class LinkedRecipe {
  final String name;
  final List<String> ingredients;

  /// The servings the page states; null when it states none.
  final int? servings;

  const LinkedRecipe({
    required this.name,
    required this.ingredients,
    this.servings,
  });
}

/// The text is one web address and nothing else.
Uri? recipeLinkIn(String text) {
  final trimmed = text.trim();
  if (trimmed.contains(RegExp(r'\s'))) return null;
  final uri = Uri.tryParse(trimmed);
  return uri != null &&
          (uri.scheme == 'https' || uri.scheme == 'http') &&
          uri.host.isNotEmpty
      ? uri
      : null;
}

/// Reads a recipe page. Recipe sites publish a schema.org
/// Recipe for search engines; its ingredient lines are what bulk add reads,
/// so no model is needed and none of the page's other text goes anywhere.
/// Reviewed against aeobrien's "Phase 12", which instead sends the page's
/// stripped text to Claude: not ported.
class RecipeLinkReader {
  static const _timeout = Duration(seconds: 15);

  final http.Client _client;

  RecipeLinkReader(this._client);

  /// Null when the page has no recipe data; raises on a network failure.
  Future<LinkedRecipe?> read(Uri link) async {
    final response = await _client.get(link).timeout(_timeout);
    if (response.statusCode != 200) {
      throw http.ClientException('HTTP ${response.statusCode}', link);
    }
    return recipeFromHtml(response.body);
  }
}

/// The first schema.org Recipe in [html]'s JSON-LD blocks with ingredients.
LinkedRecipe? recipeFromHtml(String html) {
  final blocks = RegExp(
    r'''<script[^>]*type\s*=\s*["']application/ld\+json["'][^>]*>([\s\S]*?)</script>''',
    caseSensitive: false,
  ).allMatches(html);
  for (final block in blocks) {
    Object? json;
    try {
      json = jsonDecode(block[1]!);
    } on FormatException {
      continue;
    }
    final recipe = _findRecipe(json);
    if (recipe == null) continue;
    final ingredients = [
      for (final line in recipe['recipeIngredient'] as List? ?? const [])
        if (line is String && _clean(line).isNotEmpty) _clean(line),
    ];
    if (ingredients.isEmpty) continue;
    return LinkedRecipe(
      name: _clean('${recipe['name'] ?? ''}'),
      ingredients: ingredients,
      servings: _servings(recipe['recipeYield']),
    );
  }
  return null;
}

/// A Recipe node: the block itself, an item of a list, or of its @graph.
Map<String, dynamic>? _findRecipe(Object? json) {
  if (json is List) {
    for (final item in json) {
      if (_findRecipe(item) case final found?) return found;
    }
  }
  if (json is! Map<String, dynamic>) return null;
  final type = json['@type'];
  if (type == 'Recipe' || (type is List && type.contains('Recipe'))) {
    return json;
  }
  return _findRecipe(json['@graph']);
}

/// "4", 4, "Serves 4 people" or ["4", "4 servings"]: the first number.
int? _servings(Object? yield_) {
  final text = yield_ is List ? yield_.firstOrNull : yield_;
  final count = int.tryParse(
    RegExp(r'\d+').firstMatch('${text ?? ''}')?[0] ?? '',
  );
  return count != null && count > 0 && count <= 100 ? count : null;
}

/// Tags gone, the common entities decoded, whitespace collapsed.
String _clean(String text) => text
    .replaceAll(RegExp(r'<[^>]+>'), ' ')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&quot;', '"')
    .replaceAll(RegExp('&#0?39;|&apos;'), "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&amp;', '&')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
