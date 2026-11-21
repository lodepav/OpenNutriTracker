// Reset profile data says first that the shared AI key goes too, on the row
// and in the dialog, and calls logged foods by that name (the round-2 G6
// critique).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/probe_ai_endpoint_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/run_ai_endpoint_probe_usecase.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/diary_bloc.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/profile/presentation/bloc/profile_bloc.dart';
import 'package:opennutritracker/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:opennutritracker/fork/screens/settings/settings_screen.dart';
import 'package:opennutritracker/features/trends/presentation/bloc/trends_bloc.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:opennutritracker/fork/settings/settings_index.dart';

import '../../helpers/test_l10n.dart';

/// A loaded settings screen without the config box behind it.
///
/// The screen only ever reads the state and posts `LoadSettingsEvent`, so a
/// bloc that answers with one fixed loaded state renders exactly what the
/// real one renders — and skips Hive, `package_info`, and the cache size
/// read, none of which are what these tests are about.
class _FakeSettingsBloc extends Fake implements SettingsBloc {
  @override
  SettingsState get state =>
      const SettingsLoadedState('1.0.0', false, AppThemeEntity.system, false);

  @override
  Stream<SettingsState> get stream => const Stream<SettingsState>.empty();

  @override
  void add(SettingsEvent event) {}

  /// Held open by the tests, so a reload sent before the flag is stored
  /// shows up. Made on the call, inside the test's fake-async zone; one
  /// made in setUp would complete outside it.
  Completer<void>? mealMacrosSaved;

  @override
  Future<void> setShowMealMacros(bool showMealMacros) =>
      (mealMacrosSaved = Completer<void>()).future;
}

/// The screen resolves these in `initState` and only calls them from
/// controls no test here touches.
class _FakeProfileBloc extends Fake implements ProfileBloc {}

class _FakeHomeBloc extends Fake implements HomeBloc {
  @override
  void add(HomeEvent event) {}
}

class _FakeDiaryBloc extends Fake implements DiaryBloc {
  final List<DiaryEvent> added = [];

  @override
  void add(DiaryEvent event) => added.add(event);
}

class _FakeCalendarDayBloc extends Fake implements CalendarDayBloc {
  @override
  void add(CalendarDayEvent event) {}
}

class _FakeTrendsBloc extends Fake implements TrendsBloc {
  @override
  void add(TrendsEvent event) {}
}

/// Nothing is configured, which is the state a user arrives in from a
/// rejected key or a refused destination; what a test writes stays.
class _EmptyStorage implements FlutterSecureStorage {
  final _values = <String, String>{};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _values[key];

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
    value == null ? _values.remove(key) : _values[key] = value;
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
  }) async => _values.remove(key);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The runner is real; only the thing that would talk to a server is not.
/// Nothing here presses the check, so it is never asked anything.
class _FakeProber extends Fake implements AiEndpointProber {}

void _register() {
  final getIt = GetIt.instance;
  getIt.registerSingleton<SettingsBloc>(_FakeSettingsBloc());
  getIt.registerSingleton<ProfileBloc>(_FakeProfileBloc());
  getIt.registerSingleton<HomeBloc>(_FakeHomeBloc());
  getIt.registerSingleton<DiaryBloc>(_FakeDiaryBloc());
  getIt.registerSingleton<CalendarDayBloc>(_FakeCalendarDayBloc());
  getIt.registerSingleton<TrendsBloc>(_FakeTrendsBloc());
  final credentials = AiCredentialStorage(_EmptyStorage());
  getIt.registerSingleton<AiCredentialStorage>(credentials);
  getIt.registerSingleton<AiEndpointProbeRunner>(
    AiEndpointProbeRunner(credentials, _FakeProber()),
  );
}

Widget _app({SettingsSection? section, double textScale = 1}) => MaterialApp(
  localizationsDelegates: const [
    S.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: S.supportedLocales,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: SettingsScreen(section: section),
);

void main() {
  setUp(_register);
  tearDown(() => locator.reset());

  testWidgets('the row names the shared AI key and logged foods', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(section: SettingsSection.data));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Profile, logged foods, activities, weight history, fasting '
        'sessions and the shared AI key',
      ),
      findsOneWidget,
    );
  });

  testWidgets('the dialog says first that the shared AI key goes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(section: SettingsSection.data));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10nEn.settingsDeleteAllDataLabel));
    await tester.pumpAndSettle();
    final body = tester
        .widget<Text>(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.textContaining('every profile'),
          ),
        )
        .data!;
    expect(
      body,
      startsWith(
        'This also removes the AI provider key and server address, which '
        'every profile on this device shares.',
      ),
    );
    expect(body, contains('logged foods'));
    expect(body, isNot(contains(' meals, activities')));
    // Cancel leaves everything as it was.
    await tester.tap(find.text(l10nEn.dialogCancelLabel));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
}
