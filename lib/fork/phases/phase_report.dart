import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_weight_log_usecase.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_service.dart';
import 'package:opennutritracker/fork/adaptive/trend_points.dart';
import 'package:opennutritracker/fork/phases/phases.dart';
import 'package:opennutritracker/fork/trends/detail_stats.dart';
import 'package:opennutritracker/fork/trends/detail_widgets.dart';
import 'package:opennutritracker/core/utils/calc/calendar_day_calc.dart';
import 'package:opennutritracker/fork/trends/trend_stats.dart'
    show isLogged, meanOf;
import 'package:opennutritracker/fork/units/energy_text.dart';
import 'package:opennutritracker/fork/units/weight_text.dart';

DateTime _date(DateTime t) => DateTime(t.year, t.month, t.day);

/// How one phase of a plan went, from its first day to its last, or to
/// today while it runs.
class PhaseReport {
  final int index;
  final DietPhase phase;
  final DateTime first;
  final DateTime last;
  final bool running;

  /// The trend weight on its first and last day; null where the trend
  /// does not reach.
  final double? startKg;
  final double? endKg;

  /// The change its pace planned over the days so far, stopping at the
  /// weight it was set to end at.
  final double plannedKg;

  /// The mean energy of its logged days, and how they went against their
  /// goals.
  final double? eatenKcal;
  final ({int onTarget, int under, int over, int logged}) days;

  /// The expenditure estimate on its first and last day.
  final double? startBurnKcal;
  final double? endBurnKcal;

  const PhaseReport({
    required this.index,
    required this.phase,
    required this.first,
    required this.last,
    required this.running,
    required this.startKg,
    required this.endKg,
    required this.plannedKg,
    required this.eatenKcal,
    required this.days,
    required this.startBurnKcal,
    required this.endBurnKcal,
  });

  int get length => CalendarDayCalc.daysBetween(first, last) + 1;

  double? get changeKg =>
      startKg == null || endKg == null ? null : endKg! - startKg!;

  /// The change a week; null under a week in.
  double? get kgPerWeek {
    final days = CalendarDayCalc.daysBetween(first, last);
    return changeKg == null || days < 7 ? null : changeKg! / days * 7;
  }
}

/// A report for each phase of [plan] that has begun by [today], the
/// latest first.
List<PhaseReport> phaseReports(
  PhasePlan plan, {
  required DateTime today,
  required Map<DateTime, double> trendByDay,
  required List<TrackedDayEntity> trackedDays,
  required Map<DateTime, double> burnByDay,
}) {
  final now = _date(today);
  final reports = <PhaseReport>[];
  for (var i = 0; i < plan.phases.length; i++) {
    final first = plan.startOf(i);
    if (first.isAfter(now)) break;
    final end = plan.startOf(i + 1);
    final running = end.isAfter(now);
    final last = running ? now : DateTime(end.year, end.month, end.day - 1);
    final dates = [
      for (
        var d = first;
        !d.isAfter(last);
        d = DateTime(d.year, d.month, d.day + 1)
      )
        d,
    ];
    final phase = plan.phases[i];
    final startKg = trendByDay[first];
    var planned =
        phase.kgPerWeek * CalendarDayCalc.daysBetween(first, last) / 7;
    if (phase.untilKg case final until? when startKg != null) {
      final toGo = until - startKg;
      if (toGo * phase.kgPerWeek > 0 && planned.abs() > toGo.abs()) {
        planned = toGo;
      }
    }
    final outcomes = dayOutcomes(trackedDays, dates);
    final eaten = [
      for (final d in trackedDays)
        if (isLogged(d) && dates.contains(_date(d.day))) d.caloriesTracked,
    ];
    reports.add(
      PhaseReport(
        index: i,
        phase: phase,
        first: first,
        last: last,
        running: running,
        startKg: startKg,
        endKg: trendByDay[last],
        plannedKg: planned,
        eatenKcal: meanOf(eaten),
        days: (
          onTarget: outcomes.onTarget,
          under: outcomes.under,
          over: outcomes.over,
          logged: outcomes.logged,
        ),
        startBurnKcal: burnByDay[first],
        endBurnKcal: burnByDay[last],
      ),
    );
  }
  return reports.reversed.toList();
}

/// What the reports read: the trend, the tracked days and the estimate.
typedef PhaseReportData = ({
  Map<DateTime, double> trendByDay,
  List<TrackedDayEntity> trackedDays,
  Map<DateTime, double> burnByDay,
});

