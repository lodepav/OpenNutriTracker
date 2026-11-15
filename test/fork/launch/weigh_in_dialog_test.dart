import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_weight_log_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_weight_log_usecase.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/profile/presentation/bloc/profile_bloc.dart';
import 'package:opennutritracker/features/profile/presentation/widgets/set_weight_dialog.dart';
import 'package:opennutritracker/fork/display/home_tiles.dart';
import 'package:opennutritracker/fork/launch/launch_actions.dart';
import 'package:opennutritracker/fork/launch/quick_actions.dart';
import 'package:opennutritracker/fork/reminders/reminder_taps.dart';
import 'package:opennutritracker/generated/l10n.dart';

class _Config extends Fake implements GetConfigUsecase {
  @override
  Future<ConfigEntity> getConfig() async => _Kg();
}

class _Kg extends Fake implements ConfigEntity {
  @override
  bool get usesImperialFoodUnits => false;
  @override
  Map<String, int> get mealKcalSharesPct => const {};
  @override
  BodyWeightUnit get bodyWeightUnit => BodyWeightUnit.kg;
}

class _User extends Fake implements UserEntity {
  @override
  final double weightKG;
  _User(this.weightKG);
}

/// The user record, which a weigh-in today updates, as the real store does.
class _Store extends Fake implements GetUserUsecase, AddWeightLogUsecase {
  double kg = 87;

  @override
  Future<UserEntity> getUserData() async => _User(kg);

  @override
  Future<void> addEntry(WeightLogEntity entry) async => kg = entry.weightKg;
}

class _NoWeighIns extends Fake implements GetWeightLogUsecase {
  @override
  Future<List<WeightLogEntity>> getAllEntries() async => const [];
}

/// Home's reload after a profile update, as Home's weight.
class _Profile extends Fake implements ProfileBloc {
  final ValueNotifier<double> home;
  _Profile(this.home);

  @override
  Future<void> updateUser(UserEntity userEntity) async =>
      home.value = userEntity.weightKG;
}

class _Pushes extends NavigatorObserver {
  final routes = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      routes.add(route);
}

final _home = GlobalKey();

void main() {
  late ValueNotifier<double> homeKg;
  late _Pushes pushes;

  setUp(() {
    homeKg = ValueNotifier(87);
    pushes = _Pushes();
    final store = _Store();
    locator
      ..registerSingleton<GetConfigUsecase>(_Config())
      ..registerSingleton<GetUserUsecase>(store)
      ..registerSingleton<AddWeightLogUsecase>(store)
      ..registerSingleton<GetWeightLogUsecase>(_NoWeighIns())
      ..registerSingleton<ProfileBloc>(_Profile(homeKg));
  });
  tearDown(locator.reset);

  /// Home as far as this needs: the quick actions and the weight tile,
  /// keyed by the weight as HomeTiles keys it, under the main screen's host.
  Future<void> pumpHome(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          S.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: S.supportedLocales,
        navigatorObservers: [pushes],
        home: LaunchActionHost(
          child: Scaffold(
            key: _home,
            body: Column(
              children: [
                const QuickActions(),
                ValueListenableBuilder<double>(
                  valueListenable: homeKg,
                  builder: (_, kg, _) => WeightTile(
                    key: ValueKey(kg),
                    weightKg: kg,
                    unit: BodyWeightUnit.kg,
                    load: () async => const [],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    pushes.routes.clear();
  }

  bool homeIsCurrent() => ModalRoute.of(_home.currentContext!)!.isCurrent;

  testWidgets('the Weigh in tile opens the weigh-in over Home and saves '
      'there', (tester) async {
    await pumpHome(tester);
    expect(find.text('87.0 kg'), findsOneWidget);

    await tester.tap(find.bySemanticsIdentifier('home-quick-weigh-in'));
    await tester.pumpAndSettle();
    expect(find.byType(SetWeightDialog), findsOneWidget);
    expect(pushes.routes.whereType<PageRoute<dynamic>>(), isEmpty);

    await tester.enterText(find.byType(TextField), '86.4');
    await tester.pump();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byType(SetWeightDialog), findsNothing);
    expect(homeIsCurrent(), isTrue);
    expect(find.text('86.4 kg'), findsOneWidget);
    expect(find.text('86.4 kg logged for today'), findsOneWidget);
  });

  NotificationResponse tap(String? payload) => NotificationResponse(
    notificationResponseType: NotificationResponseType.selectedNotification,
    payload: payload,
  );

  testWidgets('a tap on the weigh-in reminder opens the weigh-in over Home', (
    tester,
  ) async {
    await pumpHome(tester);
    onNotificationTap(tap('weighInReminder'));
    await tester.pumpAndSettle();
    expect(find.byType(SetWeightDialog), findsOneWidget);
    expect(pushes.routes.whereType<PageRoute<dynamic>>(), isEmpty);

    // Once: closing it does not bring it back.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(SetWeightDialog), findsNothing);
    expect(homeIsCurrent(), isTrue);
  });

  testWidgets('a tap that started the app waits for the main screen', (
    tester,
  ) async {
    onNotificationTap(tap('weighInReminder'));
    await pumpHome(tester);
    expect(find.byType(SetWeightDialog), findsOneWidget);
  });

  testWidgets("other notifications' taps only open the app", (tester) async {
    await pumpHome(tester);
    for (final payload in [null, '', 'checkInReminder', 'garbage']) {
      onNotificationTap(tap(payload));
    }
    await tester.pumpAndSettle();
    expect(find.byType(SetWeightDialog), findsNothing);
    expect(pushes.routes, isEmpty);
  });
}
