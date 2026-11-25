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
ANDROID_SERIAL=emulator-5556 fork/tools/journey-check.sh       # J1 and J2
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
which then holds it.

## Profiles

In `~/.cache/openbite/`, never in the repo:

- `ux-profile.tar`: the demo data (`DemoSeedOptions.dev`, through the `seedDemo` command) over the
  app as it was, restarted past onboarding. `--make-ux-profile`.
- `owner-profile.tar`: the owner's MacroFactor export imported through Settings → Data → Import
  history, the calorie target set to Adaptive (Settings → Goals → Trend and calorie target), and
  the weight import turned on against the fake Health Connect.
  `--make-owner-profile <csv>`. The CSV is only read: it is copied into the app's cache on the
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
