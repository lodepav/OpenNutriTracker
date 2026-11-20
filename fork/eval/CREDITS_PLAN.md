# Spending the Anthropic promo credits on real evals

Plan agreed 2026-11-05 (about $100 of personal Anthropic API credits),
revised 2026-11-08 with measured call counts and a step 0. Steps 0-7 ran
on 2026-11-08 and 2026-11-09, step 8 on 2026-11-10, the photo portion ideas
on 2026-11-11, the weighed own meals (idea 7) on 2026-11-17 and a firm
Haiku baseline on 2026-11-19 (Results below). Not run yet: the app's Gemini
preset against Google itself (needs a Google AI Studio key) and the
about 30 weighed plates the idea 7 section asks for (needs the user's
meals). The credits
expire on **2026-11-26**. The photo and
text evals in `test/fork/eval/` have run on answers a Claude Code subagent
wrote (`REPLAY.md`). This spends the credits on the same tests with real API
calls, through the app's own Anthropic client.

## Why real calls

- **The subagent is not the app's request.** It runs under Claude Code's
  own instructions, without the app's tool schema, image encoding or
  thinking settings. Its answers are close to the API's, not the same: on
  one pork plate the app's call said 180 g of potatoes, the subagent 300 g.
  Step 2 (2026-11-09) found that the replay does not stand in for live.
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
  in two halves, `tune` (46) and `held` (45), each cuisine split evenly
  (134 photos, 68 and 66, since step 7, round 3).
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

On the 2026-11-08 photo set, one pass of the four main suites is about
**280 calls**: calorie about 100
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
| 2 | Replay against live, same photos | 1 replay + 3 live Haiku | done, $0.05 |
| 3 | Your own meals | 3 × | done, $0.02 |
| 4 | Tune the photo prompts on `tune`, check on `held` | rounds 1-4, 2 × each half | done, $0.45 |
| 5 | Typed meals and the harder cases | 3 × | done, $0.24 |
| 6 | Sonnet 5.5, three passes | 3 × the four main suites | done, $4.17 |
| 7 | Global checks: typed meals, a resolution audit, photo prompt bias, repeated reads, counting | typed 6 ×, audit 1 judge, photos 9 × | done, six rounds; round 1 about $0.15, rounds 3-5 about $6-7 |
| 8 | A photo with no note estimates grams | three rounds | done, about $2.06 |
| | Photo portion ideas, rounds 10-12 | | done, about $1.66 (Gemini $2.68 on OpenRouter) |
| | Idea 7: weighed own meals, six trials | | done, about $1.35 ($0.18 on OpenRouter) |
| | Firm Haiku baseline and body comparison | 5 × the scenarios, 3 × the body pairs | done, about $0.37 |
| | Label reader, and the note evals after the fixes | 3 × | done, label about $0.03 |
| | Spent by 2026-11-08, with the fix checks | | about $4.40 |
| | Recorded by 2026-11-19 in the runs' `usage.json` files under `build/fork-eval` | | about $23 |

The `usage.json` total counts cache reads at the full input price and
leaves out the emulator's calls with the key, so it is not the balance;
the Anthropic Console has that.

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

### Step 2: the replay against live (2026-11-09)

A Haiku subagent answered the calorie and portion suites' 39 requests
(`build/fork-eval/replay/step2`), set beside three live Haiku passes on the
same code (`280d5e4c`, after the fixes above).

| Suite | Live median off | Replay median off | Replay inside the live runs' range | Replay off the live mean (median, of the reference) |
|---|---|---|---|---|
| Calorie (22 reads) | 41% | 38% | 3/22 | 49% |
| Portion (17 reads) | 37% | 24% | 5/17 | 28% |

- **The replay does not stand in for live.** The medians land close, but
  read by read the replay falls inside the three live runs' range 3 times in
  22 and 5 in 17, while live itself moves little (median spread 9% and 19%).
  A replay score says little about what the app's real call does.
- **The subagent breaks the tool's shape.** 10 of 39 answers were one item
  instead of `{"items": [...]}`, which a forced tool call cannot return;
  they were wrapped by hand (originals in `answers-orig`). Others left out
  quantities, so a row logged at 1 kcal.
- **So step 4 iterates live.** A Haiku pass of these two suites costs about
  $0.05, which leaves the spare untouched; the replay stays for tests that
  need no real model.
- **Live misses for step 4:** chłodnik at 470-510 kcal against 132 with no
  note (370-380 with one); the pork cutlets at 7 kcal in one run of each
  suite; solyanka with its note at 880-960 against 354; plov with its note
  at 965-980 against 753.

## Step 3: own meals (2026-11-09)

Six of the user's own canteen and hotel-buffet meals, each with a short
name as the note (`FORK_EVAL_PHOTOS`, kept under `build/`). Nobody weighed
them: the reference is Claude's estimate from the photo, so the set checks
for large misses, not accuracy. Three live Haiku passes: median off 19-35%,
logged 109-123% of the estimates in total. Most of that is one breakfast
plate read at 1,925-2,433 kcal against about 1,430, and the chicken plate
once at 487 against 770.

## Step 4, round 1: two dishes (2026-11-09)

Two live Haiku passes of each suite on each half, against step 2's three.

- **Added to the dishes table:** chłodnik (36 kcal per 100 g, a 300 g bowl;
  the egg stays its own row) and fried pork cutlets (299, a 90 g cutlet).
  With no note, chłodnik went from 488 to 227 kcal (reference 132) and the
  pork cutlets from 336 to 539 (659). Held's calorie median went from 36% to
  24%, tune's from 30% to 34%, within run-to-run noise.
- **The table matters only with no note.** With a note the photo goes the
  estimated-plate way: the model splits a named dish into its foods with
  grams, so a table dish is not looked up. The portion medians moved
  within noise (tune 41% to 44%, held 29% to 36%).
- **The report showed no rows** for a dish the read split itself; it now
  names each such dish with its kcal.

## Step 4, round 2: a main dish starts at a plate (2026-11-09)

A food with no serving logged at 100 g, a third of a plate: "Spaghetti
Bolognese" at 85 kcal (510) and "Pilaf" at 167 (plov, 753). A cooked main
dish with neither an amount nor a serving now starts at 300 g, as a soup
starts at a bowl (S98, `isMainDish`). Two live Haiku passes on each half,
against round 1's: the calorie median went from 34% to 22% on tune and
from 24% to 18% on held; plov from 405 to 844 kcal, bolognese from 169 to
339. With a note the model estimates the grams, so the portion suite does
not reach this default; its medians moved within noise.

