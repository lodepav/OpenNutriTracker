// OpenBite's next version and its release notes, from the merges since the last release (D16),
// after openGym-Hevier's release-notes.mjs (its D52).
//
//   dart fork/tools/release_notes.dart next [--major]   # JSON: {from, version, notes} unreleased
//   dart fork/tools/release_notes.dart notes <ref>      # the notes of the release at <ref>
//   dart fork/tools/release_notes.dart changelog <version> <date> <upstream> <notes file>
//
// Every feature reaches fork/main as one `--no-ff` merge, "Merge fork/<branch>: what it does", so
// those merges, read along fork/main's first parents, are the release's notes. A merge that adds
// a decision (a new `| D<n> |` row in fork/DECISIONS.md) is listed under New and raises the minor
// version; any other is under Fixes and changes and raises the patch. A merge of upstream's is
// listed under From OpenNutriTracker. A major release is only ever asked for. A merge with no
// text of its own ("Merge branch 'fork/label' into fork/main") is noted by its branch's last
// commit. Before the first release, upstream's history (its `v` tags) is left out.
// fork/tools/release-apk.sh writes the notes into fork/CHANGELOG.md and the GitHub release.
import 'dart:convert';
import 'dart:io';

const tagPrefix = 'openbite-v';

typedef Note = ({bool fork, String text});
typedef Merge = ({String subject, String diff, String tip});
typedef Entry = ({String section, String text, List<String> decisions});

final _forkMerge = RegExp(
  r"^Merge (?:branch )?'?fork/[^:\s']+'?(?: into \S+)?(?::\s*(.+))?$",
);
final _conventional = RegExp(r'^\w+(?:\([^)]*\))?!?:\s*');

/// The fork's merge subject as a note: "Merge fork/x: text" is the fork's text; one without
/// text takes [tip], its branch's last commit, without the conventional prefix; anything else
/// is upstream's.
Note noteOf(String subject, {String tip = ''}) {
  final m = _forkMerge.firstMatch(subject.trim());
  if (m != null) {
    final text = m.group(1)?.trim() ?? '';
    final fallback = tip.trim().replaceFirst(_conventional, '');
    return (fork: true, text: text.isNotEmpty ? text : _capital(fallback));
  }
  return (
    fork: false,
    text: subject
        .trim()
        .replaceFirst(RegExp(r'^Merge\s+'), '')
        .replaceFirst(RegExp(r"\s+into\s+'?fork/main'?$"), '')
        .trim(),
  );
}

