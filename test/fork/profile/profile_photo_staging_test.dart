import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/profile_entity.dart';
import 'package:opennutritracker/core/domain/usecase/update_profile_usecase.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/profile/presentation/screens/profile_editor_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';

import '../helpers/photo_docs.dart';

// The profile editor keeps a picked or removed photo until Save (G3 P1):
// Back leaves the stored photo as it was; Save writes it.

class _Update extends Fake implements UpdateProfileUsecase {
  final saved = <ProfileEntity>[];

  @override
  Future<void> updateProfile(ProfileEntity profile) async => saved.add(profile);
}

const _stored = 'profile_images/p1.webp';

final _alex = ProfileEntity(
  id: 'p1',
  name: 'Alex',
  createdAt: DateTime(2026),
  boxSuffix: '',
  imagePath: _stored,
);

void main() {
  late _Update update;
  late PhotoDocs docs;

  setUp(() async {
    update = _Update();
    locator.registerSingleton<UpdateProfileUsecase>(update);
    docs = await PhotoDocs.create();
  });
  tearDown(() async {
    await locator.reset();
    await docs.dispose();
  });

  Future<void> open(WidgetTester tester) async {
    await tester.runAsync(() => docs.write(_stored, storedBytes));
    fakePicker(tester, docs.picked);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [S.delegate],
        supportedLocales: S.supportedLocales,
        home: const Scaffold(),
      ),
    );
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .push(
          MaterialPageRoute<bool>(
            builder: (_) => ProfileEditorScreen(profile: _alex),
          ),
        );
    await settleWithIo(tester, () => editorOpen(tester));
  }

  Finder tile() => find.bySemanticsIdentifier('profile-image-picker');
  Finder save() => find.bySemanticsIdentifier('profile-editor-save');

  testWidgets('Back after a remove leaves the stored photo', (tester) async {
    await open(tester);
    await choose(tester, tile(), 'Remove photo');
    await backAndDiscard(tester, docs);

    expect(find.byType(ProfileEditorScreen), findsNothing);
    expect(await tester.runAsync(() => docs.read(_stored)), storedBytes);
  });

  testWidgets('Back after a pick leaves the stored photo and no staged file', (
    tester,
  ) async {
    await open(tester);
    await choose(tester, tile(), 'Choose from gallery');
    await backAndDiscard(tester, docs);

    expect(find.byType(ProfileEditorScreen), findsNothing);
    expect(await tester.runAsync(() => docs.read(_stored)), storedBytes);
    expect(await tester.runAsync(() => docs.list('profile_images')), [
      'p1.webp',
    ]);
  });

  testWidgets('Back with nothing changed does not ask', (tester) async {
    await open(tester);
    await tester.binding.handlePopRoute();
    await settleWithIo(tester, () => editorClosed(tester));
    expect(find.text('Discard'), findsNothing);
    expect(find.byType(ProfileEditorScreen), findsNothing);
  });

  testWidgets('Back after typing a name asks first', (tester) async {
    await open(tester);
    await tester.enterText(find.byType(TextField), 'Sam');
    await tester.pump();
    await tester.binding.handlePopRoute();
    await settleWithIo(
      tester,
      () => find.text('Discard').evaluate().isNotEmpty,
    );
    expect(find.text('Discard'), findsOneWidget);
    expect(find.byType(ProfileEditorScreen), findsOneWidget);
  });

  testWidgets('Save after a pick writes the new photo at the stored path', (
    tester,
  ) async {
    await open(tester);
    await choose(tester, tile(), 'Choose from gallery');
    await tester.tap(save());
    await settleWithIo(
      tester,
      () => find.byType(ProfileEditorScreen).evaluate().isEmpty,
    );

    expect(update.saved.single.imagePath, _stored);
    expect(await tester.runAsync(() => docs.read(_stored)), pickedBytes);
    expect(await tester.runAsync(() => docs.list('profile_images')), [
      'p1.webp',
    ]);
  });

  testWidgets('Save after a remove deletes the stored photo', (tester) async {
    await open(tester);
    await choose(tester, tile(), 'Remove photo');
    await tester.tap(save());
    await settleWithIo(
      tester,
      () => find.byType(ProfileEditorScreen).evaluate().isEmpty,
    );

    expect(update.saved.single.imagePath, isNull);
    expect(await tester.runAsync(() => docs.read(_stored)), isNull);
  });

  testWidgets('a failed pick says so', (tester) async {
    await open(tester);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/image_picker'),
      (_) async => throw PlatformException(code: 'camera_access_denied'),
    );
    await choose(tester, tile(), 'Choose from gallery');
    expect(find.text('Could not add the photo'), findsOneWidget);
    expect(await tester.runAsync(() => docs.read(_stored)), storedBytes);
  });
}
