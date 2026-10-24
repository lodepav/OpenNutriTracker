# Phase 3 simulation: tuning the expenditure estimate

2026-10-22. Phase 3 steps 1–3 (D13). The code is in `lib/fork/adaptive/` (`simulator.dart`,
`trend.dart`, `energy.dart`, `expenditure.dart`). Re-run with
`dart run fork/tools/tune_adaptive.dart`, or add `sweep` for the full grid. The inputs and their
sources are in [phase3-macrofactor-algorithms.md](phase3-macrofactor-algorithms.md),
under "Simulator inputs".

## Setup

Nine synthetic users, 180 days each, five seeds each:

- losing (heavy and lean)
- maintaining
- gaining
- a sloppy logger: 75% logged, 30% of days unlogged, 15% half-logged, 60% of weigh-ins missed,
  0.8 kg noise
- a step of +300 or −300 kcal in activity from day 90
- two users with a ±0.8–1.0 kg, 28-day water swing

How the simulated users behave:

- **Truth.** Weight follows energy balance, split into fat and lean by Forbes. Expenditure falls
  22 kcal/day per kg lost, and drops 5% of the deficit as adaptation.
- **Scale noise.** Daily scale noise has an SD of 0.5 kg. On top of it come a 0.35% weekly
  cycle and two 4-day water shifts.
- **Prior.** The estimate starts from a prior 10% off the true base expenditure. The truth is in
  logged calories, so the prior is about 20% off in practice.

Scores are counted from day 30 on, as MacroFactor reports them:

- **Error:** the mean |estimate − truth|, in kcal/day.
- **Stability:** the mean |day-to-day change| of the estimate, in kcal/day per day.
- **Response:** the days until the estimate has moved 80% of a step.

## Sweep

The sweep covered:

- α (trend weight): 0.05–0.25
- window: 14, 20 or 28 days
- calibration blend (first 30 days): 0.1 or 0.2
- blend after that: 0.02–0.1

How the settings traded off:

- The lowest error, 70, came with 45-day responses.
- Responses within about 30 days cost error 94+ and stability 12+.
- Error and responsiveness trade against each other, mostly through the blend weight.

**Chosen:** α 0.1 (Walker's), window 20 (MacroFactor's), calibration blend 0.2, blend 0.05,
14-day warm-up. The first check-in falls after two weeks, and the warm-up changed the error by
only 1–3 kcal.

| User | Error | Stability | Response |
|---|---|---|---|
| losing, heavy | 47 | 3.9 | |
| losing, lean | 34 | 3.1 | |
| maintaining | 81 | 3.6 | |
| gaining | 121 | 3.7 | |
| sloppy logger | 98 | 5.7 | |
| more active from day 90 | 92 | 4.1 | 46 |
| less active from day 90 | 76 | 4.2 | 40 |
| cycle, losing | 47 | 6.7 | |
| cycle, maintaining | 62 | 7.5 | |
| **all** | **73** | **4.7** | **42** |
| all, flat 6,000 kcal/kg | 86 | 4.3 | 45 |
| all, prior −20% / 0% / +20% | 75 / 73 / 73 | 4.7 | 42 |

MacroFactor publishes these figures for its own estimate:

- median error 89–108 kcal over 100 days, on real users
- about 7 kcal/day per day of movement
- settles in 14–30 days

Our simulated users are kinder than real ones, so a lower error here is no claim of beating it.

## Responsiveness

2026-10-24 (D17). Settings offers three presets. Only the blend weight differs between them,
since the sweep found it trades response for stability at the least cost in error:

| Preset | Blend | Error | Stability | Response |
|---|---|---|---|---|
| Steady | 0.03 | 71 | 3.1 | 51 |
| Standard (the chosen one above) | 0.05 | 73 | 4.7 | 42 |
| Responsive | 0.1 | 84 | 8.2 | 36 |

A faster trend (α 0.12–0.2) or a 14-day window responded no faster for the error it cost.
Responsive's stability is close to MacroFactor's published ~7.

## Counted activity

D17 lets steps and workouts count. The estimate takes the window's mean counted activity off the
energy balance, and the target adds activity back: the past week's mean at the check-in, or each
day's own. When activity is steady, base plus activity equals what the energy balance measured,
whatever share of the counted activity is real (`expenditure_settings_test.dart`). So a watch
that overstates moves the average target little. The share counted only sets how far one active
day or week moves it. The simulator has no counted activity yet.

## A real journey (D18)

`fork/tools/replay_journey.dart` replays a MacroFactor export (made into a journey file kept
outside the repo) through the check-in: its daily intake and weigh-ins, its goals and their
paces, partly logged days left out, every proposal accepted. A drift run moves the intake by how
far our target differs from the one followed, and the weight by that energy. Against 17 months
of one user, the estimate stayed close to MacroFactor's and the trend matched it. It found the
three faults D18 fixes: goal changes held back by the cap, a high formula prior let down slowly,
and a logging gap priced at the logged days' intake. The goal's kcal per kg differs by design:
Forbes's (about 6,000–6,400 kcal/kg at 15–20% body fat) against MacroFactor's 7,700, so cuts ask for a smaller
deficit than MacroFactor's at the same pace.

The runs after D18 (D19): with the window starting at the first logged day and a 7-day
warm-up, the first estimate came a week sooner on the journey and its largest weekly move fell
from 278 to 185 kcal; the synthetic users' error rose from 74 to 76 (the sloppy logger 106 to
113). The 7,700 kcal/kg switch cut the drift run's end shift from 7.0 to 4.3 kg. A blend of
0.07 for Standard followed a −300 kcal step about 6 days sooner to 80% for a third more
wobble, so the presets stay as they are.

Stress runs on the same journey (weekly check-ins, each event in a fully logged stretch of one
goal, set against the unchanged run): a weigh-in typed 3 kg high or low moved the target at
most 24 kcal; two weeks without weighing, 41; ten days away with nothing logged or weighed, 66.
Five days 1,500 kcal over moved it +108 when logged in full (the replay put the surplus on at
7,700 kcal/kg, the estimate reads it at body composition's), −110 with the days unlogged (5 of
20 missing passes the 60% rule, and the gain is priced at the other days' intake) and −169 with
the usual intake logged, which is what the log says. Each faded within about five weeks, and
none reached the cap.

## Findings

- **Forbes beats the flat 6,000 kcal/kg:** error 73 against 86. The lean and the heavy users
  are where one constant is most wrong. Forbes stays.
- **The prior hardly matters after 30 days.** Being ±20% off moves the error by 2 kcal.
- **Partly logged days are the main bias.** 5% of days logged at half pulls the estimate about
  60 kcal low for the maintaining and gaining users. MacroFactor says it cannot detect such
  days either. This backs the research doc's "not fully logged" mark: a marked day is left out
  of the mean.
- **Responses are slower than MacroFactor's 14–30 days.** The trend lag (about 9 days), the
  20-day window and the blend add up. Faster settings cost too much error on our users. To be
  revisited with real data.
- **The menstrual swing.** The swing users keep a low error but wobble more (7 against 4). With a
  28-day window, which covers a full cycle, their wobble halves to 3.0 at the same error
  (55 → 53). The weekly check-in's capped change absorbs some of it. A "track a cycle" option
  that uses the 28-day window is the fix the plan anticipated (step 4).
