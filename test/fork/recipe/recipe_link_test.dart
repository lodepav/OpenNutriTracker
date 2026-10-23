import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:opennutritracker/fork/recipe/recipe_link.dart';

const _page = '''
<html><head>
<script type="application/ld+json">{"@type": "WebSite", "name": "Cooking"}</script>
<script type="application/ld+json">
{"@context": "https://schema.org", "@graph": [
  {"@type": "BreadcrumbList"},
  {"@type": ["Recipe", "NewsArticle"], "name": "Mac &amp; cheese",
   "recipeYield": ["4", "4 servings"],
   "recipeIngredient": ["250 g macaroni", " 2 cups <b>milk</b> ", "",
     "100 g cheddar, grated"]}
]}
</script></head><body>Comments, ads, a life story.</body></html>
''';

void main() {
  test('a link is one web address and nothing else', () {
    expect(recipeLinkIn(' https://example.com/r/1 ')?.host, 'example.com');
    expect(recipeLinkIn('see https://example.com/r/1'), isNull);
    expect(recipeLinkIn('200 g rice'), isNull);
    expect(recipeLinkIn('ftp://example.com'), isNull);
  });

  test('reads name, lines and servings from the page\'s Recipe data', () {
    final recipe = recipeFromHtml(_page)!;

    expect(recipe.name, 'Mac & cheese');
    expect(recipe.ingredients, [
      '250 g macaroni',
      '2 cups milk',
      '100 g cheddar, grated',
    ]);
    expect(recipe.servings, 4);
  });

  test('a page without Recipe data, or with broken JSON, gives null', () {
    expect(recipeFromHtml('<html>no data</html>'), isNull);
    expect(
      recipeFromHtml(
        '<script type="application/ld+json">{"@type": "Recipe",</script>',
      ),
      isNull,
    );
  });

  test('fetches the page; a failed request raises', () async {
    final reader = RecipeLinkReader(
      MockClient(
        (request) async => request.url.path == '/ok'
            ? http.Response(_page, 200)
            : http.Response('', 404),
      ),
    );

    expect(
      (await reader.read(Uri.parse('https://example.com/ok')))?.servings,
      4,
    );
    expect(
      reader.read(Uri.parse('https://example.com/gone')),
      throwsA(isA<http.ClientException>()),
    );
  });
}
