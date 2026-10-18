# Phase 3 research — how MacroFactor does it, and what we can copy

2026-10-18. Input for phase 3 (trend weight, expenditure, weekly check-in). MacroFactor
publishes its structure and a few constants; the filter weights and the
fat-fraction mapping are not published. Anything below marked *ours* is a choice we
make and must cite or tune, not something MacroFactor states.

## What MacroFactor publishes

| Piece | Published | Source |
|---|---|---|
| Trend weight | "a moving average … that places greater emphasis on more recent weigh-ins", over "a pretty long time scale". Missing days filled by **linear interpolation** (151 Mon, 150 Wed → 150.5 Tue). No outlier rule stated. Weigh daily, at least 3×/week. | [Weight Trend](https://help.macrofactorapp.com/en/articles/21-weight-trend), [Algorithms and core philosophy](https://macrofactor.com/macrofactors-algorithms-and-core-philosophy/) |
| Change rate | Trend change **over the past 20 days**, shown per week. | [Change Rate](https://help.macrofactorapp.com/en/articles/19-change-rate) |
| Expenditure | Deterministic energy balance: intake − change in stored energy, from trend weight. Adherence plays no part. | [Expenditure](https://help.macrofactorapp.com/en/articles/20-expenditure) |
| Energy in weight change | Fat ≈ **9,400 kcal/kg**, lean ≈ **1,800 kcal/kg**; slower loss or faster gain is assumed to be a larger fat share. The mapping from rate to fat share is not published. | [Body recomposition](https://help.macrofactorapp.com/en/articles/220-how-do-macrofactor-s-algorithms-respond-to-body-recomposition), [Expenditure](https://help.macrofactorapp.com/en/articles/20-expenditure) |
| Starting estimate | Own BMR equation × activity multiplier. The BMR already assumes 5–8% lower when losing; then × (1 − 4 × weekly goal rate), so 1%/week → about 10% lower overall, 2%/week → about 15%. | [Expenditure modifiers](https://macrofactor.com/expenditure-modifiers/) |
| Response speed | Ignores 1–4 day blips, reacts from day 4–5 of a persistent change. Settles in about 14–30 days. First 30 days are a calibration period with larger updates. Average change is about 7 kcal/day per day. Median expenditure error 89–108 kcal over 100 days. | Algorithms article, Expenditure modifiers |
| Gaps | After a break in tracking, the last high-confidence expenditure is carried forward. | Algorithms article |
| Data needed | Food logged ≥ 4 of every 7 days (7 ideal), weight ≥ 1 per 7 days (3+ ideal). Partly logged days cannot be detected and pull expenditure down. | [Goal adjustments](https://help.macrofactorapp.com/en/articles/222-how-does-macrofactor-make-adjustments-for-a-weight-gain-or-weight-loss-goal), Expenditure |
| Weekly check-in | Goal rate is a **% of body weight per week**. Target = expenditure ± the rate's energy. Each week is self-contained: no making up for last week. Changes are smoothed (a stall that would justify −500 kcal gives −200 to −300). Big changes need 3–4 weeks of consistent data. The first check-in moves only a few kcal. | Goal adjustments |
| Macros | Protein first (lean mass, exercise type, chosen level), changing a gram or two a day. Fat and carbs take the energy changes per the chosen split. Fat has a floor; below it, carbs are cut. | Goal adjustments |
| Optional modifiers | Steps nudge expenditure gradually, never added per day. Changing the goal nudges expenditure (e.g. lose 1%/wk → gain 0.5%/wk: +6% over a couple of weeks). | Expenditure modifiers |

## What upstream does today

- **Target** = IOM 2005 TDEE + goal adjustment + logged activities (`lib/core/utils/calc/calorie_goal_calc.dart`).
  The goal adjustment is ±500 kcal, or weekly pace × 1,100 kcal/day per kg/week (7,700 kcal/kg).
  It can taper to maintenance within 5 → 1 kg of the target weight.
- **Trend** = a 7-day moving average drawn on the weight chart (`WeightMovingAverage`). Nothing reads it back into the target.
- No measured expenditure.

## Other references

- **SparkyFitness `AdaptiveTdeeService.ts`** (MIT, in this machine's SparkyFitness checkout):
  - linear interpolation, then a 7-day simple moving average
  - 28-day window
  - mean intake over days with ≥ 200 kcal logged
  - a flat **6,000 kcal/kg**, documented as a 55/45 fat/lean blend
  - a ±500 kcal clamp around the formula TDEE
  - HIGH/MEDIUM/LOW confidence, lowered for gaps of 3+ days and for under 6 weeks of tracking
- **Hacker's Diet** (John Walker): an exponentially smoothed trend, 10% weight on the new reading, which lags about like a 20-day average. [fourmilab](https://fourmilab.ch/hackdiet/www/subsubsection1_2_4_0_4_4.html)
- **Hall 2008**, "What is the required energy deficit per unit weight loss?":
  - The 7,700 kcal/kg rule fits only people with more than ~30 kg body fat. It overstates the deficit for leaner people.
  - The fat share follows Forbes's curve and depends on body fat.
  - [PubMed](https://pubmed.ncbi.nlm.nih.gov/17848938/)
- **Thomas et al. 2013 (IJO):** measured loss averaged 67% of the 7,700-rule's prediction (range 39–94%). [IJO](https://www.nature.com/articles/ijo2012109)

## Proposed fork design (for D13)

The settings switch has two independent choices.

**Weight trend:** *7-day average* (upstream) or *Smoothed trend*.

**Calorie target:** *Formula* (upstream, unchanged) or *Adaptive*.

The *Adaptive* target follows the MacroFactor structure above:

1. **Trend.** Interpolate missing days linearly (MF). Smooth exponentially with 10% weight on each new day (Walker; *ours*, tuned in step 7).
2. **Change rate.** Trend change over the past 20 days (MF).
3. **Stored energy.** The fat share comes from Forbes's curve via Hall 2008, which needs a body-fat estimate (from BMI if none is entered).
   Fat 9,400 kcal/kg, lean 1,800 kcal/kg (MF; Hall).
   Fallback: a flat 6,000 kcal/kg (SparkyFitness), until we know the curve helps.
4. **Expenditure.** Mean intake over logged days in the window, minus stored-energy change per day.
   - It is blended into the running estimate rather than replacing it, faster during the first 30 days (MF's structure; blend weights *ours*).
   - Prior: upstream's IOM 2005 TDEE × (1 − 4 × weekly goal rate) (MF).
   - Not updated in a week with fewer than 4 days logged or no weigh-in (MF); the last confident value is carried.
5. **Weekly check-in.**
   - Target = expenditure ± goal rate (% of body weight per week) × energy density. Adherence-neutral.
   - The change per check-in is limited (*ours*, after MF's "200–300 instead of 500").
   - Accepted or edited by the user.
6. **Kept from upstream:** the taper near the target weight and the low-calorie warning.
   **Not kept:** adding logged activities to an adaptive target. Measured expenditure already contains them, so adding them counts exercise twice.
7. **Tuning and checks.** Simulate users with a known expenditure: weights from Hall-style energy balance, daily water noise of about ±1 kg, missed days, under-logged days.
   Measure, as MF does:
   - stability: kcal/day change per day
   - responsiveness: days to follow a step change in expenditure
   - error against the known truth

   Run the same on upstream's demo-seeded year. The tuning chooses the trend weight and the blend weights.

Upstream angle: the maintainer cites a source for every calculation. Everything above except the
blend and limit weights has one. Those come from the simulation, which can be published with the PR.
