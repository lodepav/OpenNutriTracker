# Spending the Anthropic promo credits on real evals

Plan agreed 2026-11-05 (about $100 of personal Anthropic API credits). The
photo and text evals in `test/fork/eval/` have run on answers a Claude Code
subagent wrote (`REPLAY.md`). This spends the credits on the same tests
with real API calls, through the app's own Anthropic client.

## Why real calls

- **The subagent is not the app's request.** It runs under Claude Code's
  own instructions, without the app's tool schema, image encoding or
  thinking settings. Its answers are close to the API's, not the same: on
  one pork plate the app's call said 180 g of potatoes, the subagent 300 g.
- **Answers vary between runs.** One plate's meatballs came back three
  ways. Repeats show whether a fix holds or got lucky once, and at these
  prices repeats are cheap.
- **The harness is built.** `FORK_EVAL_ANTHROPIC_KEY` makes the tests call
  `AnthropicMealItemsApi` directly (`direct:<model>` specs).

## Where to run it

On your **personal computer**, with the key there. Not on a work laptop,
WSL or not, since the credits and key are personal. Not in a Claude Code
cloud session either: it sends `api.anthropic.com` requests under the
session's own account and stores no key for that host.

Never paste the key into a chat, a commit, or a cloud environment's
variables (stored as plain text). Set a spend limit in the Anthropic
Console before the first run.

The same computer can run the Android emulator, so the new screens (amount
picker, review list, macro colours, fat following the goal, the basket's
meal card) can be checked in the running app too (`tools/adb/`). A Claude
session can drive both through Remote Control, from the Claude desktop app
or `claude remote-control` in the project folder; the key stays local.

## Setup

```sh
git checkout claude/backups-report-redesign-gbfeka   # or fork/main once merged
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter gen-l10n
python3 -m pip install pillow
python3 -I fork/tools/fetch_eval_photos.py          # the 65-photo test set
export FORK_EVAL_ANTHROPIC_KEY=sk-ant-...
export FORK_EVAL_ONLINE=1                           # search Open Food Facts as the app does (D40)
```

With only the Anthropic key set, the tests run the app's default,
`direct:claude-haiku-5-5`. `FORK_EVAL_MODELS=direct:claude-haiku-5-5,direct:claude-sonnet-5-5`
runs both side by side; Sonnet 5.5 is asked unforced, as it refuses a
forced tool call. Each run writes `build/fork-eval/<time>-<kind>/report.md`.

`FORK_EVAL_ONLINE=1` matters: without it the tests search only the bundled
table, and a branded Open Food Facts product winning a row (the tinned
tomatoes and dry porridge mix of D40's breakfast) cannot show up.

## What it costs

Prices per million tokens: Haiku 5.5 $0.10 in, $0.50 out; Sonnet 5.5 $2 in,
$10 out. A photo read is about 3,000 tokens in and a few hundred to a
thousand out: about $0.001 a call on Haiku, $0.02-0.03 on Sonnet. A pass
of the photo suites is on the order of 1,000 calls: about **$1 on Haiku**,
**$20-30 on Sonnet**. These are estimates; the first run's usage in the
Console gives the real figure, and the plan below should be rescaled to it.

## The plan, in order

| Step | What | Runs | About |
|---|---|---|---|
| 1 | Baseline on Haiku 5.5 | 3 × areas 1-2 | $3 |
| 2 | Your own meals | each, a few times | cents |
| 3 | Tune the photo prompts against a held-back half | as needed | $10-20 |
| 4 | One Sonnet 5.5 pass | 1 × areas 1-2 | $25 |
| | Spare, for repeats and area 3 | | ~$50 |

**1. Baseline (Haiku, three times).** Where the photo path stands and how
much it varies, and a check that the recent prompt changes (foods named as
cooked, counts for bacon and meatballs, halves counted as whole items)
made nothing worse.

```sh
flutter test test/fork/eval/calorie_eval_test.dart
flutter test test/fork/eval/portion_eval_test.dart
flutter test test/fork/eval/photo_eval_test.dart
flutter test test/fork/eval/ilunch_eval_test.dart
```

**2. Your own meals.** The most valuable data: photos you logged, each with
a weight you measured or a menu's published value. `portion_eval_test`
takes a private set with `FORK_EVAL_PHOTOS=<dir>/photos.json` (photos in
`<dir>/photos`, each with the note in its `typed` field). Keep the set
under `build/` or outside the repo, so the photos are never committed.

**3. Prompt tuning.** Change a photo prompt, run it, and keep the change
only if a held-back half of the photos improves too, so the prompt is not
fitted to the photos it was tuned on.

**4. One Sonnet pass.** Whether an optional "more accurate" model is worth
offering, and how much better it reads hard plates.

## What the tests measure

Each sends real photos or typed meals through the app's logging code,
takes every food at the amount the review starts it at (as if Log were
tapped without changes), and scores the result against known values.

1. **Calories from a photo** (the main score). `calorie_eval_test`: logged
   kcal against the plate's, no note. `portion_eval_test`: the same with
   only the dish's name typed ("pork chop"), the way most meals are logged.
2. **Naming the foods.** `photo_eval_test`: whether each photo's foods are
   named and find a row. `ilunch_eval_test`: Riga lunch photos with
   Latvian notes, recognition only (their menus publish no nutrition).
3. **Harder cases**, once 1-2 show where the app goes wrong.
   `hard_note_eval_test`: notes that contradict the photo, give grams, a
   fraction, a lower count or an unseen food, and the app set to Latvian.
   `weighed_plate_eval_test`: the five ways a note states weights.
   `dish_eval_test`: a dish split into ingredients against the recipe's
   per-serving values.
4. **Typed meals.** `text_eval_test`: "2 eggs, 100 g toast" and the like,
   in English and Latvian.

Each report gives the typical kcal error, how many plates land within the
margin, the worst misses, and the foods the model got wrong.

Skipped for now: `macrofactor_photo_test` and `macrofactor_search_test`
need a list built from a MacroFactor log kept outside the repo, and
`body_compare_eval_test` is the progress-photo feature, not meal logging.

## After a run

Share the `report.md` files (or paste them into a Claude session). The
misses become fixes, and the same suites, re-run, confirm them. A fix is
done when it holds across the three repeats, not one.
