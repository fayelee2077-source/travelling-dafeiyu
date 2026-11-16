// Notes on the coffee table (补充条款四·修订一、修订二): a folder anyone at home can drop .txt notes into, who left
// it first in the file name (妈妈_11月13日.txt). The plugin reads only this folder and only its .txt files, never
// changes or deletes them; she hears the ones she has not read when she uses her tools in the little home, and
// can leave one herself (大肥鱼_11月13日_0930.txt). What she has read is kept in the home record.
import fs from 'node:fs'
import path from 'node:path'

export const MAX_CHARS = 300
const PER_LOOK = 5
const MINE = '大肥鱼'
const SHOW_MINE = 86400        // her own note stays on the table this long (seconds)
const MAX_READ = 65536

const pad = (n) => String(n).padStart(2, '0')
/** "11月9日" from a unix time (local). */
export const dayText = (t) => { const d = new Date(t * 1000); return `${d.getMonth() + 1}月${d.getDate()}日` }

export class Notes {
  /** dir: the notes folder ('' = none); record: { data: {notes_read, note_left}, now() } of the home record. */
  constructor(dir, record) {
    this.dir = dir
    this.record = record
  }

  /** Notes she has not read, oldest first: [{file, time}]. A note edited after she read it counts as new. */
  unread() {
    if (!this.dir) return []
    let files
    try { files = fs.readdirSync(this.dir, { withFileTypes: true }) } catch { return [] }
    const read = this.record.data.notes_read
    const out = []
    for (const f of files) {
      if (!f.isFile() || path.extname(f.name).toLowerCase() !== '.txt') continue
      let time
      try { time = Math.floor(fs.statSync(path.join(this.dir, f.name)).mtimeMs / 1000) } catch { continue }
      if (Number(read[f.name] ?? -1) !== time) out.push({ file: f.name, time })
    }
    return out.sort((a, b) => a.time - b.time)
  }

  /** Up to PER_LOOK unread notes for her to read now ({from, day, text}); they count as read from here on. */
  take() {
    const out = []
    for (const n of this.unread().slice(0, PER_LOOK)) {
      const name = n.file.slice(0, -path.extname(n.file).length)
      out.push({ from: name.split('_')[0] || name, day: dayText(n.time), text: noteText(path.join(this.dir, n.file)) })
      this.record.data.notes_read[n.file] = n.time
    }
    return out
  }

  /** She leaves a note on the table. False if it could not be written. */
  write(text) {
    if (!this.dir) return false
    const d = new Date(this.record.now() * 1000)
    const base = `${MINE}_${d.getMonth() + 1}月${d.getDate()}日_${pad(d.getHours())}${pad(d.getMinutes())}`
    let file = `${base}.txt`
    for (let i = 2; fs.existsSync(path.join(this.dir, file)); i++) file = `${base}_${i}.txt`
    try {
      fs.mkdirSync(this.dir, { recursive: true })
      fs.writeFileSync(path.join(this.dir, file), text, { flag: 'wx' })
      this.record.data.notes_read[file] = Math.floor(fs.statSync(path.join(this.dir, file)).mtimeMs / 1000)
    } catch { return false }
    this.record.data.note_left = this.record.now()
    return true
  }

  /** What the window shows: how many she has not read, and whether a note lies on the table. */
  state() {
    const unread = this.unread().length
    return { unread, on_table: unread > 0 || this.record.now() - Number(this.record.data.note_left || 0) < SHOW_MINE }
  }
}

/** The note's words: UTF-8, on one line, at most MAX_CHARS. */
export function noteText(file) {
  let s
  try {
    const fd = fs.openSync(file, 'r')
    const buf = Buffer.alloc(MAX_READ)
    const n = fs.readSync(fd, buf, 0, MAX_READ, 0)
    fs.closeSync(fd)
    s = buf.subarray(0, n).toString('utf8')
  } catch { return '' }
  let one = ''
  for (let line of s.replace(/^\uFEFF/, '').replace(/\r/g, '').split('\n')) {
    line = line.trim()
    // Chinese lines join straight on; a space only between Latin words
    if (line) one += (one && one.codePointAt(one.length - 1) < 0x2E80 ? ' ' : '') + line
  }
  const chars = [...one]
  return chars.slice(0, MAX_CHARS).join('') + (chars.length > MAX_CHARS ? '……' : '')
}
