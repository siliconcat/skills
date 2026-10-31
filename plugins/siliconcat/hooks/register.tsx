import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { Ask } from '../types'

const asks = atom({ plugin: 'siliconcat', key: 'asks' } as const, [] as Ask[])
const checkedAt = atom({ plugin: 'siliconcat', key: 'checkedAt' } as const, 0)
// asks a Yes was already sent for, by sig(); they stay hidden until the ask is closed
const pressed = atom({ plugin: 'siliconcat', key: 'pressed' } as const, [] as string[])
// Only the session that loaded the director skill shows the band: a Yes pressed in any other session never reaches the director.
const director = atom({ plugin: 'siliconcat', key: 'director' } as const, false)
// Director session ids, in $.store so a resumed director session keeps its band.
const DIRECTOR_SESSIONS = 'directorSessions'
const KEPT_SESSIONS = 50

// req (linked there by the skill) finds the project's request store from the session's directory and prints nothing outside one.
const REQ_ASKS = ['bash', '-c', 'exec "$HOME/.local/share/director/bin/req" asks']
const SHOWN = 5
// A yes-no row is drawn whole, wrapped, so only a few of them go in the band.
const MAX_YES_NO = 3

export function visible(list: Ask[]): Ask[] {
  const out: Ask[] = []
  for (const a of list) {
    if (out.length === SHOWN || (a.yesNo && out.filter(x => x.yesNo).length === MAX_YES_NO)) break
    out.push(a)
  }
  return out
}

export function parse(stdout: string): Ask[] {
  return stdout
    .split('\n')
    .map(line => line.split('\t'))
    .filter(cols => cols.length >= 3 && /^R-\d{4}$/.test(cols[0] ?? ''))
    .map(([id = '', since = '', ...rest]) => {
      const kind = rest.length > 1 && /^(yes-no|open)$/.test(rest[rest.length - 1] ?? '') ? rest.pop() : 'open'
      return { id, since, text: rest.join(' '), yesNo: kind === 'yes-no' }
    })
}

export function age(since: string, now: number): string {
  const minutes = Math.max(0, Math.floor((now - Date.parse(since)) / 60_000))
  if (Number.isNaN(minutes)) return '?'
  if (minutes < 60) return `${minutes}m`
  if (minutes < 48 * 60) return `${Math.floor(minutes / 60)}h`
  return `${Math.floor(minutes / 1440)}d`
}

const sig = (a: Ask) => `${a.id}\t${a.since}\t${a.text}`

async function fetchAsks($: EngineInterface): Promise<Ask[] | null> {
  try {
    const { exitCode, stdout } = await $.process.run(REQ_ASKS, { timeoutMs: 5_000 })
    if (exitCode === 0) return parse(stdout)
  } catch {
    // a missing or slow req leaves the band empty rather than failing the turn
  }
  return null
}

// Asks a Yes was sent for and not yet closed, set before the press's first await so a second press at once finds them taken.
const held = new Set<string>()
// What the band last drew, so a press acts on the rows the user saw.
let drawnCoverable: Ask[] = []

async function directorSessions($: EngineInterface): Promise<string[]> {
  const ids = await $.store.get(DIRECTOR_SESSIONS)
  return Array.isArray(ids) ? ids.filter((x): x is string => typeof x === 'string') : []
}

async function refresh($: EngineInterface, keepOnFailure = false): Promise<void> {
  if (!(await read($, director))) return
  const fetched = await fetchAsks($)
  if (!fetched && keepOnFailure) return
  const found = fetched ?? []
  const now = await $.clock.now()
  await update($, asks, () => found)
  await update($, checkedAt, () => now)
  if (!fetched) return
  for (const x of held) if (!found.some(a => sig(a) === x)) held.delete(x)
  await update($, pressed, p => p.filter(x => found.some(a => sig(a) === x)))
}

async function release($: EngineInterface, sigs: string[]): Promise<void> {
  for (const x of sigs) held.delete(x)
  await update($, pressed, p => p.filter(x => !sigs.includes(x)))
}

