// Settings depth after the G6 rounds (2026-11-22): units spaced in the
// nutrient editor's help (S586), Search sources titled as its row (S587)
// with "About them" on its own line, and a workout import that fails
// for a reason other than a refusal says so (S584).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/data/repository/health_import_repository.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/import_workouts_usecase.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/food_sources_screen.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/health_sync_screen.dart';
import 'package:opennutritracker/fork/settings/unit_spacing.dart';
import 'package:opennutritracker/generated/l10n.dart';

import '../../fixture/user_entity_fixtures.dart';

class _GetConfig extends Fake implements GetConfigUsecase {
  ConfigEntity config = const ConfigEntity(
    true,
    true,
    false,
    AppThemeEntity.system,
  );

  @override
  Future<ConfigEntity> getConfig() async => config;
}

class _AddConfig extends Fake implements AddConfigUsecase {}

class _Settings extends Fake implements SettingsBloc {}

class _Health extends Fake implements HealthImportRepository {
  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<double?> getLatestBodyFatPercent() async => null;
}

class _FailingImport extends Fake implements ImportWorkoutsUsecase {
  @override
  Future<int> importNow() async => throw StateError('platform said no');
}

class _User extends Fake implements GetUserUsecase {
  @override
  Future<UserEntity> getUserData() async =>
      UserEntityFixtures.youngSedentaryMaleWantingToMaintainWeight;
}

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: const [S.delegate],
  supportedLocales: S.supportedLocales,
  home: child,
);

void main() {
  late _GetConfig config;

  setUp(() {
    config = _GetConfig();
    locator
      ..registerSingleton<GetConfigUsecase>(config)
      ..registerSingleton<AddConfigUsecase>(_AddConfig());
  });

  tearDown(() => GetIt.instance.reset());

  test('units in the help text stand a space off the number', () {
    expect(
      spaceUnits('Default varies by age and gender (21g to 38g).'),
      'Default varies by age and gender (21 g to 38 g).',
    );
    expect(
      spaceUnits('Default reference is 1000mg.'),
      'Default reference is 1000 mg.',
    );
    expect(spaceUnits('8mg male, 18mg female'), '8 mg male, 18 mg female');
    // Already spaced, or a unit with no number, stays as it is
    expect(spaceUnits('Daily target in mg: 20 g'), 'Daily target in mg: 20 g');
  });

  testWidgets('Search sources is titled as the row that opens it, and '
      '"About them" sits above its links', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_wrap(const FoodSourcesScreen()));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Search sources'),
      ),
      findsOneWidget,
    );
    final label = tester.getRect(find.text('About them'));
    final links = find.descendant(
      of: find.byType(Wrap),
      matching: find.byType(TextButton),
    );
    expect(links, findsWidgets);
    expect(label.bottom, lessThanOrEqualTo(tester.getRect(links.first).top));
    expect(tester.getRect(links.first).left, lessThanOrEqualTo(label.left));
  });

  testWidgets('a workout import that throws says it could not read, not '
      'that permission was refused', (tester) async {
    config.config = const ConfigEntity(
      true,
      true,
      false,
      AppThemeEntity.system,
      healthImportEnabled: true,
    );
    locator
      ..registerSingleton<SettingsBloc>(_Settings())
      ..registerSingleton<HealthImportRepository>(_Health())
      ..registerSingleton<ImportWorkoutsUsecase>(_FailingImport())
      ..registerSingleton<GetUserUsecase>(_User());
    await tester.binding.setSurfaceSize(const Size(400, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_wrap(const HealthSyncScreen()));
    await tester.pumpAndSettle();

    final now = find.bySemanticsIdentifier('health-sync-import-now');
    await tester.ensureVisible(now);
    await tester.pumpAndSettle();
    await tester.tap(now);
    await tester.pumpAndSettle();

    expect(
      find.text('Could not read workouts from $healthPlatformName'),
      findsOneWidget,
    );
  });
}
