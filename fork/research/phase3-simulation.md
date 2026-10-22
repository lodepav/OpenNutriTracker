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
