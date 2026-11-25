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
export const SCRIPTED = ['J1', 'J2']
export const PROFILE_OF = { J1: 'ux', J2: 'owner' }

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

export const CHECKS = { J1: checkJ1, J2: checkJ2 }

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
