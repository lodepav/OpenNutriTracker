"""List the reads a live eval run got no answer for, as FORK_EVAL_ONLY wants.

A typed run (build/fork-eval/<time>-typed/) lists the meals each model
answered; the rest of text_eval_test.dart's meals failed. A photo run
(build/fork-eval/<time>/) records each failed call's error in results.json.
Several runs merge into one file, so a retry pass covers them all:

    python3 -I fork/tools/eval_failed.py build/fork-eval/<run> ... > failed.json
    FORK_EVAL_ONLY=failed.json FORK_EVAL_OPENROUTER_KEY=... flutter test test/fork/eval/text_eval_test.dart test/fork/eval/photo_eval_test.dart
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
NOTE = ' + note'


def typed_reads():
    """Every typed read the eval makes, as `locale|text`."""
    source = (ROOT / 'test/fork/eval/text_eval_test.dart').read_text()
    reads = []
    for text, latvian in re.findall(
        r"text:\s*'((?:[^'\\]|\\.)*)',\s*latvian:\s*(true|false)", source
    ):
        text = text.replace("\\'", "'")
        reads.append(f'en|{text}')
        if latvian == 'true':
            reads.append(f'lv|{text}')
    return reads


def typed_failed(run):
    answered, spec = {}, None
    for line in (run / 'report.md').read_text().splitlines():
        if line.startswith('## '):
            spec = line[3:].strip()
            answered[spec] = set()
            continue
        cells = [c.strip() for c in line.split('|')]
        if spec and len(cells) > 3 and cells[2] in ('en', 'lv'):
            answered[spec].add(f'{cells[2]}|{cells[1]}')
    return {
        spec: [r for r in typed_reads() if r not in done]
        for spec, done in answered.items()
    }


def photo_failed(run):
    failed = {}
    for key, results in json.loads((run / 'results.json').read_text()).items():
        spec, suffix = (key[: -len(NOTE)], '+note') if key.endswith(NOTE) else (key, '')
        failed.setdefault(spec, []).extend(
            r['id'] + suffix for r in results if r.get('error')
        )
    return failed


def main(runs):
    merged = {}
    for run in map(pathlib.Path, runs):
        found = photo_failed(run) if (run / 'results.json').exists() else typed_failed(run)
        for spec, reads in found.items():
            bucket = merged.setdefault(spec, [])
            bucket.extend(r for r in reads if r not in bucket)
    json.dump({s: r for s, r in merged.items() if r}, sys.stdout, ensure_ascii=False, indent=1)
    print(file=sys.stderr)
    for spec, reads in merged.items():
        if reads:
            print(f'{spec}: {len(reads)} failed', file=sys.stderr)


if __name__ == '__main__':
    main(sys.argv[1:])
