// The little home's record and rules, kept by the plugin (补充条款四·修订二): whether she is in, her trips,
// postcards, souvenirs, the magazine on the table, what she chose to do, the coffee-table notes. The window and
// the web page only show it (a page nobody looks at stops, the record must not). Only facts are kept, in
// <dataDir>/home.json; the notes folder is the only other place read or written. The rules are the window's
// old ones (scripts/travel.gd): a trip lasts 8–20 hours, the postcard comes halfway, she brings home a photo
// she has not brought before and the souvenir; home early, only the one she chose.
import fs from 'node:fs'
import path from 'node:path'
import { Notes, dayText } from './notes.js'

const HOURS = [8, 20]
const FILE = 'home.json'
// trips: [{place, left, back, postcard_at, message, postcard (arrived), home (back home), photo, souvenir, early?}]
// chosen: what she chose to do {name, until (unix seconds), reason}; activities / wall_slots: told by the window
const EMPTY = () => ({
  trips: [], magazine: '', magazine_new: false, unseen: 0, inside: false, notes_read: {}, note_left: 0,
  chosen: null, activities: [], wall_slots: null, outfit: 'maid',
})
// the clothes she can choose (her own choice, 11-16; the window has a sheet for each)
export const OUTFITS = { maid: '女仆裙', winter: '冬装', summer: '夏装', rain: '雨衣' }
const DRESS = '换衣服'          // the wardrobe in the house, where she changes
const SEASONS = ['winter', 'winter', 'spring', 'spring', 'spring', 'summer', 'summer', 'summer', 'autumn', 'autumn', 'autumn', 'winter']

export class Home {
  /**
   * dataDir: where home.json lives; notesDir: the coffee-table notes folder ('' = none); places: {id: {name,
   * short, souvenir, photos}} she can go to; onChange(view) after every change (the windows show it).
   */
  constructor({ dataDir, notesDir = '', places = {}, tripMinutes = 0, logger = console, onChange = () => {},
    now = () => Date.now() / 1000, random = Math.random }) {
    this.file = path.join(dataDir, FILE)
    this.places = places
    this.tripMinutes = tripMinutes
    this.logger = logger
    this.onChange = onChange
    this.now = now
    this.random = random
    this.data = EMPTY()
    try {
      const saved = JSON.parse(fs.readFileSync(this.file, 'utf8'))
      if (saved && typeof saved === 'object') Object.assign(this.data, saved)
    } catch (error) {
      if (error.code !== 'ENOENT') logger.warn?.(`living-dock: home record unreadable (${error.message}), starting empty`)
    }
    this.notes = new Notes(notesDir, this)
    this.notesSeen = JSON.stringify(this.notes.state())
  }

  /** No window has handed over its old record yet (seed; once per plugin record). */
  get fresh() { return !this.data.seeded }

  away() {
    const last = this.data.trips.at(-1)
    return last && !last.home ? last : null
  }

  isInside() { return Boolean(this.data.inside) && !this.away() }

  canGo(place) { return Boolean(this.places[place]?.photos?.length) }

  /** Saves and tells the windows. */
  changed() {
    try {
      fs.mkdirSync(path.dirname(this.file), { recursive: true })
      fs.writeFileSync(this.file + '.tmp', JSON.stringify(this.data, null, 1))
      fs.renameSync(this.file + '.tmp', this.file)
    } catch (error) {
      this.logger.warn?.(`living-dock: could not save the home record: ${error.message}`)
    }
    const view = this.view()
    this.notesSeen = JSON.stringify(view.notes)
    this.onChange(view)
  }

  /** What the windows show: the record without the notes she has read, plus the notes on the table. */
  view() {
    const { notes_read, activities, wall_slots, ...rest } = this.data
    return { ...rest, notes: this.notes.state() }
  }

