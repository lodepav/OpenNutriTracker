"""Fetch nutrition-label photos with known values for the label eval.

Takes the most-scanned products on Open Food Facts that have a selected
nutrition photo and kcal, fat, carbohydrate and protein per 100 g, and
writes the photos and a manifest (labels.json) into build/fork-eval/labels/.
The photos and values belong to Open Food Facts' contributors (ODbL,
CC BY-SA), so they are fetched, not committed. The typed values are
crowd-entered: a miss can be the entry's, so the report shows both.

    python3 -I fork/tools/fetch_label_photos.py [--count 20]
"""
import argparse
import json
import pathlib
import time
import urllib.error
import urllib.request

UA = 'label-eval/0.1'
OUT = pathlib.Path('build/fork-eval/labels')
KEYS = {
    'energyKcal': 'energy-kcal_100g',
    'fat': 'fat_100g',
    'carbs': 'carbohydrates_100g',
    'protein': 'proteins_100g',
    'sugars': 'sugars_100g',
    'saturatedFat': 'saturated-fat_100g',
}


def get(url):
    request = urllib.request.Request(url, headers={'User-Agent': UA})
    for wait in (10, 30, 60, None):
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                return response.read()
        except urllib.error.HTTPError as e:
            # The search answers 503 past about 10 requests a minute.
            if e.code not in (429, 503) or wait is None:
                raise
            time.sleep(wait)


def candidates():
    for page in range(1, 11):
        data = json.loads(get(
            'https://world.openfoodfacts.org/api/v2/search?fields=code,'
            'product_name,nutriments,images&sort_by=unique_scans_n'
            f'&page_size=50&page={page}'))
        yield from data['products']
        time.sleep(6)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--count', type=int, default=20)
    count = parser.parse_args().count
    OUT.mkdir(parents=True, exist_ok=True)
    labels = []
    for product in candidates():
        n = product.get('nutriments') or {}
        values = {k: n.get(off) for k, off in KEYS.items()}
        if any(values[k] is None for k in ('energyKcal', 'fat', 'carbs',
                                            'protein')):
            continue
        if not values['energyKcal']:
            continue
        images = product.get('images') or {}
        nutrition = [k for k in images if k.startswith('nutrition_')]
        if not nutrition:
            continue
        key = nutrition[0]
        image = images[key]
        if image.get('sizes', {}).get('full', {}).get('w', 0) < 600:
            continue
        code = product['code']
        path = '/'.join([code[0:3], code[3:6], code[6:9], code[9:]]) \
            if len(code) > 8 else code
        url = (f'https://images.openfoodfacts.org/images/products/{path}/'
               f'{key}.{image["rev"]}.full.jpg')
        try:
            (OUT / f'{code}.jpg').write_bytes(get(url))
        except OSError as e:
            print(f'skip {code}: {e}')
            continue
        labels.append({
            'code': code,
            'name': product.get('product_name') or '',
            'expect': {k: v for k, v in values.items() if v is not None},
        })
        print(f'{len(labels):2} {code} {labels[-1]["name"]}')
        if len(labels) == count:
            break
    (OUT / 'labels.json').write_text(json.dumps(labels, indent=1))


if __name__ == '__main__':
    main()
