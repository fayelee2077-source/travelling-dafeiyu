// node --test test/tools.test.mjs
import test from 'node:test'
import assert from 'node:assert/strict'
import net from 'node:net'
import { FrameServer } from '../lib/server.js'
import { createTools, defineToolLocal, describe } from '../lib/tools.js'

const quiet = { info: () => {}, warn: () => {} }
const WORLD = {
  inside: false, leaving: false, hour: 14.5, weather: 'clear', season: 'autumn', at: '', trips: 1, postcards: 1,
  souvenirs: ['西湖龙井'], places: [{ id: 'hangzhou', name: '杭州·西湖' }], away: null,
  magazine: { id: 'suzhou', name: '苏州', new: true },
}

function tools(server, attach) {
  return Object.fromEntries(createTools((m) => server.request(m, 1000), attach).map((t) => [t.name, defineToolLocal(t)]))
}

// A fake frame: pairs, then answers every command with ok / why and a world report.
function frame(port, answer) {
  return new Promise((resolve) => {
    const c = net.connect(port, '127.0.0.1', () => c.write(JSON.stringify({ t: 'hello', code: '4242' }) + '\n'))
    let buf = ''
    c.on('data', (d) => {
      buf += d
      let i
      while ((i = buf.indexOf('\n')) >= 0) {
        const msg = JSON.parse(buf.slice(0, i))
        buf = buf.slice(i + 1)
        if (msg.t === 'welcome') resolve(c)
        if (msg.t === 'cmd') c.write(JSON.stringify({ t: 'reply', id: msg.id, ...answer(msg) }) + '\n')
      }
    })
  })
}

test('describe words the report as facts', () => {
  const text = describe(WORLD)
  assert.match(text, /14:30，秋天，晴/)
  assert.match(text, /不在小家里/)
  assert.match(text, /纪念品柜里有：西湖龙井/)
  assert.match(text, /《苏州》旅行杂志（用户放的，你第一次看到）/)
  assert.match(text, /能去旅行的地方：杭州·西湖/)
})

test('postcards and souvenirs say which trip they came from', () => {
  const w = { ...WORLD, trips: 9, postcards: 9, wall: ['11月12日·杭州', '11月11日·苏州'], shelf: ['西湖龙井（11月12日·杭州）'] }
  const text = describe(w)
  assert.match(text, /明信片墙上有 9 张明信片：11月12日·杭州、11月11日·苏州（墙上挂满了，只挂得下最新的 2 张）。/)
  assert.match(text, /纪念品柜里有：西湖龙井（11月12日·杭州）。/)
})

test('notes on the coffee table are read to her only in the little home', () => {
  const inside = describe({ ...WORLD, inside: true, notes: [{ from: '妈妈', day: '11月13日', text: '记得带伞' }], notes_waiting: 1 })
  assert.match(inside, /茶几上有 1 张给你的纸条/)
  assert.match(inside, /- 妈妈留的（11月13日）：记得带伞/)
  assert.match(inside, /茶几上还有 1 张纸条，下次再看/)
  assert.match(describe({ ...WORLD, notes: [], notes_waiting: 2 }), /茶几上有 2 张你还没看的纸条，进了小家才能看/)
  assert.doesNotMatch(describe(WORLD), /纸条/)
})

test('without a frame the tools say the window is closed', async () => {
  const server = new FrameServer({ port: 49880, beaconPort: 49881, findPort: 0, pairCode: '4242', logger: quiet, snapshot: () => ({}) })
  server.start()
  const t = tools(server)
  assert.match((await t.little_home_enter.execute({})).text, /小家现在没打开/)
  server.stop()
})

