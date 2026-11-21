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

import '../../helpers/ux_checks.dart';

// The scanner's torch and camera buttons say what they do, the preview shows
// it is starting, and "Type code manually" keeps off its outline at 200%.

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

  Future<void> pumpScanner(WidgetTester tester) async {
    await pumpOnPhone(
      tester,
      Navigator(
        onGenerateRoute: (_) => MaterialPageRoute(
          settings: RouteSettings(
            arguments: ScannerScreenArguments(
              DateTime(2026, 11, 21),
              IntakeTypeEntity.lunch,
            ),
          ),
          builder: (_) => const ScannerScreen(),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('torch and camera buttons have tooltips', (tester) async {
    await pumpScanner(tester);
    // The test has no camera, so its torch reads as off.
    expect(find.byTooltip('Turn on torch'), findsOneWidget);
    expect(find.byTooltip('Switch camera'), findsOneWidget);
  });

  testWidgets('the preview shows progress until the camera starts', (
    tester,
  ) async {
    await pumpScanner(tester);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('"Type code manually" keeps off its outline', (tester) async {
    await pumpScanner(tester);
    final button = tester.getRect(find.byType(OutlinedButton));
    final label = tester.getRect(find.text('Type code manually'));
    final icon = tester.getRect(find.byIcon(Icons.keyboard_rounded));
    expect(icon.left - button.left, greaterThanOrEqualTo(12));
    expect(button.right - label.right, greaterThanOrEqualTo(12));
  });
}
