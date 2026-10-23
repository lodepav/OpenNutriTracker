import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:opennutritracker/core/data/repository/config_repository.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_gender_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_pal_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_macro_goal_usecase.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_ui.dart';
import 'package:opennutritracker/fork/adaptive/macro_program.dart';

Future<UserEntity> _user() async => UserEntity(
  birthday: DateTime(1990, 1, 1),
  heightCM: 180,
  weightKG: 80,
  gender: UserGenderEntity.male,
  goal: UserWeightGoalEntity.maintainWeight,
  pal: UserPALEntity.active,
);

class _Config extends Fake implements ConfigRepository {
  @override
  Future<ConfigEntity> getConfig() async =>
      const ConfigEntity(false, false, false, AppThemeEntity.system);
}

/// In memory, as real Hive hangs under `testWidgets`.
class _MemoryStore extends AdaptiveStore {
  AdaptiveSettings saved = const AdaptiveSettings();

  @override
  Future<void> save(AdaptiveSettings value) async {
    saved = value;
    AdaptiveStore.settings.value = value;
  }
}

void main() {
  void expectEnergy(FixedMacros m, double kcal) =>
      expect(m.kcal, closeTo(kcal, 0.001));

  group('the split', () {
    test('balanced: protein per kg, fat 30%, carbs the rest', () {
      final m = const MacroProgram().macrosFor(
        kcal: 2500,
        weightKg: 80,
        bodyFatPercent: 20,
      );
      expect(m.proteinG, closeTo(144, 0.001));
      expect(m.fatG, closeTo(2500 * 0.3 / 9, 0.001));
      expectEnergy(m, 2500);
    });

    test('lean mass takes weight less body fat', () {
      final m = const MacroProgram(
        proteinGPerKg: 2.2,
        leanMass: true,
      ).macrosFor(kcal: 2500, weightKg: 80, bodyFatPercent: 25);
      expect(m.proteinG, closeTo(2.2 * 60, 0.001));
    });

    test('low carb holds carbs at 25%, keto at 30 g', () {
      final low = const MacroProgram(
        style: MacroStyle.lowCarb,
      ).macrosFor(kcal: 2000, weightKg: 70, bodyFatPercent: 20);
      expect(low.carbsG, closeTo(125, 0.001));
      expectEnergy(low, 2000);

      final keto = const MacroProgram(
        style: MacroStyle.keto,
      ).macrosFor(kcal: 2000, weightKg: 70, bodyFatPercent: 20);
      expect(keto.carbsG, 30);
      expectEnergy(keto, 2000);
    });

    test('a weekday shift moves carbs and fat, not protein', () {
      const program = MacroProgram(style: MacroStyle.lowFat);
      final usual = program.macrosFor(
        kcal: 2200,
        weightKg: 80,
        bodyFatPercent: 20,
      );
      final up = program.macrosFor(
        kcal: 2600,
        weightKg: 80,
        bodyFatPercent: 20,
      );
      expect(up.proteinG, usual.proteinG);
      expect(up.carbsG, greaterThan(usual.carbsG));
      expect(up.fatG, greaterThan(usual.fatG));
    });

    test('a small target caps protein and never goes negative', () {
      final m = const MacroProgram(
        proteinGPerKg: 3,
      ).macrosFor(kcal: 800, weightKg: 120, bodyFatPercent: 30);
      expect(m.proteinG, closeTo(800 * 0.6 / 4, 0.001));
      expect(m.carbsG, greaterThanOrEqualTo(0));
      expect(m.fatG, greaterThanOrEqualTo(0));
      expectEnergy(m, 800);
    });
  });

  group('the goals', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('program');
      Hive.init(dir.path);
      AdaptiveStore.settings.value = const AdaptiveSettings();
    });

    tearDown(() async {
      AdaptiveStore.settings.value = const AdaptiveSettings();
      await Hive.deleteFromDisk();
      await dir.delete(recursive: true);
    });

    test("another profile's program reads its own user", () async {
      final other = AdaptiveStore.otherProfile(
        () => Hive.openBox<dynamic>('other'),
      );
      await other.save(
        const AdaptiveSettings(macroProgram: MacroProgram(proteinGPerKg: 2)),
      );
      final goals = GetMacroGoalUsecase(_Config(), other, _user);
      expect(await goals.getProteinsGoal(2400), closeTo(160, 0.001));
      expect(await goals.getFatsGoal(2400), closeTo(80, 0.001));
    });

    test('the fixed grams win over the program', () async {
      AdaptiveStore.settings.value = const AdaptiveSettings(
        fixedTarget: true,
        fixedMacros: FixedMacros(proteinG: 100, carbsG: 250, fatG: 100),
        macroProgram: MacroProgram(),
      );
      final goals = GetMacroGoalUsecase(_Config(), null, _user);
      expect(await goals.getProteinsGoal(2300), closeTo(100, 0.001));
    });

    test('the program round-trips with the settings', () {
      const settings = AdaptiveSettings(
        macroProgram: MacroProgram(
          style: MacroStyle.keto,
          proteinGPerKg: 2.4,
          leanMass: true,
        ),
      );
      expect(
        AdaptiveSettings.fromJson(settings.toJson()).toJson(),
        settings.toJson(),
      );
      expect(AdaptiveSettings.fromJson({}).macroProgram, isNull);
    });
  });

  testWidgets('the dialog turns a program on and off', (tester) async {
    final memory = _MemoryStore();
    AdaptiveStore.settings.value = const AdaptiveSettings();
    addTearDown(() => AdaptiveStore.settings.value = const AdaptiveSettings());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AdaptiveSettingsTile(store: memory)),
      ),
    );
    await tester.tap(find.byType(ListTile));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('macro-program')));
    expect(find.text('Percentages from your macro split'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('macro-program')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('macro-program-on')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('macro-style-keto')));
    await tester.tap(find.byKey(const ValueKey('macro-lean')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final program = memory.saved.macroProgram!;
    expect(program.style, MacroStyle.keto);
    expect(program.leanMass, isTrue);
    expect(program.proteinGPerKg, MacroProgram.defaultPerKgLean);
    expect(find.text('Keto, protein 2.2 g/kg of lean mass'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('macro-program')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('macro-program-on')));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(memory.saved.macroProgram, isNull);
  });
}
