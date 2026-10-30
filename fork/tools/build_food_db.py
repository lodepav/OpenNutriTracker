#!/usr/bin/env python3
"""Build the fork's offline food table (D11) from the open source files.

    python3 -I fork/tools/build_food_db.py \
        --sr-legacy  <dir of FoodData_Central_sr_legacy_food_csv_*> \
        --foundation <dir of FoodData_Central_foundation_food_csv_*> \
        --survey     <dir of FoodData_Central_survey_food_csv_*> \
        --bls        <BLS_4_0_Daten_*.xlsx> \
        [--fineli    <dir of the unzipped Fineli open-data package>] \
        [--dishes fork/data/dishes.json] \
        [--out assets/fork/foods.json.gz]

    python3 -I fork/tools/build_food_db.py --add-dishes

adds the dishes of fork/data/dishes.json that the built table lacks, worked
out from its own rows, without the source files; a full build gives them the
same ids and, up to the table's rounding, the same nutrients.

Downloads (all free):
  USDA FoodData Central (public domain): https://fdc.nal.usda.gov/download-datasets
    SR Legacy, Foundation and FNDDS Survey, CSV. The asset is built from SR
    Legacy 2018-04, Foundation 2025-12-18 and Survey 2024-10-31.
  BLS 4.0 (CC BY 4.0, Max Rubner-Institut): https://www.blsdb.de/download
  Fineli (CC BY 4.0, THL): https://fineli.fi/fineli/en/avoin-data (browser only;
    the site challenges scripts)

The fork's own dishes (fork/data/dishes.json) are recipes over rows of those
tables, for dishes they lack (solyanka, cepelinai); they are worked out last.

The output is gzipped JSON in the shape of the ONT backend's `food_summary` rows
(SPConst column names), so `SpFoodDTO.fromJson` reads it unchanged:

  {"columns": [...], "foods": [[...], ...], "portions": {"<food_id>": [[label, grams], ...]}}

Standard library only, so it runs anywhere Python 3 does.
"""
import argparse
import csv
import gzip
import json
import os
import re
import sys
import zipfile
import xml.etree.ElementTree as ET

# The app's nutrient columns and units (MealNutrimentsEntity): kcal, g, mg, µg.
NUTRIENTS = [
    'energy_kcal_100', 'carbohydrates_100', 'fat_100', 'proteins_100',
    'sugars_100', 'saturated_fat_100', 'fiber_100', 'monounsaturated_fat_100',
    'polyunsaturated_fat_100', 'trans_fat_100', 'cholesterol_100', 'sodium_100',
    'potassium_100', 'magnesium_100', 'calcium_100', 'iron_100', 'zinc_100',
    'phosphorus_100', 'vitamin_a_100', 'vitamin_c_100', 'vitamin_d_100',
    'vitamin_b6_100', 'vitamin_b12_100', 'niacin_100',
]
COLUMNS = ['food_id', 'source', 'source_code', 'name', 'serving_size',
           'serving_gram_weight', 'has_portion'] + NUTRIENTS

# FDC nutrient ids, in preference order (FDCConst in the app). Foundation
# foods often carry only the "by summation" carbohydrate and fat ids.
FDC_IDS = {
    'energy_kcal_100': [2048, 2047, 1008],
    'carbohydrates_100': [1005, 1050],
    'fat_100': [1004, 1085],
    'proteins_100': [1003],
    'sugars_100': [1063, 2000],
    'saturated_fat_100': [1258],
    'fiber_100': [1079],
    'monounsaturated_fat_100': [1292],
    'polyunsaturated_fat_100': [1293],
    'trans_fat_100': [1257],
    'cholesterol_100': [1253],
    'sodium_100': [1093],
    'potassium_100': [1092],
    'magnesium_100': [1090],
    'calcium_100': [1087],
    'iron_100': [1089],
    'zinc_100': [1095],
    'phosphorus_100': [1091],
    'vitamin_a_100': [1106],
    'vitamin_c_100': [1162],
    'vitamin_d_100': [1114],
    'vitamin_b6_100': [1175],
    'vitamin_b12_100': [1178],
    'niacin_100': [1167],
}

