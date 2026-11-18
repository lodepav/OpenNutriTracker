// S223: the Add food screen's search field has one magnifier, the button
// beside it; elsewhere the field keeps its own.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/presentation/widgets/meal_search_bar.dart';
import 'package:opennutritracker/generated/l10n.dart';

Future<void> _pump(WidgetTester tester, {bool? showSearchIcon}) =>
    tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: S.supportedLocales,
        home: Scaffold(
          body: showSearchIcon == null
              ? MealSearchBar(
                  searchStringListener: ValueNotifier(''),
                  onSearchSubmit: (_) {},
                  onBarcodePressed: () {},
                )
              : MealSearchBar(
                  searchStringListener: ValueNotifier(''),
                  onSearchSubmit: (_) {},
                  onBarcodePressed: () {},
                  showSearchIcon: showSearchIcon,
                ),
        ),
      ),
    );

void main() {
  testWidgets('by default the field keeps its magnifier', (tester) async {
    await _pump(tester);
    expect(find.byIcon(Icons.search_rounded), findsNWidgets(2));
  });

  testWidgets('off, only the search button shows one', (tester) async {
    await _pump(tester, showSearchIcon: false);
    expect(find.byIcon(Icons.search_rounded), findsOneWidget);
  });
}
