import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/profile_entity.dart';
import 'package:opennutritracker/core/domain/usecase/update_profile_usecase.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/profile/presentation/screens/profile_editor_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';

// The profile editor refuses a blank name, as Add profile does (S302): a
// cleared name would save and show as "Profile 1".

class _Update extends Fake implements UpdateProfileUsecase {
  final saved = <ProfileEntity>[];

  @override
  Future<void> updateProfile(ProfileEntity profile) async => saved.add(profile);
}

final _alex = ProfileEntity(
  id: 'p1',
  name: 'Alex',
  createdAt: DateTime(2026),
  boxSuffix: '',
);

void main() {
  late _Update update;

  setUp(() {
    update = _Update();
    locator.registerSingleton<UpdateProfileUsecase>(update);
  });
  tearDown(locator.reset);

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [S.delegate],
        supportedLocales: S.supportedLocales,
        home: const Scaffold(),
      ),
    );
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute<bool>(
        builder: (_) => ProfileEditorScreen(profile: _alex),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder name() => find.bySemanticsIdentifier('profile-editor-name');
  Finder save() => find.bySemanticsIdentifier('profile-editor-save');

  for (final blank in ['', '   ']) {
    testWidgets('Save refuses the name "$blank" with a field error', (
      tester,
    ) async {
      await pump(tester);
      await tester.enterText(
        find.descendant(of: name(), matching: find.byType(TextField)),
        blank,
      );
      await tester.tap(save());
      await tester.pumpAndSettle();

      expect(find.text('Enter a name'), findsOneWidget);
      expect(update.saved, isEmpty);
      expect(find.byType(ProfileEditorScreen), findsOneWidget);
    });
  }

  testWidgets('typing a name clears the error, and Save keeps it trimmed', (
    tester,
  ) async {
    await pump(tester);
    final field = find.descendant(of: name(), matching: find.byType(TextField));
    await tester.enterText(field, '');
    await tester.tap(save());
    await tester.pumpAndSettle();
    await tester.enterText(field, ' Sam ');
    await tester.pumpAndSettle();
    expect(find.text('Enter a name'), findsNothing);

    await tester.tap(save());
    await tester.pumpAndSettle();
    expect(update.saved.single.name, 'Sam');
    expect(find.byType(ProfileEditorScreen), findsNothing);
  });
}
