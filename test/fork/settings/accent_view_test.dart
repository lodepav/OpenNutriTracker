import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/styles/accent_colors.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/theme_mode_provider.dart';
import 'package:opennutritracker/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/accent_colour_screen.dart';
import 'package:opennutritracker/fork/settings/accent_view.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

// Seam S136: the accent colour as MacroFactor's.

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: const [
    S.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: S.supportedLocales,
  home: Scaffold(body: child),
);

class _Settings extends Fake implements SettingsBloc {
  _Settings(this._state);

  final SettingsLoadedState _state;
  final calls = <String>[];

  @override
  SettingsState get state => _state;

  @override
  Stream<SettingsState> get stream => const Stream.empty();

  @override
  void add(SettingsEvent event) {}

  @override
  void setUseMaterialYou(bool useMaterialYou) =>
      calls.add('wallpaper $useMaterialYou');

  @override
  void setAccentColor(int? value) =>
      calls.add('colour ${value?.toRadixString(16)}');
}

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize = const Size(
      1200,
      2700,
    );
    binding.platformDispatcher.views.first.devicePixelRatio = 3;
  });
  tearDown(() {
    TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.views.first
        .resetPhysicalSize();
  });

  testWidgets('every preset, the chosen one ticked; a tap picks it', (
    tester,
  ) async {
    final picked = <Color>[];
    await tester.pumpWidget(
      _wrap(
        AccentColourView(
          offersWallpaper: false,
          matchesWallpaper: false,
          currentArgb: accentPresetColors[3].toARGB32(),
          onWallpaper: (_) {},
          onColor: picked.add,
          onCustom: () {},
        ),
      ),
    );
    for (var i = 0; i < accentPresetColors.length; i++) {
      final id = 'accent-preset-${i.toString().padLeft(2, '0')}';
      expect(find.bySemanticsIdentifier(id), findsOneWidget, reason: id);
    }
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsIdentifier('accent-preset-03')),
      containsSemantics(
        label: 'Colour #FFB300',
        isButton: true,
        isSelected: true,
        hasTapAction: true,
      ),
    );
    expect(
      tester.getSize(find.bySemanticsIdentifier('accent-preset-00')).height,
      greaterThanOrEqualTo(48),
    );
    // Off Android there is no wallpaper to match.
    expect(find.text('Match my wallpaper'), findsNothing);

    await tester.tap(find.bySemanticsIdentifier('accent-preset-07'));
    expect(picked, [accentPresetColors[7]]);
  });

  testWidgets('matching the wallpaper, no preset is ticked', (tester) async {
    final switched = <bool>[];
    var custom = 0;
    await tester.pumpWidget(
      _wrap(
        AccentColourView(
          offersWallpaper: true,
          matchesWallpaper: true,
          currentArgb: accentPresetColors[3].toARGB32(),
          onWallpaper: switched.add,
          onColor: (_) {},
          onCustom: () => custom++,
        ),
      ),
    );
    expect(find.byIcon(Icons.check_rounded), findsNothing);
    await tester.tap(find.text('Match my wallpaper'));
    expect(switched, [false]);
    await tester.tap(find.bySemanticsIdentifier('accent-custom-colour'));
    expect(custom, 1);
  });

  group('the screen', () {
    tearDown(() => GetIt.instance.reset());

    Future<_Settings> pump(WidgetTester tester, {int? accent}) async {
      final settings = _Settings(
        SettingsLoadedState(
          '1.0.0',
          false,
          AppThemeEntity.system,
          false,
          useMaterialYou: true,
          accentColor: accent,
        ),
      );
      locator.registerSingleton<SettingsBloc>(settings);
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => ThemeModeProvider(appTheme: AppThemeEntity.system),
          child: _wrap(const AccentColourScreen()),
        ),
      );
      await tester.pump();
      return settings;
    }

    testWidgets('the wallpaper off keeps the colour chosen before', (
      tester,
    ) async {
      final settings = await pump(tester, accent: 0xFF00897B);
      await tester.tap(find.text('Match my wallpaper'));
      expect(settings.calls, ['colour ff00897b', 'wallpaper false']);
    });

    testWidgets('or, with none, the first preset', (tester) async {
      final settings = await pump(tester);
      await tester.tap(find.text('Match my wallpaper'));
      expect(settings.calls, [
        'colour ${accentPresetColors.first.toARGB32().toRadixString(16)}',
        'wallpaper false',
      ]);
    });
  });
}
