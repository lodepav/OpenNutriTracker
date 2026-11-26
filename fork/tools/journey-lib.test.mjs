// node --test fork/tools/journey-lib.test.mjs
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { added, checkJ1, checkJ2, checkJ3, checkJ4, checkJ5, checkJ6, diffFacts, hollow, mathProblems, report } from './journey-lib.mjs'

const per = (kcal, protein, carbs, fat) => ({ kcal, protein, carbs, fat })
const at = (meal, name, amount, p, unit = 'g') => ({
  meal, name, amount, unit, source: 'fdc',
  // as the handler rounds: to 0.1
  kcal: Math.round((p.kcal * amount) / 10) / 10,
  protein: Math.round((p.protein * amount) / 10) / 10,
  carbs: Math.round((p.carbs * amount) / 10) / 10,
  fat: Math.round((p.fat * amount) / 10) / 10,
  per100: p,
})
const OATS = per(379, 13.2, 67.7, 6.5)
const MILK = per(61, 3.3, 4.6, 3.3)
const shown = entries => {
  const s = k => Math.round(entries.reduce((n, e) => n + e[k], 0))
  return { goalKcal: 2400, eatenKcal: s('kcal'), leftKcal: 2400 - s('kcal'), protein: s('protein'), carbs: s('carbs'), fat: s('fat') }
}
const day = (entries, extra = {}) => ({ entries, shown: shown(entries), weight: null, adaptive: null, ...extra })

// the profile already holds a lunch; the journey adds oats (edited 80 → 120 g) and milk once after Undo
const lunch = at('lunch', 'Rice, white, long-grain, regular, enriched, cooked', 150, per(130, 2.7, 28.2, 0.3))
const j1 = (after, ui = {}) => checkJ1({
  before: day([lunch]),
  after,
  ui: { undoShown: true, undoTookBack: true, ...ui },
})
const goodJ1 = () => day([lunch, at('breakfast', 'Oats, raw', 120, OATS), at('snack', 'Milk, whole', 250, MILK)])

test('a good J1 run has no problems and keeps only its own entries', () => {
  const r = j1(goodJ1())
  assert.deepEqual(r.problems, [])
  assert.deepEqual(r.facts.entries.map(e => e.name), ['Oats, raw', 'Milk, whole'])
  assert.equal(report('J1', r).code, 0)
})

test('the edit kept the amount it replaced', () => {
  const r = j1(day([lunch, at('breakfast', 'Oats, raw', 80, OATS), at('snack', 'Milk, whole', 250, MILK)]))
  assert.ok(r.problems.some(p => p.includes('saved as 80 g')), r.problems.join('\n'))
})

test('the edit added a second entry instead of changing the first', () => {
  const r = j1(day([lunch, at('breakfast', 'Oats, raw', 80, OATS), at('breakfast', 'Oats, raw', 120, OATS), at('snack', 'Milk, whole', 250, MILK)]))
  assert.ok(r.problems.some(p => p.includes('2 new entries match /^Oats/')))
})

test('Undo that did not take the drink back leaves it twice', () => {
  const r = j1(day([...goodJ1().entries, at('snack', 'Milk, whole', 250, MILK)]), { undoTookBack: false })
  assert.ok(r.problems.some(p => p.includes('still logged after Undo')))
  assert.ok(r.problems.some(p => p.includes('2 new entries match /^Milk/')))
})

test('kcal that is not per 100 × grams fails, rounding does not', () => {
  // 379 × 1.2 = 454.8; 454.8 is right, 455 is the screen's rounding, 379 is the 100 g value saved
  assert.deepEqual(mathProblems({ ...at('breakfast', 'Oats, raw', 120, OATS), kcal: 454.8 }), [])
  assert.deepEqual(mathProblems({ ...at('breakfast', 'Oats, raw', 120, OATS), kcal: 455 }), [])
  assert.equal(mathProblems({ ...at('breakfast', 'Oats, raw', 120, OATS), kcal: 379 }).length, 1)
  // a serving is not weighed, so no per-100 rule
  assert.deepEqual(mathProblems({ ...at('snack', 'Bar', 1, per(400, 1, 1, 1), 'serving'), kcal: 210 }), [])
})

