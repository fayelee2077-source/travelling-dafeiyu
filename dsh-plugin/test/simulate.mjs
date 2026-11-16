// Runs the plugin inside a fake DSH host and replays a scripted day, so the
// frame can be tested without touching the real DSH profile.
//   node test/simulate.mjs [pairCode] [loop | tools <tool>[:json args] ...] [--port=N]
// "tools" calls the companion's little-home tools in turn (8 s apart) and prints what she would read, e.g.
//   node test/simulate.mjs 123456 tools little_home_look little_home_enter 'little_home_travel:{"place":"杭州"}'
// The home record and the notes folder are temporary ones (--data-dir / --notes-dir to choose), never the real
// ones; --trip-minutes=N makes a trip that short; --gap=S seconds between tool calls (default 8).
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { apply } from '../index.js'

const flags = Object.fromEntries(process.argv.filter((a) => a.startsWith('--')).map((a) => a.slice(2).split('=')))
const args = process.argv.slice(2).filter((a) => !a.startsWith('--'))
const pairCode = args[0] || '123456'
const loop = args[1] === 'loop'
const toolCalls = args[1] === 'tools' ? args.slice(2) : null
const port = Number(flags.port || 48960)

const handlers = new Map()
const effects = []
const tools = new Map()
let photos = 0
const ctx = {
  logger: () => ({ info: (m) => console.log('[info]', m), warn: (m) => console.log('[warn]', m) }),
  on(type, fn) {
    handlers.set(type, fn)
    return () => handlers.delete(type)
  },
  effect(fn) { effects.push(fn()) },
  plugin(p) {
    if (p.inject?.includes('webServer')) return      // no DSH web server here (--web-dir serves on its own port)
    p.apply({
      tools: { register: (t) => { tools.set(t.name, t); return () => tools.delete(t.name) } },
      // photos are written next to this run's output instead of going to a model (--photos=<folder>)
      get: (name) => (name === 'attachments' && flags.photos ? {
        saveImage: async ({ data, mediaType }) => {
          const file = path.join(flags.photos, `little-home-${++photos}.jpg`)
          fs.writeFileSync(file, data)
          console.log(`[photo] ${file} (${data.length} bytes)`)
          return { attachmentId: file, mediaType, bytes: data.length }
        },
      } : undefined),
    })
  },
}
// --web-dir=<Godot web export> also serves the web version on --web-port (default port + 3)
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'living-dock-sim-'))
const dataDir = flags['data-dir'] || path.join(temp, 'data')
const notesDir = flags['notes-dir'] || path.join(temp, 'notes')
console.log(`[sim] home record in ${dataDir}, notes in ${notesDir}`)
apply(ctx, {
  pairCode, port, beaconPort: port + 1, findPort: port + 2, dataDir, notesDir, tripMinutes: Number(flags['trip-minutes'] || 0),
  webPort: flags['web-dir'] ? Number(flags['web-port'] || port + 3) : 0, webDir: flags['web-dir'],
})

if (toolCalls) {
  for (const call of toolCalls) {
    await new Promise((resolve) => setTimeout(resolve, Number(flags.gap || 8) * 1000))
    const [toolName, json] = call.split(/:(.*)/s)
    const result = await tools.get(toolName).execute(json ? JSON.parse(json) : {})
    console.log(`\n=== ${call}\n${result.text}`)
  }
  for (const dispose of effects) dispose?.()
  setTimeout(() => process.exit(0), 300)
}

const work = { header: { id: 'b1c2-work-session' } }
const chat = { header: { id: 'onebot-private-10000-abcd' } }
const group = { header: { id: 'onebot-group-20000-abcd' } }
let seq = 0
const emit = (session, type, data = {}) => handlers.get('session/event')?.(session, { type, seq: ++seq, data })

const script = [
  [3, () => emit(chat, 'turn/start', { turn: 1 })],
  [3, () => emit(chat, 'assistant/message', { message: { role: 'assistant', content: [{ type: 'text', text: 'SECRET reply text' }] } })],
  [2, () => emit(chat, 'turn/end', { reason: { kind: 'completed' } })],
  [2, () => emit(group, 'turn/start', { turn: 1 })],
  [1, () => emit(work, 'turn/start', { turn: 1 })],
  [3, () => emit(work, 'tool/call', { name: 'read_file', callId: 'c1' })],
  [3, () => emit(work, 'tool/result', { callId: 'c1' })],
  [1, () => emit(work, 'tool/call', { name: 'edit_file', callId: 'c2' })],
  [4, () => emit(work, 'tool/result', { callId: 'c2' })],
  [1, () => emit(work, 'tool/call', { name: 'shell', callId: 'c3' })],
  [3, () => emit(work, 'approval/asked', { id: 'a1', toolName: 'shell' })],
  [4, () => emit(work, 'approval/decided', { id: 'a1' })],
  [2, () => emit(work, 'tool/result', { callId: 'c3' })],
  [2, () => emit(work, 'turn/end', { reason: { kind: 'completed' } })],
  [8, () => emit(work, 'turn/start', { turn: 2 })],
  [3, () => emit(work, 'turn/end', { reason: { kind: 'error', error: { message: 'x' } } })],
  [10, () => {}],
]

async function run() {
  do {
    for (const [seconds, step] of script) {
      await new Promise((resolve) => setTimeout(resolve, seconds * 1000))
      step()
    }
  } while (loop)
  for (const dispose of effects) dispose?.()
  setTimeout(() => process.exit(0), 300)
}
if (!toolCalls) run()
