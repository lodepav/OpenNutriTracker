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
import 'package:opennutritracker/features/fasting/presentation/fasting_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';

// Seam S123: the screen writes a change to the fast under way, and the
// timer and history follow it.

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

  @override
  Future<bool> requestPermission() async => true;

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

  testWidgets('a plan picked during a fast is written, and the timer and '
      'its notification follow it', (tester) async {
    final start = DateTime.now().subtract(const Duration(hours: 2));
    repository.sessions['f'] = FastingSessionEntity(
      id: 'f',
      startedAt: start,
      targetDurationMinutes: 16 * 60,
    );
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
    expect(find.text('of a 16-hour fast · 12%'), findsOneWidget);
    final before = notifications.scheduled;

    await tester.tap(find.text('18:6'));
    await tester.pump();
    await tester.pump();

    expect(repository.sessions['f']!.targetDurationMinutes, 18 * 60);
    expect(repository.sessions['f']!.startedAt, start);
    expect(find.text('of a 18-hour fast · 11%'), findsOneWidget);
    expect(notifications.scheduled, greaterThan(before));
    // The fast under way is in the history's bars.
    expect(find.text('Last fast'), findsOneWidget);

    // The screen's timer stops with it.
    await tester.pumpWidget(const SizedBox());
  });
}
