// node --test test/home.test.mjs
import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { Home, homeRequest } from '../lib/home.js'
import { noteText } from '../lib/notes.js'
import { createTools, defineToolLocal } from '../lib/tools.js'

const PLACES = {
  hangzhou: { name: '杭州·西湖', short: '杭州', souvenir: '西湖龙井', photos: ['h1.png', 'h2.png'] },
  xuexiang: { name: '中国雪乡', short: '雪乡', souvenir: '雪屋小摆件', photos: ['x1.png'] },
}
const quiet = { info: () => {}, warn: () => {} }

function setup(extra = {}) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'living-dock-home-'))
  const clock = { t: Date.UTC(2026, 10, 16, 6, 0) / 1000 }
  const sent = []
  const make = () => new Home({ dataDir: path.join(dir, 'data'), notesDir: path.join(dir, 'notes'), places: PLACES, logger: quiet,
    now: () => clock.t, random: () => 0, onChange: (v) => sent.push(v), ...extra })
  return { dir, clock, sent, make, home: make(), done: () => fs.rmSync(dir, { recursive: true, force: true }) }
}

test('she goes in, chooses something, travels; the postcard comes halfway and she comes home', () => {
  const { clock, sent, make, home, done } = setup()
  assert.equal(home.fresh, true)
  assert.equal(home.handle({ op: 'do', activity: '荡秋千' }), 'outside')
  assert.equal(home.handle({ op: 'enter' }), '')
  assert.equal(home.handle({ op: 'enter' }), 'already_inside')
  assert.equal(home.handle({ op: 'do', activity: '荡秋千' }), 'unknown_activity')   // no window has told what there is yet
  home.world({ activities: ['荡秋千', '钓鱼'], wall_slots: 2 })
  assert.equal(home.handle({ op: 'do', activity: '秋千', minutes: 15, reason: '吹风' }), '')
  assert.deepEqual(home.report({ arrived: false }).doing, { name: '荡秋千', reason: '吹风', minutes_left: 15, arrived: false })
  assert.equal(home.handle({ op: 'travel', place: 'beijing' }), 'unknown_place')
  assert.equal(home.handle({ op: 'travel', place: 'hangzhou', message: '荷花开了' }), '')
  assert.equal(home.handle({ op: 'enter' }), 'away')
  const trip = home.data.trips[0]
  assert.equal(trip.back - trip.left, 8 * 3600)                     // random() = 0: the shortest trip
  assert.equal(home.data.inside, false)
  assert.equal(home.data.chosen, null)
  assert.equal(sent.at(-1).trips.length, 1)                          // the windows were told
  clock.t += 4 * 3600
  home.tick()
  assert.equal(trip.postcard, true)
  assert.equal(home.data.unseen, 1)
  assert.equal(home.handle({ op: 'postcard', text: '晚了' }), 'postcard_sent')
  clock.t += 4 * 3600
  home.tick()
  assert.equal(trip.home, true)
  assert.equal(trip.photo, 'h1.png')
  assert.equal(trip.souvenir, '西湖龙井')
  assert.equal(home.isInside(), true)
  const r = home.report()
  assert.equal(r.trips, 1)
  assert.deepEqual(r.wall, ['11月16日·杭州'])
  assert.deepEqual(r.shelf, ['西湖龙井（11月16日·杭州）'])
  assert.deepEqual(r.places.map((p) => p.id), ['hangzhou', 'xuexiang'])
  // kept on disk: a new plugin start has the same record
  const again = make()
  assert.equal(again.fresh, true)                                     // trips of its own do not stop a handover
  assert.equal(again.data.trips[0].photo, 'h1.png')
  // the second trip there brings the other photo
  home.handle({ op: 'travel', place: 'hangzhou' })
  clock.t += 9 * 3600
  home.tick()
  assert.equal(home.data.trips[1].photo, 'h2.png')
  done()
})

test('home early brings only the one she chose', () => {
  const { home, done } = setup()
  home.handle({ op: 'travel', place: 'xuexiang' })
  assert.equal(home.handle({ op: 'come_back', keep: 'souvenir' }), '')
  const t = home.data.trips[0]
  assert.equal(t.home, true)
  assert.equal(t.photo, '')
  assert.equal(t.souvenir, '雪屋小摆件')
  assert.equal(home.handle({ op: 'come_back' }), 'not_away')
  done()
})