test('Home totals that are not the sum of entries fail, whole-number rounding does not', () => {
  const after = goodJ1()
  assert.deepEqual(j1({ ...after, shown: { ...after.shown, eatenKcal: after.shown.eatenKcal + 1, leftKcal: after.shown.leftKcal - 1 } }).problems, [])
  const off = j1({ ...after, shown: { ...after.shown, eatenKcal: after.shown.eatenKcal - 195 } })
  assert.ok(off.problems.some(p => p.includes('kcal eaten')))
  assert.ok(off.problems.some(p => p.includes('left of 2400')))
})

test('no totals on Home is a failure, not a pass', () => {
  const r = j1({ ...goodJ1(), shown: null })
  assert.ok(r.problems.some(p => p.includes('no totals')))
})

test('added() keeps a food the profile already logged once and the journey logged again', () => {
  const m = at('snack', 'Milk, whole', 250, MILK)
  assert.equal(added({ entries: [m] }, { entries: [m, m] }).length, 1)
  assert.equal(added({ entries: [m] }, { entries: [m] }).length, 0)
})

// J2: the owner's day, with a weigh-in from the fake Health Connect and the check-in's numbers
const CHICKEN = per(176, 31, 0, 5.3)
const RICE = per(130, 2.7, 28.2, 0.3)
const LETTUCE = per(17, 1.2, 3.3, 0.3)
const adaptive = { due: false, expenditureKcal: 2611, proposedTargetKcal: 2111, averageIntakeKcal: 2034, trendKg: 79.4, weekChangeKg: -0.21, loggedDays: 27, weighIns: 30, lastCheckIn: { daysAgo: 3, acceptedKcal: 2150, expenditureKcal: 2650 } }
const goodJ2 = (extra = {}) => {
  const entries = [
    at('breakfast', 'Overnight oats', 1, per(520, 30, 60, 15), 'serving'),
    at('snack', 'Protein shake', 1, per(260, 40, 10, 5), 'serving'),
    // the fake AI's guess at a photo, saved as a weighed custom food
    at('lunch', 'Dirty fries with pork', 430, per(240, 9, 22, 13)),
    at('dinner', 'Chicken breast, grilled without sauce, skin not eaten', 200, CHICKEN),
    at('dinner', 'Rice, white, long-grain, regular, enriched, cooked', 150, RICE),
    at('dinner', 'Lettuce, cos or romaine, raw', 80, LETTUCE),
  ]
  return checkJ2({ before: day([]), after: day(entries, { weight: { kg: 79, source: 'health' }, adaptive, ...extra }), ui: { checkInOpened: true } })
}

test('a good J2 run has no problems; its facts hold the check-in numbers', () => {
  const r = goodJ2()
  assert.deepEqual(r.problems, [])
  assert.equal(r.facts.adaptive.expenditureKcal, 2611)
  assert.equal(report('J2', r, r.facts).code, 0)
})

test('J2 with no weigh-in today fails twice and reports the weight as hollow', () => {
  const r = goodJ2({ weight: null })
  assert.ok(r.problems.some(p => p.includes("no weigh-in on today's date")))
  assert.ok(r.problems.some(p => p.includes('is missing')))
  assert.match(report('J2', r).text, /hollow fact weight/)
})

test('a typed weigh-in is not the Health Connect one', () => {
  assert.ok(goodJ2({ weight: { kg: 79, source: 'typed' } }).problems.some(p => p.includes('is typed')))
})

test('a check-in that threw fails and leaves adaptive hollow', () => {
  const r = goodJ2({ adaptive: { error: 'Bad state: no weights' } })
  assert.ok(r.problems.some(p => p.includes('Bad state: no weights')))
  assert.match(report('J2', r).text, /hollow fact adaptive/)
})

test('a profile with no check-in yet is not hollow', () => {
  const r = goodJ2({ adaptive: { ...adaptive, lastCheckIn: null } })
  assert.deepEqual(r.problems, [])
  assert.doesNotMatch(report('J2', r).text, /hollow/)
})

test('a moved expenditure is a DIFF against the baseline', () => {
  const base = goodJ2().facts
  const r = goodJ2({ adaptive: { ...adaptive, expenditureKcal: 2590 } })
  const out = report('J2', r, base)
  assert.equal(out.code, 1)
  assert.match(out.text, /DIFF adaptive\.expenditureKcal: 2611 → 2590/)
  assert.match(out.text, /0 failed checks, 1 difference/)
})