# BLS component code and the factor to the app's unit.
BLS_CODES = {
    'energy_kcal_100': ('ENERCC', 1), 'carbohydrates_100': ('CHO', 1),
    'fat_100': ('FAT', 1), 'proteins_100': ('PROT625', 1),
    'sugars_100': ('SUGAR', 1), 'saturated_fat_100': ('FASAT', 1),
    'fiber_100': ('FIBT', 1), 'monounsaturated_fat_100': ('FAMS', 1),
    'polyunsaturated_fat_100': ('FAPU', 1), 'cholesterol_100': ('CHORL', 1),
    'sodium_100': ('NA', 1), 'potassium_100': ('K', 1),
    'magnesium_100': ('MG', 1), 'calcium_100': ('CA', 1), 'iron_100': ('FE', 1),
    'zinc_100': ('ZN', 1), 'phosphorus_100': ('P', 1),
    'vitamin_a_100': ('VITAA', 1), 'vitamin_c_100': ('VITC', 1),
    'vitamin_d_100': ('VITD', 1), 'vitamin_b6_100': ('VITB6', 0.001),  # µg → mg
    'vitamin_b12_100': ('VITB12', 1), 'niacin_100': ('NIA', 1),
}

# Ids are ints in the app. FDC keeps its own (under 10 million); the other
# tables get their own ranges so ids never collide.
BLS_ID_BASE = 10_000_000
FINELI_ID_BASE = 20_000_000
DISH_ID_BASE = 30_000_000


def num(text):
    if text is None:
        return None
    text = str(text).strip().replace(',', '.')
    if not text:
        return None
    try:
        return float(text)
    except ValueError:
        return None


def rounded(value):
    if value is None:
        return None
    return float(f'{value:.4g}')


def read_csv(path):
    with open(path, newline='', encoding='utf-8') as f:
        yield from csv.DictReader(f)


def find(directory, name):
    for root, _, files in os.walk(directory):
        if name in files:
            return os.path.join(root, name)
    sys.exit(f'{name} not found under {directory}')


# --- USDA FoodData Central ---------------------------------------------------

def fdc_foods(directory, source, id_file):
    ids = {row['fdc_id'] for row in read_csv(find(directory, id_file))}
    names = {row['fdc_id']: row['description']
             for row in read_csv(find(directory, 'food.csv'))
             if row['fdc_id'] in ids}
    wanted = {i for ids_ in FDC_IDS.values() for i in ids_}
    # The FNDDS export puts the nutrient *number* (208 for energy) where the
    # other exports put the id (1008); numbers are three digits, ids four.
    id_of_number = {}
    for row in read_csv(find(directory, 'nutrient.csv')):
        number = num(row.get('nutrient_nbr'))
        if number is not None:
            id_of_number.setdefault(int(number), int(row['id']))
    amounts = {}
    for row in read_csv(find(directory, 'food_nutrient.csv')):
        if row['fdc_id'] not in names:
            continue
        nid = int(row['nutrient_id'])
        if nid < 1000:
            nid = id_of_number.get(nid, nid)
        if nid in wanted:
            amounts.setdefault(row['fdc_id'], {})[nid] = num(row['amount'])

    units = {row['id']: row['name']
             for row in read_csv(find(directory, 'measure_unit.csv'))}
    portions, unspecified = {}, {}
    for row in read_csv(find(directory, 'food_portion.csv')):
        if row['fdc_id'] not in names:
            continue
        grams = num(row['gram_weight'])
        if grams and is_unspecified(row):
            unspecified[row['fdc_id']] = rounded(grams)
        label = portion_label(row, units)
        if not grams or grams <= 0 or not label:
            continue
        portions.setdefault(row['fdc_id'], []).append(
            (int(row.get('seq_num') or 0) if (row.get('seq_num') or '').isdigit() else 0,
             label, rounded(grams)))

    for fdc_id, name in names.items():
        values = amounts.get(fdc_id, {})
        nutrients = {}
        for column, preferred in FDC_IDS.items():
            nutrients[column] = next(
                (values[i] for i in preferred if values.get(i) is not None), None)
        food_portions = [(label, grams) for _, label, grams in
                         sorted(portions.get(fdc_id, []), key=lambda p: p[0])]
        serving = (('1 serving', unspecified[fdc_id]) if fdc_id in unspecified
                   else food_portions[0] if food_portions else None)
        yield int(fdc_id), source, fdc_id, name, nutrients, food_portions, serving


def is_unspecified(row):
    """FNDDS's "Quantity not specified": what the survey counts for a food
    eaten in an amount nobody gave. It is the default serving, the amount a
    row starts at when the user or the model named none, where the first
    portion was "1 cup" of butter (224 g) or "1 raisin" (0.5 g)."""
    return (row.get('portion_description') or '').strip().lower() \
        .startswith('quantity not')


