import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/home/domain/entity/shared_meal_payload.dart';
import 'package:opennutritracker/features/scanner/presentation/scanner_bloc.dart';
import 'package:opennutritracker/features/scanner/scanner_screen.dart';
import 'package:opennutritracker/fork/basket/basket.dart';
import 'package:opennutritracker/generated/l10n.dart';

class _Bloc extends Fake implements ScannerBloc {
  @override
  Stream<ScannerState> get stream => const Stream.empty();
  @override
  ScannerState get state => ScannerInitial();
  @override
  Future<void> close() async {}
}

/// A shared meal's code logs it on import, which choosing foods must not.
void main() {
  final code = const SharedMealPayload(
    version: 2,
    offRefs: [SharedMealOffRef(barcode: '1', amount: 100, unit: 'g')],
    items: [],
    recipes: [],
  ).toJsonString();

  setUp(() => GetIt.instance.registerFactory<ScannerBloc>(_Bloc.new));
  tearDown(() async {
    FoodBasket.instance.planning = null;
    await GetIt.instance.reset();
  });

  Future<List<String>> scan(WidgetTester tester) async {
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [S.delegate],
        supportedLocales: S.supportedLocales,
        onGenerateRoute: (settings) {
          if (settings.name != '/') opened.add(settings.name!);
          return MaterialPageRoute<void>(
            settings: settings.name == '/'
                ? RouteSettings(
                    arguments: ScannerScreenArguments(
                      DateTime(2026, 11, 3),
                      IntakeTypeEntity.lunch,
                    ),
                  )
                : settings,
            builder: (_) => settings.name == '/'
                ? const ScannerScreen()
                : const SizedBox.shrink(),
          );
        },
      ),
    );
    await tester.pump();
    tester.widget<MobileScanner>(find.byType(MobileScanner)).onDetect!(
      BarcodeCapture(barcodes: [Barcode(rawValue: code)]),
    );
    await tester.pump();
    await tester.pump();
    return opened;
  }

  testWidgets('imports it normally', (tester) async {
    expect(await scan(tester), [NavigationOptions.importMealScannerRoute]);
  });

  testWidgets('not while planning', (tester) async {
    FoodBasket.instance.planning = PlanMode.once;
    expect(await scan(tester), isEmpty);
  });
}
