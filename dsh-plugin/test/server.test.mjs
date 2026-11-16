// node --test test/server.test.mjs
import test from 'node:test'
import assert from 'node:assert/strict'
import dgram from 'node:dgram'
import net from 'node:net'
import { FrameServer } from '../lib/server.js'
import { WebHome } from '../lib/web.js'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'

const quiet = { info: () => {}, warn: () => {} }

function start(base) {
  const server = new FrameServer({
    port: base, beaconPort: base + 1, findPort: base + 2, pairCode: '4242', logger: quiet,
    snapshot: () => ({ t: 'state', state: 'idle', activity: null, source: 'none' }),
  })
  server.start()
  return server
}

test('answers a find probe by unicast', async () => {
  const server = start(49860)
  const sock = dgram.createSocket('udp4')
  await new Promise((resolve) => sock.bind(0, '127.0.0.1', resolve))
  const reply = new Promise((resolve) => sock.once('message', (data) => resolve(JSON.parse(data.toString()))))
  await new Promise((resolve) => setTimeout(resolve, 100))
  sock.send(JSON.stringify({ t: 'living-dock-find' }), 49862, '127.0.0.1')
  const msg = await reply
  assert.equal(msg.t, 'living-dock')
  assert.equal(msg.port, 49860)
  sock.close()
  server.stop()
})

test('wrong pair code is denied, right one gets welcome and a snapshot', async () => {
  const server = start(49870)
  await new Promise((resolve) => setTimeout(resolve, 100))
  const talk = (code) => new Promise((resolve) => {
    const c = net.connect(49870, '127.0.0.1', () => c.write(JSON.stringify({ t: 'hello', code }) + '\n'))
    let buf = ''
    c.on('data', (d) => {
      buf += d
      const lines = buf.split('\n').filter(Boolean).map((l) => JSON.parse(l))
      if (lines[0]?.t === 'denied' || lines.length >= 2) { c.destroy(); resolve(lines) }
    })
  })
  assert.equal((await talk('0000'))[0].t, 'denied')
  const ok = await talk('4242')
  assert.equal(ok[0].t, 'welcome')
  assert.equal(ok[1].t, 'state')
  server.stop()
})

function startWeb(base) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ld-web-'))
  fs.writeFileSync(path.join(dir, 'index.html'), '<html><head><title>t</title></head><body></body></html>')
  const frames = start(base)
  const web = new WebHome({ port: base + 3, dir, pairCode: '4242', logger: quiet, frames })
  web.start()
  return { frames, web, stop: () => { web.stop(); frames.stop(); fs.rmSync(dir, { recursive: true, force: true }) } }
}

// raw request, so Host / Origin can be anything; resolves with the status line
const rawStatus = (port, lines) => new Promise((resolve) => {
  const c = net.connect(port, '127.0.0.1', () => c.write(lines.join('\r\n') + '\r\n\r\n'))
  c.once('data', (d) => { c.destroy(); resolve(String(d).split('\r\n')[0]) })
})

test('web page: only for this computer, carries the pair code', async () => {
  const s = startWeb(49880)
  await new Promise((resolve) => setTimeout(resolve, 100))
  const page = await (await fetch('http://127.0.0.1:49883/')).text()
  assert.match(page, /window\.LIVING_DOCK=\{"pair":"4242","link":"\/link"\}/)
  assert.equal((await fetch('http://127.0.0.1:49883/nothing.js')).status, 404)
  assert.match(await rawStatus(49883, ['GET / HTTP/1.1', 'Host: evil.example:49883']), / 403 /)
  assert.match(await rawStatus(49883, ['GET /..%2f..%2fwindows HTTP/1.1', 'Host: 127.0.0.1:49883']), / 404 /)
  const ws = ['GET /link HTTP/1.1', 'Host: 127.0.0.1:49883', 'Upgrade: websocket', 'Connection: Upgrade',
    'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==', 'Sec-WebSocket-Version: 13']
  assert.match(await rawStatus(49883, [...ws, 'Origin: http://evil.example']), / 403 /)
  assert.match(await rawStatus(49883, [...ws, 'Origin: http://127.0.0.1:49883']), / 101 /)
  s.stop()
})

