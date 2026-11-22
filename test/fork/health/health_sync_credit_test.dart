import 'dart:ui' show SemanticsFlag;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/data/repository/health_import_repository.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/import_workouts_usecase.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/health_sync_screen.dart';

import '../../fixture/user_entity_fixtures.dart';
import '../../helpers/test_l10n.dart';
import '../../helpers/ux_checks.dart';

class _Settings extends Fake implements SettingsBloc {
  @override
  Future<void> setHealthImportEnabled(bool enabled) async {}

  @override
  Future<void> setHealthWorkoutKcalMultiplier(double multiplier) async {}
}

class _Config extends Fake implements GetConfigUsecase {
  ConfigEntity config;
  _Config(this.config);

  @override
  Future<ConfigEntity> getConfig() async => config;
}

class _Health extends Fake implements HealthImportRepository {
  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<double?> getLatestBodyFatPercent() async => null;
}

class _Import extends Fake implements ImportWorkoutsUsecase {}

class _User extends Fake implements GetUserUsecase {
  @override
  Future<UserEntity> getUserData() async =>
      UserEntityFixtures.youngSedentaryMaleWantingToMaintainWeight;
}

ConfigEntity _config({required bool on, double? multiplier}) => ConfigEntity(
  true,
  true,
  false,
  AppThemeEntity.system,
  healthImportEnabled: on,
  healthWorkoutKcalMultiplier: multiplier,
);

void main() {
  late _Config config;

  setUp(() {
    config = _Config(_config(on: false));
    locator.registerSingleton<SettingsBloc>(_Settings());
    locator.registerSingleton<GetConfigUsecase>(config);
    locator.registerSingleton<HealthImportRepository>(_Health());
    locator.registerSingleton<ImportWorkoutsUsecase>(_Import());
    locator.registerSingleton<GetUserUsecase>(_User());
  });

  tearDown(() => GetIt.instance.reset());

  const hint =
      'When you turn on Workouts in, OpenBite sets the credit from your '
      'height and weight.';

  testWidgets('before opt-in the credit says what turning it on does', (
    tester,
  ) async {
    await pumpOnPhone(tester, const HealthSyncScreen(), textScale: 1);
    await tester.pumpAndSettle();
    expect(find.text(hint), findsOneWidget);
  });

  testWidgets('no hint once a credit is stored, the opt-in keeps it', (
    tester,
  ) async {
    config.config = _config(on: false, multiplier: 0.8);
    await pumpOnPhone(tester, const HealthSyncScreen(), textScale: 1);
    await tester.pumpAndSettle();
    expect(find.text(hint), findsNothing);
  });

  testWidgets('the slider says its value once, with what it means', (
    tester,
  ) async {
    config.config = _config(on: true, multiplier: 1);
    final semantics = tester.ensureSemantics();
    await pumpOnPhone(tester, const HealthSyncScreen(), textScale: 1);
    await tester.pumpAndSettle();
    final node = find.semantics
        .byFlag(SemanticsFlag.isSlider)
        .evaluate()
        .single;
    expect(node.value, '100% of workout calories');
    expect(node.label, isEmpty);
    semantics.dispose();
  });

  testWidgets('Workouts in off says what stays, as the other cards do', (
    tester,
  ) async {
    config.config = _config(on: true, multiplier: 1);
    await pumpOnPhone(tester, const HealthSyncScreen(), textScale: 1);
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier('health-sync-auto-import'));
    await tester.pumpAndSettle();
    expect(
      find.text('Workout import off; imported workouts stay in the diary'),
      findsOneWidget,
    );
  });

  testWidgets('the info button opens Sources at the credit entry', (
    tester,
  ) async {
    await pumpOnPhone(tester, const HealthSyncScreen(), textScale: 1);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (w) =>
            w is Semantics && w.properties.identifier == 'health-sync-sources',
      ),
    );
    await tester.pumpAndSettle();
    final title = find.text(l10nEn.sourcesEnergyCompensationTitle);
    expect(title, findsOneWidget);
    final rect = tester.getRect(title);
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(rect.top, greaterThanOrEqualTo(kToolbarHeight));
    expect(rect.bottom, lessThanOrEqualTo(screen.height));
  });
}
