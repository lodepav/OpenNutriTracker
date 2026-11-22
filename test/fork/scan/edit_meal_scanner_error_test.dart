import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/data/data_source/custom_meal_data_source.dart';
import 'package:opennutritracker/core/data/repository/config_repository.dart';
import 'package:opennutritracker/core/data/repository/favourite_meal_repository.dart';
import 'package:opennutritracker/core/data/repository/intake_repository.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/edit_meal/presentation/bloc/edit_meal_bloc.dart';
import 'package:opennutritracker/features/edit_meal/presentation/edit_meal_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

// Seam S520: Edit meal's barcode scanner with the camera refused shows the
// fork's message, and its way around leads back to the typed code field.

class _Config extends Fake implements GetConfigUsecase {
  @override
  Future<ConfigEntity> getConfig() async =>
      const ConfigEntity(true, true, false, AppThemeEntity.system);
}

class _ConfigRepository extends Fake implements ConfigRepository {
  @override
  Future<String?> getCustomMealFormMode() async =>
      CustomMealFormMode.simple.name;
}

class _Library extends Fake implements CustomMealDataSource {}

class _Favourites extends Fake implements FavouriteMealRepository {}

class _Intakes extends Fake implements IntakeRepository {}

const _channel = MethodChannel('dev.steenbakker.mobile_scanner/scanner/method');
// The scanner's streams cancel after a test ends, so they stay answered.
const _streams = [
  MethodChannel('dev.steenbakker.mobile_scanner/scanner/event'),
  MethodChannel('dev.steenbakker.mobile_scanner/scanner/deviceOrientation'),
];

void main() {
  final getIt = GetIt.instance;
  TestDefaultBinaryMessenger messenger() =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    getIt.registerFactory<EditMealBloc>(
      () => EditMealBloc(
        _Config(),
        _Library(),
        _ConfigRepository(),
        _Favourites(),
        _Intakes(),
      ),
    );
    for (final stream in _streams) {
      messenger().setMockMethodCallHandler(stream, (_) async => null);
    }
    // The camera is refused: denied state, and asking again is refused too.
    messenger().setMockMethodCallHandler(_channel, (call) async {
      if (call.method == 'state') return 2;
      if (call.method == 'request') return false;
      return null;
    });
  });

  tearDown(() async {
    for (final stream in _streams) {
      messenger().setMockMethodCallHandler(stream, null);
    }
    messenger().setMockMethodCallHandler(_channel, null);
    await getIt.reset();
  });

  testWidgets('a refused camera says so and leads back to the code field', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<EnergyUnitProvider>(
        create: (_) => EnergyUnitProvider(),
        child: MaterialApp(
          localizationsDelegates: const [S.delegate],
          supportedLocales: S.supportedLocales,
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            settings: RouteSettings(
              arguments: EditMealScreenArguments(
                DateTime(2026, 11, 21),
                MealEntity.empty(),
                IntakeTypeEntity.lunch,
                false,
              ),
            ),
            builder: (_) => const EditMealScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scan = find.byTooltip('Scan barcode');
    await tester.ensureVisible(scan);
    await tester.tap(scan);
    await tester.pumpAndSettle();
    expect(find.text('Camera access is off'), findsOneWidget);

    await tester.tap(find.text('Paste a code instead'));
    await tester.pumpAndSettle();
    expect(find.text('Camera access is off'), findsNothing);
    expect(find.text('New custom food'), findsOneWidget);
  });
}