test('the magazine is news once; the album being looked at clears the count', () => {
  const { home, done } = setup()
  home.user({ op: 'magazine', place: 'xuexiang' })
  assert.deepEqual(home.report().magazine, { id: 'xuexiang', name: '雪乡', new: true })
  assert.equal(home.report().magazine.new, false)
  home.user({ op: 'magazine', place: 'nowhere' })
  assert.equal(home.data.magazine, 'xuexiang')
  home.handle({ op: 'travel', place: 'xuexiang' })
  assert.equal(home.data.magazine, '')                              // she took it with her
  home.data.unseen = 2
  home.user({ op: 'seen' })
  assert.equal(home.data.unseen, 0)
  done()
})

test('notes: read only inside, five at a time, edited ones again; hers stay on the table a day', () => {
  const { dir, clock, home, done } = setup()
  const notes = path.join(dir, 'notes')
  fs.mkdirSync(notes, { recursive: true })
  for (let i = 1; i <= 6; i++) {
    fs.writeFileSync(path.join(notes, `妈妈_${i}.txt`), `\uFEFF第${i}张\r\n记得\r\n带伞`)
    fs.utimesSync(path.join(notes, `妈妈_${i}.txt`), 1000 + i, 1000 + i)
  }
  fs.writeFileSync(path.join(notes, 'ignore.md'), 'x')
  assert.deepEqual(home.report().notes, [])
  assert.equal(home.report().notes_waiting, 6)
  home.handle({ op: 'enter' })
  const r = home.report()
  assert.equal(r.notes.length, 5)
  assert.deepEqual(r.notes[0], { from: '妈妈', day: r.notes[0].day, text: '第1张记得带伞' })
  assert.equal(r.notes_waiting, 1)
  assert.equal(home.report().notes.length, 1)
  assert.equal(home.view().notes.unread, 0)
  fs.utimesSync(path.join(notes, '妈妈_2.txt'), 5000, 5000)       // edited after she read it
  assert.equal(home.notes.unread().length, 1)
  assert.equal(home.handle({ op: 'note', text: '  ' }), 'empty_note')
  assert.equal(home.handle({ op: 'note', text: '出门啦' }), '')
  const mine = fs.readdirSync(notes).filter((f) => f.startsWith('大肥鱼_'))
  assert.equal(mine.length, 1)
  assert.equal(fs.readFileSync(path.join(notes, mine[0]), 'utf8'), '出门啦')
  assert.equal(home.notes.unread().length, 1)                        // her own note does not count as unread
  home.report()
  assert.deepEqual(home.view().notes, { unread: 0, on_table: true })
  clock.t += 86401
  assert.deepEqual(home.view().notes, { unread: 0, on_table: false })
  done()
})

test('a long note is cut, Latin lines get a space', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'living-dock-note-'))
  fs.writeFileSync(path.join(dir, 'a.txt'), 'see you\nsoon\n' + '鱼'.repeat(400))
  const text = noteText(path.join(dir, 'a.txt'))
  assert.ok(text.startsWith('see you soon 鱼'))
  assert.equal([...text].length, 300 + 2)
  fs.rmSync(dir, { recursive: true, force: true })
})

test('a window hands over its old record once, only while there is none', () => {
  const { home, make, done } = setup()
  const old = { trips: [{ place: 'hangzhou', left: 1, back: 2, postcard_at: 1.5, message: 'hi', postcard: true, home: true, photo: 'h1.png', souvenir: '西湖龙井' }],
    magazine: 'xuexiang', magazine_new: true, unseen: 1, inside: true, notes_read: { 'a.txt': 5 }, note_left: 3, extra: 'dropped' }
  home.world({ activities: ['荡秋千'], wall_slots: 4 })                // a window says what there is before handing over
  assert.equal(make().fresh, true)                                    // even after a restart
  assert.equal(home.seed(old), true)
  assert.equal(home.data.trips.length, 1)
  assert.equal(home.data.extra, undefined)
  assert.equal(home.seed(old), false)
  assert.equal(make().seed(old), false)                               // a record is on disk now
  done()
  // things already happened here (she came in) but no trip yet: the trips still come over, her being in stays
  const later = setup()
  later.home.world({ activities: ['荡秋千'] })
  assert.equal(later.home.handle({ op: 'enter' }), '')
  assert.equal(later.home.seed({ ...old, inside: false, magazine: '' }), true)
  assert.equal(later.home.data.trips.length, 1)
  assert.equal(later.home.data.inside, true)
  assert.equal(later.home.seed({ trips: [] }), false)
  later.done()
  // she already travelled from the plugin before the window handed over: old trips go in by date, a trip
  // still under way in the window's copy is left out, and the one she is on here stays last
  const both = setup()
  both.home.handle({ op: 'travel', place: 'xuexiang' })
  const onTheWay = { place: 'hangzhou', left: 5, back: 9e12, postcard_at: 9e12, postcard: false, home: false }
  assert.equal(both.home.seed({ trips: [...old.trips, onTheWay] }), true)
  assert.deepEqual(both.home.data.trips.map((t) => t.place), ['hangzhou', 'xuexiang'])
  assert.equal(both.home.away().place, 'xuexiang')
  assert.equal(both.home.seed(old), false)
  both.done()
})

