// The web version of the little home: the page (the Godot web export in `dir`) and a WebSocket at <base>/link
// where the page connects back as one more frame of the FrameServer (same pairing and messages as the TCP
// frames). It is served two ways, both only to this computer: through DSH's own web server under /living-dock/
// (what the little home panel in DSH shows, like other plugins' pages), and on its own port (127.0.0.1) for
// opening in a browser. No dependencies.
//   Pages from other sites can neither read the page (it carries the pair code) nor connect (Origin check), and
// a renamed host pointing here is refused (Host check: only loopback names).
import http from 'node:http'
import crypto from 'node:crypto'
import fs from 'node:fs'
import path from 'node:path'

const TYPES = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.wasm': 'application/wasm',
  '.pck': 'application/octet-stream', '.png': 'image/png', '.svg': 'image/svg+xml', '.ico': 'image/x-icon',
  '.json': 'application/json',
}
const WS_GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'
const MAX_MESSAGE = 8 * 1024 * 1024   // a photo reply is up to ~1 MB
export const DSH_BASE = '/living-dock'
const LOOPBACK = /^(127\.0\.0\.1|localhost|\[::1\])(:\d+)?$/i

export class WebHome {
  constructor({ port, dir, pairCode, logger, frames }) {
    this.port = port
    this.dir = path.resolve(dir)
    this.pairCode = String(pairCode)
    this.logger = logger
    this.frames = frames
    this.server = null
    this.sockets = new Set()
  }

  /** Whether the page files are there (the plugin can be installed without the web version). */
  get ready() { return fs.existsSync(path.join(this.dir, 'index.html')) }

  /** On its own port, 127.0.0.1 only. */
  start() {
    this.server = http.createServer((req, res) => this.serve(req, res, ''))
    this.server.on('upgrade', (req, socket) => this.upgrade(req, socket, ''))
    this.server.on('error', (error) => this.logger.warn?.(`living-dock: web error: ${error.message}`))
    this.server.listen(this.port, '127.0.0.1', () => this.logger.info?.(`living-dock: little home page on http://127.0.0.1:${this.port}/`))
  }

  /** Under /living-dock/ of DSH's web server (ctx.webServer); returns the disposer. */
  mount(webServer) {
    const off = [
      webServer.register({ kind: 'prefix', path: DSH_BASE, handler: (req, res) => this.serve(req, res, DSH_BASE) }),
      webServer.registerUpgrade({ path: `${DSH_BASE}/link`, handler: (req, socket) => this.upgrade(req, socket, DSH_BASE) }),
    ]
    this.logger.info?.(`living-dock: little home page in DSH at ${DSH_BASE}/`)
    return () => { for (const dispose of off) { try { dispose() } catch { /* already gone */ } } }
  }

  stop() {
    for (const socket of this.sockets) socket.destroy()
    this.sockets.clear()
    this.server?.close()
  }

  serve(req, res, base) {
    if (!LOOPBACK.test(req.headers.host ?? '') || !['GET', 'HEAD'].includes(req.method)) {
      res.writeHead(403)
      return res.end()
    }
    let rel
    try { rel = decodeURIComponent(new URL(req.url, 'http://x').pathname) } catch { rel = '' }
    if (base) {
      if (rel === base) {                        // relative file names in the page need the slash
        res.writeHead(302, { Location: `${base}/` })
        return res.end()
      }
      rel = rel.startsWith(base + '/') ? rel.slice(base.length) : ''
    }
    if (rel === '/health') {
      const body = JSON.stringify({ ok: true, page: this.ready })
      res.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' })
      return res.end(req.method === 'HEAD' ? undefined : body)
    }
    if (rel === '/') rel = '/index.html'
    const file = path.resolve(this.dir, '.' + rel)
    if (!rel || !file.startsWith(this.dir + path.sep)) {
      res.writeHead(404)
      return res.end()
    }
    fs.readFile(file, (error, data) => {
      if (error) {
        res.writeHead(404)
        return res.end()
      }
      if (path.basename(file) === 'index.html') {
        const boot = `<script>window.LIVING_DOCK=${JSON.stringify({ pair: this.pairCode, link: `${base}/link` })}</script>`
        data = Buffer.from(String(data).replace('<head>', '<head>' + boot))
      }
      res.writeHead(200, {
        'Content-Type': TYPES[path.extname(file).toLowerCase()] || 'application/octet-stream',
        'Content-Length': data.length,
        'Cache-Control': path.basename(file) === 'index.html' ? 'no-store' : 'no-cache',
        'X-Content-Type-Options': 'nosniff',
      })
      res.end(req.method === 'HEAD' ? undefined : data)
    })
  }

