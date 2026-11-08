# Spending the Anthropic promo credits on real evals

Plan agreed 2026-11-05 (about $100 of personal Anthropic API credits),
revised 2026-11-08 with measured call counts and a step 0. Steps 0, 1, 5
and 6 ran on 2026-11-08 (Results below). The credits expire on
**2026-11-26**. The photo and
text evals in `test/fork/eval/` have run on answers a Claude Code subagent
wrote (`REPLAY.md`). This spends the credits on the same tests with real API
calls, through the app's own Anthropic client.

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

The key is `ANTHROPIC_KEY` in the repo's `.env`, which git ignores (`*.env`
in `.gitignore`). Never paste it into a chat, a commit, or a cloud
environment's variables (stored as plain text). Set a spend limit in the
Anthropic Console before the first run.

The same computer can run the Android emulator, so the new screens (amount
picker, review list, macro colours, fat following the goal, the basket's
meal card) can be checked in the running app too (`tools/adb/`). A Claude
session can drive both through Remote Control, from the Claude desktop app
or `claude remote-control` in the project folder; the key stays local.
The app on the emulator may use this key (decided 2026-11-08), so those
screens can be checked with real answers rather than the fake AI. The
OpenRouter key stays off the emulator, and the fake AI stays the default.

## Setup

```sh
git checkout fork/main
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter gen-l10n
python3 -m pip install pillow
python3 -I fork/tools/fetch_eval_photos.py          # the photo test sets
# the key from .env, without printing it
export FORK_EVAL_ANTHROPIC_KEY="$(sed -n 's/^ANTHROPIC_KEY=//p' .env)"
export FORK_EVAL_ONLINE=1                           # search Open Food Facts as the app does (D40)
```

With only the Anthropic key set, the tests run the app's default,
`direct:claude-haiku-5-5`. `FORK_EVAL_MODELS=direct:claude-haiku-5-5,direct:claude-sonnet-5-5`
runs both side by side; Sonnet 5.5 is asked unforced, as it refuses a
forced tool call. Each run writes `build/fork-eval/<time>-<kind>/report.md`.

