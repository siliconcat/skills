import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { Ask } from '../types'

const asks = atom({ plugin: 'siliconcat', key: 'asks' } as const, [] as Ask[])
const checkedAt = atom({ plugin: 'siliconcat', key: 'checkedAt' } as const, 0)

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

async function refresh($: EngineInterface): Promise<void> {
  let found: Ask[] = []
  try {
    const { exitCode, stdout } = await $.process.run(REQ_ASKS, { timeoutMs: 5_000 })
    if (exitCode === 0) found = parse(stdout)
  } catch {
    // a missing or slow req leaves the band empty rather than failing the turn
  }
  const now = await $.clock.now()
  await update($, asks, () => found)
  await update($, checkedAt, () => now)
}

const keyOf = (prefix: string, a: Ask) => `${prefix}-${a.id}-${a.since}`

// Approving buttons get no digit hotkey: a bare digit typed into an empty prompt presses a band Button.
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
    const { Box, Button, Text } = $.ui.resolve(e)
    const shown = list.slice(0, SHOWN)

    const send = async (text: string) => {
      await $.prompt.submit({ text, asUser: true })
      await refresh($)
    }
    const yesToAll = async () => {
      const covered = (await read($, asks)).slice(0, SHOWN).filter(a => a.yesNo)
      if (covered.length > 0) await send(`yes to all: ${covered.map(a => `${a.id} — ${a.text}`).join('; ')}`)
    }

    return (
      <Box flexDirection="column">
        <Box flexDirection="column" borderStyle="round" borderColor="warning">
          <Box flexDirection="row" gap={1}>
            <Text color="warning" weight="bold">
              Waiting on you ({list.length})
            </Text>
            {shown.filter(a => a.yesNo).length > 1 ? (
              <Button key="yes-all" label="Yes to all" hotkey="a" plain onPress={yesToAll} />
            ) : null}
          </Box>
          {shown.map((a, i) => (
            <Box key={keyOf('row', a)} flexDirection="row" gap={1}>
              <Box flexShrink={1}>
                <Text wrap="truncate-end">
                  <Text dimColor>
                    {a.id} · {age(a.since, now)} ·{' '}
                  </Text>
                  {a.text}
                </Text>
              </Box>
              {a.yesNo ? (
                <Button key={keyOf('yes', a)} label="Yes" onPress={() => send(`${a.id}: yes — ${a.text}`)} />
              ) : null}
              <Button
                key={keyOf('answer', a)}
                label="Answer"
                hotkey={String(i + 1)}
                plain
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
