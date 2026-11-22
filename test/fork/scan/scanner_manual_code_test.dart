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

// The scanner: a mistyped code stays in the dialog with the error under it,
// and the title fits its app bar at 200%.

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
      Builder(
        // A phone's 200% grows large text less than small (Android 14).
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const _Android200()),
          child: Navigator(
            // A page below, so the app bar has its back button as on a phone.
            initialRoute: '/scan',
            onGenerateRoute: (route) => route.name == '/'
                ? MaterialPageRoute(builder: (_) => const SizedBox())
                : MaterialPageRoute(
                    settings: RouteSettings(
                      arguments: ScannerScreenArguments(
                        DateTime(2026, 11, 21),
                        IntakeTypeEntity.lunch,
                      ),
                    ),
                    builder: (_) => const ScannerScreen(),
                  ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a mistyped code keeps the dialog and its digits', (
    tester,
  ) async {
    await pumpScanner(tester);
    await tester.tap(find.text('Type code manually'));
    await _settle(tester);

    // 4006381333931 is a valid EAN-13; its last digit changed.
    await tester.enterText(find.byType(TextField), '4006381333932');
    await tester.tap(find.bySemanticsIdentifier('scanner-manual-entry-submit'));
    await _settle(tester);

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('4006381333932'), findsOneWidget);
    const invalid =
        "That barcode doesn't look valid. Please check the digits and try again.";
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(invalid),
      ),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsNothing);
    expect(cutText(tester), isNot(contains(invalid)));

    // Fixing the digits clears the error.
    await tester.enterText(find.byType(TextField), '400638133393');
    await tester.pump();
    expect(find.text(invalid), findsNothing);

    // A valid code closes the dialog and goes to the lookup.
    await tester.enterText(find.byType(TextField), '4006381333931');
    await tester.tap(find.bySemanticsIdentifier('scanner-manual-entry-submit'));
    await _settle(tester);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('the title fits its app bar at 200%', (tester) async {
    await pumpScanner(tester);
    final bar = tester.getRect(find.byType(AppBar));
    final title = tester.getRect(find.text('Scan product'));
    expect(title.top, greaterThanOrEqualTo(bar.top));
    expect(title.bottom, lessThanOrEqualTo(bar.bottom));
    expect(cutText(tester), isNot(contains('Scan product')));
  });
}

/// The camera's progress ring never settles, so step past the dialog's
/// transitions instead.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Android 14's font scale table at 200%, as Flutter applies it on a phone.
class _Android200 extends TextScaler {
  const _Android200();

  static const _sp = [8.0, 10, 12, 14, 18, 20, 24, 30, 100];
  static const _dp = [16.0, 20, 24, 28, 36, 40, 48, 60, 100];

  @override
  double scale(double fontSize) {
    if (fontSize <= _sp.first) return fontSize * 2;
    for (var i = 1; i < _sp.length; i++) {
      if (fontSize <= _sp[i]) {
        final t = (fontSize - _sp[i - 1]) / (_sp[i] - _sp[i - 1]);
        return _dp[i - 1] + t * (_dp[i] - _dp[i - 1]);
      }
    }
    return fontSize;
  }

  @override
  double get textScaleFactor => 2;
}