## Step 4, round 3: spaghetti, the pizza slice, cutlets (2026-11-09)

- **Spaghetti:** "spaghetti, boiled" found spaghetti squash (49 kcal per
  100 g), which holds both words. An everyday row's name now also stands
  for its "boiled" and state-first spellings ("boiled spaghetti", "cooked
  spaghetti"), so it finds cooked pasta. Bolognese went from 339 to 517
  kcal against 510.
- **The pizza slice:** "2 slices of pepperoni pizza" matched the word pizza
  in "1 personal size pizza" and logged 870 kcal against 600. A slice of a
  food with no slice portion now takes its piece (S202): 753.
- **Pork cutlet and meat patty** already find round 1's dish, not Open Food
  Facts products.
- Two live Haiku passes against round 2's: the calorie median went from 22%
  to 15% on tune and from 18% to 24% on held. Held's change is all the dill
  sauce: in one run the model listed its garlic apart, and "garlic" logged
  raw garlic at 136 g, 203 kcal. That amount is left to look at; the
  portion medians held level (53% to 50%, 27% both).

## Step 4, round 4: garlic and chłodnik (2026-11-09)

- **Garlic** with no amount took USDA's first serving, a 136 g cup: it now
  starts at no more than 5 g, like a herb (S98, `garnishGrams`).
- **Chłodnik** came back as "cold beetroot soup (chlodnik)", "chilled
  borscht" or "cold beet soup (chilled borscht with kefir or yogurt)": no
  row held every word, so a second call broke it down at 263-351 kcal. The
  dish's name now holds those words, and a name that finds nothing drops
  its bracketed part and tries again.
- Two live Haiku passes against round 3's: the calorie median went from
  15% to 14% on tune and from 24% to 18% on held; chłodnik from 437 to
  263 kcal (132), the dill sauce from 443 to 244 (238). The portion
  medians went from 50% to 44% on tune and stayed at 27% on held.
- **Left:** chłodnik's two egg halves log as two eggs (155 of its 263 kcal).

## Step 7: global checks (2026-11-09)

Fixes that move many foods at once, not a dish at a time.

**1. Typed meals.** `text_eval_test` was 53-58% off (median) in English
and 66-93% in Latvian, logging 166-198% of the references. The prompt
kept each food in the language it was typed in, and the fork's table is
English: a Latvian name fell to whatever product shared a word. Orange
juice became "Rica Sula" at 148 kcal per 100 g, coffee with milk became
popcorn, butter peanut butter, an omelette 2,295 kcal of "Egg Omletes".

- The typed prompt now asks for each food as its nearest generic English
  name, keeping a brand, and a named dish as one entry (S204).
- A model's reading of typed text now ranks a product the name does not
  brand below the generic row, as a photo's does (S196); the parser's
  words still may mean the packet.
- A product with no brand trails too: a brandless "Big Mac" with no
  serving logged 1 g.
- Six live Haiku passes, the last two with everything: 16% off in
  English, 7% in Latvian, logging 99-109% of the references.

| Typed, median off | Before | Prompt | + named dishes | + brandless |
|---|---|---|---|---|
| English | 53-58% | 25% | 18-19% | 16% |
| Latvian | 66-93% | 14-29% | 13% | 7% |

**2. Resolution audit.** The 326 distinct food names in every report
under `build/fork-eval` were resolved again against the table
(`resolution_dump_test.dart`), and Haiku judged each name and row: 192
fine, 33 the wrong food, 24 an odd serving, 10 the wrong form, 8 an
implausible energy. By how often each name came up, the top four were
one cause: a single Latvian word matched one word of a fork dish's
bracketed names. "lasis" (salmon) found a salmon soup made "ar lasi",
"pankūkas" liver patties ("aknu pankūkas"), "biezpiens" syrniki,
"speķis" grey peas with bacon, 159 uses in all.

- A dish's bracketed names now count only whole, up to what it is made
  with, unless the name also shares a word with the dish's own name:
  "pelēkie zirņi" and "fried pork patties" still find their dishes.
  "Gyros" is added to the shawarma as a name of its own.
- Left, each a food or two: cooked carrots at 72 kcal per 100 g, "pork
  chop" landing on a stuffed chop (fixed under 3), "melted butter" on Brussels sprouts
  with butter, "meat sauce" on meatballs.

**3. Photo prompt bias.** The note path's estimate (`estimatedPlatePrompt`,
the portion suite) logged 157% of the labels on tune and 136% on held.
Dropping "Restaurant and recipe photos are often generous" moved neither
(157%, 131%), so the line is gone and the plate sizes stay. The ingredient
rows of each breakdown, now listed in the reports, showed where the excess
came from: the rows, not the grams. "beef, cooked" found beef bacon at 449
kcal per 100 g in a stuffed pepper and a solyanka, "pork, cooked, roasted"
fatty backribs, "pork chop" a stuffed chop. A meat named only by how it
was cooked or cut now takes its generic row ("Beef, NFS", "Pork, NFS",
"Pork, chop, NS as to fat eaten"; `everydayRowName`).

**4. Repeated reads.** Three passes of the same code read most photos
identically (the median spread is 0%), so the median of three reads
changes little: 25% off against 25% for one read, the mean 34% against
37%. Not worth three times the cost; the variation between runs comes
from Open Food Facts' live results more than from the model.

**5. Counting.** The photo prompt's halves rule now starts with "2 egg
halves are 1 egg" (S60), and the estimate's piece sizes say two halves
are one egg: chłodnik with no note went from 252 to 180 kcal (132). A
note naming one plain food now asks for every piece the photo shows:
"chicken cutlets" had logged one cutlet, 192 kcal against 418, and now
logs 491-534.

| After 3-5, two live passes | Before | After |
|---|---|---|
| Calorie, tune: median, total | 21%, 131% | 19%, 115% |
| Calorie, held: median, total | 25%, 100% | 24%, 101% |
| Portion, tune: median, total | 53%, 157% | 31%, 122-141% |
| Portion, held: median, total | 50%, 136% | 39-40%, 127-128% |

- **Left:** the estimate still puts 100 g of egg in a chłodnik and a full
  bowl of solids in each soup (solyanka 530-629 against 354, borscht 331
  against 181).

