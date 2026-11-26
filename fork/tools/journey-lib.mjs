// The pure half of journey-check.mjs: what each scripted journey (fork/ux/JOURNEYS.md, "Check")
// must leave behind, read from the app's own repositories through the journey entry point's
// `state` command, and the comparison with the accepted baseline. journey-lib.test.mjs runs it
// without the emulator.
//
// A run gives two things. `problems`: the rules the journey states, checked on every run whatever
// the baseline says. `facts`: what the run saved, compared with the baseline. Facts hold nothing
// that moves with the date: no ids or times, and only the entries the journey added, since the
// profile's own days and goals shift as the calendar moves past the snapshot.

/** What J1 types and picks, on the ux profile. Patterns are Dart and JS RegExps alike (no flags). */
export const J1_TYPED = {
  BREAKFAST: { meal: 'breakfast', query: 'oats raw', pattern: '^Oats, raw', loose: '^Oats', grams: 80, edited: 120 },
  DRINK: { meal: 'snack', query: 'milk whole', pattern: '^Milk, whole', loose: '^Milk' },
}
/** What J2 types and picks, on the owner profile (the owner's habits, confirmed 2026-11-25). */
export const J2_TYPED = {
  SHAKE: { meal: 'snack', query: 'whey', loose: '[Ww]hey|[Ss]hake' },
  LUNCH_NOTE: 'dirty fries with pork 430g',
  DINNER: [
    { meal: 'dinner', query: 'chicken breast grilled', pattern: '^Chicken breast, grilled', loose: '[Cc]hicken', grams: 200 },
    { meal: 'dinner', query: 'rice white cooked', pattern: '^Rice, white, long-grain, regular, enriched, cooked', loose: '^Rice, white', grams: 150 },
    { meal: 'dinner', query: 'lettuce romaine', pattern: '^Lettuce, cos or romaine', loose: '^Lettuce', grams: 80 },
  ],
}
/** J3, a snack logged yesterday from the Diary, on the ux profile. */
export const J3_TYPED = {
  SNACK: { meal: 'snack', query: 'almonds unroasted', pattern: '^Almonds, unroasted', loose: '^Almonds', grams: 30 },
}
/** J4, on the owner profile: the lunch logged yesterday first when the profile holds none there. */
export const J4_TYPED = {
  SEED: { meal: 'lunch', query: 'chicken breast grilled', pattern: '^Chicken breast, grilled', loose: '[Cc]hicken', grams: 150 },
}
/**
 * J5, on the ux profile: a product a scan made online would have cached. 200… is the in-store
 * range, which no product sold anywhere carries; its check digit is valid.
 */
export const J5_TYPED = {
  PRODUCT: { meal: 'snack', code: '2000000000008', name: 'Journey muesli bar', pattern: '^Journey muesli bar', grams: 45, per100: { kcal: 412, protein: 8.5, carbs: 62, fat: 13.2 } },
}
export const SCRIPTED = ['J1', 'J2', 'J3', 'J4', 'J5', 'J6']
export const PROFILE_OF = { J1: 'ux', J2: 'owner', J3: 'ux', J4: 'owner', J5: 'ux', J6: 'owner' }

const WEIGHED = new Set(['g', 'ml', 'gram', 'grams', 'milliliter', 'gml'])
const near = (a, b, tol) => a != null && b != null && Math.abs(Number(a) - Number(b)) <= tol
const sum = (xs, k) => xs.reduce((n, x) => n + Number(x[k] || 0), 0)
const keyOf = e => JSON.stringify([e.meal, e.name, e.amount, e.unit])
const matches = (e, re) => new RegExp(re).test(e.name || '')

/** An entry as the facts keep it: what was logged and what it counts. */
export const entryFacts = e => ({
  meal: e.meal, name: e.name, amount: e.amount, unit: e.unit,
  kcal: e.kcal, protein: e.protein, carbs: e.carbs, fat: e.fat,
})

/** The entries in `after` that `before` did not hold, one for one (a food logged twice stays twice). */
export function added(before, after) {
  const left = new Map()
  for (const e of before?.entries || []) left.set(keyOf(e), (left.get(keyOf(e)) || 0) + 1)
  const out = []
  for (const e of after?.entries || []) {
    const n = left.get(keyOf(e)) || 0
    if (n > 0) left.set(keyOf(e), n - 1)
    else out.push(e)
  }
  return out
}

