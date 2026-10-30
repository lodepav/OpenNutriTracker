#!/usr/bin/env python3
"""Fork strings that break the glossary in fork/UX_STANDARDS.md (rule C5).

Run from anywhere: fork/tools/ux_words.py. Exits 1 and lists what it finds.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

# The word the glossary rules out, and the one it asks for.
WORDS = {
    r"weight entr(y|ies)": "weigh-in",
    r"entr(y|ies)": "food",
    r"sections?": "meal",
}

# Where the word is right, and why.
ALLOWED = {
    "lib/fork/body/body_card.dart": "a body metric's values, not foods",
    "lib/fork/history/history_import.dart": "a day's totals, not foods",
    "lib/fork/leftovers/ai_leftovers.dart": "a prompt for the model",
    "lib/fork/label/label_scan.dart": "a prompt for the model",
    "lib/fork/photos/body_compare.dart": "a prompt for the model",
    "lib/fork/layout/home_layout.dart": "Home's sections, not meals",
}

STRING = re.compile(r"'(?:[^'\\\n]|\\.)*'|\"(?:[^\"\\\n]|\\.)*\"")
INTERPOLATED = re.compile(r"\$\{[^}]*\}|\$\w+")
NOT_SHOWN = re.compile(r"Key\(|identifier:|^\s*import |^\s*part |[lL]og\w*\.|Logger\(")


def hits():
    for path in sorted((ROOT / "lib/fork").rglob("*.dart")):
        relative = path.relative_to(ROOT).as_posix()
        if relative in ALLOWED:
            continue
        for number, line in enumerate(path.read_text().splitlines(), 1):
            if line.lstrip().startswith("//") or NOT_SHOWN.search(line):
                continue
            for match in STRING.finditer(line):
                text = INTERPOLATED.sub("", match.group())
                for word, wanted in WORDS.items():
                    if re.search(rf"\b{word}\b", text, re.IGNORECASE):
                        yield f"{relative}:{number}: {match.group()} (say {wanted})"
                        break


def main():
    found = list(hits())
    print("\n".join(found) if found else "No glossary breaks.")
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main())