test('diffFacts names an added and a dropped value', () => {
  assert.deepEqual(diffFacts({ a: 1, b: [1] }, { a: 1, b: [1, 2], c: null }), ['b.1: – → 2', 'c: – → null'])
})

test('hollow finds null, false and empty, not zero', () => {
  assert.deepEqual(hollow({ a: 0, b: '', c: null, d: [], e: {}, f: false, g: [1] }), ['c', 'd', 'e', 'f'])
})

test('a photo lunch saved twice (a submit tapped twice) fails', () => {
  const twice = at('lunch', 'Chicken rice bowl', 430, per(114, 12, 10, 2))
  const r = checkJ2({ before: day([]), after: day([twice, twice], { weight: { kg: 79, source: 'health' }, adaptive }), ui: { checkInOpened: true } })
  assert.ok(r.problems.some(p => p.includes('saved 2 entries, not 1')))
})

// J3: a snack logged on yesterday from the Diary; the day row holds the totals the Diary shows
const ALMONDS = per(579, 21.2, 21.6, 49.9)
const tracked = entries => {
  // the day row adds the unrounded values, so it drifts from the rounded entries by a little
  const s = k => Math.round(entries.reduce((n, e) => n + e[k], 0) * 10) / 10 + 0.04
  return { kcal: s('kcal'), protein: s('protein'), carbs: s('carbs'), fat: s('fat') }
}
const yday = (entries, extra = {}) => ({ entries, tracked: entries.length ? tracked(entries) : null, shown: null, ...extra })
const demoLunch = at('lunch', 'Brown rice', 180, per(112, 2.3, 23.5, 0.8))
const todayDay = day([lunch])
const j3 = ({ y = [demoLunch, at('snack', 'Almonds, unroasted', 30, ALMONDS)], today = todayDay, yExtra = {} } = {}) => checkJ3({
  before: { ...todayDay, yesterday: yday([demoLunch]) },
  after: { ...today, yesterday: yday(y, yExtra) },
  ui: { backToToday: true },
})

test('a good J3 run has no problems and keeps the snack alone', () => {
  const r = j3()
  assert.deepEqual(r.problems, [])
  assert.deepEqual(r.facts.entries.map(e => [e.name, e.amount]), [['Almonds, unroasted', 30]])
  assert.equal(report('J3', r).code, 0)
})

test('J3: a snack that landed on today fails twice: none yesterday, today changed', () => {
  const r = j3({ y: [demoLunch], today: day([lunch, at('snack', 'Almonds, unroasted', 30, ALMONDS)]) })
  assert.ok(r.problems.some(p => p.includes('yesterday gained none')), r.problems.join('\n'))
  assert.ok(r.problems.some(p => p.includes('today changed: gained Almonds, unroasted 30 g')))
  assert.match(report('J3', r).text, /hollow fact entries/)
})

test("J3: a day row that missed the snack fails yesterday's totals", () => {
  const y = [demoLunch, at('snack', 'Almonds, unroasted', 30, ALMONDS)]
  const r = j3({ y, yExtra: { tracked: tracked([demoLunch]) } })
  assert.ok(r.problems.some(p => p.includes("yesterday's kcal total is")), r.problems.join('\n'))
})

test('J3: no day row yesterday is a failure, not a pass', () => {
  const r = j3({ yExtra: { tracked: null } })
  assert.ok(r.problems.some(p => p.includes('yesterday has no day totals')))
})

test('J3: the snack saved as a serving is not the grams typed', () => {
  const r = j3({ y: [demoLunch, at('snack', 'Almonds, unroasted', 1, ALMONDS, 'serving')] })
  assert.ok(r.problems.some(p => p.includes('saved as 1 serving, typed 30 g')))
})

// J4: yesterday's lunch, one food imported food by food and one logged here, copied to today
const owLunch = [
  at('lunch', 'Chicken breast, grilled without sauce, skin not eaten', 150, CHICKEN),
  { ...at('lunch', 'Rice, white, long-grain, regular, enriched, cooked', 212.5, RICE), source: 'custom' },
]
const owYesterday = yday([at('breakfast', 'Oats, raw', 60, OATS), ...owLunch])
const j4 = (todayAfter, yAfter = owYesterday, ui = {}) => checkJ4({
  before: { ...day([]), yesterday: yday([]) },
  after: { ...day(todayAfter), yesterday: yAfter },
  // the profile held no lunch yesterday, so the journey logged one before the copy
  ui: { yesterdayBefore: owYesterday, seeded: true, ...ui },
})