/** Per 100 × amount, for a weighed entry: kcal and each macro, within the rounding of both. */
export function mathProblems(e) {
  if (!WEIGHED.has(String(e.unit).toLowerCase())) return []
  const out = []
  for (const [k, per] of [['kcal', 'kcal'], ['protein', 'protein'], ['carbs', 'carbs'], ['fat', 'fat']]) {
    const p = e.per100?.[per]
    if (p == null) continue
    const want = (p * e.amount) / 100
    // shown to 0.1; the table's per-100 value carries its own rounding, about 0.5%
    if (!near(e[k], want, 0.06 + want * 0.005)) out.push(`${e.name}: ${k} ${e[k]}, but ${p} per 100 × ${e.amount} ${e.unit} is ${Math.round(want * 10) / 10}`)
  }
  return out
}

/** The day's totals as Home shows them against the entries saved, and the goal left. */
function dayRules(rule, after) {
  const s = after?.shown
  if (!rule('Home shows the day', s, 'Home shows no totals for today (state.shown is empty)')) return
  const all = after.entries || []
  // each total is rounded to a whole number on screen
  rule('kcal total = sum of entries', near(s.eatenKcal, sum(all, 'kcal'), 1), `Home says ${s.eatenKcal} kcal eaten, the entries add up to ${Math.round(sum(all, 'kcal'))}`)
  for (const k of ['protein', 'carbs', 'fat']) {
    rule(`${k} total = sum of entries`, near(s[k], sum(all, k), 1), `Home says ${s[k]} g ${k}, the entries add up to ${Math.round(sum(all, k))}`)
  }
  rule('left = goal − eaten', near(s.leftKcal, s.goalKcal - s.eatenKcal, 1), `Home says ${s.leftKcal} kcal left of ${s.goalKcal} with ${s.eatenKcal} eaten`)
}

// A journey's named rules: each one's outcome goes to the facts, a failure to the problems.
function rules(J) {
  const problems = []
  const checks = {}
  const rule = (name, ok, line) => { checks[name] = !!ok; if (!ok) problems.push(`${J}: ${line}`); return !!ok }
  return { problems, checks, rule }
}

/**
 * J1, a common day on the ux profile. `run`: { before, after (state), ui: { breakfastAdded,
 * undoShown, undoTookBack, editOpened } }.
 */
export function checkJ1(run) {
  const { problems, checks, rule } = rules('J1')
  const T = J1_TYPED
  const { after, ui = {} } = run
  const mine = added(run.before, after)
  const oats = mine.filter(e => matches(e, T.BREAKFAST.loose))
  const milk = mine.filter(e => matches(e, T.DRINK.loose))
  rule('breakfast logged once', oats.length === 1, `step 1: ${oats.length} new entries match /${T.BREAKFAST.loose}/, not 1 (the edit added a second, or none was saved)`)
  const o = oats[0]
  rule('breakfast in breakfast', o?.meal === T.BREAKFAST.meal, `step 1: the oats went to ${o?.meal ?? 'nothing'}, not ${T.BREAKFAST.meal}`)
  rule('edited amount saved', o?.amount === T.BREAKFAST.edited && WEIGHED.has(String(o?.unit)), `step 4: the oats saved as ${o?.amount} ${o?.unit}, typed ${T.BREAKFAST.edited} g over ${T.BREAKFAST.grams} g (D54)`)
  rule('undo offered', ui.undoShown, 'step 3: no Undo on the bar after the drink was added (D56)')
  rule('undo took it back', ui.undoTookBack, 'step 3: the drink was still logged after Undo')
  rule('drink logged once', milk.length === 1, `step 3: ${milk.length} new entries match /${T.DRINK.loose}/ after add, Undo, add, not 1`)
  rule('drink in its meal', milk[0]?.meal === T.DRINK.meal, `step 3: the drink went to ${milk[0]?.meal ?? 'nothing'}, not ${T.DRINK.meal}`)
  for (const e of mine) for (const p of mathProblems(e)) rule(`${e.name} counts per 100 × amount`, false, p)
  dayRules(rule, after)
  return { problems, facts: { checks, entries: mine.map(entryFacts) }, info: { shown: after?.shown ?? null } }
}

