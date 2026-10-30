import { expect, test } from 'claude-code/testing'

import { age, parse } from './register'

const BAND = {
  plugin: 'director',
  component: 'AbovePrompt',
  props: {
    hasSurvey: false,
    isWorking: false,
    maxRows: 20,
    bodyColumns: 80,
    scroll: { offset: 0, bodyRows: 20 },
    view: {},
  },
} as const

const NOW = Date.parse('2026-10-30T16:00Z')

test('parse reads req asks and skips anything else', async () => {
  expect(parse('R-0005\t2026-10-30T15:40Z\tapprove merging #96\nnoise\n')).toEqual([
    { id: 'R-0005', since: '2026-10-30T15:40Z', text: 'approve merging #96' },
  ])
  expect(parse('')).toEqual([])
})

test('age reads minutes, hours, then days', async () => {
  expect(age('2026-10-30T15:40Z', NOW)).toBe('20m')
  expect(age('2026-10-30T10:00Z', NOW)).toBe('6h')
  expect(age('2026-10-27T16:00Z', NOW)).toBe('3d')
})

test('the band lists what the director waits on, on every surface', async ($, on) => {
  on('process.run', () => ({
    value: { exitCode: 0, stdout: 'R-0005\t2026-10-30T15:40Z\tapprove merging #96\n', stderr: '' },
  }))
  on('clock.now', () => ({ value: NOW }))
  on('clock.every', () => ({ value: undefined }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))

  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ ...BAND, surface })
    expect((await ui.find({ type: 'Text', text: /Waiting on you \(1\)/ }))?.text).toBe('Waiting on you (1)')
    expect((await ui.find({ type: 'Text', text: /approve merging #96/ }))?.text).toBe('R-0005 · 20m · approve merging #96')
    await ui.unmount()
  }
})

test('no asks, no band', async ($, on) => {
  on('process.run', () => ({ value: { exitCode: 0, stdout: '', stderr: '' } }))
  on('clock.now', () => ({ value: NOW }))
  on('clock.every', () => ({ value: undefined }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>engine</Text>
  })

  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })

  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /Waiting on you/ })).toBe(undefined)
  await ui.unmount()
})
