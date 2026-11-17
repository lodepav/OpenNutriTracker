"""Score a fresh eval run's photo reads against the user's weighed meals.

Answers where a read's gram error is and whether the review's tools could
correct it. Inputs: a weighed manifest (build/fork-eval/weighed/photos.json,
private, or weighed-note/ for the runs whose notes state the weights), whose
photos give `per_serving.kcal` (true grams times estimated densities, so
approximate) and `foods: [{name, grams, match}]`; and run dirs
build/fork-eval/<time>-fresh*/ whose kcal.json lists the reads (KcalReads in
test/fork/eval/logged_kcal.dart). A row counts toward the first food one of
whose `match` words is in its query ('*' takes every row); others are extra.

1. Grams per food: read/true, medians by true size (<35, 35-150, >150 g),
   foods read as 0 g counted apart.
2. Error split: portion error (logged - kcal at true grams, each food at the
   read's own kcal per gram) and row/density error (that - reference).
3. Review reach, reads without a weights note: the meal Size (×0.6-×1.4,
   lib/fork/bulk/meal_scale.dart) at the level nearest the needed plate
   scale, then the amount question's chip (lib/fork/bulk/amount_question.dart)
   nearest the truth on the row with the most energy.

    python3 -I fork/tools/weighed_grams.py --manifest <photos.json> <run dir>...
    python3 -I fork/tools/weighed_grams.py --self-test
"""
import argparse
import json
import math
import pathlib
import re
import statistics

SIZES = [0.6, 0.8, 1.0, 1.2, 1.4]
# the amount pattern of lib/fork/bulk/note_weights.dart; shortcut: ignores
# its count exception ("200g rice, 2 eggs"), fine while no note mixes them
WEIGHT = re.compile(r'(\d+(?:[.,]\d+)?)\s*(kg|grams?|gr|g|ml|l|oz|lb)\b', re.I)


def friendly(value):
    """friendlyAmount in grams; floor(x + 0.5) as Dart rounds half up."""
    step = 5.0 if value < 100 else 10.0 if value <= 300 else 25.0
    return math.floor(value / step + 0.5) * step


def chips(grams):
    """The weight chips around [grams]: it, then about 1½, ¾ and ½ of it.
    shortcut: count chips (a row within 15% of a piece) need the table's
    portions, which kcal.json lacks; add them if a read logs pieces."""
    values = [grams]
    for share in (1.5, 0.75, 0.5):
        v = friendly(grams * share)
        if v > 0 and all(f'{v:g}' != f'{x:g}' for x in values):
            values.append(v)
    return sorted(values)


def food_of(foods, query):
    q = query.lower()
    for i, food in enumerate(foods):
        if any(w == '*' or w in q for w in food['match']):
            return i
    return None


def analyse(read, foods):
    """One read: per food grams and status, the error split, review reach."""
    got = [{'g': 0.0, 'kcal': 0.0, 'rows': 0} for _ in foods]
    extra, rows = 0.0, []
    for r in read['rows']:
        i = food_of(foods, r['query'])
        g, kcal = r.get('grams') or 0.0, r.get('kcal') or 0.0
        if i is None:
            extra += kcal
        else:
            got[i]['rows'] += 1
            got[i]['g'] += g
            got[i]['kcal'] += kcal
        if g > 0:
            rows.append((i, g, kcal))
    logged, ref = read['kcal'], read['reference']
    status, at_true = [], extra
    for food, x in zip(foods, got):
        if x['g'] > 0:
            status.append('read')
            at_true += x['kcal'] / x['g'] * food['grams']
        else:  # its true kcal is unknown from the read, so it lands in density
            status.append('no table row' if x['rows'] else 'not read')
    out = {'photo': read['photo'], 'logged': logged, 'ref': ref,
           'at_true': at_true, 'status': status,
           'read_g': [x['g'] for x in got], 'true_g': [f['grams'] for f in foods],
           'weighed': bool(WEIGHT.search(read.get('note') or ''))}
    seen = [i for i, s in enumerate(status) if s == 'read']
    if out['weighed'] or not seen:
        return out
    need = sum(foods[i]['grams'] for i in seen) / sum(got[i]['g'] for i in seen)
    size = min(SIZES, key=lambda s: abs(s - need))
    out.update(need=need, need_kcal=at_true / logged if logged else None,
               size=size, at_size=logged * size)
    # shortcut: every resolved row counts as one the Size scales (all gram
    # rows, no guesses, in the runs of 2026-11-17); check isScalableRow if not
    top = max(rows, key=lambda r: r[2])
    i, g, kcal = top
    out['top'] = foods[i]['name'] if i is not None else '(extra)'
    if len(seen) > 1 and i is not None:
        # the food whose correction removes the most kcal (D45's question);
        # the gram ratio alone would always pick a small sauce at 2x
        worst = max(seen, key=lambda j: abs(got[j]['g'] - foods[j]['grams'])
                    * got[j]['kcal'] / got[j]['g'])
        out['top_worst'] = i == worst
        ratio = max(seen, key=lambda j: abs(math.log(got[j]['g'] / foods[j]['grams'])))
        out['top_ratio'] = i == ratio
    if i is None:  # no truth for an extra row: the question stays unanswered
        out['inside'], out['at_chip'] = None, out['at_size']
        return out
    # a food read as several rows: its truth split among them as read
    true_row = g * foods[i]['grams'] / got[i]['g']
    first = chips(g)
    out['inside'] = first[0] <= true_row <= first[-1]
    pick = min(chips(math.floor(g * size + 0.5)), key=lambda c: abs(c - true_row))
    out['at_chip'] = out['at_size'] - kcal * size + kcal / g * pick
    return out


