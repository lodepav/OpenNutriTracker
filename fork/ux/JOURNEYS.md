# Journeys

Scripted days in OpenBite, tapped through on the emulator the way a person would, then checked
against what the app saved. They catch what unit tests miss after an upstream merge: a seam no
longer called, a sheet that will not open, a total that stopped adding up.

`fork/tools/journey-check.sh` runs them. `fork/tools/journey-check.mjs` taps through each step over
flutter_driver; `fork/tools/journey-lib.mjs` holds the checks (tests: `node --test
fork/tools/journey-lib.test.mjs`).

## Running

```sh
fork/tools/journey-check.sh --build --make-ux-profile          # once: build, boot, make the ux profile
fork/tools/journey-check.sh --make-owner-profile <export.csv>  # once: the owner profile, from a MacroFactor export
ANDROID_SERIAL=emulator-5556 fork/tools/journey-check.sh       # J1 to J6
fork/tools/journey-check.sh J3 J5                              # these only
fork/tools/journey-check.sh --accept J2                        # the differences are meant: keep this run as J2's baseline
```

The build is `lib/fork/dev/main_journey.dart` with `--dart-define=FORK_FAKE_AI=true`: the normal
app, the driver extension, the fake AI and the fake Health Connect. It refuses a release build.
No connection leaves the app (`JourneyOffline`): search reads the bundled tables only.

Exit 0 when every check passed and nothing differs from the baseline, 1 on a FAIL or DIFF, 2 when
it could not run. A journey also exits 2 while any path off the device is on in its profile: an AI
key other than the fake one, an Open Food Facts account, the real Health Connect, auto-backup to a
folder. The run names it.

## Snapshot first, delete nothing

Before anything, the runner force-stops the app and saves its own data:
`run-as <pkg> tar -cf - app_flutter shared_prefs files databases no_backup`, without
`app_flutter/flutter_assets`. On every exit, a failure included, it force-stops the app and untars
the snapshot over those folders. Nothing on the device is deleted: then it lists the app's files
and names any the snapshot did not hold (a box a journey created), exits 2 and leaves them.
Hive's `.lock` files are not counted. Meal photos (`app_flutter/meal_images/`) and the engine's
`res_timestamp-*` are named as leftovers but don't stop the run: after the restore no entry points
at the photos, and every install rewrites the timestamp. When the restore fails, the snapshot stays and its path is
printed; put it back by hand with `adb exec-in run-as <pkg> tar -xf - < app.tar`.

A profile is loaded the same way, untarred over the folders. A file on the device that the profile
does not hold would run with it, so the journey is refused (exit 2) and the file named. A box the
app opens for the first time (`fork_meal_groups.hive` was one) does this once: remake the profile,
which then holds it. Both `--make-…-profile` runs first open every box of the active profile
(`openBoxes`: upstream's open at start, the fork's are `forkProfileBoxes`), so a box a journey
writes to is in the profile and the restore overwrites it. A new owner profile adds that profile's
boxes to the device: make the owner profile first, then the ux profile, which then holds them.

## Profiles

In `~/.cache/openbite/`, never in the repo:

- `ux-profile.tar`: the demo data (`DemoSeedOptions.dev`, through the `seedDemo` command) over the
  app as it was, restarted past onboarding. `--make-ux-profile`.
- `owner-profile.tar`: a new profile, "Owner", made beside what the app holds by the app's own
  use cases (`ownerProfile`: CreateProfileUsecase, SwitchProfileUsecase, then onboarding's save
  with the values its pages start on: male, born 1990-01-01, 180 cm, 80 kg, maintain, low
  activity, no reminder; onboarding's 80 kg weigh-in is taken back). The app restarts into it.
  Then the owner's MacroFactor export imported through Settings → Data → Import history, the
  calorie target set to Adaptive (Settings → Goals → Trend and calorie target), and the weight
  import turned on against the fake Health Connect. The archive holds both profiles; the owner's
  is active, so no fact depends on the demo. `--make-owner-profile <csv>`. The CSV is only read: it is copied into the app's cache on the
  device and handed to the import by a stand-in file picker.

A profile opens only on the install it was made on: the core boxes' key sits in that AVD's
Keystore. The runner keeps the AVD's name beside the profile (`<profile>.avd`) and refuses another
AVD (exit 2); boot that one, or remake the profile there.

Baselines: `~/.cache/openbite/journeys/<J>.json`, the facts of a run. A journey without one keeps
its first run when every check passed.

## J1: A common day (ux profile)

1. Breakfast by search: + → Breakfast → search, the Food source, "oats raw", the row "Oats, raw",
   80 g, Add.
2. A drink from search: + → Snack → search, the Food source, "milk whole", the row's + for
   "Milk, whole".
3. Undo once: Undo on the bar takes the drink back (D56); the row's + adds it again.
4. One amount edited (D54): Diary → the oats → More → Edit, 120 g, OK.

**Check:** the oats are logged once, in Breakfast, at the 120 g typed; the drink once, in Snack,
after Undo took the first one back. Each new weighed entry's kcal, protein, carbs and fat are its
per-100 g values × grams. Home's day totals are the sum of the day's entries, and left is the goal
minus eaten. Facts: the check outcomes and the new entries.

## J2: The owner's day (owner profile)

1. The planned breakfast: + → Breakfast → the first recent food's +.
2. The protein shake: + → Snack → search, "whey", Recently, the shake's + (the owner's shakes are
   whey; "protein" also matched a protein bar).