def portion_label(row, units):
    description = (row.get('portion_description') or '').strip()
    if description:
        # FNDDS: "1 cup", "1 slice"; "Quantity not specified" is no portion.
        return None if is_unspecified(row) else description
    amount = num(row.get('amount')) or 1
    unit = units.get(row.get('measure_unit_id') or '', '')
    if unit in ('undetermined', ''):
        unit = ''
    modifier = (row.get('modifier') or '').strip()
    if modifier.isdigit():  # FNDDS modifier codes carry no text
        modifier = ''
    amount_text = f'{amount:g}'
    return ' '.join(part for part in (amount_text, unit, modifier) if part) \
        if (unit or modifier) else None


# --- BLS 4.0 -----------------------------------------------------------------

_NS = {'m': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}


def xlsx_rows(path):
    """Rows of the first sheet as lists of strings (minimal stdlib reader)."""
    with zipfile.ZipFile(path) as z:
        shared = []
        if 'xl/sharedStrings.xml' in z.namelist():
            for si in ET.parse(z.open('xl/sharedStrings.xml')).getroot():
                shared.append(''.join(t.text or '' for t in si.iter(
                    '{%s}t' % _NS['m'])))
        sheet = sorted(n for n in z.namelist()
                       if re.match(r'xl/worksheets/sheet\d+\.xml$', n))[0]
        for _, row in ET.iterparse(z.open(sheet)):
            if row.tag != '{%s}row' % _NS['m']:
                continue
            cells = {}
            for c in row.findall('m:c', _NS):
                col = re.match(r'[A-Z]+', c.get('r')).group()
                index = 0
                for ch in col:
                    index = index * 26 + ord(ch) - 64
                v = c.find('m:v', _NS)
                if v is None:
                    inline = c.find('m:is/m:t', _NS)
                    text = inline.text if inline is not None else None
                elif c.get('t') == 's':
                    text = shared[int(v.text)]
                else:
                    text = v.text
                cells[index - 1] = text
            row.clear()
            if cells:
                yield [cells.get(i) for i in range(max(cells) + 1)]


def bls_foods(path):
    rows = xlsx_rows(path)
    header = next(rows)
    column_of = {}
    for i, title in enumerate(header):
        if title and '[' in title:  # "ENERCC Energie (Kilokalorien) [kcal/100g]"
            column_of[title.split(' ')[0]] = i
    code_col = header.index('BLS Code')
    name_col = header.index('Food name')
    for n, row in enumerate(rows):
        row = row + [None] * (len(header) - len(row))
        code, name = row[code_col], row[name_col]
        if not code or not name:
            continue
        nutrients = {}
        for column, (bls_code, factor) in BLS_CODES.items():
            value = num(row[column_of[bls_code]]) if bls_code in column_of else None
            nutrients[column] = value * factor if value is not None else None
        nutrients['trans_fat_100'] = None
        yield BLS_ID_BASE + n, 'bls', code, bls_name(name), nutrients, [], None


# BLS writes "Herring smoked", "Kefir min. 3.5 % fat": the food, then its
# qualifiers, with no comma. The app scores the text before the first comma
# as the title (`deriveTitle`), so "Quark < 10 % fat" lost to "Quark, with
# herbs" on a search for quark. A comma before the first qualifier word puts
# them on the USDA convention: "Herring, smoked", "Kefir, min. 3.5 % fat".
_BLS_QUALIFIER = re.compile(
    r'\s+(?=(?:raw|cooked|boiled|stewed|steamed|fried|deep-fried|roasted|'
    r'grilled|baked|braised|smoked|salted|dried|canned|frozen|drained|'
    r'pickled|marinated|fresh|ripe|peeled|unpeeled|with|without|from|in|'
    r'min\.|max\.|approx\.|[<>]|\d)(?:\b|\s|$))')


def bls_name(name):
    name = name.strip()
    head = name.split(',', 1)
    match = _BLS_QUALIFIER.search(head[0])
    if not match or match.start() == 0:
        return name
    return head[0][:match.start()] + ', ' + head[0][match.end():] + \
        (',' + head[1] if len(head) > 1 else '')


# --- Fineli ------------------------------------------------------------------

def fineli_foods(directory):
    sys.exit('Fineli: parser not written yet; run without --fineli')


# --- The fork's dishes ------------------------------------------------------

