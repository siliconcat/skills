import { expect, test } from 'claude-code/testing'

import { age, parse, visible } from './register'

const BAND = {
  plugin: 'siliconcat',
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

type B = { key?: string; props: Record<string, unknown> }
const NOW = Date.parse('2026-10-30T16:00Z')

// Stands in for the session id, the skill loader and $.store; returns the store so a test can read what was kept.
function session(on: any, id = 's-1', store: Record<string, unknown> = {}) {
  on('session.id', () => ({ value: id }))
  on('skill.prompt', (_: any, e: any) => ({ text: e.text }))
  on('store.get', (_: any, e: any) => ({ value: store[e.key] }))
  on('store.set', (_: any, e: any) => {
    store[e.key] = e.value
    return { value: undefined }
  })
  return store
}

const loadDirector = ($: any) => $.skill.prompt({ skill: 'siliconcat:director', text: '', pluginName: 'siliconcat' })

test('parse reads req asks and skips anything else', async () => {
  expect(parse('R-0005\t2026-10-30T15:40Z\tapprove merging #96\nnoise\n')).toEqual([
    { id: 'R-0005', since: '2026-10-30T15:40Z', text: 'approve merging #96', yesNo: false },
  ])
  expect(parse('')).toEqual([])
})

test('parse reads the kind column and treats a missing one as open', async () => {
  expect(parse('R-0007\t2026-10-30T15:40Z\tmerge #97?\tyes-no\nR-0008\t2026-10-30T15:41Z\tpick a name\topen\nR-0009\t2026-10-30T15:42Z\tolder\n')).toEqual([
    { id: 'R-0007', since: '2026-10-30T15:40Z', text: 'merge #97?', yesNo: true },
    { id: 'R-0008', since: '2026-10-30T15:41Z', text: 'pick a name', yesNo: false },
    { id: 'R-0009', since: '2026-10-30T15:42Z', text: 'older', yesNo: false },
  ])
})

test('age reads minutes, hours, then days', async () => {
  expect(age('2026-10-30T15:40Z', NOW)).toBe('20m')
  expect(age('2026-10-30T10:00Z', NOW)).toBe('6h')
  expect(age('2026-10-27T16:00Z', NOW)).toBe('3d')
})

test('the band lists what the director waits on, on every surface', async ($, on) => {
  on('process.run', () => ({
    value: { exitCode: 0, stdout: 'R-0005\t2026-10-30T15:40Z\tapprove merging #96\topen\n', stderr: '' },
  }))
  on('clock.now', () => ({ value: NOW }))
  on('clock.every', () => ({ value: undefined }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>engine</Text>
  })

  session(on)
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  await loadDirector($)

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

  session(on)
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  await loadDirector($)

  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /Waiting on you/ })).toBe(undefined)
  await ui.unmount()
})

const ASKS = [
  'R-0007\t2026-10-30T15:40Z\tmerge #97?\tyes-no',
  'R-0006\t2026-10-30T15:41Z\tpick a name\topen',
  'R-0004\t2026-10-30T15:42Z\tdeploy to dev?\tyes-no',
].join('\n')

async function band($: any, on: any, stdout: string, opts: { submitFails?: boolean } = {}) {
  let code = 0
  const sent: string[] = []
  const filled: { text: string; mode?: string }[] = []
  on('process.run', () => ({ value: { exitCode: code, stdout, stderr: '' } }))
  on('clock.now', () => ({ value: NOW }))
  // never resolves, so the 60 s interval does not loop as fast as the stand-in answers
  on('clock.every', () => new Promise(() => {}))
  on('session.start', (_: any, e: any) => ({ cwd: e.cwd }))
  on('prompt.submit', (_: any, e: any) => {
    if (opts.submitFails) throw new Error('refused')
    sent.push(e.text)
    return { text: e.text }
  })
  on('prompt.fill', (_: any, e: any) => {
    filled.push({ text: e.text, mode: e.mode })
    return { isFilled: true, text: e.text, cursor: e.text.length }
  })
  on('ui.render', ($: any, e: any) => {
    const { Text } = $.ui.resolve(e)
    return <Text>engine</Text>
  })
  session(on)
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  await loadDirector($)
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  return { ui, sent, filled, set: (s: string) => (stdout = s), reqDown: () => (code = 1) }
}