  /** Every second: the postcard arriving, her coming home, a note dropped on the table. */
  tick() {
    let changed = false
    const a = this.away()
    const now = this.now()
    if (a && !a.postcard && now >= a.postcard_at) {
      a.postcard = true
      this.data.unseen += 1
      this.logger.info?.(`living-dock: postcard from ${a.place}`)
      changed = true
    }
    if (a && now >= a.back) {
      this.#comeHome(a)
      this.logger.info?.(`living-dock: back from ${a.place}`)
      changed = true
    }
    if (this.data.chosen && now >= this.data.chosen.until) {
      this.data.chosen = null
      changed = true
    }
    this.ticks = (this.ticks ?? 0) + 1
    const notes = this.ticks % 5 === 0 ? JSON.stringify(this.notes.state()) : this.notesSeen   // the folder every 5 s
    if (notes !== this.notesSeen) {
      this.notesSeen = notes
      if (!changed) this.onChange(this.view())
    }
    if (changed) this.changed()
  }

  /**
   * Her own decisions through her DSH tools (supplement 4): nothing here happens unless she calls one.
   * Returns '' when done, else why not (the words are in tools.js).
   */
  handle(msg) {
    const busy = this.away() ? 'away' : ''
    const d = this.data
    switch (msg.op) {
      case 'look':
        return ''
      case 'do': {
        if (busy) return busy
        if (!this.isInside()) return 'outside'
        const name = this.#activity(String(msg.activity ?? ''))
        if (!name) return 'unknown_activity'
        const minutes = Math.min(Math.max(Number(msg.minutes) || 20, 1), 240)
        d.chosen = { name, until: this.now() + minutes * 60, reason: String(msg.reason ?? '').slice(0, 100) }
        break
      }
      case 'enter':
        if (busy) return busy
        if (this.isInside()) return 'already_inside'
        d.inside = true
        break
      case 'leave':
        if (busy) return busy
        if (!this.isInside()) return 'not_inside'
        d.inside = false
        d.chosen = null
        break
      case 'travel': {
        if (busy) return busy
        const place = String(msg.place ?? '')
        if (!this.canGo(place)) return 'unknown_place'
        const now = this.now()
        const length = this.tripMinutes > 0 ? this.tripMinutes * 60
          : (HOURS[0] + this.random() * (HOURS[1] - HOURS[0])) * 3600
        d.trips.push({ place, left: now, back: now + length, postcard_at: now + length * 0.5,
          message: String(msg.message ?? ''), postcard: false, home: false, photo: '', souvenir: '' })
        if (d.magazine === place) d.magazine = ''
        d.inside = false
        d.chosen = null
        break
      }
      case 'come_back': {
        const a = this.away()
        if (!a) return 'not_away'
        a.early = msg.keep === 'souvenir' ? 'souvenir' : 'photo'
        a.back = Math.min(a.back, this.now())
        a.postcard_at = Math.min(a.postcard_at, a.back)
        break
      }
      case 'postcard': {
        const a = this.away()
        if (!a) return 'not_away'
        if (a.postcard) return 'postcard_sent'
        a.message = String(msg.text ?? '')
        break
      }
      case 'note': {
        if (busy) return busy
        if (!this.isInside()) return 'outside'
        const text = String(msg.text ?? '').trim().slice(0, 300)
        if (!text) return 'empty_note'
        if (!this.notes.write(text)) return 'note_failed'
        break
      }
      case 'dress': {
        if (busy) return busy
        if (!this.isInside()) return 'outside'
        const outfit = String(msg.outfit ?? '')
        if (!OUTFITS[outfit]) return 'unknown_outfit'
        if (outfit === (d.outfit || 'maid')) return 'already_wearing'
        d.outfit = outfit
        // she goes to the wardrobe and changes there (the window shows it); what she was doing stops
        d.chosen = d.activities?.includes(DRESS) ? { name: DRESS, until: this.now() + 120, reason: '' } : null
        break
      }
      default:
        return 'unknown_op'
    }
    this.logger.info?.(`living-dock: she chose ${msg.op}`)
    d.started = true
    this.changed()
    if (msg.op === 'come_back') this.tick()          // home right away
    return ''
  }

