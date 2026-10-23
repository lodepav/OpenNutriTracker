import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/fork/off/off_contribution.dart';

MealEntity _crispbread() => MealEntity(
  code: '6410500090014',
  name: 'Rye crispbread',
  brands: 'Finn Crisp',
  url: null,
  mealQuantity: null,
  mealUnit: 'g',
  servingQuantity: 10,
  servingUnit: 'g',
  servingSize: null,
  nutriments: MealNutrimentsEntity(
    energyKcal100: 350,
    carbohydrates100: 58,
    fat100: 2.5,
    proteins100: 11,
    sugars100: null,
    saturatedFat100: null,
    fiber100: 19,
    sodium100: 480,
  ),
  source: MealSourceEntity.custom,
);

const _account = OffAccount(enabled: true, userId: 'me', password: 'pw');

void main() {
  test('a custom food goes up per 100 g, sodium as salt, blanks left out', () {
    final fields = OffUpload.fromMeal(_crispbread()).fields;

    expect(fields['code'], '6410500090014');
    expect(fields['product_name'], 'Rye crispbread');
    expect(fields['brands'], 'Finn Crisp');
    expect(fields['nutrition_data_per'], '100g');
    expect(fields['nutriment_energy-kcal'], '350');
    expect(fields['nutriment_fat'], '2.5');
    expect(fields['nutriment_salt'], '1.2');
    expect(fields['nutriment_salt_unit'], 'g');
    expect(fields.containsKey('nutriment_sugars'), isFalse);
  });

  test('only what Open Food Facts lacks is sent', () {
    final upload = OffUpload.fromMeal(_crispbread());

    final nameOnly = upload.without(
      const OffProduct(hasBrand: true, hasNutrients: true),
    );
    expect(nameOnly.fields.keys, ['code', 'product_name']);
    expect(
      upload
          .without(
            const OffProduct(hasName: true, hasBrand: true, hasNutrients: true),
          )
          .isEmpty,
      isTrue,
    );
  });

  test('the client reads what is there and writes as the user', () async {
    final requests = <http.Request>[];
    final client = OffContributionClient(
      MockClient((request) async {
        requests.add(request);
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'product': {
                'product_name': 'Rye crispbread',
                'brands': '',
                'nutriments': {'fat_100g': 2.5},
              },
            }),
            200,
          );
        }
        return http.Response(jsonEncode({'status': 1}), 200);
      }),
      version: () async => '1.0',
    );

    final there = await client.product(_account, '6410500090014');
    expect(there.hasName, isTrue);
    expect(there.hasBrand, isFalse);
    expect(there.hasNutrients, isTrue);

    await client.upload(
      _account,
      OffUpload.fromMeal(_crispbread()).without(there),
    );
    final post = requests.last;
    expect(post.url.host, 'world.openfoodfacts.net');
    expect(post.headers['Authorization'], startsWith('Basic '));
    expect(post.headers['User-Agent'], startsWith('OpenBite - '));
    expect(post.headers['User-Agent'], contains('Version 1.0'));
    expect(post.bodyFields, {
      'user_id': 'me',
      'password': 'pw',
      'code': '6410500090014',
      'brands': 'Finn Crisp',
    });
  });

  test('an unknown product has nothing; a refusal raises', () async {
    final client = OffContributionClient(
      MockClient(
        (request) async => request.method == 'GET'
            ? http.Response('{}', 404)
            : http.Response(jsonEncode({'status': 0}), 200),
      ),
      version: () async => '1.0',
    );
    final real = const OffAccount(
      enabled: true,
      userId: 'me',
      password: 'pw',
      useTestServer: false,
    );

    expect((await client.product(real, '1')).hasNutrients, isFalse);
    await expectLater(
      client.upload(real, OffUpload.fromMeal(_crispbread())),
      throwsA(
        isA<OffContributionException>().having(
          (e) => e.failure,
          'failure',
          OffFailure.rejected,
        ),
      ),
    );
  });

  test('the label photo goes up as the nutrition picture', () async {
    late http.Request sent;
    final client = OffContributionClient(
      MockClient((request) async {
        sent = request;
        return http.Response(jsonEncode({'status': 'status ok'}), 200);
      }),
      version: () async => '1.0',
    );

    await client.uploadNutritionPhoto(
      _account,
      '6410500090014',
      Uint8List.fromList([0xFF, 0xD8, 0xFF]),
      language: 'lv',
    );

    expect(sent.url.path, '/cgi/product_image_upload.pl');
    expect(sent.headers['Content-Type'], startsWith('multipart/form-data'));
    final body = latin1.decode(sent.bodyBytes);
    expect(body, contains('name="imagefield"\r\n\r\nnutrition_lv'));
    expect(body, contains('name="imgupload_nutrition_lv"'));
    expect(body, contains('name="user_id"\r\n\r\nme'));
  });
}
