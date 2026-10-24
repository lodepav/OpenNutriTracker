---
name: ux-review
description: Review the app's UX on the emulator with the fresh-context ux-reviewer agent against fork/UX_STANDARDS.md, triage its findings, fix what is worth it, reinstall and review again. Use for /ux-review.
argument-hint: "[rounds, default 2] [focus]"
disable-model-invocation: true
---

# UX review loop

Modelled on `implement-review`. The reviewer is the `ux-reviewer` agent (`.claude/agents/ux-reviewer.md`; where that type is not loaded, spawn a general-purpose agent told to follow that file). It starts with a clean context every round, and that independence is the value: never pass it your opinion of the screens or why something is the way it is. Pass only what "Reviewer prompt" lists.

## 0. Set up

1. Boot and install: `SEED=1 FAKE_AI=true fork/tools/emulator.sh` (headless). Push the sample import files if `/sdcard/Download` lacks them.
2. Run `flutter analyze lib test` and `flutter test` once; record the baseline.
3. Start the **ledger**: `round, id, severity, rule, claim, decision, one-line reason`.

## 1. Rounds (default 2)

Each round:

1. **Spawn** the reviewer (a new spawn each round) with the prompt below. Do not touch the emulator while it runs.
2. **Triage** every finding not withdrawn: **accept**, **reject** (wrong, the counterargument wins, or the fix costs more than it gives; say which), or **defer** (real, but upstream-only after phase 4, or out of scope). Look at the screenshot and read the code before deciding. Lows are deferred or rejected unless the fix is small and clearly helps. Improvements are triaged the same way.
3. **Fix** accepted findings with the minimal change, at seams for upstream files (`fork/SEAMS.md`).
4. **Test**: analyze and the full suite. Tests are ground truth.
5. **Reinstall** (`SEED=1 FAKE_AI=true fork/tools/emulator.sh`) and check each fix on screen yourself.
6. Write the round into the ledger.

### Reviewer prompt

```
Round N of M. Follow .claude/agents/ux-reviewer.md.
Screenshots: build/ux/roundN
Focus: <focus, or "the default coverage">
Ledger (do not re-raise rejected/deferred items without new evidence;
check that accepted ones are fixed on screen):
<ledger rows: id, severity, rule, claim, decision, reason>
```

## 2. Report

Do not commit unless asked. End with: rounds run, tests before and after, the full ledger table, the deferred list (for upstream or later), and any finding where you and the reviewer disagreed on a high.

## Guardrails

- At most one reviewer spawn per round, and only one at a time: they share the emulator.
- If round 2 mostly raises new lows or rephrases rejections, that is the noise floor: say so.
- If a `[heavy-usage]` WIND DOWN line appears, stop after the current triage and report.