def dish_foods(path, rows):
    """Each dish of [path] as a row: its ingredients' nutrients summed and
    put over the cooked weight. [rows] are the built rows by (source, name);
    a nutrient any ingredient lacks is unknown for the dish."""
    with open(path, encoding='utf-8') as f:
        dishes = json.load(f)['dishes']
    for n, dish in enumerate(dishes):
        nutrients = {}
        for column in NUTRIENTS:
            total = 0.0
            for source, name, grams in dish['ingredients']:
                if (source, name) not in rows:
                    sys.exit(f'{dish["code"]}: no {source} row "{name}"')
                value = rows[source, name][column]
                if value is None:
                    total = None
                    break
                total += value * grams / 100
            nutrients[column] = (None if total is None
                                 else total * 100 / dish['yield_g'])
        serving = tuple(dish['serving'])
        yield (DISH_ID_BASE + n, 'fork_dishes', dish['code'], dish['name'],
               nutrients, [serving], serving)


# --- Output ------------------------------------------------------------------

def add_dishes(dishes_path, out):
    """Appends to the table at [out] the dishes it lacks, by code."""
    with gzip.open(out, 'rt', encoding='utf-8') as f:
        table = json.load(f)
    columns = table['columns']
    rows = {}
    for food in table['foods']:
        row = dict(zip(columns, food))
        rows.setdefault((row['source'], row['name']), row)
    have = {row[2] for row in table['foods'] if row[1] == 'fork_dishes'}
    added = []
    for food_id, src, code, name, nutrients, food_portions, serving in \
            dish_foods(dishes_path, rows):
        if code in have:
            continue
        table['foods'].append([food_id, src, code, name, serving[0],
                               serving[1], True]
                              + [rounded(nutrients.get(c)) for c in NUTRIENTS])
        table['portions'][str(food_id)] = [list(p) for p in food_portions]
        added.append(name)
    if not added:
        print(f'no dishes to add -> {out} unchanged')
        return
    payload = json.dumps(table, ensure_ascii=False, separators=(',', ':'))
    with gzip.open(out, 'wt', encoding='utf-8', compresslevel=9) as f:
        f.write(payload)
    print(f'added {len(added)} dishes: {added} -> {out}')


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--add-dishes', action='store_true',
                        help='add the dishes the built table lacks, from its rows')
    parser.add_argument('--sr-legacy')
    parser.add_argument('--foundation')
    parser.add_argument('--survey')
    parser.add_argument('--bls')
    parser.add_argument('--fineli')
    parser.add_argument('--dishes', default='fork/data/dishes.json')
    parser.add_argument('--out', default='assets/fork/foods.json.gz')
    args = parser.parse_args()
    if args.add_dishes:
        return add_dishes(args.dishes, args.out)
    if not (args.sr_legacy and args.foundation and args.survey and args.bls):
        parser.error('--sr-legacy, --foundation, --survey and --bls are '
                     'required for a full build')

    sources = [
        fdc_foods(args.sr_legacy, 'fdc_sr_legacy', 'sr_legacy_food.csv'),
        fdc_foods(args.foundation, 'fdc_foundation', 'foundation_food.csv'),
        fdc_foods(args.survey, 'fdc_survey', 'survey_fndds_food.csv'),
        bls_foods(args.bls),
    ]
    if args.fineli:
        sources.append(fineli_foods(args.fineli))

    foods, portions, counts, skipped = [], {}, {}, 0
    by_name = {}

    def dishes():
        yield from dish_foods(args.dishes, by_name)

    for source in sources + [dishes()]:
        for food_id, src, code, name, nutrients, food_portions, serving in source:
            if nutrients.get('energy_kcal_100') is None:
                skipped += 1
                continue
            serving = serving or (None, None)
            foods.append([food_id, src, code, name, serving[0], serving[1],
                          bool(food_portions)]
                         + [rounded(nutrients.get(c)) for c in NUTRIENTS])
            if food_portions:
                portions[str(food_id)] = [list(p) for p in food_portions]
            counts[src] = counts.get(src, 0) + 1
            by_name.setdefault((src, name), nutrients)

    os.makedirs(os.path.dirname(args.out) or '.', exist_ok=True)
    payload = json.dumps({'columns': COLUMNS, 'foods': foods, 'portions': portions},
                         ensure_ascii=False, separators=(',', ':'))
    with gzip.open(args.out, 'wt', encoding='utf-8', compresslevel=9) as f:
        f.write(payload)
    print(f'{len(foods)} foods ({counts}), {len(portions)} with portions, '
          f'{skipped} skipped without energy; {os.path.getsize(args.out)} bytes '
          f'-> {args.out}')


if __name__ == '__main__':
    main()
