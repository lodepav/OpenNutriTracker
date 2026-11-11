import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/bulk/note_chips.dart';
import 'package:opennutritracker/fork/bulk/note_counts.dart';
import 'package:opennutritracker/fork/bulk/note_weights.dart';
import 'package:opennutritracker/fork/bulk/weighed_plate.dart';

NoteChip _chip(String label) => noteChips.singleWhere((c) => c.label == label);

void main() {
  group('a tap', () {
    test('puts the words in an empty note, the cursor after them', () {
      final next = toggleNoteChip('', _chip('Home-cooked'));
      expect(next.text, 'home-cooked');
      expect(next.cursor, 11);
    });

    test('adds them after what is typed, with a comma', () {
      expect(
        toggleNoteChip('pelmeni', _chip('Restaurant')).text,
        'pelmeni, restaurant portion',
      );
      expect(
        toggleNoteChip('pelmeni, ', _chip('Small plate')).text,
        'pelmeni, small plate',
      );
    });

    test('"weighed:" and "counts:" leave a space for the number', () {
      final weighed = toggleNoteChip('plov', _chip('Weighed'));
      expect(weighed.text, 'plov, weighed: ');
      expect(weighed.cursor, weighed.text.length);
      expect(toggleNoteChip('', _chip('Counts')).text, 'counts: ');
    });

    test('a second tap takes exactly those words out', () {
      final chip = _chip('Large plate');
      final on = toggleNoteChip('pelmeni', chip).text;
      expect(noteHasChip(on, chip), isTrue);
      final off = toggleNoteChip(on, chip);
      expect(off.text, 'pelmeni');
      expect(noteHasChip(off.text, chip), isFalse);
    });

    test('takes them out from the middle, one comma kept', () {
      expect(
        toggleNoteChip(
          'pelmeni, home-cooked, sour cream',
          _chip('Home-cooked'),
        ).text,
        'pelmeni, sour cream',
      );
      expect(
        toggleNoteChip('home-cooked, pelmeni', _chip('Home-cooked')).text,
        'pelmeni',
      );
    });

    test('"weighed:" goes, the grams typed after it stay', () {
      expect(toggleNoteChip('weighed: 350 g', _chip('Weighed')).text, '350 g');
    });

    test('the words typed in another case are the chip\'s', () {
      final chip = _chip('Weighed');
      expect(noteHasChip('Weighed: 300 g', chip), isTrue);
      expect(toggleNoteChip('Weighed: 300 g', chip).text, '300 g');
      expect(noteHasChip('pelmeni, Home-Cooked', _chip('Home-cooked')), isTrue);
    });

    test('words changed by the user are not the chip\'s', () {
      expect(noteHasChip('small plates', _chip('Small plate')), isFalse);
      expect(noteHasChip('a large plateful', _chip('Large plate')), isFalse);
      expect(
        toggleNoteChip('small plates', _chip('Small plate')).text,
        'small plates, small plate',
      );
    });

    test('takes the opposite chip\'s words out', () {
      expect(
        toggleNoteChip('pelmeni, small plate', _chip('Large plate')).text,
        'pelmeni, large plate',
      );
      expect(
        toggleNoteChip('large plate, pelmeni', _chip('Small plate')).text,
        'pelmeni, small plate',
      );
      expect(
        toggleNoteChip('restaurant portion', _chip('Home-cooked')).text,
        'home-cooked',
      );
      expect(
        toggleNoteChip('Home-cooked, weighed: 300 g', _chip('Restaurant')).text,
        'weighed: 300 g, restaurant portion',
      );
      // the plates leave the kitchen words alone
      expect(
        toggleNoteChip('home-cooked', _chip('Small plate')).text,
        'home-cooked, small plate',
      );
    });
  });

  group('the app\'s rules read the chips\' words', () {
    test('"weighed:" with grams is a weighed plate, its total or foods', () {
      expect(noteWeights('weighed: 350 g')!.totalGrams, 350);
      expect(noteWeights('plov, weighed: 350 g')!.totalGrams, 350);
      final foods = noteWeights('weighed: rice 200 g, chicken 150 g')!.foods;
      expect([for (final f in foods) f.name], ['rice', 'chicken']);
    });

    test('"weighed:" alone states no weight', () {
      expect(noteWeights('weighed:'), isNull);
      expect(noteStatesNoAmount('weighed:'), isTrue);
    });

    test('a plain chip beside a weighed dish makes no second food', () {
      // read as "plov 350 g": the plate's total, one thing named
      final weights = noteWeights('plov 350 g, home-cooked')!;
      expect(weights.totalGrams, 350);
      expect(weights.namesOneThing, isTrue);
      expect(weights.foods, isEmpty);
    });

    test('"counts:" with a count is a count the note states', () {
      expect(noteStatesCount('counts: 2 eggs, 1.5 pancakes', 1.5), isTrue);
      expect(noteWeights('counts: 2 eggs'), isNull);
    });

    test('the plain words state no amount', () {
      for (final chip in noteChips.where((c) => !c.asksMore)) {
        expect(noteStatesNoAmount(chip.words), isTrue, reason: chip.label);
      }
    });

    test('taken out for the rules, the rest kept', () {
      expect(
        withoutChipWords('rice, home-cooked, chicken 150 g'),
        'rice, chicken 150 g',
      );
      expect(withoutChipWords('weighed: 350 g, large plate'), '350 g');
    });
  });
}