## Step 7, round 2: soups, comma spellings, brand words (2026-11-09)

- **A bowl's foods fill the bowl.** The estimate put 300 g of broth and
  360 g of solids in one bowl of solyanka, and 490 g in a small chłodnik.
  It now hears that the solids take the base's place. Solyanka went from
  731-926 to 494-682 kcal (354), cold beet soup from 117-169 to 118-144
  (100). The borscht stays near 290 against 181: the recipe's reference
  leaves out the toasted bread beside the bowl, which the read counts.
- **A mapped name in other commas.** "pork cutlet, breaded, fried" missed
  the schnitzel mapped to "pork, cutlet, breaded, fried" and found minced
  pork patties. Every mapped name now matches by its words alone: the
  karbonāde went from 389-449 to 330 kcal (262).
- **A brand made of the product's own words** ("Rice Pilaf", for "Giant,
  rice pilaf") no longer counts as named: a plov's "pilaf with carrots
  and rice" logged that dry mix at 339 kcal per 100 g, 1,312 in all.
- Tried and dropped: "spaghetti bolognese" mapped to a restaurant plate.
  Its 554 g serving, beside the spaghetti a photo lists too, made 932
  kcal (510).
- Typed: 14% off in English, 7-13% in Latvian.
- **Left, each a row's energy, not a read's:** LIDO's garlic sauce
  (495 kcal per 100 g on its label) against the table's 683, now that
  the note's estimate gives its 60 g instead of the 32 g serving; the
  dill sauce's Open Food Facts product at 607; a stuffed pepper listed
  beside its own filling; "baked casserole with cheese and tomato" falling
  back to dry black beans.

## Step 7, round 3: more photos, MacroFactor, Sonnet again (2026-11-09)

- **43 more photos** from recipe sites with published nutrition: 22 to
  tune (now 68), 21 held (now 66).
- **MacroFactor list** (git-ignored, under `build/fork-eval/macrofactor`):
  150 logged foods and 22 dish photos. With Open Food Facts live, the
  122 single foods: search top row 102 (92% weighted by how often they
  are logged), first 5 111 (96%), resolver on the typed name 119 (99%).
  The test parsed the amount off first only after this round: searched
  with "10 g butter" it found a "10 oz" steak. Haiku's describe: 108-110
  of 122 right, dishes 22-24 of 28. The dish photos: named 16 of 22,
  right row 15.
- **Junk rows.** Resolution never used the Food tab's most-words fallback;
  the junk came from other places, now dropped for a model's read: a row
  whose food is only in its "with" tail ("rice with chicken" for
  chicken), an Open Food Facts product without the query's food word
  (black beans for a casserole), and a row holding none of a dish's sides.
  A named variety the table lacks falls back to its food ("green apple"
  to the apple), except after a dish word or a way of cooking it.
  Brackets are dropped from a searched name ("coriander (cilantro)").
  Audit of 326 saved queries: 9 changed, all for the better.
- **Powders.** A ready food (latte, soup, porridge, mash, kissel...) puts
  powders and dry mixes after its prepared rows, and a model's read
  drops a dry row with nothing cooked beside it.
- **A dish beside its parts.** Of 1,255 saved reads, the double counts
  were khachapuri with its egg and cheese (53 reads), chłodnik's garnish,
  bolognese with its spaghetti and a stuffed pepper with its filling. A
  model's read now drops a part a dish row of 3 or more words names,
  unless the part is the dish's own food.
- **Emulator, typed Latvian with the real key:** "sautēti kāposti ar desu"
  found M&S red cabbage and the cream found an oat fraiche at 468 kcal;
  the cabbage is now broken down (213 kcal). Typed without accents,
  "griki" reads as yogurt even with a prompt line; "griķi" reads right.
  That is the model's vocabulary, left. Kefir 300 ml still asks to check
  the unit.
- **Sonnet re-run**, 3 passes on the new set (median off, total, within
  25%):

  | Suite | Model | Tune | Held |
  |---|---|---|---|
  | kcal | Haiku | 32%, 117%, 12/32 | 43%, 113%, 11/33 |
  | kcal | Sonnet | 68%, 97%, 7/32 | 46%, 105%, 13/33 |
  | portion | Haiku | 28% | 38% |
  | portion | Sonnet | 30% | 39% |

  Haiku stays the default. On the old photos Haiku held its numbers
  (tune 14%, held 35%); the new ones are harder (46%, 49%).
- **Left, from the new photos:** a dish row at a guessed 60-100 g
  (macaroni with meat 35-69 kcal against 513, millet pumpkin porridge 74
  against 357); a canned soup product picked for a home soup (chicken rice
  soup 89 against 427); salads and soups read 2-4 times over (vegetable
  salad 676-1,180 against 236, lagman up to 1,910 against 555, buckwheat
  kupecheski 671-892 against 285).
- Cost: about $4-5 of the promo credits.

## Step 7, round 4: a dish's start, home soups, mixed salads (2026-11-09)

The photo prompt asks for no grams, so a dish's amount is the app's
default; most of round 3's low reads were that default.

- **A bowl or a plate the read names.** A soup or a main dish the read
  itself names starts at its bowl or plate whatever row it found, and a
  sauce word before a food ("Meat sauce macaroni") is that food, not a
  60 g ladle. Porridge, stuffed cabbage and pasta with a sauce are main
  dishes; laksa, ramen, pho, lagman, kharcho and ukha soups. Millet
  porridge with pumpkin went from 74 to 359 kcal (357), makarony
  po-flotski from 68 to 336 (513).
- **Four home dishes** in `fork/data/dishes.json`: chicken and rice soup,
  makarony po-flotski, millet porridge with pumpkin, braised cabbage with
  meat. A home chicken rice soup had found Healthy Choice's canned diet
  soup, 37 kcal per 100 g: 89 to 256 kcal (427). Ranking canned rows last
  was tried on paper and dropped: where a canned row won, the table had
  no other.
- **Mixed salads and fried rice are one entry** in the photo prompt, as
  soups were: an Olivier beside its beets, potatoes, sausage and egg went
  from 848 to 503 kcal (236), chicken fried rice from 680 to 343 (441).
- **Junk rows.** A product must hold every food word before the query's
  "with" ("cabbage soup" found a carrot and coriander soup, 123 kcal
  against 626), and a fork dish's bracketed names count only before their
  own "with" ("melted cheese" found the pork chop with cheese, 534 kcal).