3. Lunch as a photo: Photo log → camera (a bundled meal photo) → Lunch → the note "dirty fries
   with pork 430g" → parse → log the items, read by the fake AI.
4. Dinner searched, from the Food source: "Chicken breast, grilled" 200 g, "Rice, white,
   long-grain, regular, enriched, cooked" 150 g, "Lettuce, cos or romaine" 80 g.
5. Today's weigh-in, from the fake Health Connect import, run now through the handler (at launch it
   waits out its interval since the profile was made). Before 7:00 the fake scale's weigh-in for
   today is at the current time, so a run at night has one.
6. The check-in screen: You → Settings → Goals → Trend and calorie target → Expenditure and
   check-ins → Open check-in (shown only while the target is Adaptive).

**Check:** every group fails the run. Saved entries: a breakfast, a shake, one photo lunch entry
with energy (two means a submit was tapped twice), each dinner food at the grams typed, and each weighed entry per-100 g × grams. Day
totals: Home's totals are the sum of the day's entries, left is the goal minus eaten. Adaptive:
the check-in computes an expenditure and a target, the screen opens, and its numbers differ from
the baseline as a DIFF. Weight: today has a weigh-in, from Health Connect. Facts: the check
outcomes, the new entries, the check-in's numbers and the weigh-in.

## J3: Log yesterday (ux profile)

1. Diary, one swipe to the right (a real touch, `adb shell input swipe`, low on the list; the
   driver's synthetic scroll never reached the drag handler): the Diary steps back a day (S176)
   and offers Go to today. An add or a copy brings the Diary back on today; the journey swipes
   back again where it needs yesterday.
2. A snack by search, in grams: Snack's + on yesterday ("Add to Snack"), the Food source,
   "almonds unroasted", the row "Almonds, unroasted", 30 g, Add.
3. Back to today: Go to today.

**Check:** the snack is the one entry yesterday gained, in Snack, at the 30 g typed, its kcal,
protein, carbs and fat per-100 g × grams. Yesterday's totals (its day row, as the Diary shows
them) are the sum of yesterday's entries, a day row missing counted as a failure. Today is
unchanged from before the journey. Facts: the check outcomes and the snack.

## J4: Copy a meal (owner profile)

1. Diary, one swipe to the right, to yesterday. A profile made more than a day ago holds no lunch
   there: one is logged first as J3 logs, "Chicken breast, grilled" 150 g into Lunch.
2. A tap on yesterday's Lunch header selects all of it (D30).
3. The bar's Copy, Today, Copy: the sheet keeps the same times and Lunch. Then Go to today.
   (Home's "Same lunch as yesterday" shows only while the clock's meal is lunch: not scripted.)

**Check:** yesterday held a lunch before the copy. Today gained exactly yesterday's lunch entries,
same names, amounts and kcal, all in Lunch, nothing else. Yesterday is unchanged by the copy.
Facts: the check outcomes and the copied entries.

## J5: Barcode, offline (ux profile)

1. A product in the scan cache, as a scan made online leaves it (`cacheProduct`: the full
   record of "Journey muesli bar", code 2000000000008, the in-store range no sold product uses).
   The lookup reads the user's own foods, then this cache, then the network
   (SearchProductByBarcodeUseCase), so with the cache it needs none.
2. + → Snack → search, the code typed and submitted: a valid barcode goes to the scanner's lookup
   without the camera.
3. Grams, 45 g, Add.

**Check:** the product is the one entry the journey added, in Snack, at the 45 g typed. Its
per-100 g values are the cached product's, and its kcal, protein, carbs and fat are per-100 g ×
grams. Facts: the check outcomes and the entry.

## J6: Weekly check-in by hand (owner profile)

1. The check-in made due (`checkInDue`): due already on a profile without check-ins, else the
   check-in day (Settings → Goals → Trend and calorie target → Expenditure and check-ins) set to
   today. No clock is moved.
2. Home's card for it ("Your first target", "Weekly check-in", ...) opens the check-in; the
   target field's value is read.
3. Accept, at the target shown.
4. Back to Home.

**Check:** a check-in was due and its screen opened from Home's card. The target shown is the one
the check-in proposes. The accepted target, recorded today, is the one shown. Home's goal is the
accepted target with today's weekday offset and counted activity. The check-in history gained
one row. Facts: the check outcomes only; the numbers move with the calendar.
