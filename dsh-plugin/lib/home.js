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
// trips: [{place, left, back, postcard_at, message, to?, season?, postcard (arrived), home (back home), photo, souvenir, early?}]
// chosen: what she chose to do {name, until (unix seconds), reason}; activities / wall_slots: told by the window
const EMPTY = () => ({
  trips: [], magazine: '', magazine_new: false, unseen: 0, inside: false, notes_read: {}, note_left: 0,
  chosen: null, activities: [], wall_slots: null, outfit: 'maid',
})
// the clothes she can choose (her own choice, 11-16; the window has a sheet for each)
export const OUTFITS = { maid: '女仆裙', winter: '冬装', summer: '夏装', rain: '雨衣' }
const DRESS = '换衣服'          // the wardrobe in the house, where she changes
const SEASONS = ['winter', 'winter', 'spring', 'spring', 'spring', 'summer', 'summer', 'summer', 'autumn', 'autumn', 'autumn', 'winter']

// Printed scenic footer on a postcard back (place + season), distinct from her own handwritten message.
export const SCENIC_NOTES = {
  hangzhou: {
    spring: '苏堤的柳丝刚蘸到水，风里都是软的',
    summer: '荷叶挨着荷叶，风过时翻起一片白背',
    autumn: '晚风里有桂花味，雷峰塔的影子拉得很长',
    winter: '断桥边的残荷立在冷水里，湖面格外安静',
  },
  suzhou: {
    spring: '月洞门外的细雨，把青石板洗得发亮',
    summer: '芭蕉叶大得能遮阴，池里的锦鲤躲在石影下',
    autumn: '白墙角落下几片黄叶，水面上一点风也没有',
    winter: '花窗格子里漏进一点冬阳，茶气散得很慢',
  },
  huangshan: {
    spring: '山缝里开了小野花，云海从脚底下漫上来',
    summer: '松针上挂着雾珠，山顶的风比山下凉快得多',
    autumn: '日出把云海染成橘红色，松影落在石头上',
    winter: '迎客松的针叶裹着白霜，踩雪声传得很远',
  },
  xiamen: {
    spring: '海风潮乎乎的，老院子墙头垂下一串花',
    summer: '白浪一层层拍在礁石上，阳光晒得石头暖洋洋',
    autumn: '傍晚的海风不燥了，巷子里飘来一段钢琴声',
    winter: '南方的冬天海还是蓝的，浪花漫过脚边的沙',
  },
  xuexiang: {
    spring: '屋檐的厚雪化出冰溜子，滴答滴答落在木阶上',
    summer: '林子里的木屋收起了厚雪，夜里风还是很凉',
    autumn: '松林先黄了一层，木屋烟囱早早升起了白烟',
    winter: '屋顶的雪厚得像白蘑菇，红灯笼把雪照成暖橙色',
  },
  shanghai: {
    spring: '江风吹过来带点凉意，对岸的灯一盏接一盏亮了',
    summer: '夏夜的江面晃着粉紫色的灯影，汽笛声慢悠悠的',
    autumn: '梧桐叶落了满街，傍晚江上的晚霞像橘子汽水',
    winter: '江边的风有点冻耳朵，亮灯的塔在夜空里特别清楚',
  },
  suichang: {
    spring: '山谷的晨雾还没散，竹林里全是新笋和泥土味',
    summer: '蓄满水的梯田像一块块亮镜子，把天光接住了',
    autumn: '一层层稻田黄透了，山腰小村飘着做长粽的香气',
    winter: '清晨梯田结了一层薄霜，山里安静得只听见竹叶响',
  },
  xianghu: {
    spring: '湖面像没擦干的玻璃，远山淡淡地洇在水里',
    summer: '木栈道边的芦苇绿得发亮，小木舟轻轻晃着水波',
    autumn: '芦苇荡全变成金黄色了，夕阳把湖水染得暖融融',
    winter: '起雾的早晨，湖面像没擦干的玻璃',
  },
  beijing: {
    spring: '灰瓦屋檐上掠过鸽哨声，胡同口的槐花刚开',
    summer: '老槐树把青石板遮出大片凉阴，蝉声一声接一声',
    autumn: '金黄的银杏叶铺在灰瓦上，风里有糖炒栗子香',
    winter: '细雪静静落在青砖灰瓦上，枝头还挂着几个冻红柿',
  },
  xian: {
    spring: '古老的城砖缝里冒出小草，春风顺着城墙跑得很远',
    summer: '太阳落下去以后，青砖还留着白天的余温',
    autumn: '天色刚暗成群青蓝，城墙上的一排红灯笼全亮了',
    winter: '城墙上的红灯笼在冷风里轻轻晃，暖光映着旧砖',
  },
  guilin: {
    spring: '细雨像烟一样拢着青峰，竹筏划开绿绸子似的水',
    summer: '江水清得能数见水底鹅卵石，把脚伸进去凉丝丝的',
    autumn: '秋天的江面平得像块碧玉，一层层山影倒映在水里',
    winter: '薄雾贴着江面慢慢走，远处的青山像淡墨画出来的',
  },
  dali: {
    spring: '苍山腰上系着一条白云带，洱海蓝得晃眼睛',
    summer: '午后的风穿过水边大树，湖面上碎银似地闪着光',
    autumn: '天高得没有一丝杂色，晒在院里的蓝白染布随风鼓起来',
    winter: '冬天的阳光还是暖的，水鸟贴着蓝盈盈的湖面飞',
  },
  chengdu: {
    spring: '竹叶间漏下碎阳光，盖碗茶的盖子轻轻磕出清脆响声',
    summer: '高高的翠竹挡住了暑气，竹椅坐上去凉快又踏实',
    autumn: '细雨打在竹叶上沙沙响，铜茶壶嘴冒着一缕白热气',
    winter: '捧着热乎乎的盖碗茶窝在竹椅里，半天都不想起来',
  },
  dunhuang: {
    spring: '风吹过沙脊留下一道道细波纹，沙粒簌簌地轻响',
    summer: '傍晚的沙山还带着日头的暖意，月牙泉绿得像块宝石',
    autumn: '夕阳把连绵的沙丘染成金橙色，风里有远远的驼铃声',
    winter: '清冷的夕光落在金色沙脊上，一弯泉水安安静静映着天',
  },
}