test('inside DSH: page and link under /living-dock/ of its web server; the home comes after the welcome', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ld-web-'))
  fs.writeFileSync(path.join(dir, 'index.html'), '<html><head></head><body></body></html>')
  const seen = []
  const frames = new FrameServer({ port: 49900, beaconPort: 49901, findPort: 0, pairCode: "4242", logger: quiet,
    snapshot: () => ({ t: 'state', state: 'idle' }),
    greet: () => ({ welcome: { keeper: true }, messages: [{ t: 'home', data: { inside: true } }] }),
    onMessage: (m) => seen.push(m) })
  frames.start()
  // a stand-in for DSH's webServer service: prefix routes and exact upgrade routes
  const routes = new Map()
  const upgrades = new Map()
  const fake = {
    register: (r) => { routes.set(r.path, r); return () => routes.delete(r.path) },
    registerUpgrade: (r) => { upgrades.set(r.path, r); return () => upgrades.delete(r.path) },
  }
  const host = (await import('node:http')).createServer((req, res) => {
    const p = new URL(req.url, 'http://x').pathname
    const r = [...routes.values()].find((x) => p === x.path || p.startsWith(x.path + '/'))
    if (r) r.handler(req, res); else res.writeHead(404).end()
  })
  host.on('upgrade', (req, socket, head) => {
    const r = upgrades.get(new URL(req.url, 'http://x').pathname)
    if (r) r.handler(req, socket, head); else socket.destroy()
  })
  await new Promise((resolve) => host.listen(49904, '127.0.0.1', resolve))
  const web = new WebHome({ port: 0, dir, pairCode: '4242', logger: quiet, frames })
  const dispose = web.mount(fake)
  const page = await (await fetch('http://127.0.0.1:49904/living-dock/')).text()
  assert.match(page, /"link":"\/living-dock\/link"/)
  assert.equal((await fetch('http://127.0.0.1:49904/living-dock', { redirect: 'manual' })).status, 302)
  assert.deepEqual(await (await fetch('http://127.0.0.1:49904/living-dock/health')).json(), { ok: true, page: true })
  const ws = ['GET /living-dock/link HTTP/1.1', 'Host: 127.0.0.1:49904', 'Upgrade: websocket', 'Connection: Upgrade',
    'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==', 'Sec-WebSocket-Version: 13']
  assert.match(await rawStatus(49904, [...ws, 'Origin: https://evil.example']), / 403 /)
  assert.match(await rawStatus(49904, [...ws, 'Origin: dsh-app://desktop']), / 101 /)
  const sock = new WebSocket('ws://127.0.0.1:49904/living-dock/link')
  const got = []
  sock.onmessage = (e) => { for (const l of String(e.data).split('\n').filter(Boolean)) got.push(JSON.parse(l)) }
  await new Promise((resolve) => { sock.onopen = resolve })
  sock.send(JSON.stringify({ t: 'hello', code: '4242' }))
  await new Promise((resolve) => setTimeout(resolve, 200))
  assert.deepEqual(got.map((m) => m.t), ['welcome', 'state', 'home'])
  assert.equal(got[0].keeper, true)
  sock.send(JSON.stringify({ t: 'user', op: 'seen' }))
  await new Promise((resolve) => setTimeout(resolve, 100))
  assert.deepEqual(seen, [{ t: 'user', op: 'seen' }])
  sock.close()
  dispose()
  assert.equal(routes.size + upgrades.size, 0)
  web.stop()
  frames.stop()
  host.close()
  fs.rmSync(dir, { recursive: true, force: true })
})

test('web page link: pairs like a frame and answers commands', async () => {
  const s = startWeb(49890)
  await new Promise((resolve) => setTimeout(resolve, 100))
  const ws = new WebSocket('ws://127.0.0.1:49893/link')
  const got = []
  ws.onmessage = (e) => {
    for (const line of String(e.data).split('\n').filter(Boolean)) {
      const msg = JSON.parse(line)
      got.push(msg)
      if (msg.t === 'cmd') ws.send(JSON.stringify({ t: 'reply', id: msg.id, ok: true, big: 'x'.repeat(200000) }))
    }
  }
  await new Promise((resolve) => { ws.onopen = resolve })
  ws.send(JSON.stringify({ t: 'hello', code: '4242' }))
  await new Promise((resolve) => setTimeout(resolve, 200))
  assert.deepEqual(got.slice(0, 2).map((m) => m.t), ['welcome', 'state'])
  const reply = await s.frames.request({ t: 'cmd', op: 'look' })
  assert.equal(reply.ok, true)
  assert.equal(reply.big.length, 200000)
  ws.close()
  s.stop()
})
