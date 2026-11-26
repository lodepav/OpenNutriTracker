#!/usr/bin/env node
// The "Check" mode of the journeys (fork/ux/JOURNEYS.md): taps through a journey's steps on the
// running app the way a person would, over flutter_driver's extension on the Dart VM service, then
// reads what was saved through the journey entry point's `state` command and checks it
// (journey-lib.mjs). The app must be the journey build (lib/fork/dev/main_journey.dart).
//
//   node fork/tools/journey-check.mjs run <J1..J6> <out.json> [--base <baseline.json>]
//   node fork/tools/journey-check.mjs network              # exit 2 naming any path off the device
//   node fork/tools/journey-check.mjs request '<json>'      # one requestData command (seedDemo, ...)
//   node fork/tools/journey-check.mjs import <app path>    # Settings → Data → Import history
//
// journey-check.sh runs it: it restores the journey's profile first and the app's own data after.
// Exit 0 when every check passed and nothing differs from the baseline, 1 when not, 2 when it could
// not run. Node 22 or later: its global WebSocket, no npm packages.
import { execFileSync } from 'node:child_process'
import { createHash } from 'node:crypto'
import { readFileSync, writeFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { CHECKS, J1_TYPED, J2_TYPED, J3_TYPED, J4_TYPED, J5_TYPED, report } from './journey-lib.mjs'

const ADB = process.env.ADB || homedir() + '/Android/Sdk/platform-tools/adb'
const APP_ID = process.env.APP_ID || 'io.github.lodepav.openbite.develop'
const APK = process.env.JOURNEY_APK || 'build/app/outputs/flutter-apk/app-develop-debug.apk'
const sleep = ms => new Promise(ok => setTimeout(ok, ms))
const until = async (ok, tries = 16, ms = 500) => { for (let n = 0; n < tries; n++) { if (await ok()) return true; await sleep(ms) } return false }
const adb = (...args) => execFileSync(ADB, args, { encoding: 'utf8', timeout: 20000 }).trim()
const fail = msg => { console.error('journey-check: ' + msg); process.exit(2) }
const withTimeout = (p, ms, what) => Promise.race([p, sleep(ms).then(() => { throw new Error(`${what}: no answer in ${ms / 1000} s`) })])

// ---- the VM service --------------------------------------------------------------------------

let ws, isolateId, forwarded
let nextId = 1
const waiting = new Map()

function rpc(method, params = {}, ms = 15000) {
  const id = String(nextId++)
  ws.send(JSON.stringify({ jsonrpc: '2.0', id, method, params }))
  return withTimeout(new Promise((ok, no) => waiting.set(id, { ok, no })), ms, method).finally(() => waiting.delete(id))
}

/** The build on the device is the one built here, the app runs, and its driver extension answers. */
async function open() {
  let local
  try { local = createHash('sha1').update(readFileSync(APK)).digest('hex') } catch { fail(`no APK at ${APK}: run with --build`) }
  const path = adb('shell', 'pm', 'path', APP_ID).split('\n').find(l => l.startsWith('package:'))?.slice(8)
  if (!path) fail(`${APP_ID} is not installed`)
  const installed = adb('shell', 'sha1sum', path).split(/\s+/)[0]
  if (installed !== local) fail(`the installed app is not ${APK} (sha1 ${installed} vs ${local}): run with --build`)

  let url
  await until(() => {
    const pid = adb('shell', 'pidof', APP_ID).split(/\s+/)[0]
    if (!pid) return false
    const log = adb('logcat', '-d', `--pid=${pid}`)
    url = [...log.matchAll(/Dart VM service is listening on http:\/\/127\.0\.0\.1:(\d+)\/([^/\s]+)\//g)].at(-1)
    return !!url
  }, 40)
  if (!url) fail('no Dart VM service in the log: is the app the debug journey build, and running?')
  const port = adb('forward', 'tcp:0', 'tcp:' + url[1])
  forwarded = 'tcp:' + port
  ws = new WebSocket(`ws://127.0.0.1:${port}/${url[2]}/ws`)
  await withTimeout(new Promise((ok, no) => { ws.onopen = ok; ws.onerror = () => no(new Error('the VM service socket would not open')) }), 10000, 'the VM service')
  ws.onmessage = ev => {
    const m = JSON.parse(ev.data)
    const w = waiting.get(m.id)
    if (!w) return
    if (m.error) w.no(new Error(`${m.error.message}: ${JSON.stringify(m.error.data ?? '')}`))
    else w.ok(m.result)
  }
  const found = await until(async () => {
    for (const ref of (await rpc('getVM')).isolates) {
      const iso = await rpc('getIsolate', { isolateId: ref.id })
      if (iso.extensionRPCs?.includes('ext.flutter.driver')) { isolateId = ref.id; return true }
    }
    return false
  }, 40)
  if (!found) fail('the app has no flutter_driver extension: it is not built from lib/fork/dev/main_journey.dart')
  // a looping spinner would hold every command until it stops
  await driver({ command: 'set_frame_sync', enabled: 'false' })
  const hi = await request({ cmd: 'hello' })
  if (!hi.journey) fail('the journey handler did not answer')
}

async function close() {
  try { ws?.close() } catch {}
  if (forwarded) try { adb('forward', '--remove', forwarded) } catch {}
}

/** One flutter_driver command; a driver error throws. Every command has a timeout, or waitFor waits forever. */
async function driver(params, ms = 4000) {
  const r = await rpc('ext.flutter.driver', { isolateId, timeout: String(ms), ...params }, ms + 5000)
  if (r.isError) throw new Error(`${params.command}: ${typeof r.response === 'string' ? r.response.split('\n')[0] : JSON.stringify(r.response)}`)
  return r.response
}

/** A requestData command to journeyHandler (lib/fork/dev/journey_handler.dart). */
async function request(cmd) {
  const r = JSON.parse((await driver({ command: 'request_data', message: JSON.stringify(cmd) }, 20000)).message)
  if (!r.ok) throw new Error(`${cmd.cmd}: ${r.error}`)
  return r
}

// ---- finding and tapping ---------------------------------------------------------------------

// A target: { id } a Semantics identifier, { key } a ValueKey<String>, { text } or { tooltip } a
// pattern, { back: true } the app bar's back button. Journey finders match on screen only.
const finder = t =>
  t.key ? { finderType: 'ByValueKey', keyValueString: t.key, keyValueType: 'String' }
  : t.back ? { finderType: 'PageBack' }
  : { finderType: 'Journey', by: t.id ? 'id' : t.text ? 'text' : 'tooltip', value: t.id ?? t.text ?? t.tooltip, index: String(t.index ?? 0) }
const what = t => t.key ? `key ${t.key}` : t.back ? 'the back button' : t.id ? `id ${t.id}` : t.text ? `text /${t.text}/` : `tooltip /${t.tooltip}/`

let lastError = ''
/** Retries `step` for a few seconds before failing with what it last said. */
async function must(name, step, tries = 12) {
  const ok = await until(async () => { try { await step(); return true } catch (e) { lastError = e.message; return false } }, tries, 500)
  if (!ok) throw new Error(`${name}: ${lastError}`)
}
const seen = async t => { try { await driver({ command: 'waitFor', ...finder(t) }, 600); return true } catch { return false } }
// frame sync is off, so a tap returns before the app redraws: a short settle after each
const tap = async (t, name = 'tap ' + what(t)) => {
  // wait for it, then one tap: a retry after a late answer would tap twice
  if (!(await until(() => seen(t), 12, 500))) throw new Error(`${name}: ${what(t)} is not on the page`)
  await driver({ command: 'tap', ...finder(t) }, 3000)
  await sleep(400)
}
/** An id the app sets as a Semantics identifier on one screen and as a ValueKey on another. */
// Finds which of the two the page has, then taps once: a tap that landed but answered late must
// not be tapped again (a submit would save twice)
const tapEither = async name => {
  let t
  if (!(await until(async () => (t = (await seen({ id: name })) ? { id: name } : (await seen({ key: name })) ? { key: name } : null), 12, 500))) {
    throw new Error(`tap ${name}: neither id nor key ${name} is on the page`)
  }
  await driver({ command: 'tap', ...finder(t) }, 3000)
  await sleep(400)
}
/** Types into the field `t`: a tap focuses it, enter_text replaces its whole value. */
async function type(t, text) {
  await tap(t)
  await must(`type "${text}" into ${what(t)}`, () => driver({ command: 'enter_text', text: String(text) }))
}
/** Scrolls the page's list (or with `sideways` the first row of chips) until `t` is on screen. */
async function reveal(t, sideways = false) {
  if (await seen(t)) return
  // a widget built out of view (a chip past the row's edge) scrolls in by itself
  await driver({ command: 'scrollIntoView', ...finder(t), any: '1', alignment: '0.5' }, 1500).catch(() => {})
  for (let n = 0; n < 12; n++) {
    if (await seen(t)) return
    const move = sideways ? { value: 'horizontal', dx: '-250', dy: '0' } : { value: '', dx: '0', dy: '-350' }
    await driver({ command: 'scroll', finderType: 'Journey', by: 'scrollable', index: '0', duration: '300000', frequency: '60', ...move }).catch(() => {})
    await sleep(300)
  }
  throw new Error(`${what(t)} is not on the page after scrolling`)
}
/** Back to Home: the back button until the tab bar shows, then the Home tab. */
async function home() {
  for (let n = 0; n < 5 && !(await seen({ id: 'nav-home' })); n++) await driver({ command: 'tap', ...finder({ back: true }) }, 1000).catch(() => {})
  await tap({ id: 'nav-home' })
}
/** Sets a meal chip (a menu of Breakfast, Lunch, Dinner, Snack) to `meal`. */
async function pickMeal(chip, meal) {
  const label = meal[0].toUpperCase() + meal.slice(1)
  await tapEither(chip)
  await tap({ text: `^${label}$`, index: 0 }, `choose ${label}`)
}

// ---- the steps -------------------------------------------------------------------------------

const today = () => adb('shell', 'date', '+%Y-%m-%d')
const state = () => request({ cmd: 'state', date: today() })
const stateOn = date => request({ cmd: 'state', date })
/** The calendar day `n` days from `day` (YYYY-MM-DD). */
const shiftDay = (day, n) => { const t = new Date(day + 'T12:00:00Z'); t.setUTCDate(t.getUTCDate() + n); return t.toISOString().slice(0, 10) }
// journeys whose checks read yesterday too
const WITH_YESTERDAY = new Set(['J3', 'J4'])
const snap = async J => {
  const s = await state()
  if (WITH_YESTERDAY.has(J)) s.yesterday = await stateOn(shiftDay(today(), -1))
  return s
}
const label = meal => meal[0].toUpperCase() + meal.slice(1)
const GO_TODAY = { tooltip: '^Go to today$' }

/** Home → + → `meal` → search: the Add food screen with the bundled foods' tab chosen. */
async function searchFoods(meal, query) {
  // the add sheet can still be animating from the last step and swallow a tap: open it again
  for (let n = 0; ; n++) {
    await home()
    await tapEither('fab-add-item')
    await tapEither('add-item-' + meal)
    await tapEither('add-item-search')
    if (await until(() => seen({ id: 'meal-search-field' }), 6)) break
    if (n === 2) throw new Error(`the search for ${meal} did not open`)
  }
  await type({ id: 'meal-search-field' }, query)
  // "All" would ask Open Food Facts too; the journeys use the bundled table only
  await reveal({ text: '^Food$' }, true)
  await tap({ text: '^Food$' }, 'choose the Food source')
}

/** The food row matching `pattern` (else `loose`) on the Add food screen, opened to its page; grams typed; added. */
async function addWeighed(food, grams) {
  await searchFoods(food.meal, food.query)
  const row = (await until(() => seen({ text: food.pattern }), 10)) ? { text: food.pattern } : { text: food.loose }
  await tap(row, `open ${food.pattern}`)
  await tap({ text: '^Grams$' }, 'choose grams')
  await type({ key: 'amount-field' }, grams)
  await tapEither('meal-detail-add')
}

/** Home → Diary → one swipe to the right: the Diary steps back a day (S176), and offers "Go to today". */
async function diaryYesterday() {
  await home()
  await tap({ id: 'nav-diary' })
  if (await seen(GO_TODAY)) throw new Error('the Diary was not on today')
  // one swipe, never retried: a second would step another day back
  // a real touch swipe, left to right low on the list: the driver's synthetic scroll never reached
  // the Diary's drag handler
  const [w, h] = adb('shell', 'wm', 'size').match(/(\d+)x(\d+)\s*$/).slice(1).map(Number)
  adb('shell', 'input', 'swipe', String(Math.round(w * 0.15)), String(Math.round(h * 0.75)), String(Math.round(w * 0.85)), String(Math.round(h * 0.75)), '200')
  await sleep(400)
  if (!(await until(() => seen(GO_TODAY), 8))) throw new Error('the swipe did not step the Diary back a day')
}

/** On the day the Diary shows: the meal's +, the Food source, the row, grams typed, Add. */
async function addOnShownDay(food) {
  const plus = { tooltip: `^Add to ${label(food.meal)}$` }
  await reveal(plus)
  await tap(plus, `add to ${food.meal} on the day shown`)
  await type({ id: 'meal-search-field' }, food.query)
  await reveal({ text: '^Food$' }, true)
  await tap({ text: '^Food$' }, 'choose the Food source')
  const row = (await until(() => seen({ text: food.pattern }), 10)) ? { text: food.pattern } : { text: food.loose }
  await tap(row, `open ${food.pattern}`)
  await tap({ text: '^Grams$' }, 'choose grams')
  await type({ key: 'amount-field' }, food.grams)
  await tapEither('meal-detail-add')
}

/** From wherever the add left the app, the Diary again, still on the day before. */
async function backToDiaryYesterday() {
  if (await until(() => seen(GO_TODAY), 4)) return
  // the app came back to the Diary on today: a day back again
  await diaryYesterday()
}
/** Today in the Diary: Go to today when it is on another day; an add or a copy may have put it there already. */
async function diaryToday() {
  if (await seen(GO_TODAY)) await tap(GO_TODAY)
  if (!(await until(async () => !(await seen(GO_TODAY)), 8))) throw new Error('the Diary did not come back to today')
}

async function J1(ui) {
  const T = J1_TYPED
  // 1. breakfast by search, in grams
  await addWeighed(T.BREAKFAST, T.BREAKFAST.grams)
  ui.breakfastAdded = true
  // 2-3. a drink with the row's +, Undo once, then add it again
  await searchFoods(T.DRINK.meal, T.DRINK.query)
  const plus = { tooltip: `^Add ${T.DRINK.pattern.slice(1)}` }
  const count = s => s.entries.filter(e => new RegExp(T.DRINK.loose).test(e.name)).length
  const before = count(await state())
  await tap(plus, 'add the drink')
  await must('the drink is saved', async () => { if (count(await state()) !== before + 1) throw new Error('not saved') })
  ui.undoShown = await until(() => seen({ text: '^Undo$' }), 8)
  if (ui.undoShown) {
    await tap({ text: '^Undo$' })
    ui.undoTookBack = await until(async () => count(await state()) === before, 10)
  }
  await tap(plus, 'add the drink again')
  await must('the drink is saved again', async () => { if (count(await state()) !== before + 1) throw new Error('not saved') })
  // 4. the breakfast's amount edited in the diary (D54)
  await home()
  await tap({ id: 'nav-diary' })
  await reveal({ text: T.BREAKFAST.pattern })
  await tap({ text: T.BREAKFAST.pattern }, 'select the oats')
  await tapEither('fork-selection-more')
  await tapEither('fork-selection-edit')
  ui.editOpened = true
  await tap({ text: '^Grams$' }, 'edit in grams')
  await type({ key: 'amount-field' }, T.BREAKFAST.edited)
  await tap({ text: '^OK$' }, 'save the edit')
  await home()
}

async function J2(ui) {
  const T = J2_TYPED
  // 1. the planned breakfast, from the add sheet's recent foods
  await home()
  await tapEither('fab-add-item')
  await tapEither('add-item-breakfast')
  await tap({ id: 'meal-item-add', index: 0 }, 'add the first recent breakfast')
  ui.breakfastAdded = true
  // 2. the protein shake, from the recent foods
  await home()
  await tapEither('fab-add-item')
  await tapEither('add-item-' + T.SHAKE.meal)
  await tapEither('add-item-search')
  await type({ id: 'meal-search-field' }, T.SHAKE.query)
  await tap({ text: '^Recently$' }, 'choose Recently')
  await reveal({ text: T.SHAKE.loose })
  await tap({ tooltip: `^Add .*(${T.SHAKE.loose})` }, 'add the shake')
  ui.shakeAdded = true
  // 3. lunch: a photo (the fake camera) with a note, read by the fake AI
  await home()
  await tapEither('home-quick-photo')
  await tapEither('bulk-add-photo-camera')
  await pickMeal('bulk-add-meal', 'lunch')
  await type({ id: 'bulk-add-input' }, T.LUNCH_NOTE)
  await tapEither('bulk-add-parse')
  await tapEither('bulk-add-submit')
  ui.lunchLogged = true
  // 4. dinner searched: chicken, a side, a salad
  for (const d of T.DINNER) await addWeighed(d, d.grams)
  // 5. today's weigh-in, from the fake Health Connect import that runs at launch
  await request({ cmd: 'weightImportNow' })
  await must('a weigh-in today', async () => { if (!(await state()).weight) throw new Error('none yet') }, 30)
  // 6. the check-in screen, from Settings
  await home()
  await tap({ id: 'nav-you' })
  await reveal({ id: 'profile-settings' })
  await tapEither('profile-settings')
  await tapEither('settings-section-goals')
  await reveal({ text: '^Trend and calorie target' })
  await tap({ text: '^Trend and calorie target' })
  await reveal({ text: '^Expenditure and check-ins' })
  await tap({ text: '^Expenditure and check-ins' })
  await reveal({ text: '^Open check-in$' })
  await tap({ text: '^Open check-in$' })
  ui.checkInOpened = await until(() => seen({ key: 'check-in-target' }), 16)
}

async function J3(ui) {
  const T = J3_TYPED.SNACK
  const y = shiftDay(today(), -1)
  const count = async () => (await stateOn(y)).entries.filter(e => new RegExp(T.loose).test(e.name)).length
  const before = await count()
  // 1. the Diary, a day back
  await diaryYesterday()
  // 2. a snack by search, in grams, from the section's +
  await addOnShownDay(T)
  await must('the snack is saved yesterday', async () => { if ((await count()) !== before + 1) throw new Error('not saved') })
  // 3. back to today
  await diaryToday()
  ui.backToToday = true
  await home()
}

async function J4(ui) {
  const y = shiftDay(today(), -1)
  const lunchOf = s => s.entries.filter(e => e.meal === 'lunch')
  // 1. the Diary, a day back
  await diaryYesterday()
  // a profile made more than a day ago holds no lunch yesterday: one is logged there first, as J3 logs
  if (!lunchOf(await stateOn(y)).length) {
    await addOnShownDay(J4_TYPED.SEED)
    await must('the lunch is saved yesterday', async () => { if (!lunchOf(await stateOn(y)).length) throw new Error('not saved') })
    ui.seeded = true
    await backToDiaryYesterday()
  }
  ui.yesterdayBefore = await stateOn(y)
  const want = lunchOf(await state()).length + lunchOf(ui.yesterdayBefore).length
  // 2. a tap on the meal's header selects all of it (D30)
  await reveal({ text: '^Lunch$' })
  await tap({ text: '^Lunch$' }, "select yesterday's lunch")
  // 3. the bar's Copy, to today, at the same times, into lunch (the sheet's defaults for one meal)
  await tap({ key: 'fork-selection-copy' })
  await tap({ key: 'fork-where-day0' }, 'copy to today')
  await tap({ key: 'fork-where-done' }, 'copy')
  await must("the copy is in today's lunch", async () => { if (lunchOf(await state()).length !== want) throw new Error('not copied') })
  await diaryToday()
  await home()
}

async function J5(ui) {
  const P = J5_TYPED.PRODUCT
  // 1. the product as an earlier scan made online left it in the scan cache
  await request({ cmd: 'cacheProduct', code: P.code, name: P.name, per100: P.per100 })
  // 2. the code typed into search and submitted: a valid barcode goes to the scanner's lookup,
  // which reads the cache before the network, with no camera
  await home()
  await tapEither('fab-add-item')
  await tapEither('add-item-' + P.meal)
  await tapEither('add-item-search')
  await type({ id: 'meal-search-field' }, P.code)
  await driver({ command: 'send_text_input_action', action: 'search' })
  if (!(await until(() => seen({ key: 'amount-field' }), 16))) throw new Error('the lookup opened no product (is it in the scan cache?)')
  ui.productOpened = true
  // 3. grams typed, Add
  if (await seen({ text: '^Grams$' })) await tap({ text: '^Grams$' }, 'choose grams')
  await type({ key: 'amount-field' }, P.grams)
  await tapEither('meal-detail-add')
  await must('the product is saved', async () => { if (!(await state()).entries.some(e => new RegExp(P.pattern).test(e.name))) throw new Error('not saved') })
  await home()
}

async function J6(ui) {
  // 1. the check-in made due: the check-in day set to today, unless one is due already
  ui.due = (await request({ cmd: 'checkInDue' })).due
  const rows = (await state()).adaptive?.checkIns
  // 2. Home's card for the due check-in (S13) opens it
  await home()
  const card = { text: '^(Your first target|Weekly check-in|Your goal changed|Your target settings changed)$' }
  await reveal(card)
  ui.proposed = (await state()).adaptive?.proposedTargetKcal
  await tap(card, "open the check-in from Home's card")
  ui.opened = await until(() => seen({ key: 'check-in-target' }), 16)
  if (!ui.opened) throw new Error('the check-in screen did not open')
  // shortcut: read as kcal; a profile showing kJ would differ by the unit, remake it in kcal
  ui.shownTarget = Number((await driver({ command: 'get_text', finderType: 'ByValueKey', keyValueString: 'check-in-target', keyValueType: 'String' })).text)
  // 3. accepted by hand, at the target shown
  await reveal({ key: 'check-in-accept' })
  await tap({ key: 'check-in-accept' }, 'accept the check-in')
  await must('the check-in is saved', async () => { if ((await state()).adaptive?.checkIns !== rows + 1) throw new Error('no new row') }, 20)
  // 4. Home with the new target
  await home()
}

const JOURNEYS = { J1, J2, J3, J4, J5, J6 }

/** Refuses a run while any path off the device is on (exit 2, naming it). */
async function offline() {
  const n = await request({ cmd: 'network' })
  if (n.on.length) fail('a path off the device is on: ' + n.on.join('; ') + '. Turn it off in the profile first.')
  return n
}

async function main() {
  const [cmd, ...args] = process.argv.slice(2)
  if (cmd === 'run') {
    const [J, out] = args
    const base = args.includes('--base') ? JSON.parse(readFileSync(args[args.indexOf('--base') + 1], 'utf8')) : null
    if (!JOURNEYS[J] || !out) fail('usage: run <J1..J6> <out.json> [--base <baseline.json>]')
    let result
    try {
      await open()
      const net = await offline()
      const before = await snap(J)
      const ui = {}
      try { await JOURNEYS[J](ui) } catch (e) {
        // the error first: clean-up below may hang on a stuck app
        console.error(`journey-check: ${J}: ${e.message}`)
        ui.error = e.message
      }
      const after = await snap(J)
      const checked = CHECKS[J]({ before, after, ui })
      if (ui.error) checked.problems.unshift(`${J}: the journey stopped: ${ui.error}`)
      result = { journey: J, ...checked, info: { ...checked.info, blocked: (await request({ cmd: 'network' })).blocked, sourcesOn: net.foodSourceToggles } }
    } catch (e) {
      console.error(`journey-check: ${J}: ${e.message}`)
      await withTimeout(close(), 3000, 'clean-up').catch(() => {})
      process.exit(2)
    }
    await withTimeout(close(), 3000, 'clean-up').catch(() => {})
    writeFileSync(out, JSON.stringify(result, null, 2))
    const r = report(J, result, base)
    console.log(r.text)
    process.exit(r.code)
  }
  try {
    await open()
    if (cmd === 'network') {
      const n = await offline()
      console.log('journey-check: nothing off the device is on' + (n.blocked.length ? `; refused so far: ${n.blocked.join(', ')}` : ''))
    } else if (cmd === 'request') {
      console.log(JSON.stringify(await request(JSON.parse(args[0]))))
    } else if (cmd === 'import') {
      await request({ cmd: 'importMacroFactor', path: args[0] })
      await tap({ id: 'nav-you' })
      await reveal({ id: 'profile-settings' })
      await tapEither('profile-settings')
      await tapEither('settings-section-data')
      await reveal({ key: 'fork-history-import' })
      await tap({ key: 'fork-history-import' })
      await tap({ key: 'history-import-choose' })
      await tap({ key: 'history-import' })
      await must('the import finishes', () => driver({ command: 'waitFor', ...finder({ text: '^Imported' }) }, 2000), 60)
      console.log('journey-check: imported ' + args[0])
      // the owner's target is the adaptive one, set where the owner would set it
      await home()
      await tap({ id: 'nav-you' })
      await reveal({ id: 'profile-settings' })
      await tapEither('profile-settings')
      await tapEither('settings-section-goals')
      await reveal({ text: '^Trend and calorie target' })
      await tap({ text: '^Trend and calorie target' })
      await reveal({ text: '^Adaptive$' })
      await tap({ text: '^Adaptive$' })
      console.log('journey-check: the calorie target is adaptive')
    } else fail('usage: run <J> <out> [--base <file>] | network | request <json> | import <path>')
  } catch (e) {
    console.error(`journey-check: ${cmd}: ${e.message}`)
    await withTimeout(close(), 3000, 'clean-up').catch(() => {})
    process.exit(2)
  }
  await withTimeout(close(), 3000, 'clean-up').catch(() => {})
  process.exit(0)
}

await main()