test('commands reach the frame and its answers come back', async () => {
  const server = new FrameServer({ port: 49940, beaconPort: 49941, findPort: 0, pairCode: '4242', logger: quiet,
    snapshot: () => ({ t: 'state', state: 'idle' }) })
  server.start()
  await new Promise((resolve) => setTimeout(resolve, 100))
  const seen = []
  const c = await frame(49940, (msg) => {
    seen.push(msg)
    if (msg.op === 'travel' && msg.place !== 'hangzhou') return { ok: false, why: 'unknown_place', world: WORLD }
    return { ok: true, why: '', world: { ...WORLD, inside: msg.op === 'enter' } }
  })
  const t = tools(server)
  const enter = await t.little_home_enter.execute({})
  assert.match(enter.text, /^你从院门走进了小家。/)
  assert.match(enter.text, /你在小家里/)
  const go = await t.little_home_travel.execute({ place: '西湖', message: '  荷花开了  ' })
  assert.match(go.text, /出门去杭州·西湖了。明信片背面会写上你的话/)
  assert.deepEqual(seen.at(-1), { t: 'cmd', op: 'travel', place: 'hangzhou', message: '荷花开了', id: seen.at(-1).id })
  assert.match((await t.little_home_travel.execute({ place: '北京' })).text, /^现在去不了那里。能去的地方：杭州·西湖/)
  await assert.rejects(t.little_home_postcard.execute({}), /missing required/)
  assert.match((await t.little_home_note.execute({ text: ' 出门啦 ' })).text, /^纸条写好了/)
  assert.deepEqual(seen.at(-1), { t: 'cmd', op: 'note', text: '出门啦', id: seen.at(-1).id })
  assert.match((await t.little_home_note.execute({ text: '   ' })).text, /^纸条上要写点什么/)
  c.destroy()
  server.stop()
})

test('she chooses what to do, and a photo comes back as an image for her', async () => {
  const server = new FrameServer({ port: 49950, beaconPort: 49951, findPort: 0, pairCode: '4242', logger: quiet,
    snapshot: () => ({ t: 'state', state: 'idle' }) })
  server.start()
  await new Promise((resolve) => setTimeout(resolve, 100))
  const inside = { ...WORLD, inside: true, activities: ['荡秋千', '钓鱼'] }
  const c = await frame(49950, (msg) => {
    if (msg.op === 'do') {
      return msg.activity === '荡秋千'
        ? { ok: true, world: { ...inside, doing: { name: '荡秋千', minutes_left: 15, reason: '想吹吹风' } } }
        : { ok: false, why: 'unknown_activity', world: inside }
    }
    if (msg.op === 'photo') return { ok: true, image: Buffer.from('JPEGDATA').toString('base64'), mime: 'image/jpeg', world: inside }
    return { ok: true, world: inside }
  })
  const kept = []
  const t = tools(server, async (data, type) => { kept.push([data.toString(), type]); return { attachmentId: 'a1', mediaType: type } })
  const go = await t.little_home_do.execute({ activity: '荡秋千', minutes: 15, reason: '想吹吹风' })
  assert.match(go.text, /^你去荡秋千了。/)
  assert.match(go.text, /正在荡秋千（还剩大约 15 分钟，想吹吹风）/)
  assert.match((await t.little_home_do.execute({ activity: '跳伞' })).text, /^小家里没有这件事可做。能做的事：荡秋千、钓鱼/)
  const early = await t.little_home_come_back.execute({ keep: '纪念品' })
  assert.match(early.text, /带回纪念品，这次没有照片/)
  const photo = await t.little_home_photo.execute({})
  assert.deepEqual(kept, [['JPEGDATA', 'image/jpeg']])
  assert.deepEqual(photo.image, { attachmentId: 'a1', mediaType: 'image/jpeg' })
  const parts = defineToolLocal(createTools(() => {})[0]).output.render({}, photo)
  assert.equal(parts[1].type, 'image')
  c.destroy()
  server.stop()
})

test('the news tells what she is wearing and what is in the wardrobe', () => {
  const w = { ...WORLD, inside: true, outfit: '冬装', outfits: ['女仆裙', '冬装', '夏装', '雨衣'] }
  const text = describe(w)
  assert.match(text, /你穿着冬装。/)
  assert.match(text, /衣柜里还有：女仆裙、夏装、雨衣。/)
  // outside the wardrobe stays unmentioned; away she is not worded as wearing anything
  assert.match(describe({ ...w, inside: false }), /你穿着冬装。/)
  assert.doesNotMatch(describe({ ...w, inside: false }), /衣柜里还有/)
  assert.doesNotMatch(describe({ ...w, away: { name: '中国雪乡', left: 1, back: 2, postcard: true, wrote: false } }), /你穿着/)
})