- The eval's guessed rows now say what the read stated
  ("(guess, read no amount)").
- **Haiku, 3 passes** (median off, total, within 25%):

  | Suite | Tune | Held |
  |---|---|---|
  | kcal, round 3 | 32%, 117%, 12/32 | 43%, 113%, 11/33 |
  | kcal, round 4 | 30%, 113%, 13/32 | 43%, 112%, 11/33 |
  | portion, round 3 | 28% | 38% |
  | portion, round 4 | 23% | 36% |

  Lagman went from 1,775 to 489 (555) and chakapuli from 255 to 529
  (723). Plov, borscht and the bread soup rose with the model's own
  reads, not a row these rules chose.
- **Left:** buckwheat kupecheski 825 against 285 (a 128 g cup of carrot
  beside it); the chicken pot pie soup's three biscuits; the cream in a
  model's breakdowns at 100 ml; "pasta sauce with meat" for a pasta dish
  (the table's makarony row wants every word, and the read says "sauce").
- Cost: about $1 of the promo credits.

## Step 7, round 5: regression checks, the held-out photos (2026-11-09)

- **Regression checks after round 4**, Haiku live: typed meals 14% off in
  English and 7% in Latvian, as before. MacroFactor: search 102 and 111
  of 122, the resolver 118 (99% weighted); its one change, "oat cookies",
  came from Open Food Facts not returning the Oat Cookies product this
  time. The stricter product rule of round 4 broke three AI reads ("glazed
  vanilla curd snack", "tomato beef ragu", "chicken kebab wrap"): a
  product now needs the food and half its other words, rounded up, not
  every one. "cabbage soup" still needs the cabbage.
- **Held-out deep-dive**, the 10 worst: most are a dish the model named
  with nothing found, so it is broken down, and its parts listed beside
  it as well ("buckwheat with meat and mushrooms" with beef stew meat and
  mushrooms, 889 kcal against 285; a chicken stew with its tomato and
  onion). Such a dish now counts as a dish row by its query, and its parts
  go. The rest are soups at a full bowl against small references (borscht
  309-403 against 181) and the model's own breakdowns ("bread soup base"
  found a dry soup base, 714 kcal): not rules.
- **One pass per split.** Passes in one session come back the same (0%
  spread), while between sessions one photo moves by up to ±100% (Italian
  wedding soup 403 and 834). More passes in a session add nothing, and a
  one-pass change of 2-3 points is noise.

  | Suite | Tune | Held |
  |---|---|---|
  | kcal, round 4 (3 passes) | 30%, 113% | 43%, 112% |
  | kcal, round 5 (1 pass) | 33%, 119% | 40%, 106% |
  | portion, round 4 | 23% | 36% |
  | portion, round 5 | 40% | 43% |

  The portion suite is 8 and 9 photos; its change is the model's
  breakdowns (the bread soup's base, a solyanka's), not these rules.
- Cost: about $1.

## Step 7, round 6: a photo's plate size, tried and dropped (2026-11-09)

The photo prompt may not guess grams (#1156), so every uncounted dish
starts at the same plate or bowl. Tried: the model adds "portion": "small"
or "large" to a dish it cannot count, against a usual plate or bowl, and
the row's starting amount is scaled by 0.6 or 1.5. Measured A/B in one
session, Haiku, one pass each (median off, within 25%, total):

| Variant | kcal tune | kcal held | portion tune | portion held |
|---|---|---|---|---|
| A, no sizes | 25%, 16/32, 116% | 38%, 12/33, 119% | 22% | 32% |
| B, small and large | 37%, 12/32, 118% | 35%, 12/33, 120% | 17% | 39% |
| C, small only | 34%, 10/32, 102% | 38%, 14/33, 101% | 27% | 38% |

Dropped: no variant made a meal's number better. The model calls a usual
lasagne, risotto or soup "large" (450 g), and the new prompt line moved
other reads too (an ukha listed its parts, a mushroom soup's bread came
as 4 slices). "Small" alone brought the total to about 100% of the
references, but by pulling some meals down while others stayed over: the
median and the meals within 25% did not improve. A baseline run an hour
apart gave 25% and 33% on the same photos, so a gain smaller than that
cannot be shown with this set.

## Step 8: a photo with no note estimates grams (2026-11-10)

Three rounds on branch `exp/photo-grams`, Haiku, `FORK_EVAL_ONLINE=1`, on
51 Nutrition5k plates (CC BY 4.0: lab-weighed, shot from above at
640×480; `build/n5k/set/photos.json`, built by the scripts in
`fork/tools/exp_photo_grams/` on that branch) and a second set of 48
kept unseen to the end. Read by `fresh_eval_test.dart`, with or without a
2-4 word note. Median off, within 25%, total as % of the reference:

| Read | No note | With note |
|---|---|---|
| Counts prompt (as it was, 3 runs) | 64-67%, 7-13/51, 144-156% | (D25's estimate) 34-40%, 14-17/51, 125-130% |
| Estimate without per-piece weights (F, 3 runs) | 35-43%, 17-19/51, 126-129% | 34-37%, 17-21/51, 120-125% |
| F, second set (3 runs) | 29-38%, 14-19/48, 127-131% | 37%, 16/48, 127% |

- **Round 1** (seven prompts): every estimating prompt beat the counts
  prompt without a note; among them nothing separated beyond the noise
  (up to 6 points of median, 6 plates, 12 points of total). A ten-line
  prompt with the plate sizes only was worse on the calorie suite (soups
  broken into raw ingredients). Dropping the per-piece weights (F) did no
  harm, and meat came at exactly 100 g no more often.
- **Round 2** (on F): pieces before grams, one entry per thing seen and
  a matching schema description were within noise. The plate's total
  first, rows sized to it, was best on the 51 and not on the unseen 48. A
  code-side shrink fitted to the 51 (24%, 97%) is only a ceiling: given
  the estimate, small ones are not too high, large ones are.
- **Round 3**: total-first against F on the second set three times
  (level) and on the six own meals (step 3), sized as the app sends them:
  F 10-14% off, 5-6 of 6 within 25%, 87-89% of the total; total-first
  37-42%, 1-2 of 6, 63-65%: it states a usual plate (620 g) for a full
  breakfast.
- **Small portions**: in every variant a food under 35 g comes at a
  median 2-3× its weight, 35-79 g at 1.4-1.8×, over 79 g at 0.84-1.1×.
  No prompt moved it below 2×.
- **Calorie suite**, F: tune 44%, 7-8, 121-132% (level with the counts
  prompt's 32-38%, 10-13, 113-117% within noise); held 26-34%, 13-14,
  112% (from 36-43%, 9-11, 116-129%).
- **A plate of assorted meats** (about 950 kcal): F reads 792-1,898
  without a note and 950-1,712 with one, against 1,117-1,891 before; the
  model lists 4-6 meats and seafoods for three or four foods.
- **Shipped** (D42): F for both a no-note photo and one whose note states
  no amount; the schema description on those requests; a first item
  without "dish=" taken as the meal's name (once in 102 reads); one more
  read when a food comes without grams (5-7 of 51 reads).
- Cost: about $2.06 for the three rounds.

Left, the wrong rows these reads found (query → row), for their own
piece of work (struck: fixed, with what fixed it; `wrong_rows_test.dart`):

- ~~"vegetable fritters" → Fritter, corn (404 kcal per 100 g)~~ fritters
  are a dish head, so the read breaks it down
- ~~"fried vegetables" and "fried vegetables, battered" → Fast foods,
  potato, french fried~~ what a row was fried in is not its food (Mixed
  vegetables, fried); a coating is never dropped (broken down)
- ~~"vegetables, battered and fried" → Vegetables, mixed, canned (36
  kcal)~~ the coating is kept, so broken down
- ~~"carrots, battered and fried" → Carrots, raw~~ the coating is kept:
  Carrots, in frying batter, deep-fried
- "Carrots, raw, salad" → a row at 213 kcal per 100 g (kept: the survey's
  row of that name, a dressed carrot salad)
- ~~"Zucchini fries" → a row at 0 kcal~~ fries are a dish head, and a
  photo drops a product at 0 kcal
- "Grilled squid" → a row at 300 kcal per 100 g (online only; the table
  has no grilled squid and no rule tells the product apart)
- "Chicken shashlik" → a row at 286 kcal per 100 g (the fork's own dish:
  skin-on thigh, a quarter lost; `fork/data/dishes.json`)
- ~~"chicken sausage, grilled" → Sausage, Polish, beef with chicken~~ a
  row of a meat not named trails: Turkey or chicken sausage
- ~~"chicken apple sausage" → a pork sausage~~ named: Turkey or chicken
  sausage
- ~~"pork, cooked, stir-fried" → Pork, cured, bacon (702 kcal at 150 g)~~
  fried is a way of cooking a plain meat: Pork, NFS
- ~~"pork, cured" → salt pork (for turkey bacon)~~ named: ham
- ~~"fruit soup base" → Soup base, dry (357 kcal); a cream-based one →
  Cream soup base (469 kcal)~~ a soup base is a soup, and a read with only
  its mixes has none (broken down)
- ~~"herbs, fresh, mixed" → Fresh wholemeal egg pasta with anchovy-herb
  pesto~~ words after a comma make a head, so the pasta is served with
  herbs; named: parsley
- ~~"eggs, scrambled with whole milk and butter" → Egg white omelet with
  cheese~~ what a food is made with is dropped before how it was made,
  and egg whites are a variant: Egg, whole, cooked, scrambled
- ~~"wheat berries, cooked" → Coffee Whey Protein (322 kcal)~~ named:
  Wheat whole grain, boiled
- ~~"sweet bell pepper, raw" → Roasted Red Bell Pepper Strips~~ named:
  Peppers, sweet, red, raw
- ~~"pizza crust, cheese, tomato sauce" → a stuffed-crust pizza; "tomato
  sauce, pizza" → Pizza margherita~~ a stuffed crust is a variant; a
  bracketed "(with" starts the sides; named: Sauce, pizza
- ~~"dark leafy greens" → a beef-and-rice row; "roasted mushrooms" → a
  mushroom pâté~~ "including"/"excluding" start the sides, and the search
  goes on to "greens"; a photo drops a product of another kind (pâté,
  soup, crisps, juice ...) the name does not ask for
- ~~later rounds: "oil" → Oil, oat; "coleslaw salad" → Salad dressing,
  coleslaw~~ named: Vegetable oil, NFS; Coleslaw

## Ideas not yet tried (2026-11-10)

Every round so far asked the same photo a different way. A second Haiku
pass cannot judge the plate's scale (its factor follows the needed one
at 0.19-0.27), so most of these add information instead. In the order to
try them:

1. **One question after the read.** A "smaller / as shown / larger"
   control scales the whole meal. One right scale per plate would cut the
   median error from about 35% to about 18%. No model call; needs a
   design for the review screen. Unlike round 6's sizes, the user picks.
2. **Dimensions, not grams.** The model gives each food's share of the
   plate and its height; code turns that into grams with a density
   table. Measurable on the Nutrition5k sets.
3. **A second photo from the side.** Height is what a photo from above
   hides. Nutrition5k has side-angle frames, so it can be measured before
   any app work.
4. **The user's own corrections.** A corrected weight is kept and the
   next read is told this user's usual amount of that food. The general
   usual-amount prior was dropped; this one is personal. Needs weeks of
   use to measure.
5. **Ask about the least sure food.** The model marks one food and the
   app asks about it ("how many skewers?").
6. **The image itself.** A larger photo, or one crop per food for the
   weighing. Resolution was never varied.
7. **Weighed own meals.** About ten meals, each a photo and the grams of
   every food, to settle whether reference photos help and to check any
   of the above on real plates.

Added later the same day. The first two come before everything above:
they cost next to nothing and decide which of the rest are worth doing.

8. **Does disagreement predict error?** Two reads of every plate already
   exist. If the plates where they differ most are the most wrong, the
   app can read twice and say "check the amounts" on those alone. An
   analysis of old runs, no new calls.
9. **The oracle scale test.** On the Nutrition5k sets the camera height
   is known: tell the model the frame's true width in centimetres. If the
   error does not drop, the model cannot use scale even when given it,
   and ideas 3 and 12 and a known object in the frame are dead.
10. **Household units, not grams.** The model answers in tablespoons,
    cups, slices and palm-sized pieces; code converts. Aimed at small
    portions (read at 2.3-3.5× their weight).
11. **A shrink curve by read size, in code.** Small reads are about 2.5×
    over, medium 1.4×, large about right, in every run. Calibration by
    food class was dropped; by size was not tried. Risk: own meals are
    already about right and would go under.
12. **Real scale from the phone.** When the app takes the photo, the
    camera's focus distance and focal length give the frame's width. Only
    if idea 9 passes.
13. **"Is this all yours?"** A read far above a usual meal asks how much
    of it was eaten. Aimed at platters (the meat plate).
14. **Another vendor's model as the weigher only** (Gemini is built for
    spatial tasks). Needs a Google key or OpenRouter spend; wait for the
    Sonnet chain result.

Results, 2026-11-11 (round 10, $0.97):

- **Idea 8, no.** Two reads' difference says nothing about which plates
  are wrong: Spearman about 0 on both sets, and flagging the most
  different 20-30% catches no more bad plates than chance. Haiku makes
  the same mistake each time: a plate's signed error ranks the same from
  run to run (0.85-0.90).
- **Idea 9, no.** Told the frame's true size (37 × 28 cm, checked on the
  plates), nothing changed. Told a frame 1.5× too large, totals moved
  +1-4%; 0.5×, -5%; using it would have moved them about 2×. Sonnet the
  same (+4%). The models do not measure against a stated size.
- So ideas 12 and a known object in the frame are dead, and idea 3 very
  likely is. The error is not one of scale: it is the step from what is
  seen to grams, worst for small portions. Ideas 2, 10 and 11 go after
  that step and are next.
- Nutrition5k photos are 640 × 480, the app sends up to 1440 wide: idea
  6 can only be measured on own photos.

Results, 2026-11-11 (round 11, $0.26):

- **Idea 11, no.** The 2.5× belongs to a food's weighed size, not its
  read size: reads of 0-15 g are 0.78× their weight, so a curve on read
  grams becomes a flat ×0.8 above 25 g. Own meals 88% → 70%, 97% → 78%.
  The extra kcal on the lab plates is small portions of starch and
  vegetables; oil is under-read (0.6-0.76×), not over.
- **Idea 10, no.** Household measures with grams in code: 61% median
  off, 186% total ("6 small pieces" of pepperoni became 360 g, a cup is
  read generously). Naming the measure before the grams: no different.
- **Idea 2, no.** Plate share and height, a piece's own weight for what
  is counted: small/medium/large 1.6 / 1.0 / 0.95 (baseline 2.55 / 1.40
  / 0.95), the first change to shrink small foods and leave large ones.
  But plates scatter more (median off 36% and 34%, totals 113% and
  117%), and the own meals with a note fall 97% → 82%.

Results, 2026-11-11 (round 12, $0.43), measured before any design:

- **Idea 1, build it.** Five levels, ×0.6 / 0.8 / 1 / 1.2 / 1.4, start
  on 1. A user right 70% of the time (a neighbouring level otherwise):
  lab sets 33% → 10% median off, meat plate 160% → 108%, own meals
  unchanged. Lab plates want smaller, own meals the same or larger, so
  the steps are even both ways. Whether a user can tell ±20% by eye is
  not measured.
- **Idea 13, a rule if at all.** No kcal threshold tells the meat plate
  from an own breakfast, and the model never says a photo is shared (0
  of 10). Three or more meat or fish foods of 30 g and 1,000 kcal fires
  on 19 of 20 meat-plate reads, 4 of 60 own-meal reads, none of the lab
  plates; one platter stands behind it.
- **Idea 5, not the model's mark.** The food it marks is the most wrong
  one 44-51% of the time; the food with the most kcal is 62-69%. A
  per-food mark also moved the reads up. Asking about the food with the
  most kcal needs no model change.
- **Idea 6, keep the size.** The app sends 1365 × 1024. Smaller reads
  10-20 points less food on own meals; larger reads the meat plate
  higher (172-218%) at 1.6-1.8× the tokens.

Every idea that an eval can measure is now tried. What is left is below, and ideas 1, 4, 5 and 13, which are app
features, and idea 7.

Since then: idea 1 is the Size (D44), idea 5 the amount question on the
food with the most kcal and idea 4 the user's earlier amounts and usual
sizes (D45, D46), all 2026-11-11. Idea 7 ran on 2026-11-17 (below). Idea
13 is not built (D44).

### If none of them shows a gain

- **The photo is a draft; correcting it is fast.** The foods are named
  right, the amounts are not. The work moves to the review screen: the
  whole-meal scale control (idea 1), quick per-food changes, "check this
  one" hints. Depends on taps, not on an eval.
- **The user's history instead of the photo.** The photo names the meal;
  the amounts come from the last time it was logged and corrected. Only
  a new meal needs an estimate.
- **Unbiased rather than accurate.** A week's total matters more than one
  meal. Own meals already log 90-97% of their reference; keep the total
  near 100% and catch the outliers (platters). This is the yardstick for
  the two above.
- **A better model, when there is one.** The harness measures a new model
  in an hour for a few cents. One clearly better could be offered as the
  slower, dearer choice. Gemini first (said to be better at this, about
  13 s and $0.006 a photo): five Haiku runs of every set for a firm
  baseline and noise floor, then the same sets on gemini-3.8-flash.
- **Check the premise first.** The large errors are on lab plates with
  small portions; own meals are close. The ten weighed meals (idea 7)
  show whether a real problem is left beyond platters.

Preferred: the first two together.

### Gemini against Haiku, the steps

1. **A firm Haiku baseline.** Five runs of each scenario: both
   Nutrition5k sets, the held-out calorie suite, the six own meals and
   the meat plate with and without the note. From them a noise floor per
   scenario and a spread per plate. About $0.25 on the Anthropic key;
   after the Sonnet chain runs, which use the same checkout.
   Done 2026-11-19 (below).
2. **The same scenarios on gemini-3.8-flash**, the app preset's model,
   through OpenRouter for now: three passes, about 180 photos a pass,
   about $1.10 and 40 minutes a pass, about $3.30 of the $4.60 left.
3. **Compare** per scenario against the step 1 floor: median off, meals
   within 25%, total, the small/medium/large ratios, cost and time a
   photo.
   Done 2026-11-11 ($2.68 on OpenRouter). Median off, within 25%, total,
   Haiku → Gemini: set 1 33% → 24%, 19 → 26 of 51, 122% → 90%; set 2
   33% → 21%, 18 → 28 of 48, 127% → 94%; held-out 32% → 30%, 13 → 13 of
   30, 113% → 107%; own meals 16% → 33% without a note and 14% → 30%
   with one, totals 88% → 67% and 97% → 77%. Gemini reads every plate at
   about 0.75 of Haiku's: Haiku × 0.69-0.79 matches it on the lab sets,
   and the own meals go under. Small foods 1.5× (Haiku 2.5×), large 0.8×
   (Haiku about right). 9-15 s and $0.006 a photo against 1.5-2 s and
   $0.0004-0.0009. Not better where it counts; the weighed own meals
   (idea 7) decide whether the own-meal references run low.
4. **Later, with a Google AI Studio key in `.env`:** the app's Gemini
   preset against Google itself, never yet checked live. On the free
   tier Google may use the photos, own meals included.

Dropped before trying: the user's plate and bowl sizes (no use away from
home). Weak: a known object in the frame — the meat plate has a fork in
it and is still read at 1.5-2× its reference.