/**
 * J2, the owner's day. `run`: { before, after (state), ui: { breakfastAdded, shakeAdded,
 * lunchLogged, checkInOpened } }. Every group fails the run: saved entries, day totals,
 * adaptive (a difference from the baseline too) and the weigh-in.
 */
export function checkJ2(run) {
  const { problems, checks, rule } = rules('J2')
  const T = J2_TYPED
  const { after, ui = {} } = run
  const mine = added(run.before, after)
  const of = meal => mine.filter(e => e.meal === meal)
  // Saved entries
  rule('breakfast repeated', of('breakfast').length >= 1, 'step 1: no breakfast entry was added from the recent foods')
  rule('shake logged', mine.some(e => matches(e, T.SHAKE.loose)), `step 2: no new entry matches /${T.SHAKE.loose}/`)
  const lunch = of('lunch')
  rule('photo lunch logged', lunch.length === 1 && lunch.every(e => Number(e.kcal) > 0), `step 3: the photo lunch saved ${lunch.length} entries, not 1 (a submit tapped twice?)${lunch.some(e => !(Number(e.kcal) > 0)) ? ', one with no energy' : ''}`)
  for (const d of T.DINNER) {
    const e = of('dinner').find(x => matches(x, d.loose))
    rule(`dinner ${d.query} at ${d.grams} g`, e && e.amount === d.grams && WEIGHED.has(String(e.unit)), `step 4: dinner's /${d.loose}/ saved as ${e ? `${e.amount} ${e.unit}` : 'nothing'}, typed ${d.grams} g`)
  }
  for (const e of mine) for (const p of mathProblems(e)) rule(`${e.name} counts per 100 × amount`, false, p)
  // Day totals
  dayRules(rule, after)
  // Adaptive and check-in
  const a = after?.adaptive
  rule('check-in computed', a && !a.error && a.expenditureKcal > 0 && a.proposedTargetKcal > 0, `step 6: the check-in gave ${a?.error ?? `expenditure ${a?.expenditureKcal}, target ${a?.proposedTargetKcal}`}`)
  rule('check-in screen opened', ui.checkInOpened, 'step 6: the check-in screen did not open from Settings → Goals')
  // Weight
  const w = after?.weight
  rule('weigh-in today', w && w.kg > 0, 'step 5: no weigh-in on today\'s date')
  rule('weigh-in from Health Connect', w?.source === 'health', `step 5: today's weigh-in is ${w?.source ?? 'missing'}, not from the (fake) Health Connect import`)
  const adaptive = a && !a.error ? {
    expenditureKcal: a.expenditureKcal, proposedTargetKcal: a.proposedTargetKcal, trendKg: a.trendKg,
    loggedDays: a.loggedDays, weighIns: a.weighIns,
    // a profile with no check-in yet has none to compare, which is not a hollow step
    ...(a.lastCheckIn ? { lastCheckIn: a.lastCheckIn } : {}),
  } : null
  return {
    problems,
    facts: { checks, entries: mine.map(entryFacts), adaptive, weight: w ?? null },
    info: { shown: after?.shown ?? null, adaptive: a ?? null },
  }
}

/** The entries of `a` that `b` lacks and those `b` adds, one for one: both empty when the day is unchanged. */
const changed = (a, b) => ({ gone: added(b, a), extra: added(a, b) })
const names = es => es.map(e => `${e.name} ${e.amount} ${e.unit}`).join(', ') || 'none'

/**
 * J3, yesterday's snack, on the ux profile. `run`: { before, after (today's state, each with
 * `yesterday`: that day's), ui: {} }.
 */
