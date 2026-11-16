// Turns DSH session events into what the companion is doing, for the frame.
// Privacy by design: chat text never leaves this module; chats only produce
// "a message came in" / "a reply went out" signals.

export const State = Object.freeze({
  IDLE: 'idle',
  THINKING: 'thinking',
  WORKING: 'working',
  WAITING: 'waiting',
  DONE: 'done',
  ERROR: 'error',
  CHATTING: 'chatting',
})

const PRIORITY = {
  waiting: 60,
  error: 50,
  chatting: 40,
  working: 30,
  thinking: 20,
  done: 10,
  idle: 0,
}

const TRANSIENT_MS = { done: 4000, error: 6000 }

export function toolActivity(name) {
  const value = String(name || '').toLowerCase()
  if (/search|grep|find|glob|web|read|fetch|open|list/.test(value)) return 'searching'
  if (/write|edit|patch|replace|create|move|delete/.test(value)) return 'editing'
  if (/test|check|lint|build|verify/.test(value)) return 'testing'
  if (/shell|bash|exec|command|terminal|powershell|pwsh/.test(value)) return 'commanding'
  return 'tool'
}

function compile(patterns) {
  return (patterns || []).map((p) => new RegExp(p))
}

function sessionIdOf(session) {
  return String(session?.header?.id ?? session?.id ?? 'unknown')
}

function isSubagent(session) {
  return session?.header?.origin === 'subagent' || Number(session?.header?.delegationDepth ?? 0) > 0
}

function hasReplyText(message) {
  const content = message?.content
  if (typeof content === 'string') return content.trim().length > 0
  if (!Array.isArray(content)) return false
  return content.some((part) => part?.type === 'text' && String(part.text || '').trim().length > 0)
}

export class Reducer {
  constructor(options = {}) {
    this.chat = compile(options.chatSessions ?? ['^onebot-private-'])
    this.ignore = compile(options.ignoreSessions ?? ['^onebot-group-'])
    this.now = options.now ?? (() => Date.now())
    this.sessions = new Map()
    this.last = null
  }

  kindOf(id) {
    if (this.ignore.some((re) => re.test(id))) return 'ignore'
    if (this.chat.some((re) => re.test(id))) return 'chat'
    return 'work'
  }

  #record(id) {
    let r = this.sessions.get(id)
    if (!r) {
      r = { id, kind: this.kindOf(id), state: State.IDLE, activity: undefined, until: 0, at: 0, tools: new Map() }
      this.sessions.set(id, r)
    }
    return r
  }

  #set(r, state, activity) {
    r.state = state
    r.activity = activity
    r.at = this.now()
    r.until = TRANSIENT_MS[state] ? r.at + TRANSIENT_MS[state] : 0
  }

  /** Returns the list of messages to send to the frame for this event. */
  handle(session, event) {
    if (!event || typeof event.type !== 'string' || isSubagent(session)) return []
    const id = sessionIdOf(session)
    const r = this.#record(id)
    if (r.kind === 'ignore') return []
    const out = []

    switch (event.type) {
      case 'turn/start':
        r.tools.clear()
        if (r.kind === 'chat') {
          this.#set(r, State.CHATTING, 'reading')
          out.push({ t: 'chat', dir: 'in' })
        } else {
          this.#set(r, State.THINKING)
        }
        break
      case 'assistant/message':
        if (r.kind === 'chat') {
          if (hasReplyText(event.data?.message)) {
            this.#set(r, State.CHATTING, 'replying')
            out.push({ t: 'chat', dir: 'out' })
          }
        } else if (r.tools.size === 0 && r.state !== State.WAITING) {
          this.#set(r, State.THINKING)
        }
        break
      case 'tool/call': {
        const name = String(event.data?.name ?? event.data?.message?.name ?? 'tool')
        const callId = String(event.data?.callId ?? event.data?.message?.callId ?? event.seq ?? name)
        r.tools.set(callId, name)
        if (r.kind === 'chat') this.#set(r, State.CHATTING, 'busy')
        else this.#set(r, State.WORKING, toolActivity(name))
        break
      }
      case 'tool/result': {
        const callId = String(event.data?.callId ?? event.data?.message?.source?.callId ?? '')
        if (callId) r.tools.delete(callId)
        if (r.kind === 'work' && r.state !== State.WAITING) {
          const next = r.tools.values().next().value
          if (next) this.#set(r, State.WORKING, toolActivity(next))
          else this.#set(r, State.THINKING)
        }
        break
      }
      case 'approval/asked':
        this.#set(r, State.WAITING)
        break
      case 'approval/decided':
        if (r.state === State.WAITING) {
          const open = r.tools.values().next().value
          if (r.kind === 'chat') this.#set(r, State.CHATTING, 'busy')
          else if (open) this.#set(r, State.WORKING, toolActivity(open))
          else this.#set(r, State.THINKING)
        }
        break
      case 'turn/end': {
        r.tools.clear()
        const kind = String(event.data?.reason?.kind ?? 'completed')
        if (r.kind === 'chat') this.#set(r, State.IDLE)
        else if (kind === 'completed') this.#set(r, State.DONE)
        else if (kind === 'aborted' || kind === 'interrupted') this.#set(r, State.IDLE)
        else if (kind === 'blocked') this.#set(r, State.WAITING)
        else this.#set(r, State.ERROR)
        break
      }
      default:
        return []
    }
    return out.concat(this.snapshotIfChanged())
  }

  disposeSession(session) {
    this.sessions.delete(sessionIdOf(session))
    return this.snapshotIfChanged()
  }

  /** Call periodically so transient states (done, error) fall back to idle. */
  tick() {
    return this.snapshotIfChanged()
  }

  current() {
    const t = this.now()
    let best = { state: State.IDLE, activity: undefined, source: 'none', at: 0 }
    for (const r of this.sessions.values()) {
      let state = r.state
      if (r.until && t >= r.until) {
        r.state = State.IDLE
        r.until = 0
        state = State.IDLE
      }
      if (state === State.IDLE) continue
      const better = PRIORITY[state] > PRIORITY[best.state]
        || (PRIORITY[state] === PRIORITY[best.state] && r.at > best.at)
      if (better) best = { state, activity: r.activity, source: r.kind, at: r.at }
    }
    return { t: 'state', state: best.state, activity: best.activity ?? null, source: best.source }
  }

  snapshotIfChanged() {
    const cur = this.current()
    const key = `${cur.state}|${cur.activity}|${cur.source}`
    if (key === this.last) return []
    this.last = key
    return [cur]
  }
}
