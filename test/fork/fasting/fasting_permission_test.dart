import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/notification_service.dart';
import 'package:opennutritracker/features/fasting/data/repository/fasting_repository.dart';
import 'package:opennutritracker/features/fasting/domain/entity/fasting_session_entity.dart';
import 'package:opennutritracker/features/fasting/domain/usecase/acknowledge_fasting_warning_usecase.dart';
import 'package:opennutritracker/features/fasting/domain/usecase/cancel_fasting_usecase.dart';
import 'package:opennutritracker/features/fasting/domain/usecase/complete_fasting_usecase.dart';
import 'package:opennutritracker/features/fasting/domain/usecase/get_active_fasting_session_usecase.dart';
import 'package:opennutritracker/features/fasting/domain/usecase/start_fasting_usecase.dart';
import 'package:opennutritracker/features/fasting/presentation/bloc/fasting_bloc.dart';
import 'package:opennutritracker/fork/screens/fasting/fasting_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';

// G2-12: the fasting page asks for the notification permission when a fast
// is started there, not when it opens on a fast under way.

class _Repository extends Fake implements FastingRepository {
  final sessions = <String, FastingSessionEntity>{};

  @override
  Future<void> addSession(FastingSessionEntity s) async => sessions[s.id] = s;

  @override
  Future<void> updateSession(FastingSessionEntity s) async =>
      sessions[s.id] = s;

  @override
  Future<FastingSessionEntity?> getActiveSession() async =>
      sessions.values.where((s) => s.isActive).firstOrNull;

  @override
  Future<List<FastingSessionEntity>> allSessions() async =>
      sessions.values.toList();
}

class _Config extends Fake implements GetConfigUsecase {
  @override
  Future<ConfigEntity> getConfig() async => const ConfigEntity(
    true,
    true,
    false,
    AppThemeEntity.system,
    fastingWarningAcknowledged: true,
  );
}

class _Acknowledge extends Fake implements AcknowledgeFastingWarningUseCase {}

class _Notifications extends Fake implements NotificationService {
  var scheduled = 0;
  var asked = 0;

  @override
  Future<bool> requestPermission() async {
    asked++;
    return true;
  }

  @override
  Future<void> cancelFastingComplete() async {}

  @override
  Future<void> scheduleFastingComplete({
    required DateTime when,
    required String title,
    required String body,
    required String channelName,
    required String channelDescription,
  }) async => scheduled++;
}

void main() {
  late _Repository repository;
  late _Notifications notifications;

  setUp(() {
    repository = _Repository();
    notifications = _Notifications();
    locator.registerSingleton<FastingRepository>(repository);
    locator.registerSingleton<NotificationService>(notifications);
    locator.registerFactory(
      () => FastingBloc(
        _Config(),
        GetActiveFastingSessionUseCase(repository),
        StartFastingUseCase(repository),
        CancelFastingUseCase(repository),
        CompleteFastingUseCase(repository),
        _Acknowledge(),
      ),
    );
  });

  tearDown(locator.reset);

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: S.supportedLocales,
        home: const FastingScreen(),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('opening on a fast under way does not ask', (tester) async {
    repository.sessions['f'] = FastingSessionEntity(
      id: 'f',
      startedAt: DateTime.now().subtract(const Duration(hours: 2)),
      targetDurationMinutes: 16 * 60,
    );
    await open(tester);

    expect(find.bySemanticsIdentifier('fasting-cancel'), findsOneWidget);
    expect(notifications.asked, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('changing the plan of a fast under way does not ask', (
    tester,
  ) async {
    repository.sessions['f'] = FastingSessionEntity(
      id: 'f',
      startedAt: DateTime.now().subtract(const Duration(hours: 2)),
      targetDurationMinutes: 16 * 60,
    );
    await open(tester);
    final before = notifications.scheduled;

    await tester.tap(find.text('18:6'));
    await tester.pump();
    await tester.pump();

    expect(notifications.scheduled, greaterThan(before));
    expect(notifications.asked, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('starting a fast asks once', (tester) async {
    await open(tester);
    expect(notifications.asked, 0);

    await tester.tap(find.bySemanticsIdentifier('fasting-start'));
    await tester.pump();
    await tester.pump();

    expect(notifications.asked, 1);
    expect(notifications.scheduled, 1);
    await tester.pumpWidget(const SizedBox());
  });
}