test('the band stacks above what the other plugins draw', async ($, on) => {
  const { ui } = await band($, on, ASKS)
  expect(await ui.find({ type: 'Text', text: /Waiting on you \(3\)/ })).toBeDefined()
  expect((await ui.find({ type: 'Text', text: /^engine$/ }))?.text).toBe('engine')
  await ui.unmount()
})

test('Yes is only on yes-no asks and submits the ask with the answer', async ($, on) => {
  const { ui, sent } = await band($, on, ASKS)
  expect(await ui.findAll({ type: 'Button', text: /^Yes$/ })).toHaveLength(2)
  expect(await ui.findAll({ type: 'Button', text: /^Answer$/ })).toHaveLength(3)

  const yes = await ui.findAll({ type: 'Button', text: /^Yes$/ })
  await ui.press({ key: yes[1].key })
  expect(sent).toEqual(['R-0004: yes — deploy to dev?'])
  await ui.unmount()
})

test('Answer puts the id into the prompt without losing the draft', async ($, on) => {
  const { ui, filled } = await band($, on, ASKS)
  const answers = await ui.findAll({ type: 'Button', text: /^Answer$/ })
  await ui.press({ key: answers[1].key })
  expect(filled).toEqual([{ text: 'R-0006: ', mode: 'insert' }])
  await ui.unmount()
})

test('Yes to all lists the yes-no asks drawn, never an open one', async ($, on) => {
  const { ui, sent } = await band($, on, ASKS)
  await ui.press({ key: 'yes-all' })
  expect(sent).toEqual(['yes to all: R-0007 — merge #97?; R-0004 — deploy to dev?'])
  await ui.unmount()
})

test('no Yes to all for a single yes-no ask', async ($, on) => {
  const { ui } = await band($, on, ASKS.split('\n').slice(0, 2).join('\n'))
  expect(await ui.find({ type: 'Button', text: /Yes to all/ })).toBe(undefined)
  expect(await ui.findAll({ type: 'Button', text: /Yes$/ })).toHaveLength(1)
  await ui.unmount()
})

test('Yes to all leaves out a yes-no ask scrolled into +N more', async ($, on) => {
  const rows = Array.from({ length: 7 }, (_, i) => `R-001${i}\t2026-10-30T15:4${i}Z\tq${i}\tyes-no`)
  const { ui, sent } = await band($, on, rows.join('\n'))
  await ui.press({ key: 'yes-all' })
  expect(sent).toEqual(['yes to all: R-0010 — q0; R-0011 — q1; R-0012 — q2'])
  await ui.unmount()
})

test('a press refreshes the asks', async ($, on) => {
  let stdout = ASKS
  const sent: string[] = []
  on('process.run', () => ({ value: { exitCode: 0, stdout, stderr: '' } }))
  on('clock.now', () => ({ value: NOW }))
  on('clock.every', () => ({ value: undefined }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('prompt.submit', (_, e) => {
    sent.push(e.text)
    stdout = ''
    return { text: e.text }
  })
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>engine</Text>
  })
  session(on)
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  await loadDirector($)
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  await ui.press({ key: 'yes-all' })
  expect(await ui.find({ type: 'Text', text: /Waiting on you/ })).toBe(undefined)
  await ui.unmount()
})

test('buttons are reachable from the keyboard and no approving button takes a digit', async ($, on) => {
  const { ui } = await band($, on, ASKS)

  const buttons = await ui.findAll({ type: 'Button' })
  const yes = buttons.filter((b: B) => /^yes-/.test(b.key ?? ''))
  expect(yes).toHaveLength(3)
  for (const b of yes) expect(String(b.props.hotkey ?? '')).not.toMatch(/\d/)
  expect(buttons.find((b: B) => b.key === 'yes-all')?.props.hotkey).toBe('a')

  const answers = buttons.filter((b: B) => /^answer-/.test(b.key ?? ''))
  expect(answers.map((b: B) => b.props.hotkey)).toEqual([undefined, undefined, undefined])
  for (const b of buttons) expect(String(b.props.hotkey ?? '')).not.toMatch(/\d/)
  expect(answers.map((b: B) => b.props.autoFocus)).toEqual([true, undefined, undefined])
  expect(buttons.filter((b: B) => b.props.autoFocus)).toHaveLength(1)

  expect(await ui.find({ type: 'Text', text: /ctrl\+x tab to answer from here/ })).toBeDefined()
  await ui.unmount()
})

