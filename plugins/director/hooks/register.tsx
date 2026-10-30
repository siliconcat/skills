import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { Ask } from '../types'

const asks = atom({ plugin: 'director', key: 'asks' } as const, [] as Ask[])
const checkedAt = atom({ plugin: 'director', key: 'checkedAt' } as const, 0)

// req (linked there by the skill) finds the project's request store from the session's directory and prints nothing outside one.
const REQ_ASKS = ['bash', '-c', 'exec "$HOME/.local/share/director/bin/req" asks']
const SHOWN = 5

export function parse(stdout: string): Ask[] {
  return stdout
    .split('\n')
    .map(line => line.split('\t'))
    .filter(cols => cols.length >= 3 && /^R-\d{4}$/.test(cols[0] ?? ''))
    .map(([id = '', since = '', ...text]) => ({ id, since, text: text.join(' ') }))
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
    const list = await read($, asks)
    if (e.props.hasSurvey || list.length === 0) return next(e)

    const now = await read($, checkedAt)
    const { Box, Text } = $.ui.resolve(e)

    return (
      <Box flexDirection="column" borderStyle="round" borderColor="warning">
        <Text color="warning" weight="bold">
          Waiting on you ({list.length})
        </Text>
        {list.slice(0, SHOWN).map(a => (
          <Text key={`${a.id}-${a.since}`} wrap="truncate-end">
            <Text dimColor>
              {a.id} · {age(a.since, now)} ·{' '}
            </Text>
            {a.text}
          </Text>
        ))}
        {list.length > SHOWN ? <Text dimColor>+{list.length - SHOWN} more: req asks</Text> : null}
      </Box>
    )
  })
}