// Interactive activities unlocked in the little home once each souvenir has been brought back.
export const SOUVENIR_DO = {
  hangzhou: '泡龙井茶',
  suzhou: '摇丝绸团扇',
  huangshan: '打理迎客松盆景',
  xiamen: '听钢琴音乐盒',
  xuexiang: '点亮雪屋小摆件',
  shanghai: '摇东方明珠水晶球',
  suichang: '尝遂昌长粽',
  xianghu: '尝萧山萝卜干',
  beijing: '看兔儿爷',
  xian: '看小陶马',
  guilin: '摸漓江鹅卵石',
  dali: '看扎染挂布',
  chengdu: '抱熊猫玩偶',
  dunhuang: '摇驼铃',
}

export function cleanRecipient(raw) {
  const s = String(raw ?? '').trim().replace(/^寄?给[:：\s]*/, '').trim().slice(0, 20)
  return /^(家里|家里的你|小家|自己)$/.test(s) ? '' : s
}

export function seasonOf(unixSeconds) {
  return SEASONS[new Date(unixSeconds * 1000).getMonth()] ?? 'autumn'
}

export function scenicNote(placeId, season, placeObj = {}) {
  return placeObj?.notes?.[season] ?? SCENIC_NOTES[placeId]?.[season] ?? ''
}

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
        const to = cleanRecipient(msg.to)
        const season = seasonOf(now)
        d.trips.push({
          place, left: now, back: now + length, postcard_at: now + length * 0.5,
          message: String(msg.message ?? ''), ...(to ? { to } : {}), season,
          postcard: false, home: false, photo: '', souvenir: '',
        })
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
        if (msg.text !== undefined) a.message = String(msg.text ?? '')
        if (msg.to !== undefined) {
          const to = cleanRecipient(msg.to)
          if (to) a.to = to; else delete a.to
        }
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
    const season = facts.season ?? SEASONS[date.getMonth()]
    const cards = this.#withPostcards()
    const wallCards = cards.filter((t) => !t.to)
    const r = {
      inside, leaving: false,
      hour: facts.hour ?? Math.round((date.getHours() + date.getMinutes() / 60) * 100) / 100,
      season,
      weather: facts.weather ?? null,
      at: inside ? String(facts.at ?? '') : '',
      places: Object.entries(this.places).filter(([id]) => this.canGo(id)).map(([id, p]) => ({ id, name: p.name ?? id })),
      trips: d.trips.filter((t) => t.home).length,
      postcards: cards.length,
      wall_postcards: wallCards.length,
      souvenirs: this.#souvenirs().map((p) => this.places[p]?.souvenir ?? p),
      wall: this.#wall(), sent_to: this.#sentTo(), shelf: this.#shelf(),
      away: null, magazine: null, doing: null, activities: this.#allActivities(),
      outfit: OUTFITS[d.outfit] ?? OUTFITS.maid, outfits: Object.values(OUTFITS),
    }
    if (inside && d.chosen && now < d.chosen.until) {
      r.doing = { name: d.chosen.name, reason: d.chosen.reason, minutes_left: Math.ceil((d.chosen.until - now) / 60) }
      if (typeof facts.arrived === 'boolean') r.doing.arrived = facts.arrived
    }
    if (a) {
      const tripSeason = a.season || seasonOf(a.left)
      r.away = {
        place: a.place, name: this.places[a.place]?.name ?? a.place, left: a.left, back: a.back,
        postcard: a.postcard, wrote: Boolean(a.message), to: a.to || '',
        scenic: scenicNote(a.place, tripSeason, this.places[a.place]),
      }
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
    if (Array.isArray(msg.activities)) this.data.activities = msg.activities.map(String).slice(0, 80)
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
   * A window hands over the record it kept itself before the plugin kept it (once per plugin record).
   */
  seed(data) {
    if (!this.fresh || !data || typeof data !== 'object' || !Array.isArray(data.trips) || !data.trips.length) return false
    const num = (v) => (Number.isFinite(Number(v)) ? Number(v) : 0)
    const have = new Set(this.data.trips.map((t) => `${t.place}@${t.left}`))
    const old = data.trips.filter((t) => t && typeof t.place === 'string' && t.home).map((t) => {
      const to = cleanRecipient(t.to)
      return {
        place: t.place, left: num(t.left), back: num(t.back), postcard_at: num(t.postcard_at),
        message: String(t.message ?? ''), ...(to ? { to } : {}),
        season: typeof t.season === 'string' && t.season ? t.season : seasonOf(num(t.left)),
        postcard: true, home: true, photo: String(t.photo ?? ''), souvenir: String(t.souvenir ?? ''),
        ...(t.early ? { early: t.early === 'souvenir' ? 'souvenir' : 'photo' } : {}),
      }
    }).filter((t) => !have.has(`${t.place}@${t.left}`))
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

  #allActivities() {
    const out = [...(this.data.activities ?? [])]
    for (const p of this.#souvenirs()) {
      const act = this.places[p]?.souvenir_do ?? SOUVENIR_DO[p]
      if (act && !out.includes(act)) out.push(act)
    }
    return out
  }

  #activity(text) {
    text = text.trim()
    if (!text) return ''
    const list = this.#allActivities()
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

  /** The postcards kept on her own wall (unaddressed / for home, newest first, up to wall_slots). */
  #wall() {
    const cards = this.#withPostcards().filter((t) => !t.to).reverse()
    const slots = Number.isInteger(this.data.wall_slots) ? this.data.wall_slots : cards.length
    return cards.slice(0, slots).map((t) => this.#label(t, 'postcard_at'))
  }

  /** Postcards addressed to specific people (妈妈, 姐姐...), kept in the album without taking wall slots. */
  #sentTo() {
    return this.#withPostcards().filter((t) => t.to).reverse()
      .map((t) => `${t.to}（${this.#label(t, 'postcard_at')}）`)
  }

  /** The souvenirs brought home (Dali's tie-dye cloth hangs on the wall; others stand on the shelf). */
  #shelf() {
    return this.#souvenirs().map((p) => {
      const t = this.data.trips.find((x) => x.home && x.place === p && x.souvenir)
      const where = p === 'dali' ? '挂在墙上·' : ''
      return `${this.places[p]?.souvenir ?? p}（${where}${this.#label(t, 'back')}）`
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
