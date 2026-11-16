// node --test test/
import test from 'node:test'
import assert from 'node:assert/strict'
import { Reducer } from '../lib/reducer.js'

function setup() {
  let now = 0
  const reducer = new Reducer({ now: () => now })
  return { reducer, advance: (ms) => { now += ms } }
}
const chat = { header: { id: 'onebot-private-1-x' } }
const group = { header: { id: 'onebot-group-1-x' } }
const work = { header: { id: 'abc' } }
const ev = (type, data = {}) => ({ type, data })

test('chat text never appears in output', () => {
  const { reducer } = setup()
  const out = [
    ...reducer.handle(chat, ev('turn/start')),
    ...reducer.handle(chat, ev('user/message', { content: [{ type: 'text', text: 'PRIVATE-IN' }] })),
    ...reducer.handle(chat, ev('assistant/message', { message: { content: [{ type: 'text', text: 'PRIVATE-OUT' }] } })),
  ]
  const text = JSON.stringify(out)
  assert.ok(!text.includes('PRIVATE'))
  assert.deepEqual(out.filter((m) => m.t === 'chat').map((m) => m.dir), ['in', 'out'])
})

test('group chats are ignored', () => {
  const { reducer } = setup()
  assert.deepEqual(reducer.handle(group, ev('turn/start')), [])
  assert.equal(reducer.current().state, 'idle')
})

test('work flow: thinking, working, waiting, done, back to idle', () => {
  const { reducer, advance } = setup()
  reducer.handle(work, ev('turn/start'))
  assert.equal(reducer.current().state, 'thinking')
  reducer.handle(work, ev('tool/call', { name: 'edit_file', callId: 'c' }))
  assert.deepEqual([reducer.current().state, reducer.current().activity], ['working', 'editing'])
  reducer.handle(work, ev('approval/asked', { id: 'a' }))
  assert.equal(reducer.current().state, 'waiting')
  reducer.handle(work, ev('approval/decided', { id: 'a' }))
  assert.deepEqual([reducer.current().state, reducer.current().activity], ['working', 'editing'])
  reducer.handle(work, ev('tool/result', { callId: 'c' }))
  reducer.handle(work, ev('turn/end', { reason: { kind: 'completed' } }))
  assert.equal(reducer.current().state, 'done')
  advance(5000)
  assert.equal(reducer.current().state, 'idle')
})

test('waiting outranks chatting outranks working', () => {
  const { reducer } = setup()
  reducer.handle(work, ev('tool/call', { name: 'shell', callId: 'c' }))
  reducer.handle(chat, ev('turn/start'))
  assert.equal(reducer.current().state, 'chatting')
  reducer.handle(work, ev('approval/asked', { id: 'a' }))
  assert.equal(reducer.current().state, 'waiting')
})

test('subagents are ignored', () => {
  const { reducer } = setup()
  assert.deepEqual(reducer.handle({ header: { id: 's', origin: 'subagent' } }, ev('turn/start')), [])
})
