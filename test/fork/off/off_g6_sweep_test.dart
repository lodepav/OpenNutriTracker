// The Open Food Facts account and review dialogs after the G6 critique and
// audit (2026-11-21/22): the account fields wait for the switch, sit apart
// and link to sign-up; the review's "Per 100 g" is a heading and the label
// photo is decoded at its shown size.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/fork/off/off_contribution.dart';
import 'package:opennutritracker/fork/off/off_contribution_ui.dart';

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
  late OffAccountStore store;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    store = OffAccountStore(const FlutterSecureStorage());
  });

  Future<void> openAccount(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: OffAccountTile(store: store))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fork-off-account')));
    await tester.pumpAndSettle();
  }

  bool enabled(WidgetTester tester, String key) =>
      tester.widget<TextField>(find.byKey(Key(key))).enabled ?? true;

  testWidgets('the account fields wait for "Offer to add my foods"', (
    tester,
  ) async {
    await openAccount(tester);
    expect(enabled(tester, 'fork-off-user'), isFalse);
    expect(enabled(tester, 'fork-off-password'), isFalse);

    await tester.tap(find.text('Offer to add my foods'));
    await tester.pump();
    expect(enabled(tester, 'fork-off-user'), isTrue);
    expect(enabled(tester, 'fork-off-password'), isTrue);
  });

  testWidgets('the two fields sit apart and sign-up is a tap away', (
    tester,
  ) async {
    await openAccount(tester);
    final user = tester.getRect(find.byKey(const Key('fork-off-user')));
    final password = tester.getRect(
      find.byKey(const Key('fork-off-password')),
    );
    expect(password.top - user.bottom, greaterThanOrEqualTo(8));
    expect(
      find.widgetWithText(TextButton, 'Create an account'),
      findsOneWidget,
    );
  });

  Future<void> offer(WidgetTester tester) async {
    await store.save(
      const OffAccount(enabled: true, userId: 'me', password: 'pw'),
    );
    final client = OffContributionClient(
      MockClient(
        (request) async => http.Response(jsonEncode({'product': {}}), 200),
      ),
      version: () async => '1.0',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => offerOffUpload(
                context,
                _crispbread(),
                labelPhoto: _photo,
                store: store,
                client: client,
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

  testWidgets('"Per 100 g" is a heading', (tester) async {
    await offer(tester);
    expect(
      tester.getSemantics(find.text('Per 100 g')),
      matchesSemantics(label: 'Per 100 g', isHeader: true),
    );
  });

  testWidgets('the label photo is decoded at its shown size', (tester) async {
    await offer(tester);
    final image = tester.widget<Image>(
      find.descendant(
        of: find.byKey(const Key('fork-off-photo')),
        matching: find.byType(Image),
      ),
    );
    final provider = image.image;
    expect(provider, isA<ResizeImage>());
    expect((provider as ResizeImage).width, 56 * tester.view.devicePixelRatio);
  });
}
