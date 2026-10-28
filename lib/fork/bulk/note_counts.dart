/// Whether the user's [note] states [quantity] as a part count: "1.5
/// cabbage rolls", "half a pork chop", "1½ pancakes", "a quarter of the
/// pizza". The photo path drops a count that is not whole as the model's
/// estimate (`ModelMealPhotoInterpreter._countsOnly`); one the user stated
/// is theirs, as a stated gram amount is. The words are English: the app
/// logs in English, other languages only for dish names.
bool noteStatesCount(String? note, double? quantity) =>
    note != null &&
    quantity != null &&
    _counts(note).contains(_rounded(quantity));

double _rounded(double value) => double.parse(value.toStringAsFixed(2));

const _vulgar = {'½': 0.5, '¼': 0.25, '¾': 0.75, '⅓': 1 / 3, '⅔': 2 / 3};
const _words = {'half': 0.5, 'quarter': 0.25};

final _number = RegExp(r'(?<![\d.,])(\d+)(?:[.,](\d+))?');
final _wholeAnd = RegExp(r'(\d+|one|two|three)\s+and\s+an?\s+(half|quarter)');
const _wholeWords = {'one': 1, 'two': 2, 'three': 3};

Set<double> _counts(String note) {
  final text = note.toLowerCase();
  final counts = <double>{};
  for (final m in _number.allMatches(text)) {
    final whole = double.parse(m.group(1)!);
    counts.add(
      m.group(2) == null ? whole : double.parse('${m.group(1)}.${m.group(2)}'),
    );
    // "1½": the whole and the fraction after it.
    final next = m.end < text.length ? _vulgar[text[m.end]] : null;
    if (next != null) counts.add(whole + next);
  }
  for (final MapEntry(:key, :value) in _vulgar.entries) {
    if (text.contains(key)) counts.add(value);
  }
  for (final MapEntry(:key, :value) in _words.entries) {
    if (RegExp('\\b$key\\b').hasMatch(text)) counts.add(value);
  }
  for (final m in _wholeAnd.allMatches(text)) {
    final whole = _wholeWords[m.group(1)] ?? double.parse(m.group(1)!);
    counts.add(whole + _words[m.group(2)]!);
  }
  // To two places, so a model's 0.33 is the note's ⅓.
  return {for (final c in counts) _rounded(c)};
}
