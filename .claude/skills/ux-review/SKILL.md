---
name: ux-review
description: Review the app's UX on the emulator with the fresh-context ux-reviewer agent against fork/UX_STANDARDS.md, triage its findings, fix what is worth it, reinstall and review again. Use for /ux-review.
argument-hint: "[rounds, default 2] [focus]"
disable-model-invocation: true
---

# UX review loop

Modelled on `implement-review`. The reviewer is the `ux-reviewer` agent (`.claude/agents/ux-reviewer.md`; where that type is not loaded, spawn a general-purpose agent told to follow that file). It starts with a clean context every round, and that independence is the value: never pass it your opinion of the screens or why something is the way it is. Pass only what "Reviewer prompt" lists.

## 0. Set up

1. Run `fork/tools/verify.sh` once; record the baseline. It can run beside the emulator (the `verify` skill).
2. Run `fork/tools/ux_words.py` and fix what it lists, or add it to its `ALLOWED` with the reason. Findings a tool can catch don't need a reviewer. The same goes for 200% text, targets, labels and contrast: `checkScreen` in `test/helpers/ux_checks.dart` runs in each fork screen's test file, so a new screen gets one line there.
3. Boot and install: `SEED=1 FAKE_AI=true fork/tools/emulator.sh` (headless). Push the sample import files if `/sdcard/Download` lacks them.
4. Read the **ledger**, `fork/UX_LEDGER.md`: what earlier reviews decided. New rows go at its end.
5. Set the **focus**, which every round's prompt must carry: the screens named in the arguments, or else the screens the change under review touches, by name and with no opinion of them. A sweep of the whole app takes about an hour; pass `full sweep` only when the user asks for one.

## 1. Rounds (default 2)

Each round:

1. **Spawn** the reviewer (a new spawn each round) with the prompt below. Do not touch the emulator while it runs. From round 2, the focus is only the screens of the fixes accepted in the last round.
2. **Triage** every finding not withdrawn: **accept**, **reject** (wrong, the counterargument wins, or the fix costs more than it gives; say which), or **defer** (real, but upstream-only after phase 4, or out of scope). Look at the screenshot and read the code before deciding. Lows are one line each with no counterargument, so make the case against one yourself; they are deferred or rejected unless the fix is small and clearly helps. Improvements are triaged the same way.
3. **Fix** accepted findings with the minimal change, at seams for upstream files (`fork/SEAMS.md`). An accepted A1, A2, A3 or A6 gets a test that fails without the fix: `test/helpers/ux_checks.dart` pumps a widget at 200% text in the app's font and checks for cut text, tap targets, labels and contrast.
4. **Test**: analyze and the test files of what changed. The full suite waits for the end. The emulator stays up.
5. **Reinstall** (`SEED=1 FAKE_AI=true fork/tools/emulator.sh`) and check each fix on screen yourself.
6. Write the round into the ledger, with the date and screens.

### Reviewer prompt

```
Round N of M. Follow .claude/agents/ux-reviewer.md.
Screenshots: build/ux/roundN
Focus: <screens, or "full sweep">
Ledger (do not re-raise rejected/deferred items without new evidence;
check that accepted ones are fixed on screen):
<this review's rows, and earlier reviews' rejected and deferred rows for the focus's screens>
```

## 2. Finish

Run `fork/tools/verify.sh`: tests are ground truth. Then shut the emulator down (`adb emu kill`). Do not commit unless asked; `fork/UX_LEDGER.md` goes with the fixes when you do. End with: rounds run, tests before and after, the full ledger table, the deferred list (for upstream or later), and any finding where you and the reviewer disagreed on a high.

## Guardrails

- At most one reviewer spawn per round, and only one at a time: they share the emulator.
- If round 2 mostly raises new lows or rephrases rejections, that is the noise floor: say so.
- If a `[heavy-usage]` WIND DOWN line appears, stop after the current triage and report.
