import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/fork/off/off_contribution.dart';
import 'package:opennutritracker/fork/off/off_contribution_ui.dart';

// A 1×1 PNG, which Image.memory can decode in a test.
final _photo = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

MealEntity _crispbread() => MealEntity(
  code: '6410500090014',
  name: 'Rye crispbread',
  brands: 'Finn Crisp',
  url: null,
  mealQuantity: null,
  mealUnit: 'g',
  servingQuantity: null,
  servingUnit: 'g',
  servingSize: null,
  nutriments: MealNutrimentsEntity(
    energyKcal100: 350,
    carbohydrates100: 58,
    fat100: 2.5,
    proteins100: 11,
    sugars100: null,
    saturatedFat100: null,
    fiber100: null,
  ),
  source: MealSourceEntity.custom,
);

void main() {
  late List<http.BaseRequest> sent;
  late OffAccountStore store;

  setUp(() async {
    sent = [];
    FlutterSecureStorage.setMockInitialValues({});
    store = OffAccountStore(const FlutterSecureStorage());
    await store.save(
      const OffAccount(enabled: true, userId: 'me', password: 'pw'),
    );
  });

  OffContributionClient client(Map<String, Object?> there) =>
      OffContributionClient(
        MockClient((request) async {
          sent.add(request);
          if (request.method == 'GET') {
            return http.Response(jsonEncode({'product': there}), 200);
          }
          return http.Response(
            jsonEncode(
              request.url.path.contains('image')
                  ? {'status': 'status ok'}
                  : {'status': 1},
            ),
            200,
          );
        }),
        version: () async => '1.0',
      );

  Future<void> offer(
    WidgetTester tester,
    OffContributionClient offClient, {
    Uint8List? photo,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => offerOffUpload(
                context,
                _crispbread(),
                labelPhoto: photo,
                store: store,
                client: offClient,
              ),
              child: const Text('saved'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('saved'));
    await tester.pumpAndSettle();
  }

  testWidgets('only what OFF lacks is offered, and it goes up as edited', (
    tester,
  ) async {
    await offer(
      tester,
      client({'product_name': 'Rye crispbread', 'brands': 'Finn Crisp'}),
    );

    expect(find.byKey(const Key('fork-off-name')), findsNothing);
    await tester.enterText(find.byKey(const Key('fork-off-fat')), '2,6');
    await tester.enterText(find.byKey(const Key('fork-off-proteins')), '');
    await tester.tap(find.byKey(const Key('fork-off-send')));
    await tester.pumpAndSettle();

    final post = sent.last as http.Request;
    expect(post.bodyFields['nutriment_fat'], '2.6');
    expect(post.bodyFields['nutriment_energy-kcal'], '350');
    expect(post.bodyFields.containsKey('nutriment_proteins'), isFalse);
    expect(post.bodyFields.containsKey('product_name'), isFalse);
    expect(find.text('Added to Open Food Facts. Thank you!'), findsOneWidget);
  });

  testWidgets('the label photo is sent only when kept ticked', (tester) async {
    final full = {
      'product_name': 'Rye crispbread',
      'brands': 'Finn Crisp',
      'nutriments': {'fat_100g': 2.5},
    };
    await offer(tester, client(full), photo: _photo);
    expect(find.byKey(const Key('fork-off-photo')), findsOneWidget);
    await tester.tap(find.byKey(const Key('fork-off-photo')));
    await tester.tap(find.byKey(const Key('fork-off-send')));
    await tester.pumpAndSettle();
    expect(sent.where((r) => r.method == 'POST'), isEmpty);

    sent.clear();
    await offer(tester, client(full), photo: _photo);
    await tester.tap(find.byKey(const Key('fork-off-send')));
    await tester.pumpAndSettle();
    expect(sent.map((r) => r.url.path), [
      '/api/v2/product/6410500090014',
      '/cgi/product_image_upload.pl',
    ]);
  });

  testWidgets('nothing is offered when OFF has it all', (tester) async {
    await offer(
      tester,
      client({
        'product_name': 'Rye crispbread',
        'brands': 'Finn Crisp',
        'nutriments': {'fat_100g': 2.5},
        'image_nutrition_url': 'https://images/x.jpg',
      }),
      photo: _photo,
    );
    expect(find.byKey(const Key('fork-off-send')), findsNothing);
    expect(
      find.text('Open Food Facts already has this product'),
      findsOneWidget,
    );
  });
}
