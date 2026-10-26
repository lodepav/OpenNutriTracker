#!/usr/bin/env python3
"""The fork's changes to upstream's translation files, applied by script.

    fork/tools/l10n_overlay.py           # apply
    fork/tools/l10n_overlay.py --check   # exit 1 if applying would change a file

Upstream's lib/l10n/intl_*.arb change in most releases. The fork keeps its
edits to them here instead of by hand, so a conflict in one is resolved by
taking upstream's side and running this again:
  - the app is called OpenBite in every language (S31, D8);
  - fork/l10n/intl_en_overlay.json sets English keys: the fork's own, and
    upstream's with the fork's wording (sentence case, plurals). A key is
    replaced where it stands, or added at the end with its "@" entry.
Edits are made on the text, so upstream's own formatting stays.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
L10N = ROOT / 'lib/l10n'
OVERLAY = ROOT / 'fork/l10n/intl_en_overlay.json'


def _block_end(text, start):
    """The index after the object whose `{` is at or after [start]."""
    i = text.index('{', start)
    depth, in_str, esc = 0, False, False
    for j in range(i, len(text)):
        c = text[j]
        if in_str:
            if esc:
                esc = False
            elif c == '\\':
                esc = True
            elif c == '"':
                in_str = False
        elif c == '"':
            in_str = True
        elif c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                return j + 1
    raise ValueError('unbalanced object')


def _encode(value, indent):
    if isinstance(value, dict):
        lines = json.dumps(value, indent=2, ensure_ascii=False).split('\n')
        return '\n'.join([lines[0]] + [indent + l for l in lines[1:]])
    return json.dumps(value, ensure_ascii=False)


def set_key(text, key, value):
    entry = re.compile(r'^(\s*)' + re.escape(json.dumps(key)) + r': ', re.M)
    m = entry.search(text)
    if m:
        start = m.end()
        if isinstance(value, dict):
            end = _block_end(text, start)
        else:
            end = _string_end(text, start)
        return text[:start] + _encode(value, m.group(1)) + text[end:]
    # Not there: before the closing brace, after a comma on the last entry.
    close = text.rstrip().rindex('}')
    body = text[:close].rstrip()
    return (body + ',\n  ' + json.dumps(key) + ': ' + _encode(value, '  ')
            + '\n' + text[close:])


def _string_end(text, start):
    assert text[start] == '"', text[start:start + 40]
    esc = False
    for j in range(start + 1, len(text)):
        c = text[j]
        if esc:
            esc = False
        elif c == '\\':
            esc = True
        elif c == '"':
            return j + 1
    raise ValueError('unterminated string')


def overlaid(path, overlay):
    text = path.read_text(encoding='utf-8').replace('OpenNutriTracker', 'OpenBite')
    if path.name == 'intl_en.arb':
        for key, value in overlay.items():
            text = set_key(text, key, value)
        json.loads(text)  # still valid
    return text


def main():
    check = '--check' in sys.argv
    overlay = json.loads(OVERLAY.read_text(encoding='utf-8'))
    stale = []
    for path in sorted(L10N.glob('intl_*.arb')):
        text = overlaid(path, overlay)
        if text != path.read_text(encoding='utf-8'):
            stale.append(path.relative_to(ROOT))
            if not check:
                path.write_text(text, encoding='utf-8')
    if check and stale:
        print('not applied: ' + ', '.join(map(str, stale)) +
              '; run fork/tools/l10n_overlay.py')
        sys.exit(1)


if __name__ == '__main__':
    main()