test('two asks of one request in the same minute get their own buttons', async ($, on) => {
  const { ui, sent } = await band(
    $,
    on,
    'R-0007\t2026-10-30T15:40Z\tapprove merging #96\tyes-no\nR-0007\t2026-10-30T15:40Z\tapprove deploy to prod\tyes-no'
  )
  const keys = (await ui.findAll({ type: 'Button' })).map((b: B) => b.key)
  expect(new Set(keys).size).toBe(keys.length)

  const yes = await ui.findAll({ type: 'Button', text: /^Yes$/ })
  await ui.press({ key: yes[1].key })
  expect(sent).toEqual(['R-0007: yes — approve deploy to prod'])
  await ui.unmount()
})

test('Yes to all says how many asks it covers', async ($, on) => {
  const { ui } = await band($, on, ASKS)
  expect((await ui.find({ type: 'Button', text: /Yes to all/ }))?.text).toMatch(/Yes to all \(2\)/)
  await ui.unmount()
})

test('a Yes for an ask that is gone or reworded sends nothing', async ($, on) => {
  const gone = await band($, on, ASKS)
  const yes = await gone.ui.findAll({ type: 'Button', text: /^Yes$/ })
  gone.set('R-0007\t2026-10-30T15:40Z\tmerge #97 and drop the table\tyes-no\nR-0006\t2026-10-30T15:41Z\tpick a name\topen')
  await gone.ui.press({ key: yes[0].key })
  expect(gone.sent).toEqual([])
  await gone.ui.unmount()
})

test('Yes to all sends only the asks still open at press time', async ($, on) => {
  const { ui, sent, set } = await band($, on, ASKS)
  await ui.findAll({ type: 'Button' })
  set('R-0007\t2026-10-30T15:40Z\tmerge #97?\tyes-no\nR-0006\t2026-10-30T15:41Z\tpick a name\topen')
  await ui.press({ key: 'yes-all' })
  expect(sent).toEqual(['yes to all: R-0007 — merge #97?'])
  await ui.unmount()
})

test('a pressed Yes is hidden, so a second press cannot approve twice', async ($, on) => {
  const { ui, sent } = await band($, on, ASKS)
  const yes = await ui.findAll({ type: 'Button', text: /^Yes$/ })
  await ui.press({ key: yes[0].key })
  expect(await ui.findAll({ type: 'Button', text: /^Yes$/ })).toHaveLength(1)
  expect(await ui.find({ type: 'Button', text: /Yes to all/ })).toBe(undefined)
  await ui.press({ key: 'yes-all' }).catch(() => undefined)
  expect(sent).toEqual(['R-0007: yes — merge #97?'])
  await ui.unmount()
})

test('Yes to all then hides every Yes it covered', async ($, on) => {
  const { ui, sent } = await band($, on, ASKS)
  await ui.press({ key: 'yes-all' })
  expect(await ui.findAll({ type: 'Button', text: /^Yes$/ })).toHaveLength(0)
  expect(sent).toHaveLength(1)
  await ui.unmount()
})

test('visible stops at five asks or the fourth yes-no ask, in order', async () => {
  const a = (id: string, yesNo: boolean) => ({ id, since: 's', text: id, yesNo })
  const many = [a('R-1', false), a('R-2', true), a('R-3', true), a('R-4', true), a('R-5', true), a('R-6', false)]
  expect(visible(many).map(x => x.id)).toEqual(['R-1', 'R-2', 'R-3', 'R-4'])
  expect(visible([1, 2, 3, 4, 5, 6].map(n => a(`R-${n}`, false)))).toHaveLength(5)
})