  /**
   * What she sees when she looks at the little home (facts only; tools.js words them). facts: what only a
   * window knows (weather, where she is standing, whether she got there), when one is open.
   * Telling her about a new magazine or reading her the notes counts as seen.
   */
  report(facts = {}) {
    const d = this.data
    const a = this.away()
    const now = this.now()
    const date = new Date(now * 1000)
    const inside = this.isInside()
    const r = {
      inside, leaving: false,
      hour: facts.hour ?? Math.round((date.getHours() + date.getMinutes() / 60) * 100) / 100,
      season: facts.season ?? SEASONS[date.getMonth()],
      weather: facts.weather ?? null,
      at: inside ? String(facts.at ?? '') : '',
      places: Object.entries(this.places).filter(([id]) => this.canGo(id)).map(([id, p]) => ({ id, name: p.name ?? id })),
      trips: d.trips.filter((t) => t.home).length,
      postcards: this.#withPostcards().length,
      souvenirs: this.#souvenirs().map((p) => this.places[p]?.souvenir ?? p),
      wall: this.#wall(), shelf: this.#shelf(),
      away: null, magazine: null, doing: null, activities: d.activities ?? [],
      outfit: OUTFITS[d.outfit] ?? OUTFITS.maid, outfits: Object.values(OUTFITS),
    }
    if (inside && d.chosen && now < d.chosen.until) {
      r.doing = { name: d.chosen.name, reason: d.chosen.reason, minutes_left: Math.ceil((d.chosen.until - now) / 60) }
      if (typeof facts.arrived === 'boolean') r.doing.arrived = facts.arrived
    }
    if (a) {
      r.away = { place: a.place, name: this.places[a.place]?.name ?? a.place, left: a.left, back: a.back,
        postcard: a.postcard, wrote: Boolean(a.message) }
    }
    let changed = false
    if (d.magazine) {
      r.magazine = { id: d.magazine, name: this.places[d.magazine]?.short ?? d.magazine, new: Boolean(d.magazine_new) }
      changed = Boolean(d.magazine_new)
      d.magazine_new = false
    }
    // notes on the coffee table: read to her only when she is in the little home
    r.notes = inside ? this.notes.take() : []
    r.notes_waiting = this.notes.unread().length
    if (changed || r.notes.length) this.changed()
    return r
  }

  /** The window tells what can be done in the little home and how many postcards the wall holds. */
  world(msg) {
    if (Array.isArray(msg.activities)) this.data.activities = msg.activities.map(String).slice(0, 50)
    if (Number.isInteger(msg.wall_slots)) this.data.wall_slots = msg.wall_slots
    this.changed()
  }

  /** The user, in a window: a travel magazine on the coffee table (or taken away), the album looked at. */
  user(msg) {
    if (msg.op === 'magazine' && (msg.place === '' || this.places[msg.place])) {
      this.data.magazine = msg.place
      this.data.magazine_new = msg.place !== ''
    } else if (msg.op === 'seen') {
      if (!this.data.unseen) return
      this.data.unseen = 0
    } else {
      return
    }
    this.data.started = true
    this.changed()
  }

  /**
   * A window hands over the record it kept itself before the plugin kept it (once per plugin record). Its
   * trips that are over are put in with the ones kept here, by date (the same trip twice is taken once); if
   * things already happened here (she came in, a magazine was put down), those stay as they are and only the
   * trips, the unseen count and the notes she read come over. Only the known fields are taken.
   */
  seed(data) {
    if (!this.fresh || !data || typeof data !== 'object' || !Array.isArray(data.trips) || !data.trips.length) return false
    const num = (v) => (Number.isFinite(Number(v)) ? Number(v) : 0)
    const have = new Set(this.data.trips.map((t) => `${t.place}@${t.left}`))
    const old = data.trips.filter((t) => t && typeof t.place === 'string' && t.home).map((t) => ({
      place: t.place, left: num(t.left), back: num(t.back), postcard_at: num(t.postcard_at), message: String(t.message ?? ''),
      postcard: true, home: true, photo: String(t.photo ?? ''), souvenir: String(t.souvenir ?? ''),
      ...(t.early ? { early: t.early === 'souvenir' ? 'souvenir' : 'photo' } : {}),
    })).filter((t) => !have.has(`${t.place}@${t.left}`))
    // a trip under way here stays the last one (the one she is on)
    const away = this.away()
    const done = this.data.trips.filter((t) => t !== away).concat(old).sort((a, b) => a.left - b.left)
    this.data.trips = away ? [...done, away] : done
    this.data.seeded = true
    if (!this.data.started) {
      this.data.magazine = String(data.magazine ?? '')
      for (const key of ['magazine_new', 'inside']) this.data[key] = Boolean(data[key])
      this.data.note_left = num(data.note_left)
    }
    this.data.unseen = num(this.data.unseen) + num(data.unseen)
    if (data.notes_read && typeof data.notes_read === 'object') {
      this.data.notes_read = { ...Object.fromEntries(Object.entries(data.notes_read).map(([k, v]) => [String(k), num(v)])),
        ...this.data.notes_read }
    }
    this.logger.info?.(`living-dock: took over the window's record (${old.length} old trips)`)
    this.data.started = true
    this.changed()
    this.tick()
    return true
  }

