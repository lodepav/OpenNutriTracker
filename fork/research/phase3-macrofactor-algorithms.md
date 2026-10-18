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

## Details (researched 2026-10-18)

### Fat share of a weight change — Forbes

Forbes's relation, in its small-change form: the fat-free share of a weight change is
`10.4 / (10.4 + F)`, and the fat share is `F / (10.4 + F)`, where F is current fat mass in kg.
It depends only on fat mass. Hall 2007 extended it to large changes (a Lambert-W form). For
modest changes his result is very close to Forbes's. Large losses such as after bariatric
surgery differ, and those are not this app's case. A 20-day window is a small change, so the
small-change form fits.
[Hall 2007, Br J Nutr 97:1059](https://pubmed.ncbi.nlm.nih.gov/17367567/) ·
[PMC2376748](https://pmc.ncbi.nlm.nih.gov/articles/PMC2376748) ·
[Broyles et al. 2011](https://digitalcommons.lsu.edu/psychology_pubs/777) (states both fractions)

Energy densities (Hall 2008): fat 39.5 MJ/kg ≈ 9,441 kcal/kg; lean change 7.6 MJ/kg ≈
1,817 kcal/kg. So the energy in 1 kg of change is

    ρ(F) = (9441·F + 1817·10.4) / (F + 10.4)    kcal/kg

| Fat mass F | Fat share | ρ (kcal/kg) |
|---|---|---|
| 10 kg | 49% | ≈ 5,550 |
| 20 kg | 66% | ≈ 6,830 |
| 30 kg | 74% | ≈ 7,480 |
| 50 kg | 83% | ≈ 8,130 |

The table shows why one constant is wrong. 7,700 fits only around 35 kg of fat and up.
SparkyFitness's 6,000 fits about 13 kg. Hall's worked example: F = 20 kg losing 15 kg averages
24.7 MJ/kg ≈ 5,900 kcal/kg, because ρ falls as fat is lost. Recomputing F from the trend every
day gives this for free.
[Hall 2008 (PMC2376744)](https://pmc.ncbi.nlm.nih.gov/articles/PMC2376744)

MacroFactor additionally assumes slower loss or faster gain is a larger fat share. Forbes has no
rate term, and MF does not publish theirs. **Ours:** Forbes only. A rate term is a later
experiment in the simulator, and only if it lowers error.

### Fat mass when the user has not measured it — Deurenberg

ONT stores height, weight, birthday, gender and a calories profile, and no body fat. Deurenberg,
Weststrate and Seidell 1991 (Br J Nutr), adults:

    body fat % = 1.20·BMI + 0.23·age − 10.8·sex − 5.4      (sex: 1 male, 0 female)

R² 0.79, SEE 4.1 percentage points. It slightly overestimates in obesity. One external check in
women 50+ found a 1.1-point underestimate (SEE 6.1). Ages 7–83; a separate formula applies at
15 and under, which this feature does not serve.
[PubMed 2043597](https://pubmed.ncbi.nlm.nih.gov/2043597) ·
[30-year review, PMC8980724](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC8980724/)

- **Ours:** non-binary users take `sex` from the calories profile, as upstream's TDEE does. The averaged profile uses 0.5.
- **Ours:** an optional measured body-fat entry overrides the formula (a fork field, in the backup).
- Sensitivity: a 4-point body-fat error at 80 kg is about 3 kg of fat. At F = 20 that moves ρ by about 4%, so about 20 kcal/day at a 0.5 kg/week loss. That is small next to the logging error.

### Simulator inputs

- **Day-to-day weight noise.** No clean published within-person SD was found.
  - Khosla & Billewicz 1964: day-to-day changes over 0.5 kg were common and over 1 kg occasional in free-living adults.
  - Turicchi 2020 (NoHoW, 1,421 adults): a weekly cycle of about 0.35% of body weight, up at weekends, down on weekdays.
  - Orsama 2014: the same weekly pattern.
  - Holiday gain of 1.35% over Christmas, not fully lost afterwards.

  **Ours:** noise SD 0.5 kg (swept 0.3–1.0 kg), plus the 0.35% weekly cycle, plus occasional
  multi-day water shifts (salt, carbs, creatine; MF names these as failure cases).

  [Khosla & Billewicz 1964](https://www.cambridge.org/core/services/aop-cambridge-core/content/view/4E78A0DB251133BEF39D73EB50C2F8A2/S0007114564000228a.pdf/div-class-title-measurement-of-change-in-body-weight-div.pdf) ·
  [Turicchi 2020, PLoS ONE](https://eprints.whiterose.ac.uk/162249) ·
  [Orsama 2014, Obesity Facts](https://doaj.org/article/dfacb22f12a749e287f852dab247d361)
- **Under-logging.** Against doubly labelled water, under-reporting is widespread and large. Food records ran 19–41% low in a classic study. A 2025 analysis of 6,497 DLW measurements estimated misreporting above 50% in national surveys.
  The key point for the design: **a steady under-log does not hurt an adaptive estimate.** Expenditure becomes "expenditure in logged calories", and targets in the same currency still work. That is MacroFactor's argument too.
  What hurts is *changing* under-logging (forgotten meals, holidays, a partly logged day). The simulator varies the logging fraction per day and per week rather than using a constant.
  [Systematic review, PMC6928130](https://pmc.ncbi.nlm.nih.gov/articles/PMC6928130) ·
  [Bajunaid et al. 2025, Nature Food](https://strathprints.strath.ac.uk/91881/7/Bajunaid-etal-NF-2025-Predictive-equation-derived-from-6497-doubly-labelled-water-measurements-enables-the-detection.pdf)
- **Truth model.** Simulated users follow energy balance. Stored energy changes by intake − expenditure, split by Forbes, so the simulator and the estimator share the energy model; *ours*, as a known limitation.
  Expenditure moves with body weight. Hall's model has a half time of about a year for the response to an intake change, and larger people lose more.
  **Ours:** expenditure falls about 22 kcal/day per kg lost, plus an adaptive drop of a few percent during a deficit, as in MF's 4 × rate prior. Then step changes in activity test responsiveness.
  Hall's `bw` R package and the NIDDK Body Weight Planner are the reference if the simple model proves too crude.
  [Hall et al. 2011, Lancet](https://pmc.ncbi.nlm.nih.gov/articles/PMC3880593) ·
  [Web appendix](https://www.niddk.nih.gov/-/media/Files/BWP/Hall_Lancet_Web_Appendix.pdf) ·
  [Body Weight Planner](https://www.niddk.nih.gov/research-funding/at-niddk/labs-branches/laboratory-biological-modeling/integrative-physiology-section/research/body-weight-planner)

### Trend smoothing

An exponential trend with weight α on today's value lags by about (1 − α)/α days:

| α | Lag |
|---|---|
| 0.10 (Walker) | ≈ 9 days |
| 0.05 | ≈ 19 days |
| 0.20 | ≈ 4 days |

MacroFactor ignores blips of 1–4 days and reacts from day 4–5. That suggests α near 0.1–0.2 on
interpolated daily values. Upstream's 7-day average lags 3 days, but it jumps when a weigh-in
enters or leaves the window. **Ours:** sweep α in 0.05–0.25 in the simulator.

### Partly logged days

MacroFactor cannot detect them and says so. **Ours:**
- Let the user mark a day "not fully logged" (fork data, in the backup). Marked days are left out of the intake mean, as unlogged days are.
- Upstream's tracked-day record is the natural place to read "logged at all" from.
- SparkyFitness's rule of skipping days under 200 kcal is kept as a safety net.

### Still not published anywhere

MacroFactor's filter weights, its expenditure blend and calibration schedule, its check-in cap,
and its rate term in the fat share. All four are set by the simulator, and the results go with
the upstream issue.