export function checkJ3(run) {
  const { problems, checks, rule } = rules('J3')
  const T = J3_TYPED.SNACK
  const { before, after } = run
  const y = after?.yesterday
  const mine = added(before?.yesterday, y)
  const snack = mine.filter(e => matches(e, T.loose))
  rule('snack logged once yesterday', snack.length === 1 && mine.length === 1, `step 2: yesterday gained ${names(mine)}, not one /${T.loose}/ entry`)
  const s = snack[0]
  rule('snack in its meal', s?.meal === T.meal, `step 2: the snack went to ${s?.meal ?? 'nothing'}, not ${T.meal}`)
  rule('snack at the grams typed', s?.amount === T.grams && WEIGHED.has(String(s?.unit)), `step 2: the snack saved as ${s ? `${s.amount} ${s.unit}` : 'nothing'}, typed ${T.grams} g`)
  for (const e of mine) for (const p of mathProblems(e)) rule(`${e.name} counts per 100 × amount`, false, p)
  const t = y?.tracked
  if (rule('yesterday has its totals', t, 'yesterday has no day totals (state.yesterday.tracked is empty)')) {
    const all = y.entries || []
    for (const k of ['kcal', 'protein', 'carbs', 'fat']) {
      rule(`yesterday ${k} = sum of entries`, near(t[k], sum(all, k), 1), `yesterday's ${k} total is ${t[k]}, its entries add up to ${Math.round(sum(all, k) * 10) / 10}`)
    }
  }
  const today = changed(before, after)
  rule('today unchanged', !today.gone.length && !today.extra.length, `today changed: gained ${names(today.extra)}, lost ${names(today.gone)}`)
  return { problems, facts: { checks, entries: mine.map(entryFacts) }, info: { tracked: t ?? null } }
}

/** Entries the same as a copy keeps them: meal aside (a copy can change it), name, amount, unit, kcal. */
const copyKey = e => JSON.stringify([e.name, e.amount, e.unit, Math.round(Number(e.kcal) * 10) / 10])

/**
 * J4, yesterday's lunch copied to today, on the owner profile. `run`: { before, after (today's
 * state, each with `yesterday`), ui: { yesterdayBefore (yesterday's state just before the copy,
 * after the lunch logged there when it held none), seeded } }.
 */
export function checkJ4(run) {
  const { problems, checks, rule } = rules('J4')
  const { before, after, ui = {} } = run
  const yb = ui.yesterdayBefore ?? before?.yesterday
  const lunch = (yb?.entries || []).filter(e => e.meal === 'lunch')
  rule('yesterday had a lunch', lunch.length > 0, 'step 1: yesterday held no lunch to copy')
  const mine = added(before, after)
  const got = mine.filter(e => e.meal === 'lunch')
  const want = lunch.map(copyKey).sort()
  const have = got.map(copyKey).sort()
  rule('today gained yesterday\'s lunch', mine.length === got.length && JSON.stringify(want) === JSON.stringify(have), `step 3: today gained ${names(mine)}${mine.length !== got.length ? ' (not all in lunch)' : ''}; yesterday's lunch is ${names(lunch)}`)
  const y = changed(yb, after?.yesterday)
  rule('yesterday unchanged', !y.gone.length && !y.extra.length, `step 3: yesterday changed: gained ${names(y.extra)}, lost ${names(y.gone)} (a move, not a copy?)`)
  return { problems, facts: { checks, entries: got.map(entryFacts) }, info: { seeded: !!ui.seeded } }
}

/** J5, a barcode looked up offline, on the ux profile. `run`: { before, after, ui: {} }. */
export function checkJ5(run) {
  const { problems, checks, rule } = rules('J5')
  const P = J5_TYPED.PRODUCT
  const mine = added(run.before, run.after)
  const p = mine.filter(e => matches(e, P.pattern))
  rule('product logged once', p.length === 1 && mine.length === 1, `step 3: the lookup saved ${names(mine)}, not one /${P.pattern}/ entry`)
  const e = p[0]
  rule('product in its meal', e?.meal === P.meal, `step 3: the product went to ${e?.meal ?? 'nothing'}, not ${P.meal}`)
  rule('product at the grams typed', e?.amount === P.grams && WEIGHED.has(String(e?.unit)), `step 3: the product saved as ${e ? `${e.amount} ${e.unit}` : 'nothing'}, typed ${P.grams} g`)
  const off = Object.keys(P.per100).filter(k => !near(e?.per100?.[k], P.per100[k], 0.01))
  rule('per 100 g as cached', e && !off.length, `step 2: the product's per-100 g ${off.join(', ')} are not the cached product's (${JSON.stringify(e?.per100 ?? null)})`)
  for (const x of mine) for (const m of mathProblems(x)) rule(`${x.name} counts per 100 × amount`, false, m)
  return { problems, facts: { checks, entries: mine.map(entryFacts) }, info: {} }
}

