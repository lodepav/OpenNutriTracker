// BMI info in the user's units (G5-23, S570) and its band named (G5-7,
// S571).
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_gender_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_pal_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_usecase.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/profile/presentation/widgets/bmi_info_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';

class _User extends Fake implements GetUserUsecase {
  @override
  Future<UserEntity> getUserData() async => UserEntity(
    birthday: DateTime(1990, 1, 1),
    heightCM: 180,
    weightKG: 80,
    gender: UserGenderEntity.male,
    goal: UserWeightGoalEntity.maintainWeight,
    pal: UserPALEntity.sedentary,
  );
}

class _Config extends Fake implements GetConfigUsecase {
  @override
  Future<ConfigEntity> getConfig() async => const ConfigEntity(
    true,
    true,
    false,
    AppThemeEntity.system,
    usesImperialHeightUnits: true,
    bodyWeightUnit: BodyWeightUnit.lb,
  );
}

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: S.supportedLocales,
      home: BmiInfoScreen(userUsecase: _User()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  tearDown(locator.reset);

  testWidgets('an imperial user reads ft, in and lb, the metric beside', (
    tester,
  ) async {
    locator.registerSingleton<GetConfigUsecase>(_Config());
    await _pump(tester);
    expect(find.text('5 ft 11 in (180 cm)'), findsOneWidget);
    expect(find.text('176.4 lb (80.0 kg)'), findsOneWidget);
    // The formula stays in the metric it is defined in.
    expect(find.textContaining('= 80.0 ÷ 1.80²'), findsOneWidget);
  });

  testWidgets("the user's band says it is theirs in words", (tester) async {
    await _pump(tester);
    expect(find.text('180 cm'), findsOneWidget);
    final you = find.text('You');
    expect(you, findsOneWidget);
    // On the normal-weight row (BMI 24.7), beside its range.
    expect(
      tester.getCenter(you).dy,
      closeTo(tester.getCenter(find.text('18.5 – 24.9')).dy, 1),
    );
  });
}
