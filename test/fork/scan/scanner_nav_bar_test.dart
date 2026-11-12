import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/features/scanner/domain/usecase/search_product_by_barcode_usecase.dart';
import 'package:opennutritracker/features/scanner/presentation/scanner_bloc.dart';
import 'package:opennutritracker/features/scanner/scanner_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';

// S217: the app draws edge to edge, so the scanner's manual-entry button has
// to clear the system navigation bar itself.

class _NoLookup implements SearchProductByBarcodeUseCase {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _Config implements GetConfigUsecase {
  @override
  Future<ConfigEntity> getConfig() async =>
      const ConfigEntity(true, true, false, AppThemeEntity.system);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  final getIt = GetIt.instance;

  setUp(() async {
    await getIt.reset();
    getIt.registerFactory<ScannerBloc>(
      () => ScannerBloc(_NoLookup(), _Config()),
    );
    getIt.registerSingleton<GetConfigUsecase>(_Config());
  });

  tearDown(() => getIt.reset());

  testWidgets('the manual entry button sits above the navigation bar', (
    tester,
  ) async {
    const navBar = 48.0;
    const height = 800.0;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, height);
    tester.view.padding = const FakeViewPadding(bottom: navBar);
    tester.view.viewPadding = const FakeViewPadding(bottom: navBar);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [S.delegate],
        supportedLocales: S.supportedLocales,
        onGenerateRoute: (_) => MaterialPageRoute(
          settings: RouteSettings(
            arguments: ScannerScreenArguments(
              DateTime(2026, 11, 12),
              IntakeTypeEntity.lunch,
            ),
          ),
          builder: (_) => const ScannerScreen(),
        ),
      ),
    );
    await tester.pump();

    final button = find.byType(OutlinedButton);
    expect(button, findsOneWidget);
    expect(tester.getBottomLeft(button).dy, lessThanOrEqualTo(height - navBar));
  });
}