test('a good J4 run has no problems; its facts are the copied lunch', () => {
  const r = j4(owLunch)
  assert.deepEqual(r.problems, [])
  assert.equal(r.facts.entries.length, 2)
  assert.equal(r.info.seeded, true)
  assert.equal(report('J4', r).code, 0)
})

test('J4: a move empties yesterday and fails', () => {
  const r = j4(owLunch, yday([at('breakfast', 'Oats, raw', 60, OATS)]))
  assert.ok(r.problems.some(p => p.includes('yesterday changed') && p.includes('lost Chicken')), r.problems.join('\n'))
})

test('J4: a copy that dropped a food or changed its amount fails', () => {
  assert.ok(j4([owLunch[0]]).problems.some(p => p.includes("yesterday's lunch is")))
  assert.ok(j4([owLunch[0], at('lunch', owLunch[1].name, 212, RICE)]).problems.some(p => p.includes('today gained')))
})

test('J4: a copy into another meal is not a lunch copy', () => {
  const r = j4(owLunch.map(e => ({ ...e, meal: 'snack' })))
  assert.ok(r.problems.some(p => p.includes('(not all in lunch)')), r.problems.join('\n'))
})

test('J4: no lunch yesterday to copy fails', () => {
  const r = j4([], yday([]), { yesterdayBefore: yday([]) })
  assert.ok(r.problems.some(p => p.includes('yesterday held no lunch')))
})

// J5: the cached product, logged in grams; the handler gives per100 as the cache holds it
const BAR = per(412, 8.5, 62, 13.2)
const bar = (grams = 45, p = BAR) => ({ ...at('snack', 'Journey muesli bar', grams, p), source: 'off' })
const j5 = entries => checkJ5({ before: day([lunch]), after: day([lunch, ...entries]), ui: { productOpened: true } })

test('a good J5 run has no problems', () => {
  const r = j5([bar()])
  assert.deepEqual(r.problems, [])
  assert.equal(report('J5', r).code, 0)
})

test('J5: logged twice fails', () => {
  assert.ok(j5([bar(), bar()]).problems.some(p => p.includes('not one /^Journey muesli bar/ entry')))
})

test('J5: a product with other per-100 values than the cached one fails', () => {
  // a thin search result under the same code: energy only
  const r = j5([bar(45, { kcal: 412, protein: null, carbs: null, fat: null })])
  assert.ok(r.problems.some(p => p.includes('per-100 g protein, carbs, fat')), r.problems.join('\n'))
})

// J6: the check-in made due, opened from Home's card and accepted as shown
const ad = (rows, last, extra = {}) => ({ ...adaptive, checkIns: rows, goalOffsetKcal: 0, goalActivityKcal: 0, lastCheckIn: last, ...extra })
const j6 = ({ rows = 1, accepted = 2111, goal = 2111, ui = {}, extra = {} } = {}) => checkJ6({
  before: day([], { adaptive: ad(0, null) }),
  after: { ...day([]), shown: { ...shown([]), goalKcal: goal, leftKcal: goal }, adaptive: ad(rows, { daysAgo: 0, acceptedKcal: accepted, expenditureKcal: 2611 }, extra) },
  ui: { due: true, opened: true, proposed: 2111, shownTarget: 2111, ...ui },
})

test('a good J6 run has no problems, and its facts hold no calendar numbers', () => {
  const r = j6()
  assert.deepEqual(r.problems, [])
  assert.deepEqual(Object.keys(r.facts), ['checks'])
  assert.equal(report('J6', r, r.facts).code, 0)
})

test("J6: Home's goal counts the weekday offset and today's activity", () => {
  assert.deepEqual(j6({ goal: 2361, extra: { goalOffsetKcal: 200, goalActivityKcal: 50 } }).problems, [])
  assert.ok(j6({ goal: 2150 }).problems.some(p => p.includes("Home's goal is 2150")))
})

test('J6: an accepted target other than the one shown fails', () => {
  const r = j6({ accepted: 2000, goal: 2000 })
  assert.ok(r.problems.some(p => p.includes('the screen showed 2111')), r.problems.join('\n'))
})

test('J6: a check-in that replaced the last row gains none and fails', () => {
  assert.ok(j6({ rows: 0 }).problems.some(p => p.includes('from 0 to 0 rows')))
})
