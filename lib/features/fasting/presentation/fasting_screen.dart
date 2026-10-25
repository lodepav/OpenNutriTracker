import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/notification_service.dart';
import 'package:opennutritracker/features/fasting/presentation/bloc/fasting_bloc.dart';
import 'package:opennutritracker/features/fasting/presentation/widgets/fasting_warning_dialog.dart';
import 'package:opennutritracker/generated/l10n.dart';
// [fork] S123 fasting
import 'package:opennutritracker/features/fasting/data/repository/fasting_repository.dart';
import 'package:opennutritracker/features/fasting/domain/entity/fasting_session_entity.dart';
import 'package:opennutritracker/fork/fasting/fasting_view.dart';
// [/fork]

// [fork] S123 fasting: upstream's presets (13, 16, 18, 20, 36 h) are
// the plans of FastingView and its Custom

class FastingScreen extends StatefulWidget {
  const FastingScreen({super.key});

  @override
  State<FastingScreen> createState() => _FastingScreenState();
}

class _FastingScreenState extends State<FastingScreen> {
  late FastingBloc _bloc;
  final int _selectedHours = 16;
  int? _customHours;
  bool _warningHandled = false;

  // [fork] S123 fasting: every session, for the last seven fasts; and a
  // change to the fast under way (its start or target) written, the timer
  // reloaded and its notification moved
  Future<List<FastingSessionEntity>> _forkHistory = _forkLoadHistory();

  static Future<List<FastingSessionEntity>> _forkLoadHistory() async {
    try {
      return await locator<FastingRepository>().allSessions();
    } catch (_) {
      return const [];
    }
  }

  void _forkReloadHistory() {
    final history = _forkLoadHistory();
    setState(() {
      _forkHistory = history;
    });
  }

  Future<void> _forkChange(FastingSessionEntity session) async {
    await locator<FastingRepository>().updateSession(session);
    _bloc.add(const FastingLoadRequested());
    _forkReloadHistory();
    if (!mounted) return;
    await _cancelCompleteNotification();
    if (!mounted) return;
    await _scheduleCompleteNotification(
      context,
      FastingActive(session: session, now: DateTime.now()),
    );
  }
  // [/fork]

  @override
  void initState() {
    super.initState();
    _bloc = locator<FastingBloc>();
    _bloc.add(const FastingLoadRequested());
  }

  @override
  void dispose() {
    _bloc.close();
    super.dispose();
  }