  /** The page (from either way) or the DSH desktop window's own scheme. */
  #okOrigin(origin) {
    if (origin === undefined) return true
    try {
      const u = new URL(origin)
      return u.protocol === 'dsh-app:' || (['http:', 'https:'].includes(u.protocol) && LOOPBACK.test(u.host))
    } catch { return false }
  }

  upgrade(req, socket, base) {
    const key = req.headers['sec-websocket-key']
    if (new URL(req.url, 'http://x').pathname !== `${base}/link` || !LOOPBACK.test(req.headers.host ?? '')
        || !this.#okOrigin(req.headers.origin) || !key || String(req.headers.upgrade).toLowerCase() !== 'websocket') {
      socket.end('HTTP/1.1 403 Forbidden\r\n\r\n')
      return
    }
    const accept = crypto.createHash('sha1').update(key + WS_GUID).digest('base64')
    socket.write('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n'
      + `Sec-WebSocket-Accept: ${accept}\r\n\r\n`)
    socket.setNoDelay(true)
    this.sockets.add(socket)

    const send = (opcode, payload) => {
      if (socket.destroyed) return
      const n = payload.length
      const head = n < 126 ? Buffer.from([0x80 | opcode, n])
        : n < 65536 ? Buffer.from([0x80 | opcode, 126, n >> 8, n & 255])
          : Buffer.concat([Buffer.from([0x80 | opcode, 127]), (() => { const b = Buffer.alloc(8); b.writeBigUInt64BE(BigInt(n)); return b })()])
      socket.write(Buffer.concat([head, payload]))
    }
    const close = () => { send(0x8, Buffer.alloc(0)); socket.end() }
    const conn = this.frames.connection({
      write: (line) => send(0x1, Buffer.from(line, 'utf8')),
      end: close,
      destroy: () => socket.destroy(),
      from: 'web page',
    })

    let buf = Buffer.alloc(0)
    let parts = []
    let size = 0
    socket.on('data', (chunk) => {
      buf = Buffer.concat([buf, chunk])
      while (buf.length >= 2) {
        const fin = buf[0] & 0x80
        const opcode = buf[0] & 0x0f
        let len = buf[1] & 0x7f
        let off = 2
        if (!(buf[1] & 0x80)) return socket.destroy()   // browsers always mask
        if (len === 126) {
          if (buf.length < 4) return
          len = buf.readUInt16BE(2)
          off = 4
        } else if (len === 127) {
          if (buf.length < 10) return
          const big = buf.readBigUInt64BE(2)
          if (big > BigInt(MAX_MESSAGE)) return socket.destroy()
          len = Number(big)
          off = 10
        }
        if (size + len > (conn.paired ? MAX_MESSAGE : 4096)) return socket.destroy()
        if (buf.length < off + 4 + len) return
        const mask = buf.subarray(off, off + 4)
        const data = Buffer.from(buf.subarray(off + 4, off + 4 + len))
        for (let i = 0; i < data.length; i++) data[i] ^= mask[i & 3]
        buf = buf.subarray(off + 4 + len)
        if (opcode === 0x8) return close()
        if (opcode === 0x9) { send(0xA, data); continue }
        if (opcode === 0xA) continue
        parts.push(data)
        size += len
        if (!fin) continue
        const text = Buffer.concat(parts).toString('utf8')
        parts = []
        size = 0
        for (const line of text.split('\n')) conn.line(line)
      }
    })
    const drop = () => { this.sockets.delete(socket); conn.drop() }
    socket.on('close', drop)
    socket.on('error', drop)
  }
}