## Idea 7: weighed own meals (2026-11-17, about $0.15)

Eleven of the user's meals, every food weighed on a kitchen scale, as
served (`FORK_EVAL_PHOTOS`, kept under `build/`, never committed). The
manifest lists each food's grams and the words of a read row that count
toward it; `fork/tools/weighed_grams.py` scores a run's `kcal.json`
against them. The kcal references are the true grams times Claude's
estimated energy per 100 g, so only the grams are exact. Haiku 5.5, three
passes per scenario, 13 runs in all.

- **Wrong rows first.** Carrot salad with mayonnaise found no row (0 kcal
  in every read), borsch the cold kefir soup, elk steak the ground elk
  patties, "burger" a veggie burger, "breaded chicken" frozen thighs at
  334 kcal per 100 g. Fixed (S75), seaweed salad added as a dish. Over
  the three scenarios the median miss went from 17-19% to 15-16%.
- **Grams.** Real plates are read at 0.90 of their weight: foods over
  150 g at 0.83 (n=303), 35-150 g at 1.01 (126), under 35 g at 2.00 (9,
  all the pesto). The lab plates' pattern holds for small foods, but here
  the large ones are under, not about right. 12 of 450 foods were not
  read at all (the borsch beside a plate and the pesto, no note).
- **Error split.** Without weights, a plate's miss is a median 17% of the
  reference from portions and 13% from the rows and their energy. With
  the weights in the note the portion part is 0 and the miss stays at
  16-19%: once grams are right, the rows decide.
