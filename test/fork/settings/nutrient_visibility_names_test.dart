// The Nutrients (visibility) screen names nutrients in sentence case, spelled
// as the goals editor spells them (the 2026-11-21 G6 critique, nv0.png).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/nutrient_visibility_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';

class _GetConfig extends Fake implements GetConfigUsecase {
  @override
  Future<ConfigEntity> getConfig() async =>
      const ConfigEntity(false, false, false, AppThemeEntity.system);
}

void main() {
  setUp(() => locator.registerSingleton<GetConfigUsecase>(_GetConfig()));
  tearDown(() async => locator.reset());

  testWidgets('names are in sentence case, as the goals editor spells them', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [S.delegate],
        supportedLocales: S.supportedLocales,
        home: const NutrientVisibilityScreen(),
      ),
    );
    await tester.pumpAndSettle();

    for (final name in [
      'Fibre',
      'Sodium',
      'Saturated fat',
      'Sugars',
      'Calcium',
      'Potassium',
      'Vitamin D',
      'Vitamin B12',
      'Magnesium',
    ]) {
      expect(
        find.text(name, skipOffstage: false),
        findsOneWidget,
        reason: name,
      );
    }
    expect(find.text('fiber', skipOffstage: false), findsNothing);
    expect(find.text('sugar', skipOffstage: false), findsNothing);
  });
}