Future<PhaseReportData> loadPhaseReportData(
  PhasePlan plan,
  DateTime today,
  AdaptiveService? service,
) async {
  final weights = await locator<GetWeightLogUsecase>().getAllEntries();
  final trackedDays = await locator<GetTrackedDayUsecase>()
      .getTrackedDaysByRange(plan.start, today);
  List<ExpenditureDay> history;
  try {
    history = await (service ?? AdaptiveService.fromLocator())
        .expenditureHistory();
  } catch (_) {
    history = const [];
  }
  return (
    trendByDay: {
      for (final p in trendPoints(weights, until: today))
        _date(p.date): p.weightKg,
    },
    trackedDays: trackedDays,
    burnByDay: {for (final d in history) _date(d.date): d.expenditureKcal},
  );
}

/// Each phase so far: how the weight moved against the plan, what was
/// eaten and burnt.
class PhaseReportsPage extends StatefulWidget {
  final PhasePlan plan;
  final BodyWeightUnit unit;
  final DateTime today;
  final Future<PhaseReportData> Function() load;

  const PhaseReportsPage({
    super.key,
    required this.plan,
    required this.unit,
    required this.today,
    required this.load,
  });

  @override
  State<PhaseReportsPage> createState() => _PhaseReportsPageState();
}

class _PhaseReportsPageState extends State<PhaseReportsPage> {
  late final _data = widget.load();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Phase reports')),
    body: FutureBuilder(
      future: _data,
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null) {
          return snapshot.hasError
              ? const Center(child: Text('Your history could not be read.'))
              : const Center(child: CircularProgressIndicator());
        }
        final reports = phaseReports(
          widget.plan,
          today: widget.today,
          trendByDay: data.trendByDay,
          trackedDays: data.trackedDays,
          burnByDay: data.burnByDay,
        );
        return ListView(
          padding: EdgeInsets.fromLTRB(
            Dimens.spacing16,
            Dimens.spacing8,
            Dimens.spacing16,
            Dimens.spacing32 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            if (reports.isEmpty)
              const Text('No phase has begun yet.')
            else
              for (final r in reports)
                _ReportCard(report: r, unit: widget.unit),
          ],
        );
      },
    ),
  );
}

class _ReportCard extends StatelessWidget {
  final PhaseReport report;
  final BodyWeightUnit unit;

  const _ReportCard({required this.report, required this.unit});

  @override
  Widget build(BuildContext context) {
    final r = report;
    final text = Theme.of(context).textTheme;
    final muted = paletteOf(context).textMuted;
    final format = DateFormat.MMMd();
    String weeks(int days) {
      final w = (days / 7).round();
      return w == 1 ? '1 week' : '$w weeks';
    }

    final span = r.running
        ? 'Since ${format.format(r.first)} · week ${(r.length - 1) ~/ 7 + 1} '
              'of ${r.phase.weeks}'
        : '${format.format(r.first)} – ${format.format(r.last)} · '
              '${weeks(r.length)}';
    final planPace = r.phase.kgPerWeek == 0
        ? 'maintenance'
        : '${weightChangeText(r.phase.kgPerWeek, unit)} a week';
    return Padding(
      padding: const EdgeInsets.only(top: Dimens.spacing16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              '${r.phase.kind.label}${r.running ? ' (now)' : ''}',
              style: text.titleMedium,
            ),
          ),
          Text(span, style: text.bodySmall?.copyWith(color: muted)),
          const SizedBox(height: Dimens.spacing8),
          TrendRows(
            rows: [
              if (r.startKg != null && r.endKg != null)
                (
                  label: 'Trend weight',
                  value:
                      '${weightText(r.startKg!, unit)} → '
                      '${weightText(r.endKg!, unit)}',
                ),
              (
                label: 'Change',
                value: r.changeKg == null
                    ? '– · plan ${weightChangeText(r.plannedKg, unit)}'
                    : '${weightChangeText(r.changeKg!, unit)} · plan '
                          '${weightChangeText(r.plannedKg, unit)}',
              ),
              (
                label: 'Pace',
                value: r.kgPerWeek == null
                    ? '– · plan $planPace'
                    : '${weightChangeText(r.kgPerWeek!, unit)} a week · '
                          'plan $planPace',
              ),
              (
                label: 'Eaten a day',
                value: r.eatenKcal == null
                    ? '–'
                    : energyText(context, r.eatenKcal!),
              ),
              (
                label: 'On target (within ${(onTargetShare * 100).round()}%)',
                value: '${r.days.onTarget} of ${days(r.days.logged)} logged',
              ),
              if (r.startBurnKcal != null && r.endBurnKcal != null)
                (
                  label: 'Expenditure',
                  value:
                      '${energyText(context, r.startBurnKcal!)} → '
                      '${energyText(context, r.endBurnKcal!)}',
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Opens the reports of [plan] as of [today].
void openPhaseReports(
  BuildContext context,
  PhasePlan plan, {
  required DateTime today,
  required BodyWeightUnit unit,
  AdaptiveService? service,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => PhaseReportsPage(
      plan: plan,
      unit: unit,
      today: today,
      load: () => loadPhaseReportData(plan, today, service),
    ),
  ),
);