def med(xs):
    return f'{statistics.median(xs):.2f} (n={len(xs)})' if xs else 'n/a (n=0)'


def pct(x, ref):
    return f'{100 * (x - ref) / ref:+.0f}%'


def rate(flags):
    flags = [f for f in flags if f is not None]
    return f'{sum(flags)}/{len(flags)}' if flags else 'n/a'


def summary(reads):
    ratios = [(t, r / t) for a in reads for t, r in zip(a['true_g'], a['read_g']) if r > 0]
    lines = [f'- median read/true: all {med([x for _, x in ratios])}; '
             f'<35 g {med([x for t, x in ratios if t < 35])}; '
             f'35-150 g {med([x for t, x in ratios if 35 <= t <= 150])}; '
             f'>150 g {med([x for t, x in ratios if t > 150])}']
    st = [s for a in reads for s in a['status']]
    lines.append(f'- foods read as 0 g: {st.count("not read")} not read, '
                 f'{st.count("no table row")} no table row, of {len(st)}')
    complete = [a for a in reads if all(s == 'read' for s in a['status'])]
    for name, group in (('all reads', reads), ('reads missing no food', complete)):
        lines.append(
            f'- {name}: median |logged-ref|/ref {med([abs(a["logged"] - a["ref"]) / a["ref"] for a in group])}, '
            f'|portion|/ref {med([abs(a["logged"] - a["at_true"]) / a["ref"] for a in group])}, '
            f'|row/density|/ref {med([abs(a["at_true"] - a["ref"]) / a["ref"] for a in group])}')
    tools = [a for a in reads if 'need' in a]
    if tools:
        lines += [
            f'- Size reach ({len(tools)} reads without a weights note): needs <0.6 or >1.4 '
            f'{rate([not 0.6 <= a["need"] <= 1.4 for a in tools])}; most-kcal row on the '
            f'food with the largest kcal error {rate([a.get("top_worst") for a in tools])}, '
            f'on the largest gram ratio {rate([a.get("top_ratio") for a in tools])} (photos with 2+ foods read); '
            f'true amount inside the chips {rate([a["inside"] for a in tools])}',
            f'- median |error|/ref: as read {med([abs(a["logged"] - a["ref"]) / a["ref"] for a in tools])}, '
            f'nearest Size {med([abs(a["at_size"] - a["ref"]) / a["ref"] for a in tools])}, '
            f'nearest Size + chip {med([abs(a["at_chip"] - a["ref"]) / a["ref"] for a in tools])}']
    return lines