  #comeHome(a) {
    a.postcard = true
    a.home = true
    this.data.inside = true              // back from a trip into the little home
    const place = this.places[a.place] ?? {}
    // a photo she has not brought home before, if there is one left
    const had = this.data.trips.filter((t) => t !== a && t.place === a.place).map((t) => t.photo)
    const photos = place.photos ?? []
    const fresh = photos.filter((p) => !had.includes(p))
    const pool = fresh.length ? fresh : photos
    a.photo = pool.length ? pool[Math.floor(this.random() * pool.length)] : ''
    a.souvenir = place.souvenir ?? ''
    // home early: only the one she chose to keep
    if (a.early === 'photo') a.souvenir = ''
    if (a.early === 'souvenir') a.photo = ''
    this.data.unseen += 1
  }

  #activity(text) {
    text = text.trim()
    if (!text) return ''
    const list = this.data.activities ?? []
    return list.find((n) => n === text) ?? list.find((n) => n.includes(text) || text.includes(n)) ?? ''
  }

  #withPostcards() { return this.data.trips.filter((t) => t.postcard) }

  #souvenirs() {
    const out = []
    for (const t of this.data.trips) if (t.home && t.souvenir && !out.includes(t.place)) out.push(t.place)
    return out
  }

  /** "11月12日·杭州": which trip a postcard or souvenir came from. */
  #label(t, when) { return `${dayText(t[when])}·${this.places[t.place]?.short ?? t.place}` }

  /** The postcards on the wall (newest first, as many as it has slots), labelled by trip. */
  #wall() {
    const cards = this.#withPostcards().reverse()
    const slots = Number.isInteger(this.data.wall_slots) ? this.data.wall_slots : cards.length
    return cards.slice(0, slots).map((t) => this.#label(t, 'postcard_at'))
  }

  /** The souvenirs on the shelf, each with the trip that first brought it home. */
  #shelf() {
    return this.#souvenirs().map((p) => {
      const t = this.data.trips.find((x) => x.home && x.place === p && x.souvenir)
      return `${this.places[p]?.souvenir ?? p}（${this.#label(t, 'back')}）`
    })
  }
}

/**
 * Her tools' requests: a photo needs a window (or the web page) open, everything else the plugin answers
 * itself. frames.request(message, timeoutMs) asks the windows; what only a window knows (weather, where she
 * stands) is asked with a short wait and left out when none answers.
 */
export function homeRequest(home, frames) {
  const facts = (reply) => (reply && typeof reply.facts === 'object' && reply.facts) || {}
  return async (message, timeoutMs) => {
    if (message.op === 'photo') {
      let reply
      try { reply = await frames.request(message, timeoutMs) } catch { return { ok: false, why: 'closed', world: home.report() } }
      return { ...reply, world: home.report(facts(reply)) }
    }
    const known = await frames.request({ t: 'cmd', op: 'facts' }, 800).then(facts, () => ({}))
    const why = home.handle(message)
    return { ok: why === '', why, world: home.report(known) }
  }
}