test('a yes-no row wraps so all of its text is on screen; an open row may truncate', async ($, on) => {
  const { ui } = await band($, on, ASKS)
  const texts = await ui.findAll({ type: 'Text' })
  const wrapOf = (re: RegExp) => texts.find((t: { text: string }) => re.test(t.text))?.props.wrap
  expect(wrapOf(/merge #97\?/)).toBe('wrap')
  expect(wrapOf(/deploy to dev\?/)).toBe('wrap')
  expect(wrapOf(/pick a name/)).toBe('truncate-end')
  await ui.unmount()
})

test('four yes-no asks draw three with Yes and say how many wait behind', async ($, on) => {
  const rows = Array.from({ length: 4 }, (_, i) => `R-001${i}\t2026-10-30T15:4${i}Z\tq${i}\tyes-no`)
  const { ui } = await band($, on, rows.join('\n'))
  expect(await ui.findAll({ type: 'Button', text: /^Yes$/ })).toHaveLength(3)
  expect(await ui.find({ type: 'Text', text: /\+1 more/ })).toBeDefined()
  await ui.unmount()
})

test('two presses of one Yes at once send one approval', async ($, on) => {
  const { ui, sent } = await band($, on, ASKS)
  const yes = await ui.findAll({ type: 'Button', text: /^Yes$/ })
  await Promise.all([ui.press({ key: yes[0].key }), ui.press({ key: yes[0].key }).catch(() => undefined)])
  expect(sent).toEqual(['R-0007: yes — merge #97?'])
  await ui.unmount()
})

test('Yes and Yes to all at once approve each ask once', async ($, on) => {
  const { ui, sent } = await band($, on, ASKS)
  const yes = await ui.findAll({ type: 'Button', text: /^Yes$/ })
  await Promise.all([ui.press({ key: yes[0].key }), ui.press({ key: 'yes-all' }).catch(() => undefined)])
  const text = sent.join(' | ')
  expect(text.match(/R-0007/g)).toHaveLength(1)
  expect(text.match(/R-0004/g)).toHaveLength(1)
  await ui.unmount()
})

test('a refused submit gives the Yes back', async ($, on) => {
  const { ui, sent } = await band($, on, ASKS, { submitFails: true })
  const yes = await ui.findAll({ type: 'Button', text: /^Yes$/ })
  await ui.press({ key: yes[0].key }).catch(() => undefined)
  expect(sent).toEqual([])
  expect(await ui.findAll({ type: 'Button', text: /^Yes$/ })).toHaveLength(2)
  await ui.unmount()
})

test('req failing at press time sends nothing and keeps the band', async ($, on) => {
  const { ui, sent, reqDown } = await band($, on, ASKS)
  const yes = await ui.findAll({ type: 'Button', text: /^Yes$/ })
  reqDown()
  await ui.press({ key: yes[0].key })
  expect(sent).toEqual([])
  expect(await ui.find({ type: 'Text', text: /Waiting on you \(3\)/ })).toBeDefined()
  expect(await ui.findAll({ type: 'Button', text: /^Yes$/ })).toHaveLength(2)
  await ui.unmount()
})

async function engine($: any, on: any) {
  let runs = 0
  on('process.run', () => {
    runs++
    return { value: { exitCode: 0, stdout: ASKS, stderr: '' } }
  })
  on('clock.now', () => ({ value: NOW }))
  on('clock.every', () => new Promise(() => {}))
  on('session.start', (_: any, e: any) => ({ cwd: e.cwd }))
  on('ui.render', ($: any, e: any) => {
    const { Text } = $.ui.resolve(e)
    return <Text>engine</Text>
  })
  return () => runs
}

test('a session that never loaded the director skill shows no band and runs no req', async ($, on) => {
  const runs = await engine($, on)
  session(on, 's-other')
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  await $.skill.prompt({ skill: 'commit', text: '', pluginName: 'other' })
  await $.turn.complete({} as any).catch(() => undefined)
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /Waiting on you/ })).toBe(undefined)
  expect(runs()).toBe(0)
  await ui.unmount()
})

test('loading the director skill keeps the session id, so a resumed session shows the band at start', async ($, on) => {
  await engine($, on)
  const store = session(on, 's-dir', { directorSessions: ['s-old'] })
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  await loadDirector($)
  expect(store.directorSessions).toEqual(['s-old', 's-dir'])
})

test('a resumed director session shows the band without loading the skill again', async ($, on) => {
  await engine($, on)
  session(on, 's-dir', { directorSessions: ['s-dir'] })
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /Waiting on you \(3\)/ })).toBeDefined()
  await ui.unmount()
})