- **The review's tools reach these plates.** 16 of 198 reads need a
  scale outside the Size's ×0.6-×1.4, so a wider step is not supported.
  The nearest Size takes the median miss from 15% to 11%; the amount
  question after it adds nothing on the median. The true amount is inside
  the question's chips in 192 of 198 reads. The question's food (most
  kcal) is the one with the largest kcal error in 80 of 144 reads (56%,
  round 12 found 62-69%, its measure unknown) and the one with the
  largest gram ratio in 33 (23%).
- **Idea 6, resolution: no effect shown.** The app sends 1365 × 1024
  (`MealPhotoEncoder`, short edge 1024, quality 80, WebP to the three
  hosted providers). That size against the original 4000 × 3000: with the
  dish name, 92% and 89% of the reference on the nine resized photos;
  without a note 90% and 84%, but two photos sent at the same pixels in
  both runs moved 14 points too, so three passes cannot tell it from
  noise. The API scales a 12 MP photo down to about 3.8 MP; it costs
  about 2.7× the input tokens. Keep the size. The eval sends JPEG, not
  the app's WebP.
- **The first set was sent turned.** Its photos were resized without
  their EXIF orientation, so 9 of 11 reached the model sideways or upside
  down; the app sends them upright. The row-fix comparison is unaffected
  (both sides turned); every run after it is upright.