test('the dress tool hears her own words for the clothes', async () => {
  const sent = []
  const inside = { ...WORLD, inside: true, outfits: ['女仆裙', '冬装', '夏装', '雨衣'] }
  const names = { maid: '女仆裙', winter: '冬装', summer: '夏装', rain: '雨衣' }
  const t = Object.fromEntries(createTools(async (m) => {
    sent.push(m)
    if (m.outfit === 'maid') return { ok: false, why: 'already_wearing', world: { ...inside, outfit: '女仆裙' } }
    if (!names[m.outfit]) return { ok: false, why: 'unknown_outfit', world: inside }
    return { ok: true, why: '', world: { ...inside, outfit: names[m.outfit] } }
  }).map((tool) => [tool.name, defineToolLocal(tool)]))
  const summer = await t.little_home_dress.execute({ outfit: '草帽' })
  assert.deepEqual(sent.at(-1), { t: 'cmd', op: 'dress', outfit: 'summer' })
  assert.match(summer.text, /^你走到衣柜前，换上了夏装。/)
  const rain = await t.little_home_dress.execute({ outfit: '黄雨衣' })
  assert.equal(sent.at(-1).outfit, 'rain')
  assert.match(rain.text, /^你走到衣柜前，换上了雨衣。/)
  await t.little_home_dress.execute({ outfit: '围巾' })
  assert.equal(sent.at(-1).outfit, 'winter')
  const same = await t.little_home_dress.execute({ outfit: '女仆' })
  assert.equal(sent.at(-1).outfit, 'maid')
  assert.match(same.text, /^你身上穿的就是女仆裙。/)
  const none = await t.little_home_dress.execute({ outfit: '睡衣' })
  assert.equal(sent.at(-1).outfit, '睡衣')
  assert.match(none.text, /衣柜里没有这套衣服。有：女仆裙、冬装、夏装、雨衣。/)
})

test('recipient, road scenic note, pre-halfway photo, and new place aliases work end-to-end', async () => {
  const sent = []
  const awayRoad = {
    ...WORLD,
    away: {
      place: 'dunhuang', name: '敦煌·鸣沙山', left: 1764000000, back: 1764036000,
      postcard: false, wrote: true, to: '妈妈', scenic: '夕阳把连绵的沙丘染成金橙色，风里有远远的驼铃声',
    },
    trips: 2, postcards: 2, wall_postcards: 1, wall: ['11月12日·杭州'], sent_to: ['姐姐（11月15日·雪乡）'],
  }
  const places = {
    beijing: { name: '北京·胡同', short: '北京' },
    dunhuang: { name: '敦煌·鸣沙山', short: '敦煌' },
  }
  const t = Object.fromEntries(createTools(async (m) => {
    sent.push(m)
    if (m.op === 'photo') {
      return { ok: true, kind: 'on_road', image: Buffer.from('ROADJPG').toString('base64'), mime: 'image/jpeg', world: awayRoad }
    }
    return { ok: true, why: '', world: awayRoad }
  }, async (_d, type) => ({ attachmentId: 'road1', mediaType: type }), places).map((tool) => [tool.name, defineToolLocal(tool)]))

  const go = await t.little_home_travel.execute({ place: '月牙泉', message: '沙子在唱歌', to: '给妈妈' })
  assert.deepEqual(sent.at(-1), { t: 'cmd', op: 'travel', place: 'dunhuang', message: '沙子在唱歌', to: '妈妈' })
  assert.match(go.text, /这次的明信片会寄给妈妈/)
  assert.match(go.text, /寄给妈妈的明信片还在路上/)
  assert.match(go.text, /路上的风物小注：「夕阳把连绵的沙丘染成金橙色/)
  assert.match(go.text, /另外还专门寄出过明信片给：姐姐（11月15日·雪乡）/)

  const shot = await t.little_home_photo.execute({})
  assert.match(shot.text, /正在去敦煌·鸣沙山的路上.*这是那边的风景/)
  assert.equal(shot.image.attachmentId, 'road1')

  await t.little_home_postcard.execute({ text: '改寄给姐姐啦', to: '姐姐' })
  assert.deepEqual(sent.at(-1), { t: 'cmd', op: 'postcard', text: '改寄给姐姐啦', to: '姐姐' })
})
