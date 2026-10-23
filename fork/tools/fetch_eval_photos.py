"""Download the photo test set (fork/eval/photos.json) into build/fork-eval/photos/.

The photos belong to the recipe sites, so they are not committed: the manifest
keeps their addresses and this script fetches them for a local run. Each photo
is scaled to at most 1568 px on the long side, about what the app sends, when
Pillow is installed; otherwise it is kept as downloaded. A photo with `crop`
is cut to that part first (needs Pillow), to leave out a pack's printed name.

    python3 -I fork/tools/fetch_eval_photos.py
"""
import argparse
import io
import json
import pathlib
import urllib.request

UA = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0 Safari/537.36'
MAX_SIDE = 1568


def shrink(data, crop=None):
    try:
        from PIL import Image
    except ImportError:
        return data
    image = Image.open(io.BytesIO(data)).convert('RGB')
    if crop:  # fractions of the width and height: left, top, right, bottom
        w, h = image.size
        image = image.crop((crop[0] * w, crop[1] * h, crop[2] * w, crop[3] * h))
    image.thumbnail((MAX_SIDE, MAX_SIDE))
    out = io.BytesIO()
    image.save(out, 'JPEG', quality=85)
    return out.getvalue()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--manifest', default='fork/eval/photos.json')
    parser.add_argument('--out', default='build/fork-eval/photos')
    args = parser.parse_args()
    out = pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    for photo in json.load(open(args.manifest))['photos']:
        target = out / f"{photo['id']}.jpg"
        if target.exists():
            continue
        request = urllib.request.Request(photo['image_url'], headers={'User-Agent': UA})
        try:
            data = urllib.request.urlopen(request, timeout=60).read()
        except Exception as e:  # a dead link is reported, not fatal
            print(f"{photo['id']}: {e}")
            continue
        target.write_bytes(shrink(data, photo.get('crop')))
        print(f"{photo['id']}: {target.stat().st_size // 1024} KB")


if __name__ == '__main__':
    main()