- **Double counts seen, left as they are.** A weighed plate's note
  ("burger 250 g") keeps the burger and adds its bun, patty and lettuce:
  1,690 kcal against 1,135. Kept: the user does not always weigh the
  salad, so foods beyond the note can be real. Two reads also listed the
  pork and potatoes again, raw, at 300 g each.

What is left is the rows and the user's own repeats: about 30 weighed
plates, some meals repeated and photographed in the app, would show
whether D46's per-food sizes learn anything (11 plates repeat too few
foods by name).

### Idea 7, six trials (2026-11-17, about $1.20 promo key and $0.18 OpenRouter)

On the weighed set, now sent upright at the app's size. Haiku, no note,
three passes: 29/33 within 25%, median 16%, total 99%; with the weights
in the note 25/33, 17%, 113%.

- **Sonnet 5.5: not worth it.** Portions closer (portion error 0.14
  against 0.24 of the reference, foods over 150 g at 0.89 against 0.85),
  the plate's miss barely (14% against 16%), it left out 9 of 75 foods
  against 3, at 25× the cost ($0.42 a 33-read pass).
- **Gemini 3.8 Flash, through OpenRouter: no verdict.** 18 of 33 reads
  came back with nothing (12 of 51 on 2026-11-10), the multi-food plates
  most; the 15 that did were 12/15 within 25%. The second pass was not
  run. The app calls Google directly, not this route, and the harness
  does not record why a read failed.
