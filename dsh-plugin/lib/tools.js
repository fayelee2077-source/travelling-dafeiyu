// The companion's own tools for the little home (supplement 4): she decides whether to use them. They only
// act on the little home (its record kept by this plugin, lib/home.js; the window or web page shows it); no
// QQ, no network, no other files, and the plugin never calls them by itself. Results are plain facts in
// Chinese, worded here from the home's report. Coffee-table notes (supplement 4, amendments 1 and 2) are only
// worded here, as what is written on each note and who left it.
import { cleanRecipient } from './home.js'

const WEATHER = { clear: '晴', cloudy: '多云', rain: '下雨', snow: '下雪' }
const SEASON = { spring: '春天', summer: '夏天', autumn: '秋天', winter: '冬天' }
// other names she may use for a place (the places' own names and short names always work)
const ALIASES = { 西湖: 'hangzhou', 杭州西湖: 'hangzhou', 鼓浪屿: 'xiamen', 厦门鼓浪屿: 'xiamen', 中国雪乡: 'xuexiang', 东北雪乡: 'xuexiang', 雪乡: 'xuexiang', 外滩: 'shanghai', 上海外滩: 'shanghai', 东方明珠: 'shanghai', 东方明珠塔: 'shanghai', 南尖岩: 'suichang', 丽水: 'suichang', 丽水遂昌: 'suichang', 萧山: 'xianghu', 萧山湘湖: 'xianghu', 杭州湘湖: 'xianghu', 胡同: 'beijing', 北京胡同: 'beijing', 四合院: 'beijing', 城墙: 'xian', 西安城墙: 'xian', 古城墙: 'xian', 漓江: 'guilin', 桂林漓江: 'guilin', 阳朔: 'guilin', 洱海: 'dali', 大理洱海: 'dali', 苍山: 'dali', 苍山洱海: 'dali', 宽窄巷子: 'chengdu', 竹林茶铺: 'chengdu', 成都茶铺: 'chengdu', 鸣沙山: 'dunhuang', 月牙泉: 'dunhuang', 敦煌鸣沙山: 'dunhuang' }
const CLOSED = '《旅行的大肥鱼》的小家现在没打开，看不到也去不了小家。'

const TEXT_OUT = {
  schema: { type: 'object', additionalProperties: true, properties: { text: { type: 'string', required: true } } },
  render: (_args, value) => [
    { type: 'text', text: value.text },
    ...(value.image ? [{ type: 'image', attachment: { ...value.image } }] : []),
  ],
}

const pad = (n) => String(n).padStart(2, '0')
const clock = (h) => `${Math.floor(h)}:${pad(Math.floor((h % 1) * 60))}`
const day = (t) => { const d = new Date(t * 1000); return `${d.getMonth() + 1}月${d.getDate()}日` }
const when = (t) => { const d = new Date(t * 1000); return `${day(t)} ${d.getHours()}:${pad(d.getMinutes())}` }

