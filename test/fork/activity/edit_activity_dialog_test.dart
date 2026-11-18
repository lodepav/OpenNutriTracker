import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/user_activity_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/edit_activity_dialog.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

import '../../fixture/physical_activity_entity_fixtures.dart';

final _ride = UserActivityEntity(
  'ride',
  43,
  249,
  DateTime(2026, 6, 15, 18),
  PhysicalActivityFixtures.moderateBicycling,
);

void main() {
  testWidgets('the activity dialog is named for the activity, with Delete '
      'apart from Cancel and OK', (tester) async {
    late Future<double?> result;
    late String name;
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => EnergyUnitProvider(usesKilojoules: false),
        child: MaterialApp(
          localizationsDelegates: const [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: S.supportedLocales,
          home: Builder(
            builder: (context) {
              name = _ride.physicalActivityEntity.getName(context);
              return TextButton(
                onPressed: () => result = showDialog<double>(
                  context: context,
                  builder: (_) => EditActivityDialog(activityEntity: _ride),
                ),
                child: const Text('open'),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
    expect((dialog.title! as Text).data, name);

    final delete = tester.getRect(find.text('Delete'));
    final cancel = tester.getRect(find.text('Cancel'));
    final ok = tester.getRect(find.text('OK'));
    expect(delete.right, lessThan(cancel.left));
    expect(cancel.right, lessThan(ok.left));
    // Apart: the gap to Cancel is wider than the one between Cancel and OK.
    expect(cancel.left - delete.right, greaterThan(ok.left - cancel.right));

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(await result, EditActivityDialog.deleteResult);
  });
}