String _capital(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// The D-numbers a diff of fork/DECISIONS.md adds as new rows (a changed row is removed and
/// added, so it is not new).
List<String> addedDecisions(String diff) {
  List<String> rows(String sign) => [
    for (final m in RegExp(
      '^\\$sign\\| (D\\d+) \\|',
      multiLine: true,
    ).allMatches(diff))
      m.group(1)!,
  ];
  final had = rows('-').toSet();
  return [
    for (final d in rows('+'))
      if (!had.contains(d)) d,
  ];
}

/// Each merge as an entry under 'new', 'fix' or 'upstream'; a text already listed is not
/// listed again (a branch merged twice).
List<Entry> entriesOf(List<Merge> merges) {
  final seen = <String>{};
  final entries = <Entry>[];
  for (final merge in merges) {
    final note = noteOf(merge.subject, tip: merge.tip);
    if (note.text.isEmpty || !seen.add(note.text)) continue;
    final decisions = note.fork ? addedDecisions(merge.diff) : <String>[];
    entries.add((
      section: !note.fork
          ? 'upstream'
          : decisions.isNotEmpty
          ? 'new'
          : 'fix',
      text: note.text,
      decisions: decisions,
    ));
  }
  return entries;
}

/// The version after [version]: major when asked, minor with anything new, else patch; null
/// with nothing to release.
String? nextVersion(String version, List<Entry> entries, {bool major = false}) {
  if (entries.isEmpty && !major) return null;
  final [ma, mi, pa] = version.trim().split('.').map(int.parse).toList();
  if (major) return '${ma + 1}.0.0';
  if (entries.any((e) => e.section == 'new')) return '$ma.${mi + 1}.0';
  return '$ma.$mi.${pa + 1}';
}

const _sections = [
  ('new', 'New'),
  ('fix', 'Fixes and changes'),
  ('upstream', 'From OpenNutriTracker'),
];

/// The notes as Markdown: a heading per section that has entries, newest merge first.
String render(List<Entry> entries) {
  final out = <String>[];
  for (final (key, title) in _sections) {
    final lines = [
      for (final e in entries)
        if (e.section == key) '- ${e.text}',
    ];
    if (lines.isNotEmpty) out.add('### $title\n\n${lines.join('\n')}');
  }
  return out.isEmpty ? 'No changes of its own.' : out.join('\n\n');
}

const _changelogHead =
    '# OpenBite releases\n\n'
    'Written by fork/tools/release_notes.dart at each release (D16).\n';

/// fork/CHANGELOG.md with this release's section put first, under the title.
String prependChangelog(
  String text,
  String version,
  String date,
  String upstream,
  String notes,
) {
  final body = text.startsWith('# OpenBite releases')
      ? text.substring(_changelogHead.length).replaceFirst(RegExp(r'^\n+'), '')
      : '';
  final section =
      '## $version · $date\n\nBased on OpenNutriTracker $upstream.\n\n$notes\n';
  return '$_changelogHead\n$section${body.isNotEmpty ? '\n$body' : ''}';
}

// ── git ───────────────────────────────────────────────────────────────────────────────────────

final _root = File.fromUri(Platform.script).parent.parent.parent.path;

String _git(List<String> args) {
  final r = Process.runSync('git', args, workingDirectory: _root);
  if (r.exitCode != 0) throw ProcessException('git', args, '${r.stderr}');
  return (r.stdout as String).trim();
}

List<String> _lines(String text) => [
  for (final line in text.split('\n'))
    if (line.isNotEmpty) line,
];

/// The newest OpenBite tag reachable from [ref], or null.
String? lastTag(String ref) => _lines(
  _git(['tag', '-l', '$tagPrefix*', '--sort=-v:refname', '--merged', ref]),
).firstOrNull;

/// The first-parent merges in from..to, newest first; with no [from], those upstream's
/// release tags do not reach.
List<Merge> mergesBetween(String? from, String to) {
  final range = from != null
      ? ['$from..$to']
      : [
          to,
          '--not',
          ..._lines(_git(['tag', '-l', 'v*'])),
        ];
  final log = _git([
    'log',
    '--first-parent',
    '--merges',
    '--format=%H%x09%s',
    ...range,
  ]);
  return [
    for (final line in _lines(log))
      if (line.split('\t') case [final hash, final subject])
        (
          subject: subject,
          diff: _git([
            'diff',
            '--unified=0',
            '$hash^1',
            hash,
            '--',
            'fork/DECISIONS.md',
          ]),
          tip: _git(['log', '-1', '--format=%s', '$hash^2']),
        ),
  ];
}

void main(List<String> argv) {
  switch (argv) {
    case ['next', ...final flags]:
      final from = lastTag('HEAD');
      final version = File('$_root/fork/VERSION').readAsStringSync().trim();
      final entries = entriesOf(mergesBetween(from, 'HEAD'));
      final next = nextVersion(
        version,
        entries,
        major: flags.contains('--major'),
      );
      stdout.writeln(
        jsonEncode({
          'from': from,
          'version': next,
          'notes': next != null ? render(entries) : '',
        }),
      );
    case ['notes', final ref]:
      final previous = lastTag('$ref^');
      stdout.writeln(render(entriesOf(mergesBetween(previous, ref))));
    case [
      'changelog',
      final version,
      final date,
      final upstream,
      final notesFile,
    ]:
      final file = File('$_root/fork/CHANGELOG.md');
      file.writeAsStringSync(
        prependChangelog(
          file.existsSync() ? file.readAsStringSync() : '',
          version,
          date,
          upstream,
          File(notesFile).readAsStringSync().trim(),
        ),
      );
    default:
      stderr.writeln(
        'usage: release_notes.dart next [--major] | notes <ref> | '
        'changelog <version> <date> <upstream> <notes file>',
      );
      exit(2);
  }
}
