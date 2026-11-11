// Chips that write a photo's note for the user (D49): words the app's
// rules and the photo prompt already read, one tap each, undone by a
// second.

/// One chip: what it reads, and the words it puts in the note.
class NoteChip {
  final String label;

  /// Put in the note as they are, and taken out the same.
  final String words;

  /// Words that need what the user types after them ("weighed: 350 g"):
  /// the cursor goes after them and the keyboard opens.
  final bool asksMore;

  const NoteChip(this.label, this.words, {this.asksMore = false});
}

/// The chips under a photo's note. "weighed:" and "counts:" lead to a
/// weight (the weighed plate's read, D24) and a count (S170): a weight or
/// count is what the app's rules key on, not the word. The other four are
/// plain words the photo prompt passes to the model.
const noteChips = [
  NoteChip('Weighed', 'weighed:', asksMore: true),
  NoteChip('Counts', 'counts:', asksMore: true),
  NoteChip('Restaurant', 'restaurant portion'),
  NoteChip('Home-cooked', 'home-cooked'),
  NoteChip('Small plate', 'small plate'),
  NoteChip('Large plate', 'large plate'),
];

const _separator = ', ';

/// Whether [note] holds [chip]'s words, in any case.
bool noteHasChip(String note, NoteChip chip) => _find(note, chip) >= 0;

/// [chip]'s words at a word boundary in [note]: not "small plates".
int _find(String note, NoteChip chip) {
  var from = 0;
  while (true) {
    // as typed in any case: "Weighed: 300 g" is the chip's
    final at = note.toLowerCase().indexOf(chip.words.toLowerCase(), from);
    if (at < 0) return -1;
    final end = at + chip.words.length;
    final before = at == 0 || !_isWordChar(note[at - 1]);
    final after = end == note.length || !_isWordChar(note[end]);
    if (before && after) return at;
    from = at + 1;
  }
}

bool _isWordChar(String c) =>
    RegExp(r'[\p{L}\p{N}_-]', unicode: true).hasMatch(c);

/// [note] with [chip] tapped, and where the cursor goes: its words taken out
/// with the separator before or after them when [note] holds them, else
/// added at the end after ", " (a "weighed:" or "counts:" with a space for
/// what comes next). The rest of the note is left as typed.
({String text, int cursor}) toggleNoteChip(String note, NoteChip chip) {
  final at = _find(note, chip);
  if (at >= 0) {
    var start = at;
    var end = at + chip.words.length;
    // a space typed after "weighed:" goes with it
    while (end < note.length && note[end] == ' ') {
      end++;
    }
    final head = note.substring(0, start);
    final tail = note.substring(end);
    if (head.trimRight().endsWith(',')) {
      start = head.trimRight().length - 1;
    } else if (tail.trimLeft().startsWith(',')) {
      end += tail.length - tail.trimLeft().length + 1;
    }
    final text = (note.substring(0, start) + note.substring(end))
        .replaceAll(RegExp(r' {2,}'), ' ')
        .trim();
    final cursor = start.clamp(0, text.length);
    return (text: text, cursor: cursor);
  }
  final kept = note.trimRight();
  final words = chip.asksMore ? '${chip.words} ' : chip.words;
  final text = kept.isEmpty
      ? words
      : '$kept${kept.endsWith(',') ? ' ' : _separator}$words';
  return (text: text, cursor: text.length);
}

/// [note] without the chips' plain words and with the colon after
/// "weighed" and "counts" gone, for the rules that read the note's foods
/// and weights: "home-cooked" named beside "plov 350 g" makes no second
/// food, and "weighed: rice 200 g" weighs rice.
String withoutChipWords(String note) {
  var text = note;
  for (final chip in noteChips) {
    if (chip.asksMore) {
      text = text.replaceAll(
        RegExp('\\b${RegExp.escape(chip.words)}\\s*', caseSensitive: false),
        '',
      );
    } else {
      // between two others the comma stays: "rice, home-cooked, chicken"
      text = text.replaceAllMapped(
        RegExp(
          '(,\\s*)?\\b${RegExp.escape(chip.words)}\\b(\\s*,)?',
          caseSensitive: false,
        ),
        (m) => m[1] != null && m[2] != null ? ', ' : ' ',
      );
    }
  }
  return text.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
}