`FORK_EVAL_ONLINE=1` matters: without it the tests search only the bundled
table, and a branded Open Food Facts product winning a row (the tinned
tomatoes and dry porridge mix of D40's breakfast) cannot show up.

## What a run writes

Step 0 (2026-11-08) gave the harness what the steps below need:

- **`usage.json` and a Usage section** at the end of every live run's
  `report.md`: answers, input and output tokens, and the cost for the
  `direct:` Haiku and Sonnet models. The terminal prints the same per
  model. Cache reads are counted at the full input price, so the cost is an
  upper bound.
- **`kcal.json`** beside the calorie and portion reports: each read's
  logged and reference kcal.
- **`fork/eval/split.json`**: the 91 photos (photos.json and ilunch.json)
  in two halves, `tune` (46) and `held` (45), each cuisine split evenly.
  `FORK_EVAL_SPLIT=tune` or `held` runs one half in the calorie, portion,
  photo and iLunch suites. A private set (`FORK_EVAL_PHOTOS`) is not split.
- **`fork/tools/eval_merge.dart`** sets repeated runs side by side:
  `dart fork/tools/eval_merge.dart build/fork-eval/<run> ...` gives the
  total cost, each model's median kcal error over the runs, how far its
  reads moved between runs, and the reads that moved most.

## What it costs

Prices per million tokens: Haiku 5.5 $0.10 in, $0.50 out; Sonnet 5.5 $2 in,
$10 out. A photo read is about 3,000 tokens in and a few hundred to a
thousand out: well under a tenth of a cent on Haiku, $0.01-0.02 on Sonnet.

One pass of the four main suites is about **280 calls**: calorie about 100
(65 photos, a second read where a photo has a note), portion 65, photo 65,
iLunch 26. That was estimated at $0.30 on Haiku and $6-8 on Sonnet a pass.

Measured (2026-11-08): about **$0.08 a pass on Haiku** and **$1.40 on
Sonnet** (photo $0.69, iLunch $0.39, calorie $0.15, portion $0.15). Step 5's
four suites cost $0.24 over three passes on Haiku.

## The plan, in order

| Step | What | Runs | Spent or about |
|---|---|---|---|
| 0 | Harness: usage, split, merge | - | done, $0 |
| 1 | Baseline on Haiku 5.5 | 3 × the four main suites | done, about $0.25 |
| 2 | Replay against live, same photos | 1 replay + step 1 | $0 |
| 3 | Your own meals | each, a few times | cents |
| 4 | Tune the photo prompts on `tune`, check on `held` | as needed | $1-10 |
| 5 | Typed meals and the harder cases | 3 × | done, $0.24 |
| 6 | Sonnet 5.5, three passes | 3 × the four main suites | done, $4.17 |
| | Spent by 2026-11-08, with the fix checks | | about $4.40 |
| | Left, for steps 2-4, the emulator and repeats | | about $95 |

**1. Baseline (Haiku, three times).** Where the photo path stands and how
much it varies, and a check that the recent prompt changes (foods named as
cooked, counts for bacon and meatballs, halves counted as whole items)
made nothing worse. Merge the three runs.

```sh
flutter test test/fork/eval/calorie_eval_test.dart
flutter test test/fork/eval/portion_eval_test.dart
flutter test test/fork/eval/photo_eval_test.dart
flutter test test/fork/eval/ilunch_eval_test.dart
# three times, then:
dart fork/tools/eval_merge.dart build/fork-eval/<run> build/fork-eval/<run> build/fork-eval/<run>
```

**2. Replay against live.** Run the subagent replay (`REPLAY.md`) on the
same photos and merge it with step 1's runs. If the replay's kcal fall
within the live runs' own spread, the free replay stays good enough to
iterate on, and the credits go to confirming. If not, iteration needs the
credits too, and the spare below shrinks.

**3. Your own meals.** The most valuable data: photos you logged, each with
a weight you measured or a menu's published value. `portion_eval_test`
takes a private set with `FORK_EVAL_PHOTOS=<dir>/photos.json` (photos in
`<dir>/photos`, each with the note in its `typed` field). Keep the set
under `build/` or outside the repo, so the photos are never committed.

**4. Prompt tuning.** Change a photo prompt and run it on
`FORK_EVAL_SPLIT=tune`. Keep the change only if `FORK_EVAL_SPLIT=held`
improves too, so the prompt is not fitted to the photos it was tuned on.
Never move a photo between the halves: earlier runs would stop comparing.

**5. Typed meals and the harder cases.** `text_eval_test` (typed meals,
English and Latvian), then `hard_note_eval_test`, `weighed_plate_eval_test`
and `dish_eval_test`, each three times. Text calls are cheap.

**6. Sonnet, three times.** Whether an optional "more accurate" model is
worth offering, and how much better it reads hard plates. Three passes, not
one, so a lucky run is not mistaken for a better model.

## Results (2026-11-08)

All on `FORK_EVAL_ONLINE=1`, three passes each. Steps 1 and 6 ran on the
same code (`514c07c0`), so they compare directly. The merged reports'
"median off" is the three runs' mean against the reference.

| Suite | Haiku 5.5 (step 1) | Sonnet 5.5 (step 6) |
|---|---|---|
| Photo: dish named | 57/65 | 60-61/65 |
| Photo: set-meal parts named | 46-47/55 | 48-49/55 |
| Photo: count right | 14-15/20 | 17-18/20 |
| Photo: median time a read | 2.2-2.3 s | 3.2-3.3 s |
| iLunch: dish named, no note / with note | 23-25 / 21-23 of 26 | 25 / 25 of 26 |
| Calorie: median off, merged | 52% | 56% |
| Calorie: median spread between runs | 10% | 43% |
| Calorie: within 25% every run | 5/22 | 2/22 |
| Portion: median off, merged | 23% | 36% |
| Portion: within 25% every run | 3/17 | 4/17 |

- **Sonnet recognises better and logs no better.** It names more dishes,
  parts and counts, but its kcal are no closer and move more between runs.
  The kcal error comes mostly from which row a food finds and the amount it
  starts at, not from what the model sees. Haiku stays the default; Sonnet
  is worth offering only as the better recogniser.
- **Step 5 (Haiku).** Typed meals are the weakest: English 7/24 within 25%
  (median off 45-63%), Latvian 2-4/13 (76-111%). Hard notes held, 45-51 of
  about 50 rows right. Weighed plates all passed but one bolognese read.
  Dishes found the recipe 9/9 but only 1/5 landed within 25% (50-57% off).
- **Fixes from step 1's misses** (merged as `b4537ae3` and `05a65fbf`: soup
  and crouton defaults, a count picking a piece, a soup's contents kept in
  the soup, shape words such as "slice" dropped from a search, herb and
  cheese garnish amounts). Over three Haiku calorie passes after them,
  `tune` went from 58% to 16% median off (10/30 to 18/30 within 25%), and
  `held` stayed level (29% to 31%, 14/36 both times): they mended the
  photos they came from without helping or harming the rest.
- **Left for step 4:** pork cutlet and meat patty find Open Food Facts
  products that change between searches; spaghetti bolognese starts at
  100 g; "pizza slice" logs a whole pizza; chłodnik was once split into its
  ingredients; typed Latvian meals and dishes, above.

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
3. **Harder cases.** `hard_note_eval_test`: notes that contradict the
   photo, give grams, a fraction, a lower count or an unseen food, and the
   app set to Latvian. `weighed_plate_eval_test`: the five ways a note
   states weights. `dish_eval_test`: a dish split into ingredients against
   the recipe's per-serving values.
4. **Typed meals.** `text_eval_test`: "2 eggs, 100 g toast" and the like,
   in English and Latvian.

Each report gives the typical kcal error, how many plates land within the
margin, the worst misses, the foods the model got wrong, and what the run
used.

Skipped for now: `macrofactor_photo_test` and `macrofactor_search_test`
need a list built from a MacroFactor log kept outside the repo, and
`body_compare_eval_test` is the progress-photo feature, not meal logging.

## After a run

Share the `report.md` files and the merged report (or paste them into a
Claude session). The misses become fixes, and the same suites, re-run,
confirm them. A fix is done when it holds across the three repeats, not
one.

## Decided

- **The key on the emulator** (2026-11-08): allowed, for checking the new
  screens with real answers. The OpenRouter key never; the fake AI stays
  the default.
- **When the credits expire:** 2026-11-26.