/** The little home as she would see it, from the frame's report; full adds what she can do and where she can go. */
export function describe(w, full = true) {
  const sky = w.weather ? `，${WEATHER[w.weather] ?? w.weather}` : ''
  const lines = [`小家这会儿是 ${clock(w.hour)}，${SEASON[w.season] ?? w.season}${sky}。`]
  if (w.away) {
    const toText = w.away.to ? `寄给${w.away.to}的` : ''
    const card = w.away.postcard ? `${toText}明信片已经寄到了。`
      : w.away.wrote ? `${toText}明信片还在路上，背面写了你的话。` : `${toText}明信片还在路上，背面还没写字。`
    const scenic = w.away.scenic ? `路上的风物小注：「${w.away.scenic}」（会印在明信片背面角落，给你参考）。` : ''
    lines.push(`你正在${w.away.name}旅行（${day(w.away.left)}出发，大约 ${when(w.away.back)} 回家）。${card}${scenic}`)
  } else if (w.leaving) {
    lines.push('你正往院门走，要出门了。')
  } else if (w.inside && w.doing) {
    const why = w.doing.reason ? `，${w.doing.reason}` : ''
    const now = w.doing.arrived === false ? `正走去${w.doing.name}` : `正在${w.doing.name}`
    lines.push(`你在小家里，${now}（还剩大约 ${w.doing.minutes_left} 分钟${why}）。`)
  } else if (w.inside) {
    lines.push(`你在小家里${w.at ? `（${w.at}）` : ''}。`)
  } else {
    lines.push('你现在不在小家里，房子空着，门关着，灯也没开。')
  }
  if (w.trips || w.postcards) {
    const wallCount = w.wall_postcards ?? w.postcards
    if (wallCount || !w.sent_to?.length) {
      const shown = w.wall?.length ? `：${w.wall.join('、')}${wallCount > w.wall.length ? `（墙上挂满了，只挂得下最新的 ${w.wall.length} 张）` : ''}` : ''
      lines.push(`已经旅行回来 ${w.trips} 次，明信片墙上有 ${wallCount} 张明信片${shown}。`)
    } else {
      lines.push(`已经旅行回来 ${w.trips} 次，明信片墙上还没有留给小家自己的明信片。`)
    }
    if (w.sent_to?.length) {
      lines.push(`另外还专门寄出过明信片给：${w.sent_to.join('、')}（不占你的墙面，都在旅行相册里）。`)
    }
  }
  const shelf = w.shelf?.length ? w.shelf : w.souvenirs
  if (shelf?.length) lines.push(`纪念品柜里有：${shelf.join('、')}。`)
  if (w.magazine) {
    lines.push(`茶几上放着一本《${w.magazine.name}》旅行杂志（用户放的${w.magazine.new ? '，你第一次看到' : ''}）。`)
  }
  if (w.notes?.length) {
    lines.push(`茶几上有 ${w.notes.length} 张给你的纸条（家里人放在茶几纸条文件夹里的）：`)
    for (const n of w.notes) lines.push(`- ${n.from}留的（${n.day}）：${n.text || '（空白的纸条）'}`)
  }
  if (w.notes_waiting) {
    lines.push(w.inside ? `茶几上还有 ${w.notes_waiting} 张纸条，下次再看。`
      : `茶几上有 ${w.notes_waiting} 张你还没看的纸条，${w.away ? '回家以后' : '进了小家'}才能看。`)
  }
  if (w.outfit && !w.away) {
    const others = (w.outfits ?? []).filter((o) => o !== w.outfit)
    lines.push(`你穿着${w.outfit}。${full && w.inside && others.length ? `衣柜里还有：${others.join('、')}。` : ''}`)
  }
  if (full && w.inside && w.activities?.length) lines.push(`在小家里能做的事：${w.activities.join('、')}。`)
  if (full && w.places?.length && !w.away) lines.push(`能去旅行的地方：${w.places.map((p) => p.name).join('、')}。`)
  return lines.join('\n')
}

const WHY = {
  away: (w) => `你正在${w.away?.name ?? '外面'}旅行，回来以前做不了这件事。`,
  leaving: () => '你正往院门走，要出门了。',
  already_inside: () => '你已经在小家里了。',
  not_inside: () => '你本来就不在小家里。',
  unknown_place: (w) => `现在去不了那里。${w.places?.length ? `能去的地方：${w.places.map((p) => p.name).join('、')}。` : ''}`,
  not_away: () => '你现在没有在旅行。',
  postcard_sent: () => '这次的明信片已经寄到了，改不了了。',
  outside: () => '你现在不在小家里，先进去才能在里面做事。',
  unknown_activity: (w) => `小家里没有这件事可做。${w.activities?.length ? `能做的事：${w.activities.join('、')}。` : ''}`,
  minimized: () => '小家的窗口现在缩到任务栏里了，拍不到画面。',
  empty_note: () => '纸条上要写点什么才行。',
  note_failed: () => '纸条没放上去（小家的纸条文件夹写不进去）。',
  no_postcard_yet: (w) => `你正在${w.away?.name ?? '外面'}旅行，小家里没人；那边的风景画还没准备好。`,
  closed: () => '小家的画面现在没打开（《旅行的大肥鱼》窗口和 DSH 里的小家页面都没开），拍不到照片。',
  unknown_outfit: (w) => `衣柜里没有这套衣服。${w.outfits?.length ? `有：${w.outfits.join('、')}。` : ''}`,
  already_wearing: (w) => `你身上穿的就是${w.outfit ?? '这套'}。`,
}
// what she may call each outfit (the outfits' own names always work)
const OUTFIT_WORDS = [
  [/女仆|围裙|平时|原来/, 'maid'], [/冬|围巾|毛线帽|外套|雪地/, 'winter'],
  [/夏|草帽|薄衫|短袖|凉鞋|海边/, 'summer'], [/雨|黄/, 'rain'],
]

/**
 * The tool definitions (defineTool options).
 */
