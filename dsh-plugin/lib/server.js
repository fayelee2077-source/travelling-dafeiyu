// LAN link to the frame: a UDP beacon so the frame can find this computer (plus a unicast answer to the
// frame's own "where are you" broadcast, because many tablets drop incoming broadcasts while their Wi-Fi
// saves power), and a TCP server that streams newline-delimited JSON after a pairing code.
import net from 'node:net'
import dgram from 'node:dgram'
import os from 'node:os'

const HELLO_TIMEOUT_MS = 5000
const PING_MS = 5000
const BEACON_MS = 2000

export class FrameServer {
  /**
   * snapshot(): the state message sent on connecting; greet(): more fields for the welcome and messages sent
   * after it ({ welcome, messages }); onMessage(message): anything a paired frame sends besides tool answers.
   */
  constructor({ port, beaconPort, findPort, pairCode, logger, snapshot, greet = () => ({}), onMessage = () => {} }) {
    this.port = port
    this.beaconPort = beaconPort
    this.findPort = findPort
    this.pairCode = String(pairCode)
    this.logger = logger
    this.snapshot = snapshot
    this.greet = greet
    this.onMessage = onMessage
    this.clients = new Set()
    this.server = null
    this.beacon = null
    this.finder = null
    this.timers = []
    this.pending = new Map()
    this.seq = 0
  }

  /** Sends a command to the frame(s); resolves with the first reply, rejects when none is connected or answers. */
  request(message, timeoutMs = 4000) {
    if (this.clients.size === 0) return Promise.reject(new Error('no frame connected'))
    const id = String(++this.seq)
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => { this.pending.delete(id); reject(new Error('frame did not answer')) }, timeoutMs)
      this.pending.set(id, (reply) => { clearTimeout(timer); resolve(reply) })
      this.broadcast({ ...message, id })
    })
  }

  start() {
    this.server = net.createServer((socket) => this.#accept(socket))
    this.server.on('error', (error) => this.logger.warn?.(`living-dock: server error: ${error.message}`))
    this.server.listen(this.port, '0.0.0.0', () => this.logger.info?.(`living-dock: listening on ${this.port}`))

    const payload = Buffer.from(JSON.stringify({ t: 'living-dock', port: this.port, name: os.hostname() }))
    this.beacon = dgram.createSocket({ type: 'udp4', reuseAddr: true })
    this.beacon.on('error', (error) => this.logger.warn?.(`living-dock: beacon error: ${error.message}`))
    this.beacon.bind(() => {
      this.beacon.setBroadcast(true)
      const send = () => {
        for (const address of broadcastAddresses()) {
          this.beacon.send(payload, this.beaconPort, address, () => {})
        }
      }
      send()
      this.timers.push(setInterval(send, BEACON_MS))
    })
    this.timers.push(setInterval(() => this.broadcast({ t: 'ping' }), PING_MS))

    if (this.findPort) {
      this.finder = dgram.createSocket({ type: 'udp4', reuseAddr: true })
      this.finder.on('error', (error) => this.logger.warn?.(`living-dock: find error: ${error.message}`))
      this.finder.on('message', (data, rinfo) => {
        if (data.length > 256) return
        let message
        try { message = JSON.parse(data.toString('utf8')) } catch { return }
        if (message?.t === 'living-dock-find') this.finder.send(payload, rinfo.port, rinfo.address, () => {})
      })
      this.finder.bind(this.findPort, '0.0.0.0')
    }
  }

  stop() {
    for (const timer of this.timers) clearInterval(timer)
    this.timers = []
    this.broadcast({ t: 'bye' })
    for (const client of this.clients) client.end()
    this.clients.clear()
    this.server?.close()
    try { this.beacon?.close() } catch { /* already closed */ }
    try { this.finder?.close() } catch { /* already closed */ }
  }

  broadcast(message) {
    const line = JSON.stringify(message) + '\n'
    for (const client of this.clients) client.write(line)
  }

  #accept(socket) {
    socket.setNoDelay(true)
    socket.setEncoding('utf8')
    let buffer = ''
    const conn = this.connection({
      write: (line) => socket.write(line), end: () => socket.end(), destroy: () => socket.destroy(), from: socket.remoteAddress,
    })
    socket.on('data', (chunk) => {
      buffer += chunk
      if (buffer.length > (conn.paired ? 8 * 1024 * 1024 : 4096)) return socket.destroy()   // a photo is up to ~1 MB
      let index
      while ((index = buffer.indexOf('\n')) >= 0) {
        const line = buffer.slice(0, index)
        buffer = buffer.slice(index + 1)
        conn.line(line)
      }
    })
    socket.on('close', conn.drop)
    socket.on('error', conn.drop)
  }

  /** One frame connection, whatever carries it (TCP lines here, a web page's WebSocket in web.js). */
  connection(io) {
    let paired = false
    const timeout = setTimeout(() => { if (!paired) io.destroy() }, HELLO_TIMEOUT_MS)
    return {
      get paired() { return paired },
      line: (text) => {
        text = text.trim()
        if (!text) return
        let message
        try { message = JSON.parse(text) } catch { if (!paired) io.destroy(); return }
        if (paired) {
          // answers to the companion's tools
          if (message?.t === 'reply') {
            const done = this.pending.get(String(message.id))
            this.pending.delete(String(message.id))
            done?.(message)
          } else if (message && typeof message === 'object') {
            try { this.onMessage(message) } catch (error) { this.logger.warn?.(`living-dock: ${error.message}`) }
          }
          return
        }
        if (message?.t !== 'hello' || String(message.code) !== this.pairCode) {
          io.write(JSON.stringify({ t: 'denied' }) + '\n')
          return io.end()
        }
        paired = true
        clearTimeout(timeout)
        this.clients.add(io)
        this.logger.info?.(`living-dock: frame connected from ${io.from}`)
        const { welcome = {}, messages = [] } = this.greet()
        io.write(JSON.stringify({ t: 'welcome', name: os.hostname(), ...welcome }) + '\n')
        io.write(JSON.stringify(this.snapshot()) + '\n')
        for (const m of messages) io.write(JSON.stringify(m) + '\n')
      },
      drop: () => {
        clearTimeout(timeout)
        if (this.clients.delete(io)) this.logger.info?.('living-dock: frame disconnected')
      },
    }
  }
}

function broadcastAddresses() {
  const result = new Set(['255.255.255.255'])
  for (const list of Object.values(os.networkInterfaces())) {
    for (const item of list || []) {
      if (item.family !== 'IPv4' || item.internal) continue
      const ip = item.address.split('.').map(Number)
      const mask = item.netmask.split('.').map(Number)
      result.add(ip.map((part, i) => (part & mask[i]) | (~mask[i] & 255)).join('.'))
    }
  }
  return [...result]
}
