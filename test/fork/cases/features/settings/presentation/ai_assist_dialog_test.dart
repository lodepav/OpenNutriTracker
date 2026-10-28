// Fork cases moved out of test/features/settings/presentation/ai_assist_dialog_test.dart (they test the fork's changes).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/core/utils/ai_model_catalogue.dart';
import 'package:opennutritracker/core/utils/ai_model_list_api.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/run_ai_endpoint_probe_usecase.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/ai_assist_dialog.dart';
import 'package:opennutritracker/generated/l10n.dart';

import '../../../../../helpers/test_l10n.dart';

class _MemoryStorage implements FlutterSecureStorage {
  final store = <String, String>{};

  /// Reads held open until the test releases them.
  ///
  /// The real store is a platform channel, so two reads issued in order are
  /// free to answer out of order — which is the whole of the race the dialog
  /// guards against. A map that answers in a microtask can never reproduce
  /// that on its own.
  final readGates = <String, Completer<void>>{};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    final gate = readGates[key];
    if (gate != null) await gate.future;
    return store[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      store.remove(key);
    } else {
      store[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => store.remove(key);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(
  AiCredentialStorage storage, {
  Locale? locale,
  AiModelListApi? modelList,
  AiEndpointProbeRunner? probeRunner,
}) => MaterialApp(
  locale: locale,
  localizationsDelegates: const [
    S.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: S.supportedLocales,
  home: Scaffold(
    body: AiAssistDialog(
      storage: storage,
      modelList: modelList,
      probeRunner: probeRunner,
    ),
  ),
);

void main() {
  late _MemoryStorage backing;
  late AiCredentialStorage storage;

  setUp(() async {
    backing = _MemoryStorage();
    storage = AiCredentialStorage(backing);
    // Storing a credential requires agreeing to what leaves the device
    // (#835). Every test below that saves one is about something else, so the
    // agreement is arranged as already given; the group that is about the
    // agreement clears it again.
    await storage.setTermsAccepted(true);
  });

  testWidgets('the default model is the one measurement chose', (tester) async {
    await storage.setActiveProvider(AiProvider.openrouter);
    await tester.pumpWidget(_app(storage));
    await tester.pumpAndSettle();

    final selected = tester
        .widgetList<RadioListTile<String>>(find.byType(RadioListTile<String>))
        // ignore: deprecated_member_use
        .where((tile) => tile.value == tile.groupValue)
        .single;
    expect(selected.value, 'anthropic/claude-sonnet-5.5');
  });

  testWidgets('choosing a model stores it against that provider', (
    tester,
  ) async {
    await storage.setActiveProvider(AiProvider.openrouter);
    await tester.pumpWidget(_app(storage));
    await tester.pumpAndSettle();

    // The model section sits below the credential block now, so it can be
    // off-screen on a phone-sized viewport.
    final haiku = find.bySemanticsIdentifier(
      AiAssistDialog.modelIdentifier('anthropic/claude-haiku-5.5'),
    );
    await tester.ensureVisible(haiku);
    await tester.pumpAndSettle();
    await tester.tap(haiku);
    await tester.pumpAndSettle();

    expect(
      await storage.readModel(provider: AiProvider.openrouter),
      'anthropic/claude-haiku-5.5',
    );
    expect(
      await storage.readModel(provider: AiProvider.anthropic),
      isNull,
      reason: 'the other provider keeps its own model',
    );
  });

  testWidgets('no OpenRouter row claims to be cheaper than it is', (
    tester,
  ) async {
    // The label was keyed on the *provider*, so every non-default row on a
    // list got the same string. That held while each list was two entries
    // differing the same way. On four it reached `openai/gpt-5.6-terra`,
    // which matched claude-sonnet-5 on input price and was dearer on output —
    // the row asserted something the price table contradicts. #726.
    await storage.setActiveProvider(AiProvider.openrouter);
    await tester.pumpWidget(_app(storage));
    await tester.pumpAndSettle();

    expect(
      find.textContaining(l10nEn.aiAssistModelCheaperLabel),
      findsNothing,
      reason: 'its quality claim was measured on Haiku 4.5, now off the list',
    );
    expect(
      find.textContaining(l10nEn.aiAssistModelCheaperThanRecommendedLabel),
      findsOne,
      reason: 'only gpt-6-luna, a price fact with no quality claim',
    );
    expect(
      find.textContaining(l10nEn.aiAssistModelCheapestLabel),
      findsOne,
      reason: 'only claude-haiku-5.5, which nothing undercuts',
    );
    expect(
      find.textContaining(l10nEn.aiAssistModelMoreItemsLabel),
      findsOne,
      reason: 'only gpt-6.1-terra, which returns more items a photo',
    );
    expect(find.textContaining(l10nEn.aiAssistModelRecommendedLabel), findsOne);
  });

  testWidgets('each OpenRouter row shows its eval rating and price tier', (
    tester,
  ) async {
    // S174: the words the phase 4 live eval earned each listed model.
    await storage.setActiveProvider(AiProvider.openrouter);
    await tester.pumpWidget(_app(storage));
    await tester.pumpAndSettle();

    expect(find.textContaining('Best accuracy · High cost'), findsOne);
    expect(
      find.textContaining('Good accuracy · Low cost'),
      findsNWidgets(2),
      reason: 'Haiku 5.5 and GPT-6 luna',
    );
    expect(find.textContaining('Good accuracy · Medium cost'), findsOne);
  });

  /// The model rows, and the paragraph each one actually painted.
  List<(String, RenderParagraph)> modelTitles(WidgetTester tester) => tester
      .widgetList<RadioListTile<String>>(find.byType(RadioListTile<String>))
      .map((tile) => (tile.title as Text).data!)
      // The title carries a semantics label, so its paragraph sits a
      // level below the Text.
      .map(
        (data) => (
          data,
          tester.renderObject<RenderParagraph>(
            find.descendant(
              of: find.text(data),
              matching: find.byType(RichText),
            ),
          ),
        ),
      )
      .toList();

  testWidgets('a model row stays inside its three-line bound', (tester) async {
    // 320dp at a 2.0 text scale leaves the title 156dp, which no model id
    // fits under any setting. What has to hold there is that it stops at the
    // bound rather than running down the dialog.
    //
    // Counted in painted lines rather than checked for overflow stripes: a
    // wrapping ListTile title throws nothing at all, so the exception check
    // the test above stays green through exactly this bug.
    tester.view.physicalSize = const Size(320 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await storage.setActiveProvider(AiProvider.openrouter);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
        child: _app(storage),
      ),
    );
    await tester.pumpAndSettle();

    final titles = modelTitles(tester);
    expect(titles, hasLength(AiModelCatalogue.openrouter.length));

    for (final (data, paragraph) in titles) {
      final lines = paragraph
          .getBoxesForSelection(
            TextSelection(baseOffset: 0, extentOffset: data.length),
          )
          .map((box) => box.top)
          .toSet();
      expect(
        lines.length,
        lessThanOrEqualTo(3),
        reason: '$data ran past three',
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('on a real phone the ids are whole and tell the rows apart', (
    tester,
  ) async {
    // A Pixel 6, which is the phone this was driven on. The ellipsis eats
    // the *end* of the string and the curated ids are identical until their
    // last few characters, so a title with too little room fails by painting
    // the same visible text in both rows — worse than wrapping, and just as
    // silent.
    //
    // This is what pins the vendor prefix in place. Dropping it looks like
    // it buys width and instead removes the `/`, which is the only point in
    // a model id where a line can break at all — so the shortened form
    // cannot use the second line, and truncates here where the full id fits.
    // no longer so: the title may break after each
    // `-`, so it drops the vendor, which *Served by* names below it.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    await storage.setActiveProvider(AiProvider.openrouter);
    await tester.pumpWidget(_app(storage));
    await tester.pumpAndSettle();

    final titles = modelTitles(tester);
    for (final (data, paragraph) in titles) {
      expect(
        paragraph.didExceedMaxLines,
        isFalse,
        reason: '$data was truncated on the phone this app is developed on',
      );
    }
    expect(
      titles.map((title) => title.$1).toSet(),
      hasLength(titles.length),
      reason: 'two rows painted the same text',
    );
  });
}