export function createTools(request, attach = async () => undefined, places = {}) {
  const placeNames = { ...ALIASES }
  for (const [id, p] of Object.entries(places)) {
    for (const n of [p.name, p.short, p.name?.replace(/·/g, '')]) if (n) placeNames[n] = id
  }
  const shorts = Object.entries(places).map(([id, p]) => p.short ?? id)
  const list = shorts.length > 1 ? `${shorts.slice(0, -1).join('、')} 或 ${shorts.at(-1)}` : shorts.join('')
  // full: also list what she can do and where she can go (looking, coming in, or after something she cannot do)
  const run = async (message, done, { timeoutMs, full = false } = {}) => {
    let reply
    try { reply = await request(message, timeoutMs) } catch { return { text: CLOSED } }
    const w = reply.world ?? {}
    const head = reply.ok ? await done(w, reply) : (WHY[reply.why]?.(w) ?? '这件事现在做不了。')
    const part = typeof head === 'object' ? head : { text: head }
    const home = describe(w, full || !reply.ok)
    return { ...part, text: part.text ? `${part.text}\n\n${home}` : home }
  }
  const words = (value) => (typeof value === 'string' ? value.trim().slice(0, 300) : '')
  return [
    {
      name: 'little_home_look',
      description: '看看你在《旅行的大肥鱼》小家里的近况：你在不在家、在不在旅行、明信片和纪念品、茶几上有没有杂志和纸条。只看不动。',
      parameters: {},
      isConcurrencySafe: () => true,
      execute: () => run({ t: 'cmd', op: 'look' }, () => '', { full: true }),
    },
    {
      name: 'little_home_photo',
      description: '给《旅行的大肥鱼》的小家窗口拍一张照片，看看那里此刻真实的样子（你在做什么、天色、家里的东西）。'
        + '旅行途中家里没人，给你看的是路上的风景或你寄回家的明信片正面。只看不动；每张照片会用一些图片额度。',
      parameters: {},
      isConcurrencySafe: () => true,
      execute: () => run({ t: 'cmd', op: 'photo' }, async (w, reply) => {
        const image = reply.image ? await attach(Buffer.from(reply.image, 'base64'), reply.mime || 'image/jpeg').catch(() => undefined) : undefined
        if (!image) return { text: '照片拍好了，但这里没法把图片给你看。' }
        if (reply.kind === 'on_road') {
          return { text: `你正在去${w.away?.name ?? '外面'}的路上，小家里没人。这是那边的风景（明信片过一会儿寄出）。`, image }
        }
        return reply.kind === 'postcard'
          ? { text: `你在${w.away?.name ?? '外面'}旅行，小家里没人。这是你寄出的明信片风景。`, image }
          : { text: '这是小家窗口现在的样子。', image }
      }, { timeoutMs: 10000 }),
    },
    {
      name: 'little_home_do',
      description: '在小家里做一件你想做的事，比如荡秋千、钓鱼、浇花、看花、看书、做饭、吃饭、睡觉、坐沙发，或者用你旅行带回来的纪念品（比如泡龙井茶、听钢琴音乐盒、摇驼铃；现在能做的事 little_home_look 会列出来）。'
        + '小家里的你会去做，一直做到时间到；你没选的时候，那里的你只是坐坐、在门前站站。要先进入小家。',
      parameters: {
        activity: { type: 'string', required: true, description: '做什么，例如 荡秋千、泡龙井茶、听钢琴音乐盒' },
        minutes: { type: 'number', description: '做多久（分钟，1 到 240，默认 20）' },
        reason: { type: 'string', description: '为什么想做（可选）' },
      },
      execute: (args) => run({
        t: 'cmd', op: 'do', activity: String(args.activity ?? '').trim(),
        minutes: Number(args.minutes) > 0 ? Number(args.minutes) : 20, reason: words(args.reason).slice(0, 100),
      }, (w) => `你去${w.doing?.name ?? '做这件事'}了。`),
    },
    {
      name: 'little_home_enter',
      description: '走进你在《旅行的大肥鱼》里的小家。进去以后你在那里过日子：聊天、干活、休息时，小家里的你也在做同样的事。去不去由你。',
      parameters: {},
      execute: () => run({ t: 'cmd', op: 'enter' }, () => '你从院门走进了小家。', { full: true }),
    },
    {
      name: 'little_home_leave',
      description: '离开小家：你从院门走出去，小家空着，关上灯。',
      parameters: {},
      execute: () => run({ t: 'cmd', op: 'leave' }, () => '你往院门走去，出了门，小家就空了。'),
    },
    {
      name: 'little_home_travel',
      description: '从小家出门旅行，要离开大半天（8 到 20 个小时；想早点回来可以用 little_home_come_back，但要少带一样东西）。路上会寄一张明信片（可指定寄给妈妈、姐姐等，不填就留在小家墙上），回来时带着照片和纪念品。'
        + `目的地写 ${list || '能去的地方'}（现在能去哪里，little_home_look 会告诉你）。去不去、去哪、寄给谁都由你决定。`,
      parameters: {
        place: { type: 'string', required: true, description: `去哪：${shorts.join(' / ') || '能去的地方'}` },
        message: { type: 'string', description: '想写在明信片背面的话（可选，你自己写；不写就只寄风景）' },
        to: { type: 'string', description: '明信片寄给谁（可选，例如 妈妈、姐姐；不填就寄回小家挂在墙上，填了别人就不占你自己的墙面，相册里都能看）' },
      },
      execute: (args) => {
        const place = placeNames[String(args.place ?? '').trim()] ?? String(args.place ?? '').trim().toLowerCase()
        const message = words(args.message)
        const to = cleanRecipient(args.to)
        return run({ t: 'cmd', op: 'travel', place, message, ...(to ? { to } : {}) }, (w) => {
          const name = w.away?.name ?? w.places?.find((p) => p.id === place)?.name ?? place
          const who = to ? `这次的明信片会寄给${to}。` : ''
          return `你收拾好东西，出门去${name}了。${who}${message ? '明信片背面会写上你的话。' : ''}`
        })
      },
    },
    {
      name: 'little_home_come_back',
      description: '旅行途中提前回家。提前回来的代价：照片和纪念品只能带回一样（你选），另一样就没有了；明信片还没寄到的话，你自己带回家。回不回、带哪样由你决定。',
      parameters: {
        keep: { type: 'string', description: '带回哪一样：照片 或 纪念品（默认照片）' },
      },
      execute: (args) => {
        const keep = /纪念|souvenir/i.test(String(args.keep ?? '')) ? 'souvenir' : 'photo'
        return run({ t: 'cmd', op: 'come_back', keep }, (w) =>
          `你提前从${w.away?.name ?? '旅行的地方'}往家走了，带回${keep === 'souvenir' ? '纪念品，这次没有照片' : '照片，这次没有纪念品'}。`)
      },
    },
    {
      name: 'little_home_note',
      description: '在小家的茶几上留一张纸条给家里人（比如出门前说一声）。家里人打开小家的茶几纸条文件夹就能看到。要先进入小家；写不写、写什么由你。',
      parameters: { text: { type: 'string', required: true, description: '纸条上写的话' } },
      execute: (args) => {
        const text = words(args.text)
        if (!text) return { text: '纸条上要写点什么才行。' }
        return run({ t: 'cmd', op: 'note', text }, () => '纸条写好了，放在茶几上，家里人打开茶几纸条文件夹就能看到。')
      },
    },
    {
      name: 'little_home_dress',
      description: '在小家里换一身衣服：女仆裙、冬装（毛线帽、围巾、呢子外套、雪地靴）、夏装（草帽、白色薄衫、短裙、凉鞋）、雨衣（小黄雨衣、雨靴）。'
        + '小家里的你会走到衣柜前换上，之后一直穿着，直到你再换。要先进入小家；穿什么、在院子里还是屋里换、进屋出门要不要换回来，都由你。',
      parameters: { outfit: { type: 'string', required: true, description: '换哪套：女仆裙 / 冬装 / 夏装 / 雨衣' } },
      execute: (args) => {
        const said = String(args.outfit ?? '').trim()
        const outfit = OUTFIT_WORDS.find(([re]) => re.test(said))?.[1] ?? said.toLowerCase()
        return run({ t: 'cmd', op: 'dress', outfit }, (w) => `你走到衣柜前，换上了${w.outfit ?? '这身衣服'}。`)
      },
    },
    {
      name: 'little_home_postcard',
      description: '旅行途中，给这次还没寄到的明信片写（或改写）背面的话，也可以指定或修改寄给谁（例如 妈妈、姐姐）。',
      parameters: {
        text: { type: 'string', required: true, description: '写在明信片背面的话' },
        to: { type: 'string', description: '明信片寄给谁（可选，例如 妈妈、姐姐；不填保持原样）' },
      },
      execute: (args) => {
        const text = words(args.text)
        if (!text) return { text: '明信片背面要写点什么才行。' }
        const hasTo = args.to !== undefined && String(args.to).trim() !== ''
        const to = hasTo ? cleanRecipient(args.to) : undefined
        return run({ t: 'cmd', op: 'postcard', text, ...(hasTo ? { to } : {}) }, (w) => {
          const who = w.away?.to ? `寄给${w.away.to}的` : '寄回家的'
          return `写好了，这些话会出现在${who}明信片背面。`
        })
      },
    },
  ].map((tool) => ({ ...tool, output: TEXT_OUT }))
}

/** A minimal defineTool for hosts that do not hand plugins @deepseek-ai/dsh-tools (same shape as dsh-self's). */
export function defineToolLocal(options) {
  const properties = {}
  const required = []
  for (const [key, p] of Object.entries(options.parameters ?? {})) {
    properties[key] = { type: p.type, description: p.description ?? '' }
    if (p.required) required.push(key)
  }
  const parameters = { type: 'object', properties, ...(required.length ? { required } : {}) }
  return {
    name: options.name,
    description: options.description,
    parameters,
    output: { schema: options.output?.schema ?? {}, render: options.output?.render },
    async execute(args, exec) {
      const missing = required.filter((key) => args?.[key] === undefined)
      if (missing.length) throw new Error(`missing required argument(s): ${missing.join(', ')}`)
      return options.execute(args ?? {}, exec)
    },
  }
}
