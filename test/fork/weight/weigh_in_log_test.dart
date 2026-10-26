import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_weight_log_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/delete_weight_log_usecase.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/profile/presentation/widgets/set_weight_dialog.dart';
import 'package:opennutritracker/fork/weight/weigh_in_log.dart';
import 'package:opennutritracker/generated/l10n.dart';

import '../../helpers/recording_add_weight_log_usecase.dart';

class _Delete extends Fake implements DeleteWeightLogUsecase {
  final deleted = <WeightLogEntity>[];

  @override
  Future<void> deleteEntry(WeightLogEntity entry) async => deleted.add(entry);
}

final _today = DateUtils.dateOnly(DateTime.now());
final _morning = WeightLogEntity(date: _today, weightKg: 87);

Widget _app(Widget Function(BuildContext) body) => MaterialApp(
  localizationsDelegates: const [
    S.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ],
  supportedLocales: S.supportedLocales,
  home: Scaffold(body: Builder(builder: body)),
);

void main() {
  late RecordingAddWeightLogUsecase add;
  late _Delete delete;
  late int refreshed;

  setUp(() {
    add = RecordingAddWeightLogUsecase();
    delete = _Delete();
    refreshed = 0;
    locator.registerSingleton<AddWeightLogUsecase>(add);
    locator.registerSingleton<DeleteWeightLogUsecase>(delete);
  });
  tearDown(locator.reset);

  testWidgets("a second weigh-in today says it replaces the first", (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        (_) => SetWeightDialog(
          initialKg: 87,
          unit: BodyWeightUnit.kg,
          logged: {_today: _morning},
        ),
      ),
    );
    expect(find.text("Replaces today's 87 kg"), findsOneWidget);
  });

  testWidgets('none today, nothing replaced', (tester) async {
    await tester.pumpWidget(
      _app(
        (_) => const SetWeightDialog(initialKg: 87, unit: BodyWeightUnit.kg),
      ),
    );
    expect(find.textContaining('Replaces'), findsNothing);
  });

  Future<void> log(WidgetTester tester, WeightLogEntity? replaced) async {
    await tester.pumpWidget(
      _app(
        (context) => TextButton(
          onPressed: () => logWeighIn(
            context,
            kg: 86.6,
            day: _today,
            unit: BodyWeightUnit.kg,
            replaced: replaced,
            refresh: () async => refreshed++,
          ),
          child: const Text('log'),
        ),
      ),
    );
    await tester.tap(find.text('log'));
    await tester.pumpAndSettle();
    expect(find.text('86.6 kg logged for today'), findsOneWidget);
    expect(add.entries.single.weightKg, 86.6);
    expect(refreshed, 1);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(refreshed, 2);
  }

  testWidgets("Undo brings back the weigh-in it replaced", (tester) async {
    await log(tester, _morning);
    expect(add.entries.last, _morning);
    expect(delete.deleted, isEmpty);
  });

  testWidgets('Undo takes it off where there was none', (tester) async {
    await log(tester, null);
    expect(delete.deleted.single.weightKg, 86.6);
  });
}
