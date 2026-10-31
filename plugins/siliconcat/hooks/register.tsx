import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { Ask } from '../types'

const asks = atom({ plugin: 'siliconcat', key: 'asks' } as const, [] as Ask[])
const checkedAt = atom({ plugin: 'siliconcat', key: 'checkedAt' } as const, 0)
// asks a Yes was already sent for, by sig(); they stay hidden until the ask is closed
const pressed = atom({ plugin: 'siliconcat', key: 'pressed' } as const, [] as string[])

// req (linked there by the skill) finds the project's request store from the session's directory and prints nothing outside one.
const REQ_ASKS = ['bash', '-c', 'exec "$HOME/.local/share/director/bin/req" asks']
const SHOWN = 5

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

async function refresh($: EngineInterface): Promise<void> {
  const fetched = await fetchAsks($)
  const found = fetched ?? []
  const now = await $.clock.now()
  await update($, asks, () => found)
  await update($, checkedAt, () => now)
  if (fetched) await update($, pressed, p => p.filter(x => found.some(a => sig(a) === x)))
}

// Sends one approval for `targets` that `req asks` still lists with the same text, and hides their Yes buttons first so a second press cannot repeat it.
async function approve($: EngineInterface, targets: Ask[], message: (live: Ask[]) => string): Promise<void> {
  const sigs = targets.map(sig)
  await update($, pressed, p => [...p, ...sigs])
  const found = await fetchAsks($)
  if (!found) await update($, pressed, p => p.filter(x => !sigs.includes(x)))
  const live = targets.filter(t => found?.some(a => a.yesNo && sig(a) === sig(t)))
  // asUser: the person pressed the button, so the model reads their words, not "the plugin sent a message"
  if (live.length > 0) await $.prompt.submit({ text: message(live), asUser: true })
  await refresh($)
}

const keyOf = (prefix: string, i: number, a: Ask) => `${prefix}-${i}-${a.id}-${a.since}`

// No button takes a digit hotkey: a bare digit typed into an empty prompt presses a band Button, and a message that starts with one must stay a message.
export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const started = await next(e)
    await refresh($)
    $.clock.every(60_000, () => refresh($))
    return started
  })

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
    if (e.props.hasSurvey || list.length === 0) return drawn ?? next(e)

    const now = await read($, checkedAt)
    const done = await read($, pressed)
    const { Box, Button, Text } = $.ui.resolve(e)
    const shown = list.slice(0, SHOWN)

    const open = (a: Ask) => a.yesNo && !done.includes(sig(a))
    const yesToAll = async () => {
      const pending = await read($, pressed)
      const covered = (await read($, asks)).slice(0, SHOWN).filter(a => a.yesNo && !pending.includes(sig(a)))
      if (covered.length > 0) await approve($, covered, live => `yes to all: ${live.map(a => `${a.id} — ${a.text}`).join('; ')}`)
    }
    const coverable = shown.filter(open).length

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
                <Text wrap="truncate-end">
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
          {list.length > SHOWN ? <Text dimColor>+{list.length - SHOWN} more: req asks</Text> : null}
          <Text dimColor>ctrl+x tab to answer from here</Text>
        </Box>
        {below}
      </Box>
    )
  })
}
