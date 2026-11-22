import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/features/scanner/domain/usecase/search_product_by_barcode_usecase.dart';
import 'package:opennutritracker/features/scanner/presentation/scanner_bloc.dart';
import 'package:opennutritracker/features/scanner/scanner_screen.dart';

import '../../helpers/test_l10n.dart';
import '../../helpers/ux_checks.dart';

// The product scanner with the camera refused shows the fork's message and
// a way around, the code typed in, not the package's black box.

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

  setUp(() async {
    await getIt.reset();
    getIt.registerFactory<ScannerBloc>(
      () => ScannerBloc(_NoLookup(), _Config()),
    );
    getIt.registerSingleton<GetConfigUsecase>(_Config());
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

  testWidgets('a refused camera says so and offers the typed code', (
    tester,
  ) async {
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
      textScale: 1,
    );
    await tester.pumpAndSettle();
    expect(find.text('Camera access is off'), findsOneWidget);

    await tester.tap(find.text('Paste a code instead'));
    await tester.pumpAndSettle();
    expect(find.text(l10nEn.scannerManualEntryDialogTitle), findsOneWidget);
  });
}
