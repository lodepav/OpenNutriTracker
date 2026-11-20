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

## Closed loop (D64, D65)

2026-11-20. The simulator above and the journey replay both feed the estimator an intake and a
weight decided beforehand, so a target it proposes changes nothing it later reads. In
`fork/tools/closed_loop.dart` (`flutter test fork/tools/closed_loop.dart`) the simulated user
eats each weekly check-in's target, and the truth is not the estimator's own model: glycogen
and gut water follow the intake (0, 1 or 2 kg per 1,000 kcal/day, a 3-day lag; an assumption),
tissue can count a flat 7,700 kcal/kg, and 5% of days are logged at half. 280 days, 12–30
seeds. Error is |estimate − truth| in logged calories from day 42.

**The settings.** None makes the loop unstable; the achieved pace holds whatever is chosen.

| Setting | Bias | Error | Weekly target move | Moves that turn back | Pace (goal −0.50) |
|---|---|---|---|---|---|
| Steady | +66 | 73 | 17 | 5% | −0.50 |
| Standard | +63 | 69 | 20 | 3% | −0.51 |
| Responsive | +56 | 67 | 33 | 12% | −0.52 |
| Standard, 7,700 kcal/kg | +104 | 107 | 21 | 3% | −0.51 |
| Standard, truth at 7,700 | +13 | 38 | 20 | 3% | −0.50 |
| 1 kg cycle (goal −0.30), Standard | +30 | 48 | 45 | 39% | −0.31 |
| 1 kg cycle, Responsive | +16 | 64 | 76 | 44% | −0.32 |
| 1 kg cycle, Standard, cycle window | +29 | 40 | 16 | 1% | −0.31 |

- The kcal per kg moves the estimate shown, by the goal's energy times the mismatch, and not
  the pace: at the loop's fixed point the weight changes at the goal's pace whatever a kg is
  counted as.
- The check-in limit at 200 or 300 never bound after calibration.
- A cycle without its window is the one case where the target chases water.
- A 300 kcal step in expenditure is followed without ringing: Standard closes it in about 9
  weeks, Responsive in about 6 with an overshoot under 10 kcal, Steady in about 12.

**A change in what is eaten (D64).** Pace 0 to −0.75 kg/week at day 140; estimate − truth by
week, from two weeks before (30 seeds):

| Water | Run | Weeks |
|---|---|---|
| 0 | Standard, before | −49 −47 −53 −54 −84 −112 −94 −58 −18 20 56 82 |
| 0 | Standard, D64 | −52 −50 −55 −26 −2 20 37 49 62 72 87 86 |
| 0 | Responsive, before | −53 −53 −63 −90 −144 −183 −136 −68 −2 55 101 125 |
| 0 | Responsive, D64 | −55 −56 −64 −42 −16 4 23 39 57 71 85 88 |
| 2 | Standard, before | −49 −48 −54 −6 66 142 193 187 161 133 118 112 |
| 2 | Standard, D64 | −48 −46 −52 −12 12 33 52 76 100 109 111 100 |
| 2 | Responsive, before | −50 −51 −59 2 107 203 239 183 120 84 84 97 |
| 2 | Responsive, D64 | −48 −47 −56 −13 12 32 53 90 115 107 96 88 |

Both runs end near +100: the estimate trails an expenditure that falls with the weight. The
thresholds (5% and 15% of the mean intake) were the best of a small sweep: wider ones (10% and
25–30%) let the water bump through (87–133 kcal), none at all gave the rows marked before.

**A cold start** is not damped. Mean |estimate − truth| over weeks 3–12 of six cold starts
(prior ±20%, water 0, 1, 2) was 109 undamped and 112 with damping after calibration; damping
from the first update was worse in five of the six. The first two weeks' target is the
formula's, and weeks 3–8 are still off by 100–250 kcal either way: open.

2026-11-20, a second try at the cold start. Score: mean |estimate − truth| over check-ins 3–8
and 9–15, 30 seeds, the six cold starts on Standard. "Prior ±20%" starts at +738 and −318
logged kcal, as the prior is not scaled by the 0.9 logging share. The signed error goes
opposite ways: with the prior 20% high it ends weeks 4–8 near −120 with no water and near
+120 with 2 kg, and at 1 kg the two cancel. So each change below helps some cold starts and
hurts others, and none ships.

| Run | Water 0, +20% | 0, −20% | 1, +20% | 1, −20% | 2, +20% | 2, −20% | Settled |
|---|---|---|---|---|---|---|---|
| Standard | 197 / 73 | 166 / 71 | 124 / 75 | 104 / 67 | 135 / 95 | 92 / 72 | 69 |
| Intake trend in the raw, calibrating | 127 / 71 | 123 / 71 | 173 / 91 | 81 / 66 | 243 / 119 | 71 / 68 | 73 |
| Calibration blend 0.1, 45 days | 168 / 67 | 148 / 76 | 105 / 68 | 99 / 68 | 147 / 100 | 81 / 66 | 66 |
| First update on day 10 | 183 / 74 | 156 / 72 | 128 / 74 | 105 / 68 | 126 / 94 | 97 / 72 | 69 |
| First update on day 14 | 158 / 73 | 136 / 75 | 134 / 73 | 104 / 69 | 125 / 88 | 111 / 74 | 70 |

"Intake trend in the raw" takes the window's mean of the intake's trend, which lags as the
weight's does, in place of its mean intake. It removes the lag's misreading and leaves the
water's, which the lag had been cancelling. The blend at 0.1, 0.2 or 0.3 with 30 or 45 days
moved the mean of the six by at most 11 kcal. The check-in cap does not apply while
calibrating, so it is no lever here. What is left is the water: a cut's first days shed it,
and the estimate has no way to tell it from tissue.

**Days logged at half (D65).** At maintenance, the user following the target:

| Days at half | Bias | Real drift | With the days pointed out left out |
|---|---|---|---|
| 0% | −3 | 0.0 kg/year | −3 |
| 5% | −57 | −3.6 | −3 |
| 10% | −100 | −6.2 | −6 |
| 20% | −188 | −12.0 | −16 |

Days not logged at all and a steady under-logging move nothing. With no half days and an
intake that swings 25% a day, leaving out every day pointed out reads +74 kcal high, which is
why the day is asked about.

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