- **WebP: no difference.** Nine passes each: within 25% 75/99 (WebP)
  against 80/99 (JPEG), median 16% against 18%, same tokens. One photo's
  borsch was never read as WebP and always as JPEG; one photo, not shown
  in general. Rechecked the same day with the app's own encoder: the
  photos encoded on the emulator by `MealPhotoEncoder` (Android's WebP,
  0.7-2.3 of 255 from Pillow's per pixel, same size and orientation),
  nine passes on the merged code: 75/99 within 25%, median 16%, total
  96%, and the soup read in 9 of 9, as with JPEG (Pillow's WebP, same
  code: 68/99, 17%, 92%, the soup in 0 of 9). What the app sends reads as
  JPEG does; the eval's own WebP is not a stand-in for it.
- **Row audit: merged as correctness.** 4,192 food names from every run
  so far: 173 now find their everyday row (S75), covering 3,533 past
  reads, e.g. battered fish, hash browns, farro, vinaigrette, cooked
  chicken. On these plates only one row moved energy, so no gain shows
  here.
- **A weighed food split into parts: merged.** The note's "burger 250 g"
  matched none of the model's bun, patty and lettuce and was added again
  as a whole; now the parts are sized to it (D24). Burger plate 1,710 →
  about 1,100 kcal (1,135); poke bowl 1,185 → 590 (706).
- **Raw duplicates: merged, fixed at the cause.** A plate's food the
  table lacked was broken down with the whole plate's photo, and the
  breakdown listed the plate again raw (pork loin 300 g beside the grilled
  pork). It is now sent without the photo (D42). A rule dropping raw rows
  beside cooked ones was not built: under 1% of reads, with real garnishes
  among them.
- **Found on the way: a bare number read as servings.** A read with no
  unit took "150" of chicken as 150 servings (113,597 kcal), twice in 15
  runs. A bare number above 20 on a plate is now grams (D42).

All merged, the same Haiku passes: weights in the note 29/33 within 25%,
median 13%, total 102% (from 25/33, 17%, 113%); no note 27/33, 15%, 93%,
within run-to-run noise of before.

## A firm Haiku baseline, and the body comparison live (2026-11-19, about $0.37)

Five passes of each scenario on fork/main at 87139e34, `FORK_EVAL_ONLINE=1`,
merged with `eval_merge.dart`. Spread is a plate's highest run less its
lowest, against the reference: the noise floor a later change must beat.

| Scenario | Plates | Median off | Median spread | Within 25% every run |
|---|---|---|---|---|
| Nutrition5k set 1 | 51 | 29% | 28% | 9/51 |
| Nutrition5k set 2 | 48 | 36% | 26% | 7/48 |
| Held-out calorie | 33 | 24% | 25% | 8/33 |
| Weighed own meals, no note | 11 | 14% | 18% | 8/11 |
| Weighed own meals, weights in the note | 11 | 13% | 1% | 9/11 |
| Meat plate, no note | 1 | 34% | 64% | 0/1 |
| Meat plate, "meat assortment" | 1 | 57% | 93% | 0/1 |

A lab plate moves about a quarter of its reference between runs, so a
change measured on three passes needs more than that to count. Weights in
the note all but remove the noise. The note "burger 250g, fries 170g"
logs 1,103-1,365 against 1,135; "burger 250 g" alone sizes the fries into
the burger (the emulator check below).

**The body comparison, live for the first time: half its answers fail.**
Three runs over the 16 pairs: Haiku answered every pair, but 8-9 a run
came back as `{"items":[]}` or as `key=fat` with no value, so the app
throws "No comparison in the answer". Which pairs fail changes between
runs. The replay runs never showed it: the subagent followed the
`key=value` format. Where an answer parsed, the verdicts were right (8/8
in the first run, certainty within the pair's limit, lighting named).

**Emulator, the real key (Haiku), the flows since 2026-11-11.** Worked:
Log with AI from a meal chip, its Undo, the photo notice once, a Latvian
typed dish, the Size scaling only unset amounts, totals on Home and the
Diary. Found, one run each:
- "burger 250 g" on the burger-and-fries photo: bun, patty and fries
  sized to 250 g together, 681 kcal against about 1,135 (the `shortcut:`
  in `weighed_plate.dart`).
- "chicken 150", no unit, does nothing: the note's amount needs a unit.
  The plov's breakdown also listed raw chicken and raw rice beside the
  stewed chicken; the read had no dish header, so the breakdown likely
  still got the photo (D42's case).
- ~~The cooking-fat answer adds sunflower oil beside the breakdown's own
  oil.~~ fixed 2026-11-20: the answer goes into the read's own oil or
  butter row (D48)
- ~~51 of 74 home dishes carry their alias lists in the name, cut off on
  the review row.~~ fixed 2026-11-20: the review row shows a home dish
  without its list; the amount sheet's title and the usual-sizes line
  still show the full name

**Fixed the same day.** The body prompt now says every key always
applies and the list is never empty (the fork's tool description invites
an empty list when nothing applies): 48/48 answers parsed over three
runs, 15/16 pairs right in each. "burger 250 g" on "Burger with fries"
now weighs the burger and leaves the fries their own row: 681 to
790-883 kcal (1,135). "chicken 150" weighs the chicken at 150 g: the plov
plate 852 to 558-567 (650), no raw rows. Accepted cost: "plov 150g" on a
"Plov with lamb" read weighs the plov's other words apart.
On the emulator the Weighed chip gives the same results. Its "weighed:"
does not drop the plate's oil: five passes each, the chip kept oil in all
five (twice inside "rice with oil"), 543-597 kcal against the typed
note's 500-595 (650).

After those fixes, three passes each of the note evals: weighed plates
13/16 every pass, the same three cases as on Nov 10 (the controls without
a weight, where the model still guesses grams); the hard notes 2-3/8
against 3/8 on Nov 10, the same misses (a note that contradicts the
photo, a fraction, a count). No regression from the note-weight changes.

The label reader, first time live: `test/fork/eval/label_eval_test.dart`
on 20 popular Open Food Facts nutrition photos
(`fork/tools/fetch_label_photos.py`), three passes, about $0.03. Every
pass parsed 19/20, the same numbers each time: kcal 16-17/20, fat 18/20,
carbs 15/20, protein 16/20 against the typed entries. Each miss checked
on its photo was the entry or the photo, not the reader: a chat
screenshot (read as nothing, right), a jar front with a tiny panel, a
label printing no carbs, a pack whose entry has other values (protein 29
printed, 27 typed; a Bulgarian can at 45 kcal against 42). The
`key=value` answer that half failed for the body comparison holds here.

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
5. **Private sets and other readers.** `fresh_eval_test`: a photo set
   under `build/` (`FORK_EVAL_PHOTOS`), with or without its note; the
   Nutrition5k plates and the weighed own meals ran through it, and
   `fork/tools/weighed_grams.py` scores the weighed meals' runs.
   `label_eval_test`: the nutrition label reader on Open Food Facts
   photos (`fork/tools/fetch_label_photos.py`).
   `resolution_dump_test`: resolves a list of food names
   (`FORK_EVAL_AUDIT_QUERIES`) for a judge to read, with no model call.

Each report gives the typical kcal error, how many plates land within the
margin, the worst misses, the foods the model got wrong, and what the run
used.

Not in a plain pass: `macrofactor_photo_test` and `macrofactor_search_test`
need a list built from a MacroFactor log kept outside the repo (they ran in
step 7, rounds 3 and 5), and `body_compare_eval_test` is the progress-photo
feature, not meal logging (live on 2026-11-19).

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
- **No Opus or Fable app evals** (as of 2026-11-20). The Claude Max
  subscription ends on 2026-11-23.