// Sends one approval for `targets` that `req asks` still lists with the same text; their Yes buttons are hidden until the ask closes.
async function approve($: EngineInterface, targets: Ask[], message: (live: Ask[]) => string): Promise<void> {
  const fresh = targets.filter(t => !held.has(sig(t)))
  if (fresh.length === 0) return
  const sigs = fresh.map(sig)
  for (const x of sigs) held.add(x)
  await update($, pressed, p => [...p, ...sigs])
  const found = await fetchAsks($)
  const live = fresh.filter(t => found?.some(a => a.yesNo && sig(a) === sig(t)))
  if (live.length > 0) {
    try {
      // asUser: the person pressed the button, so the model reads their words, not "the plugin sent a message"
      await $.prompt.submit({ text: message(live), asUser: true })
    } catch {
      await release($, sigs)
    }
  } else if (!found) await release($, sigs)
  await refresh($, true)
}

const keyOf = (prefix: string, i: number, a: Ask) => `${prefix}-${i}-${a.id}-${a.since}`

// No button takes a digit hotkey: a bare digit typed into an empty prompt presses a band Button, and a message that starts with one must stay a message.
export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const started = await next(e)
    if ((await directorSessions($)).includes(await $.session.id())) await update($, director, () => true)
    await refresh($)
    $.clock.every(60_000, () => refresh($))
    return started
  })

  on('skill.prompt', async ($, e, next) => {
    const loaded = await next(e)
    if (e.pluginName === 'siliconcat' && /(^|:)director$/.test(e.skill)) {
      const id = await $.session.id()
      const ids = await directorSessions($)
      if (!ids.includes(id)) await $.store.set(DIRECTOR_SESSIONS, [...ids, id].slice(-KEPT_SESSIONS))
      await update($, director, () => true)
      await refresh($)
    }
    return loaded
  }).catch(($, e, next) => next(e))

  on('turn.complete', async ($, e, next) => {
    const done = await next(e)
    await refresh($)
    return done
  })

  on('tool.call', { tool: 'Bash' }, async ($, e, next) => {
    const ran = await next(e)
    if (/\breq\b/.test(e.command)) await refresh($)
    return ran
  }).catch(($, e, next) => next(e))

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    // Draw ours above whatever the other plugins draw; the engine's own placeholder is never nested.
    const drawn = await Promise.resolve(next(e)).catch(() => null)
    const below = drawn && typeof drawn === 'object' && (drawn as { type?: string }).type !== 'engine' ? drawn : null
    const list = await read($, asks)
    if (e.props.hasSurvey || list.length === 0 || !(await read($, director))) return drawn ?? next(e)

    const now = await read($, checkedAt)
    const done = await read($, pressed)
    const { Box, Button, Text } = $.ui.resolve(e)
    const shown = visible(list)

    const open = (a: Ask) => a.yesNo && !done.includes(sig(a))
    const yesToAll = () =>
      approve($, drawnCoverable, live => `yes to all: ${live.map(a => `${a.id} — ${a.text}`).join('; ')}`)
    drawnCoverable = shown.filter(open)
    const coverable = drawnCoverable.length

    return (
      <Box flexDirection="column">
        <Box flexDirection="column" borderStyle="round" borderColor="warning">
          <Box flexDirection="row" gap={1}>
            <Text color="warning" weight="bold">
              Waiting on you ({list.length})
            </Text>
            {coverable > 1 ? (
              <Button key="yes-all" label={`Yes to all (${coverable})`} hotkey="a" plain onPress={yesToAll} />
            ) : null}
          </Box>
          {shown.map((a, i) => (
            <Box key={keyOf('row', i, a)} flexDirection="row" gap={1}>
              <Box flexShrink={1}>
                <Text wrap={a.yesNo ? 'wrap' : 'truncate-end'}>
                  <Text dimColor>
                    {a.id} · {age(a.since, now)} ·{' '}
                  </Text>
                  {a.text}
                </Text>
              </Box>
              {open(a) ? (
                <Button key={keyOf('yes', i, a)} label="Yes" onPress={() => approve($, [a], ([x]) => `${x?.id}: yes — ${x?.text}`)} />
              ) : null}
              <Button
                key={keyOf('answer', i, a)}
                label="Answer"
                autoFocus={i === 0 ? true : undefined}
                onPress={async () => {
                  await $.prompt.fill({ text: `${a.id}: `, mode: 'insert' })
                  await refresh($)
                }}
              />
            </Box>
          ))}
          {list.length > shown.length ? <Text dimColor>+{list.length - shown.length} more: req asks</Text> : null}
          <Text dimColor>ctrl+x tab to answer from here</Text>
        </Box>
        {below}
      </Box>
    )
  })
}
