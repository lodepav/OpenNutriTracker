// fork/tools/release_notes.dart, which numbers a release and writes its notes (D16).
import 'package:flutter_test/flutter_test.dart';

import '../../../fork/tools/release_notes.dart';

void main() {
  test('a fork merge gives its text; one without takes its branch tip', () {
    expect(
      noteOf('Merge fork/lasagna: bare lasagna logs a homemade beef lasagna'),
      (fork: true, text: 'bare lasagna logs a homemade beef lasagna'),
    );
    expect(noteOf("Merge branch 'fork/mf5': MacroFactor round 4"), (
      fork: true,
      text: 'MacroFactor round 4',
    ));
    expect(
      noteOf(
        "Merge branch 'fork/label' into fork/main",
        tip: 'feat(fork): AI nutrition-label scan',
      ),
      (fork: true, text: 'AI nutrition-label scan'),
    );
    expect(noteOf('Merge upstream release v2.5.0 into fork/main'), (
      fork: false,
      text: 'upstream release v2.5.0',
    ));
  });

  test('only new decision rows count, not changed ones', () {
    const diff =
        '+| D16 | **Releases.** |\n-| D8 | old |\n+| D8 | changed |\n'
        '+text | D17 |';
    expect(addedDecisions(diff), ['D16']);
  });

  test('a new decision raises the minor, anything else the patch, major only '
      'when asked', () {
    final entries = entriesOf([
      (
        subject: 'Merge fork/release: releases (D16)',
        diff: '+| D16 | x |',
        tip: '',
      ),
      (subject: 'Merge fork/potato: boiled potato', diff: '', tip: ''),
      (subject: 'Merge fork/potato: boiled potato', diff: '', tip: ''),
      (
        subject: 'Merge upstream release v2.6.0 into fork/main',
        diff: '+| D99 | not ours |',
        tip: '',
      ),
    ]);
    expect(entries.map((e) => e.section), ['new', 'fix', 'upstream']);
    expect(nextVersion('0.1.0', entries), '0.2.0');
    expect(nextVersion('0.1.0', entries.sublist(1)), '0.1.1');
    expect(nextVersion('0.1.3', entries, major: true), '1.0.0');
    expect(nextVersion('0.1.0', []), isNull);
    expect(
      render(entries),
      '### New\n\n- releases (D16)\n\n'
      '### Fixes and changes\n\n- boiled potato\n\n'
      '### From OpenNutriTracker\n\n- upstream release v2.6.0',
    );
  });

  test('the changelog keeps its title and puts the newest release first', () {
    final one = prependChangelog('', '0.1.0', '2026-10-24', '2.5.0', '- a');
    final two = prependChangelog(one, '0.1.1', '2026-10-25', '2.5.0', '- b');
    expect(two, startsWith('# OpenBite releases\n'));
    expect(two.indexOf('## 0.1.1'), lessThan(two.indexOf('## 0.1.0')));
    expect('# OpenBite releases'.allMatches(two).length, 1);
    expect(two, contains('Based on OpenNutriTracker 2.5.0.'));
  });
}