def report(name, reads, photos):
    print(f'## {name}\n\n### 1. Grams per food\n')
    print('| photo | food | true g | read g | read/true |\n|---|---|---|---|---|')
    for pid, p in photos.items():
        mine = [a for a in reads if a['photo'] == pid]
        for k, food in enumerate(p['foods']):
            gs = ' '.join(f'{a["read_g"][k]:g}' for a in mine)
            rs = ' '.join(f'{a["read_g"][k] / food["grams"]:.2f}' if a['status'][k] == 'read'
                          else a['status'][k] for a in mine)
            print(f'| {pid} | {food["name"]} | {food["grams"]} | {gs} | {rs} |')
    print('\n### 2. Error split (kcal)\n')
    print('| photo | logged | at true g | ref | portion | row/density | missed |\n|---|---|---|---|---|---|---|')
    for a in reads:
        missed = ', '.join(f['name'] for f, s in zip(photos[a['photo']]['foods'], a['status']) if s != 'read')
        print(f'| {a["photo"]} | {a["logged"]:.0f} | {a["at_true"]:.0f} | {a["ref"]:.0f} | '
              f'{a["logged"] - a["at_true"]:+.0f} | {a["at_true"] - a["ref"]:+.0f} | {missed or "-"} |')
    tools = [a for a in reads if 'need' in a]
    print('\n### 3. Review tools\n')
    if not tools:
        print('Every read has a weights note: the app does not scale weighed plates.')
    else:
        print('| photo | need (g) | need (kcal) | Size | left | most-kcal row | worst kcal | worst ratio '
              '| in chips | err read | err Size | err Size+chip |\n' + '|---' * 12 + '|')
        yn = {True: 'yes', False: 'no', None: '-'}
        for a in tools:
            nk = f'{a["need_kcal"]:.2f}' if a['need_kcal'] else '-'
            print(f'| {a["photo"]} | {a["need"]:.2f} | {nk} | ×{a["size"]:g} | {a["need"] / a["size"]:.2f} '
                  f'| {a["top"]} | {yn[a.get("top_worst")]} | {yn[a.get("top_ratio")]} | {yn[a["inside"]]} | {pct(a["logged"], a["ref"])} '
                  f'| {pct(a["at_size"], a["ref"])} | {pct(a["at_chip"], a["ref"])} |')
    print('\n### Summary\n')
    print('\n'.join(summary(reads)) + '\n')


def self_test():
    foods = [{'name': 'chicken', 'grams': 200, 'match': ['chicken']},
             {'name': 'rice', 'grams': 100, 'match': ['rice']},
             {'name': 'slaw', 'grams': 50, 'match': ['slaw']}]
    read = {'photo': 't', 'note': None, 'kcal': 360.0, 'reference': 600.0, 'rows': [
        {'query': 'chicken breast', 'grams': 130.0, 'kcal': 260.0},
        {'query': 'rice, cooked', 'grams': 50.0, 'kcal': 65.0},
        {'query': 'olive oil', 'grams': 5.0, 'kcal': 35.0},
        {'query': 'carrot slaw', 'row': None, 'grams': None, 'kcal': None}]}
    a = analyse(read, foods)
    assert a['status'] == ['read', 'read', 'no table row'], a['status']
    assert abs(a['at_true'] - (400 + 130 + 35)) < 1e-9, a['at_true']
    split = (a['logged'] - a['at_true']) + (a['at_true'] - a['ref'])
    assert abs(split - (a['logged'] - a['ref'])) < 1e-9
    assert abs(a['need'] - 300 / 180) < 1e-9 and a['size'] == 1.4
    assert chips(130) == [65, 100, 130, 200], chips(130)
    assert a['top'] == 'chicken' and a['top_worst'] is True and a['top_ratio'] is False and a['inside'] is True
    # at ×1.4 chicken is 182 g: chips 90, 140, 182, 270; truth 200 picks 182
    assert chips(182) == [90, 140, 182, 270], chips(182)
    assert abs(a['at_chip'] - 360 * 1.4) < 1e-9, a['at_chip']
    assert analyse(dict(read, note='chicken 200 g'), foods)['weighed']
    print('self-test passed')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--manifest', default='build/fork-eval/weighed/photos.json')
    parser.add_argument('--self-test', action='store_true')
    parser.add_argument('runs', nargs='*')
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    photos = {p['id']: p for p in json.loads(pathlib.Path(args.manifest).read_text())['photos']}
    every = []
    for run in args.runs:
        reads = [analyse(r, photos[r['photo']]['foods'])
                 for r in json.loads((pathlib.Path(run) / 'kcal.json').read_text())
                 if r['photo'] in photos]
        every += reads
        report(pathlib.Path(run).name, reads, photos)
    if len(args.runs) > 1:
        print(f'## Combined: {", ".join(pathlib.Path(r).name for r in args.runs)}\n')
        print('\n'.join(summary(every)))


if __name__ == '__main__':
    main()
