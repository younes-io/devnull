import type { On } from 'claude-code'
import { expect, test } from 'claude-code/testing'

const engineBeneath = (on: On) => {
  const registered: string[] = []
  const launches: (readonly string[])[] = []
  on('command.register', (_, e) => {
    registered.push(e.name)
    return { value: { command: e.name } }
  })
  on('process.run', (_, e) => {
    launches.push(e.argv)
    return { value: { exitCode: 0, stdout: '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  return { registered, launches }
}

const typed = (command: string) => ({
  command,
  args: '',
  origin: { kind: 'composer' as const },
  presentation: { isFullscreen: true, columns: 120 },
})

test('/screensaver is the only command by default', async ($, on) => {
  const { registered, launches } = engineBeneath(on)
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })

  expect(registered).toEqual(['screensaver'])
  expect((await $.command.run(typed('screensaver'))).text).toBe('Screensaver on. Esc brings you back.')
  expect(launches).toHaveLength(1)
})

test('each configured name starts the screensaver', { options: { commands: 'ss, /afk  ss bad!name' } }, async ($, on) => {
  const { registered, launches } = engineBeneath(on)
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })

  expect(registered).toEqual(['ss', 'afk'])
  for (const command of ['ss', 'afk']) {
    expect((await $.command.run(typed(command))).text).toBe('Screensaver on. Esc brings you back.')
  }
  expect(launches).toHaveLength(2)
})

test('a setting with no usable name falls back to /screensaver', { options: { commands: ' , !!' } }, async ($, on) => {
  const { registered } = engineBeneath(on)
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })

  expect(registered).toEqual(['screensaver'])
})
