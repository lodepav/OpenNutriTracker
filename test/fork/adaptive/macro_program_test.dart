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
import 'package:opennutritracker/fork/adaptive/macro_program_ui.dart';
import 'package:opennutritracker/fork/adaptive/onboarding_macros.dart';

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
    test('fat per kg: protein, then fat, per kg; carbs the rest', () {
      final m = const MacroProgram().macrosFor(
        kcal: 2500,
        weightKg: 80,
        bodyFatPercent: 20,
      );
      expect(m.proteinG, closeTo(1.6 * 80, 0.001));
      expect(m.fatG, closeTo(0.8 * 80, 0.001));
      expectEnergy(m, 2500);
    });

    test('fat per kg goes only as far as the energy left after protein', () {
      final m = const MacroProgram(
        proteinGPerKg: 2.4,
        fatGPerKg: 1.0,
      ).macrosFor(kcal: 1500, weightKg: 100, bodyFatPercent: 30);
      // Protein is held to 60% of 1,500 kcal: 225 g, 900 kcal.
      expect(m.proteinG, closeTo(225, 0.001));
      expect(m.fatG, closeTo(600 / 9, 0.001));
      expect(m.carbsG, closeTo(0, 0.001));
      expectEnergy(m, 1500);
    });

    test('an older program reads with fat per kg at its default', () {
      final old = MacroProgram.fromJson(const {
        'style': 'balanced',
        'proteinGPerKg': 1.8,
        'leanMass': false,
      });
      expect(old.style, MacroStyle.balanced);
      expect(old.fatGPerKg, MacroProgram.defaultFatPerKg);
    });

    test('balanced: protein per kg, fat 30%, carbs the rest', () {
      final m = const MacroProgram(
        style: MacroStyle.balanced,
        proteinGPerKg: 1.8,
      ).macrosFor(kcal: 2500, weightKg: 80, bodyFatPercent: 20);
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
      expect(await goals.getFatsGoal(2400), closeTo(0.8 * 80, 0.001));
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
          fatGPerKg: 1.0,
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
    for (final key in ['macro-style-keto', 'macro-lean']) {
      await tester.ensureVisible(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final program = memory.saved.macroProgram!;
    expect(program.style, MacroStyle.keto);
    expect(program.leanMass, isTrue);
    expect(program.proteinGPerKg, MacroProgram.defaultPerKgLean);
    expect(find.text('Keto, protein 1.9 g/kg of lean mass'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('macro-program')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('macro-program-on')));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(memory.saved.macroProgram, isNull);
  });

  group('the dialog\'s choices', () {
    Future<({MacroProgram? program})?> open(
      WidgetTester tester,
      MacroProgram? program,
      Future<void> Function() choose,
    ) async {
      ({MacroProgram? program})? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await showDialog(
                context: context,
                builder: (_) => MacroProgramDialog(program),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await choose();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      return result;
    }

    Future<void> tapKey(WidgetTester tester, String key) async {
      final f = find.byKey(ValueKey(key));
      await tester.ensureVisible(f);
      await tester.tap(f);
      await tester.pumpAndSettle();
    }

    testWidgets('three levels each, a level for each basis', (tester) async {
      final result = await open(tester, const MacroProgram(), () async {
        await tapKey(tester, 'macro-protein-2');
        await tapKey(tester, 'macro-fat-0');
        await tapKey(tester, 'macro-lean');
      });
      final p = result!.program!;
      expect(p.style, MacroStyle.perKg);
      expect(p.fatGPerKg, 0.6);
      expect(p.leanMass, isTrue);
      // Very high on body weight is very high on lean mass.
      expect(p.proteinGPerKg, MacroProgram.proteinPresetsLean[2]);
    });

    testWidgets('a manual value for one macro leaves the other', (
      tester,
    ) async {
      final result = await open(
        tester,
        const MacroProgram(proteinGPerKg: 2.0),
        () async {
          await tapKey(tester, 'macro-fat-manual');
          await tester.enterText(
            find.byKey(const ValueKey('macro-fat-kg')),
            '1,2',
          );
          await tester.pumpAndSettle();
        },
      );
      final p = result!.program!;
      expect(p.fatGPerKg, 1.2);
      expect(p.proteinGPerKg, 2.0);
    });

    testWidgets('a value out of range cannot be saved', (tester) async {
      await open(tester, const MacroProgram(), () async {
        await tapKey(tester, 'macro-protein-manual');
        await tester.enterText(
          find.byKey(const ValueKey('macro-protein-kg')),
          '9',
        );
        await tester.pumpAndSettle();
        expect(find.text('From 0.8 to 3.5'), findsOneWidget);
        final save = tester.widget<TextButton>(
          find.widgetWithText(TextButton, 'Save'),
        );
        expect(save.onPressed, isNull);
        await tester.enterText(
          find.byKey(const ValueKey('macro-protein-kg')),
          '2.2',
        );
        await tester.pumpAndSettle();
      });
    });

    testWidgets('keto stays a choice; a saved balanced one shows while saved', (
      tester,
    ) async {
      final result = await open(
        tester,
        const MacroProgram(style: MacroStyle.balanced),
        () async {
          expect(
            find.byKey(const ValueKey('macro-style-balanced')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('macro-style-lowFat')),
            findsNothing,
          );
          await tapKey(tester, 'macro-style-keto');
        },
      );
      expect(result!.program!.style, MacroStyle.keto);
    });
  });

  test(
    'onboarding\'s choice goes into the profile when it completes',
    () async {
      final dir = await Directory.systemTemp.createTemp('onboarding');
      Hive.init(dir.path);
      addTearDown(() async {
        OnboardingMacros.pending.value = null;
        AdaptiveStore.settings.value = const AdaptiveSettings();
        await Hive.deleteFromDisk();
        await dir.delete(recursive: true);
      });
      final store = AdaptiveStore(() => Hive.openBox<dynamic>('new'));
      await store.save(const AdaptiveSettings(smoothedTrend: true));

      await OnboardingMacros.save(store);
      expect((await store.read()).macroProgram, isNull);

      OnboardingMacros.pending.value = const MacroProgram(fatGPerKg: 1.0);
      await OnboardingMacros.save(store);
      final saved = await store.read();
      expect(saved.macroProgram!.fatGPerKg, 1.0);
      expect(saved.smoothedTrend, isTrue);
      expect(OnboardingMacros.pending.value, isNull);
    },
  );
}