  Future<void> _handleWarning(BuildContext context) async {
    if (_warningHandled) return;
    _warningHandled = true;
    final navigator = Navigator.of(context);
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const FastingWarningDialog(),
    );
    if (!mounted) return;
    if (accepted == true) {
      _bloc.add(const FastingWarningAcknowledged());
    } else {
      navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    return Scaffold(
      backgroundColor: palette.canvas,
      appBar: AppBar(
        backgroundColor: palette.canvas,
        title: Text(l10n.fastingTitle),
      ),
      body: BlocConsumer<FastingBloc, FastingState>(
        bloc: _bloc,
        listenWhen: (prev, curr) {
          // Schedule on enter-Active; cancel on enter-Idle (user ended the
          // fast). FastingCompleted intentionally not listened for here —
          // the OS-scheduled alarm is firing at exactly that moment.
          if (curr is FastingWarningRequired) return true;
          // [fork] S123: a fast started, ended or done is in the history
          if (curr.runtimeType != prev.runtimeType) return true;
          // [/fork]
          if (curr is FastingActive && prev is! FastingActive) return true;
          if (curr is FastingIdle && prev is! FastingIdle) return true;
          return false;
        },
        listener: (context, state) {
          _forkReloadHistory(); // [fork] S123
          if (state is FastingWarningRequired) {
            _handleWarning(context);
          }
          if (state is FastingActive) {
            _scheduleCompleteNotification(context, state);
          }
          if (state is FastingIdle) {
            _cancelCompleteNotification();
          }
        },
        builder: (context, state) {
          if (state is FastingInitial || state is FastingWarningRequired) {
            return const Center(child: CircularProgressIndicator());
          }
          // [fork] S123 fasting: MacroFactor's timer (FastingA): a ring
          // with the time left, the start (movable) and end, the plan and
          // the last seven fasts (upstream: a large elapsed ring and a
          // target card, the presets only before a start)
          if (state is FastingIdle || state is FastingActive) {
            return FastingView(
              state: state,
              history: _forkHistory,
              onStart: (minutes) =>
                  _bloc.add(FastingStartRequested(minutes)),
              onEnd: () => _confirmCancel(context, l10n),
              onChange: _forkChange,
              pickHours: (hours) => _pickCustomHours(context, from: hours),
            );
          }
          // [/fork]
          if (state is FastingCompleted) {
            return _buildCompleted(context, l10n);
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  // [fork] S123 fasting: upstream's _buildIdle went with FastingView
  // [fork] S123: from the plan shown, and returns the hours picked
  Future<int?> _pickCustomHours(BuildContext context, {int? from}) async {
    final controller = TextEditingController(
      text: (from ?? _customHours ?? _selectedHours).toString(),
    );
    // [/fork]
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: Dimens.shapeL,
          title: Text(S.of(ctx).fastingPresetCustom),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: InputDecoration(suffixText: S.of(ctx).hoursLabel),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(S.of(ctx).dialogCancelLabel),
            ),
            Semantics(
              identifier: 'fasting-custom-confirm',
              child: TextButton(
                onPressed: () {
                  final v = int.tryParse(controller.text.trim());
                  if (v != null && v > 0 && v <= 96) {
                    Navigator.of(ctx).pop(v);
                  }
                },
                child: Text(S.of(ctx).dialogOKLabel),
              ),
            ),
          ],
        );
      },
    );
    if (result != null) {
      setState(() {
        _customHours = result;
      });
    }
    return result; // [fork] S123
  }

  // [fork] S123 fasting: upstream's _buildActive went with FastingView

  Widget _buildCompleted(BuildContext context, S l10n) {
    final textTheme = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    final accent = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.all(Dimens.spacing24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(Dimens.spacing24),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.check_rounded, size: 64, color: accent),
          ),
          const SizedBox(height: Dimens.spacing24),
          Text(
            l10n.fastingComplete,
            style: textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: palette.textStrong,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Dimens.spacing32),
          Semantics(
            identifier: 'fasting-complete-close',
            child: FilledButton(
              style: FilledButton.styleFrom(
                shape: Dimens.shapeM,
                padding: const EdgeInsets.symmetric(
                  horizontal: Dimens.spacing32,
                  vertical: Dimens.spacing16,
                ),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.dialogCloseLabel),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmCancel(BuildContext context, S l10n) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: Dimens.shapeL,
        title: Text(l10n.fastingCancelConfirmTitle),
        content: Text(l10n.fastingCancelConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.dialogCancelLabel),
          ),
          Semantics(
            identifier: 'fasting-cancel-confirm',
            child: TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l10n.fastingCancel),
            ),
          ),
        ],
      ),
    );
    if (confirm == true) {
      _bloc.add(const FastingCancelRequested());
    }
  }

  Future<void> _scheduleCompleteNotification(
    BuildContext context,
    FastingActive state,
  ) async {
    final notificationService = locator<NotificationService>();
    final permitted = await notificationService.requestPermission();
    if (!permitted) return;
    final when = state.session.startedAt.add(state.session.targetDuration);
    if (!when.isAfter(DateTime.now())) return;
    if (!context.mounted) return;
    final l10n = S.of(context);
    await notificationService.scheduleFastingComplete(
      when: when,
      title: l10n.fastingNotificationCompleteTitle,
      body: l10n.fastingNotificationCompleteBody,
      channelName: l10n.fastingNotificationChannelName,
      channelDescription: l10n.fastingNotificationChannelDescription,
    );
  }

  Future<void> _cancelCompleteNotification() async {
    await locator<NotificationService>().cancelFastingComplete();
  }
}