test('she changes clothes at the wardrobe, only inside and not while away', () => {
  const { clock, home, done } = setup()
  assert.equal(home.data.outfit, 'maid')                                    // she starts in the maid dress
  assert.equal(home.handle({ op: 'dress', outfit: 'winter' }), 'outside')   // not in the little home
  home.world({ activities: ['荡秋千', '换衣服'] })
  assert.equal(home.handle({ op: 'enter' }), '')
  assert.equal(home.handle({ op: 'dress', outfit: 'winter' }), '')
  assert.equal(home.data.outfit, 'winter')
  assert.deepEqual(home.data.chosen, { name: '换衣服', until: clock.t + 120, reason: '' })
  assert.deepEqual(home.report().doing, { name: '换衣服', reason: '', minutes_left: 2 })
  assert.equal(home.handle({ op: 'dress', outfit: 'winter' }), 'already_wearing')
  assert.equal(home.handle({ op: 'dress', outfit: '燕尾服' }), 'unknown_outfit')
  // the windows get her clothes in Chinese, with the wardrobe's four sets
  const r = home.report()
  assert.equal(r.outfit, '冬装')
  assert.deepEqual(r.outfits, ['女仆裙', '冬装', '夏装', '雨衣'])
  // no wardrobe in this house: the change happens without a 'doing'
  home.world({ activities: ['荡秋千'] })
  assert.equal(home.handle({ op: 'dress', outfit: 'summer' }), '')
  assert.equal(home.data.outfit, 'summer')
  assert.equal(home.data.chosen, null)
  // a change of clothes waits until she comes home
  assert.equal(home.handle({ op: 'travel', place: 'hangzhou' }), '')
  assert.equal(home.handle({ op: 'dress', outfit: 'maid' }), 'away')
  done()
})

test('tools go through the home: no window needed except for the photo', async () => {
  const { home, done } = setup()
  home.world({ activities: ['荡秋千'] })
  const asked = []
  const frames = { request: async (m) => { asked.push(m.op); if (m.op === 'facts') return { facts: { weather: 'snow', at: '秋千' } }; throw new Error('none') } }
  const tools = Object.fromEntries(createTools(homeRequest(home, frames), undefined, PLACES).map((t) => [t.name, defineToolLocal(t)]))
  assert.match((await tools.little_home_enter.execute({})).text, /^你从院门走进了小家。[\s\S]*下雪[\s\S]*你在小家里（秋千）/)
  assert.match((await tools.little_home_travel.execute({ place: '东北雪乡', message: '好冷' })).text, /出门去中国雪乡了/)
  assert.match((await tools.little_home_photo.execute({})).text, /^小家的画面现在没打开/)
  assert.deepEqual(asked, ['facts', 'facts', 'photo'])
  const noWindow = { request: async () => { throw new Error('none') } }
  const t2 = Object.fromEntries(createTools(homeRequest(home, noWindow), undefined, PLACES).map((t) => [t.name, defineToolLocal(t)]))
  const look = (await t2.little_home_look.execute({})).text
  assert.match(look, /^小家这会儿是 \d+:\d\d，秋天。/)                 // no weather without a window
  assert.match(look, /你正在中国雪乡旅行/)
  assert.match(tools.little_home_travel.description ?? createTools(() => {}, undefined, PLACES).find((t) => t.name === 'little_home_travel').description, /杭州 或 雪乡/)
  done()
})