/**
 * J6, the weekly check-in accepted by hand, on the owner profile. `run`: { before, after, ui: {
 * due, opened, proposed (the check-in's proposed target as the app computed it on opening),
 * shownTarget (the target field's value on the screen) } }.
 */
export function checkJ6(run) {
  const { problems, checks, rule } = rules('J6')
  const { before, after, ui = {} } = run
  const a = after?.adaptive
  rule('check-in due', ui.due, 'step 1: no check-in was due after setting the check-in day')
  rule('check-in screen opened', ui.opened, 'step 2: the check-in did not open from Home\'s card')
  rule('shown target is the proposed one', near(ui.shownTarget, ui.proposed, 1), `step 2: the screen shows ${ui.shownTarget}, the check-in proposes ${ui.proposed}`)
  const last = a?.lastCheckIn
  rule('accepted target is the shown one', last?.daysAgo === 0 && near(last.acceptedKcal, ui.shownTarget, 1), `step 3: the last check-in is ${last ? `${last.acceptedKcal} kcal, ${last.daysAgo} days ago` : 'none'}, the screen showed ${ui.shownTarget}`)
  const s = after?.shown
  const goal = last ? last.acceptedKcal + (a.goalOffsetKcal || 0) + (a.goalActivityKcal || 0) : null
  rule('Home shows the new target', s && near(s.goalKcal, goal, 1), `step 4: Home's goal is ${s?.goalKcal ?? 'not shown'}, the accepted target with today's weekday offset and activity is ${goal}`)
  rule('history gains one row', a?.checkIns === (before?.adaptive?.checkIns ?? NaN) + 1, `step 3: the check-in history went from ${before?.adaptive?.checkIns} to ${a?.checkIns} rows, not one more`)
  // the numbers move with the calendar, so they are not facts
  return { problems, facts: { checks }, info: { proposed: ui.proposed, shownTarget: ui.shownTarget, lastCheckIn: last ?? null, shown: s ?? null } }
}

export const CHECKS = { J1: checkJ1, J2: checkJ2, J3: checkJ3, J4: checkJ4, J5: checkJ5, J6: checkJ6 }

/** Differences between two fact trees, one line per value: "path: before → after". */
export function diffFacts(a, b, path = '') {
  const show = v => (v === undefined ? '–' : JSON.stringify(v))
  if (a === b) return []
  const obj = v => v && typeof v === 'object'
  if (!obj(a) || !obj(b) || Array.isArray(a) !== Array.isArray(b)) return [`${path || '(root)'}: ${show(a)} → ${show(b)}`]
  const keys = [...new Set([...Object.keys(a), ...Object.keys(b)])]
  return keys.flatMap(k => diffFacts(a[k], b[k], path ? path + '.' + k : k))
}

/** Facts that say nothing (null, false, an empty list or object), by path: a step that quietly found nothing. */
export function hollow(v, path = '') {
  if (v == null || v === false) return [path || '(root)']
  if (Array.isArray(v)) return v.length ? v.flatMap((x, i) => hollow(x, `${path}[${i}]`)) : [path || '(root)']
  if (typeof v === 'object') {
    const keys = Object.keys(v)
    return keys.length ? keys.flatMap(k => hollow(v[k], path ? path + '.' + k : k)) : [path || '(root)']
  }
  return []
}

/** The report on one journey: its problems, its hollow facts, then its differences from the baseline. 0 when clean. */
export function report(J, result, base) {
  // a failed check is already a problem; its false outcome is not counted twice
  const empty = hollow(result.facts).filter(p => !p.startsWith('checks.'))
  const fails = [...result.problems, ...empty.map(p => `${J}: hollow fact ${p}: the step found nothing`)]
  const diffs = base ? diffFacts(base, result.facts) : []
  const lines = [...fails.map(p => '  FAIL ' + p), ...diffs.map(d => '  DIFF ' + d)]
  const head = lines.length
    ? `${J}: ${fails.length} failed check${fails.length === 1 ? '' : 's'}, ${diffs.length} difference${diffs.length === 1 ? '' : 's'} from the baseline`
    : `${J}: every check passed${base ? ', no difference from the baseline' : ''}`
  return { code: lines.length ? 1 : 0, text: [head, ...lines].join('\n') }
}
