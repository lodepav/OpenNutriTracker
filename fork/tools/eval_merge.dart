// Repeated live eval runs side by side (fork/eval/CREDITS_PLAN.md): what they cost together, and
// how far each photo's logged kcal moved between runs, so a fix is judged over repeats, not one.
//
//   dart fork/tools/eval_merge.dart build/fork-eval/<run> build/fork-eval/<run> ... > merged.md
//
// Reads each run's usage.json (any suite) and kcal.json (calorie_eval_test, portion_eval_test),
// both written by test/fork/eval/. A run without them adds nothing to that part.
import 'dart:convert';
import 'dart:io';

typedef Usage = ({int calls, int input, int output, double? usd});

/// Every run's usage.json added up by model. A model priced in one run and
/// not another has no total cost.
Map<String, Usage> mergeUsage(List<Map<String, dynamic>> runs) {
  final total = <String, Usage>{};
  for (final run in runs) {
    for (final MapEntry(:key, :value) in run.entries) {
      final u = value as Map<String, dynamic>;
      final had = total[key];
      final usd = u['usd'] as num?;
      total[key] = (
        calls: (had?.calls ?? 0) + (u['calls'] as num).toInt(),
        input: (had?.input ?? 0) + (u['input_tokens'] as num).toInt(),
        output: (had?.output ?? 0) + (u['output_tokens'] as num).toInt(),
        usd: had != null && had.usd == null || usd == null
            ? null
            : (had?.usd ?? 0) + usd,
      );
    }
  }
  return total;
}

/// One photo read (a model, a photo, a note or none) over the runs.
class Spread {
  final String spec, photo;
  final String? note;
  final double reference;
  final kcal = <double>[];

  Spread(this.spec, this.photo, this.note, this.reference);

  double get mean => kcal.reduce((a, b) => a + b) / kcal.length;
  double get min => kcal.reduce((a, b) => a < b ? a : b);
  double get max => kcal.reduce((a, b) => a > b ? a : b);

  /// How far the runs' answers lie apart, against the reference.
  double get spread => (max - min) / reference;

  /// How far the runs' mean is off the reference.
  double get off => (mean / reference - 1).abs();

  /// Whether every run landed within [margin] of the reference.
  bool alwaysWithin(double margin) =>
      kcal.every((k) => (k / reference - 1).abs() <= margin);
}

/// Every run's kcal.json, one [Spread] per read, widest first.
List<Spread> mergeKcal(List<List<dynamic>> runs) {
  final byRead = <String, Spread>{};
  for (final run in runs) {
    for (final read in run.cast<Map<String, dynamic>>()) {
      final spec = read['spec'] as String, photo = read['photo'] as String;
      final note = read['note'] as String?;
      byRead
          .putIfAbsent(
            '$spec\u0000$photo\u0000${note ?? ''}',
            () => Spread(
              spec,
              photo,
              note,
              (read['reference'] as num).toDouble(),
            ),
          )
          .kcal
          .add((read['kcal'] as num).toDouble());
    }
  }
  return byRead.values.toList()..sort((a, b) => b.spread.compareTo(a.spread));
}

String _pct(double v) => '${(v * 100).round()}%';

double _median(List<double> values) {
  final sorted = [...values]..sort();
  return sorted[sorted.length ~/ 2];
}

/// The merged report: cost, then per model how steady its reads were, then
/// the reads that moved most.
String render(
  int runCount,
  Map<String, Usage> usage,
  List<Spread> reads, {
  int widest = 15,
}) {
  final out = StringBuffer('# $runCount eval runs merged\n');
  if (usage.isNotEmpty) {
    out
      ..writeln('\n## Usage\n')
      ..writeln('| Model | Answers | Input tokens | Output tokens | Cost |')
      ..writeln('|---|---|---|---|---|');
    for (final MapEntry(:key, :value) in usage.entries) {
      final usd = value.usd;
      out.writeln(
        '| $key | ${value.calls} | ${value.input} | ${value.output} '
        '| ${usd == null ? 'price not known' : '\$${usd.toStringAsFixed(4)}'} |',
      );
    }
  }
  if (reads.isNotEmpty) {
    out
      ..writeln('\n## Kcal over the runs\n')
      ..writeln(
        'Off: the runs\' mean against the reference. Spread: the highest run less the lowest, '
        'against the reference.\n',
      )
      ..writeln(
        '| Model | Reads | Repeated | Median off | Median spread | Within 25% every run |',
      )
      ..writeln('|---|---|---|---|---|---|');
    final specs = {for (final r in reads) r.spec};
    for (final spec in specs) {
      final mine = reads.where((r) => r.spec == spec).toList();
      final repeated = mine.where((r) => r.kcal.length > 1).toList();
      out.writeln(
        '| $spec | ${mine.length} | ${repeated.length} '
        '| ${_pct(_median([for (final r in mine) r.off]))} '
        '| ${repeated.isEmpty ? '-' : _pct(_median([for (final r in repeated) r.spread]))} '
        '| ${mine.where((r) => r.alwaysWithin(0.25)).length}/${mine.length} |',
      );
    }
    final moved = reads.where((r) => r.kcal.length > 1).take(widest).toList();
    if (moved.isNotEmpty) {
      out
        ..writeln('\n## The reads that moved most\n')
        ..writeln('| Model | Photo | Note | Runs (kcal) | Reference | Spread |')
        ..writeln('|---|---|---|---|---|---|');
      for (final r in moved) {
        out.writeln(
          '| ${r.spec} | ${r.photo} | ${r.note ?? ''} '
          '| ${r.kcal.map((k) => k.round()).join(', ')} | ${r.reference.round()} '
          '| ${_pct(r.spread)} |',
        );
      }
    }
  }
  return '$out';
}

void main(List<String> argv) {
  if (argv.isEmpty) {
    stderr.writeln('usage: dart fork/tools/eval_merge.dart <run dir> ...');
    exitCode = 64;
    return;
  }
  Object? read(String dir, String name) {
    final file = File('$dir/$name');
    return file.existsSync() ? jsonDecode(file.readAsStringSync()) : null;
  }

  final usage = [
    for (final dir in argv)
      if (read(dir, 'usage.json') case final Map<String, dynamic> u) u,
  ];
  final kcal = [
    for (final dir in argv)
      if (read(dir, 'kcal.json') case final List<dynamic> k) k,
  ];
  stdout.write(render(argv.length, mergeUsage(usage), mergeKcal(kcal)));
}
