// dsh-living-dock: shows what the DSH companion is doing in her little home (《旅行的大肥鱼》: a page in DSH, a
// browser page or a window), keeps the little home's record and rules (lib/home.js, supplement 4 amendment 2),
// and gives her her own tools for the little home (supplement 4), which she decides whether to use.
// It never changes sessions, settings or memory, never sends chat text off this computer, and never calls
// the model or puts anything into a session by itself. `tools: false` turns it back to read-only.
import { Reducer } from './lib/reducer.js'
import { FrameServer } from './lib/server.js'
import { createTools, defineToolLocal } from './lib/tools.js'
import { Home, homeRequest } from './lib/home.js'
import { WebHome } from './lib/web.js'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

export const name = 'dsh-living-dock'
export const inject = []

// DSH hands plugins its own defineTool; outside DSH (tests) or on hosts that do not, use the same-shaped copy.
const defineTool = await import('@deepseek-ai/dsh-tools').then((m) => m.defineTool, () => defineToolLocal)

const DEFAULTS = {
  enabled: true,
  tools: true,
  port: 48960,
  beaconPort: 48961,
  findPort: 48962,
  webPort: 48963,     // the web version of the little home on its own port, this computer only (0 = off)
  webDir: '',         // its files (the Godot web export); '' = web\ next to this file
  dataDir: '',        // the little home's record; '' = %APPDATA%\旅行的大肥鱼
  notesDir: '',       // the coffee-table notes; '' = Documents\旅行的大肥鱼\茶几纸条 (the installer writes the real one)
  tripMinutes: 0,     // tests only: a trip lasts this many minutes (0 = 8 to 20 hours)
  pairCode: '',
  chatSessions: ['^onebot-private-'],
  ignoreSessions: ['^onebot-group-'],
}

const here = (file) => fileURLToPath(new URL(file, import.meta.url))

function readPlaces(logger) {
  try { return JSON.parse(fs.readFileSync(here('./places.json'), 'utf8')) } catch (error) {
    logger.warn?.(`living-dock: no places.json (${error.message}), nowhere to travel`)
    return {}
  }
}

export function apply(ctx, config = {}) {
  const options = { ...DEFAULTS, ...config }
  const logger = ctx.logger ? ctx.logger(name) : console
  if (options.enabled === false) return
  if (!options.pairCode) {
    options.pairCode = String(Math.floor(100000 + Math.random() * 900000))
    logger.info?.(`living-dock: no pairCode configured, using ${options.pairCode} for this run`)
  }

  const places = readPlaces(logger)
  const reducer = new Reducer(options)
  let server = null
  const home = new Home({
    dataDir: options.dataDir || path.join(process.env.APPDATA || os.homedir(), '旅行的大肥鱼'),
    notesDir: options.notesDir || path.join(os.homedir(), 'Documents', '旅行的大肥鱼', '茶几纸条'),
    places,
    tripMinutes: Number(options.tripMinutes) || 0,
    logger,
    onChange: (data) => server?.broadcast({ t: 'home', data }),
  })
  server = new FrameServer({
    port: options.port,
    beaconPort: options.beaconPort,
    findPort: options.findPort,
    pairCode: options.pairCode,
    logger,
    snapshot: () => reducer.current(),
    // windows only show the home: they get the record on connecting and after every change
    greet: () => ({ welcome: { keeper: true, fresh: home.fresh }, messages: [{ t: 'home', data: home.view() }] }),
    onMessage: (message) => {
      if (message.t === 'world') home.world(message)
      else if (message.t === 'user') home.user(message)
      else if (message.t === 'seed') home.seed(message.data)
    },
  })
  server.start()
  const web = new WebHome({
    port: options.webPort, dir: options.webDir || here('./web/'), pairCode: options.pairCode, logger, frames: server,
  })
  if (options.webPort && web.ready) web.start()
  // the page inside DSH (the little home panel, lib/client.js) comes from DSH's own web server
  ctx.plugin?.({
    name: 'dsh-living-dock-web',
    inject: ['webServer'],
    apply(wctx) { wctx.effect(() => web.mount(wctx.webServer)) },
  })

  const send = (messages) => { for (const message of messages) server.broadcast(message) }
  // Never let an exception escape into the shared session bus.
  const offEvent = ctx.on('session/event', (session, event) => {
    try { send(reducer.handle(session, event)) } catch (error) { logger.warn?.(`living-dock: ${error.message}`) }
  }, { global: true })
  const offDisposed = ctx.on('session/disposed', (session) => {
    try { send(reducer.disposeSession(session)) } catch (error) { logger.warn?.(`living-dock: ${error.message}`) }
  }, { global: true })
  const ticker = setInterval(() => {
    send(reducer.tick())
    try { home.tick() } catch (error) { logger.warn?.(`living-dock: ${error.message}`) }
  }, 1000)

  if (options.tools !== false) {
    ctx.plugin({
      name: 'dsh-living-dock-tools',
      inject: ['tools'],
      apply(tctx) {
        // photos go to the model through DSH's own attachment store (as other plugins do), never anywhere else
        const attach = async (data, mediaType) => {
          const store = tctx.get?.('attachments')
          if (!store) return undefined
          const ref = await store.saveImage({ data, mediaType, name: 'little-home.jpg' })
          return { attachmentId: String(ref.attachmentId), mediaType: ref.mediaType, bytes: ref.bytes, width: ref.width, height: ref.height }
        }
        const tools = createTools(homeRequest(home, server), attach, places)
        for (const tool of tools) tctx.tools.register(defineTool(tool))
      },
    })
  }

  ctx.effect(() => () => {
    clearInterval(ticker)
    offEvent?.()
    offDisposed?.()
    server.stop()
    web.stop()
  })
}
