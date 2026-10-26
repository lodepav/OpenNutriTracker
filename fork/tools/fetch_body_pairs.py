"""Build the progress-photo pairs (fork/eval/bodies.json) into build/fork-eval/bodies/.

The photos belong to their uploaders on Wikimedia Commons, so they are not
committed: the manifest keeps their addresses and this script fetches them
and builds each pair as the app sends it (sideBySide in ai_leftovers.dart):
the earlier photo on the left, the later on the right, 768 px high. Needs
Pillow.

    python3 -I fork/tools/fetch_body_pairs.py
"""
import argparse
import io
import json
import pathlib
import urllib.request

from PIL import Image, ImageEnhance

UA = 'OpenBite-eval/0.1 (https://github.com/lodepav/OpenNutriTracker)'
HEIGHT = 768


def crop(image, part):
    if not part.get('crop'):
        return image
    w, h = image.size
    left, top, right, bottom = part['crop']
    return image.crop((left * w, top * h, right * w, bottom * h))


def adjust(image, how):
    if how == 'dark-warm':  # dimmer, warmer light: the same body, other conditions
        image = ImageEnhance.Brightness(image).enhance(0.6)
        r, g, b = image.split()
        return Image.merge('RGB', (r.point(lambda v: min(255, v * 1.15)), g, b.point(lambda v: v * 0.8)))
    return image


def to_height(image):
    return image.resize((round(image.width * HEIGHT / image.height), HEIGHT), Image.LANCZOS)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--manifest', default='fork/eval/bodies.json')
    parser.add_argument('--out', default='build/fork-eval/bodies')
    args = parser.parse_args()
    out = pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    manifest = json.load(open(args.manifest))
    sources = {}

    def source(name):
        if name not in sources:
            request = urllib.request.Request(manifest['sources'][name]['url'], headers={'User-Agent': UA})
            data = urllib.request.urlopen(request, timeout=120).read()
            sources[name] = Image.open(io.BytesIO(data)).convert('RGB')
        return sources[name]

    def part(spec):
        return adjust(crop(source(spec['src']), spec), spec.get('adjust'))

    for pair in manifest['pairs']:
        target = out / f"{pair['id']}.jpg"
        if target.exists():
            continue
        try:
            if 'joined' in pair:
                image = to_height(part(pair['joined']))
            else:
                left, right = to_height(part(pair['left'])), to_height(part(pair['right']))
                image = Image.new('RGB', (left.width + right.width, HEIGHT))
                image.paste(left, (0, 0))
                image.paste(right, (left.width, 0))
        except Exception as e:  # a dead link is reported, not fatal
            print(f"{pair['id']}: {e}")
            continue
        image.save(target, 'JPEG', quality=80)
        print(f"{pair['id']}: {target.stat().st_size // 1024} KB")


if __name__ == '__main__':
    main()
