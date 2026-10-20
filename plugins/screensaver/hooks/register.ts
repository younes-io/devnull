import type { Register } from 'claude-code'

const commandNames = (setting: unknown): string[] => {
  const names = String(setting ?? '')
    .split(/[\s,]+/)
    .map(name => name.replace(/^\//, ''))
    .filter(name => /^[\w-]{1,64}$/.test(name))

  return names.length ? [...new Set(names)] : ['screensaver']
}

export const register: Register = (on, options) => {
  const names = commandNames(options.commands)

  on('session.start', async ($, e, next) => {
    for (const name of names) {
      await $.command.register({
        name,
        description: 'Cover this terminal with the dev-null.sh logo; Esc brings the session back',
      })
    }

    return next(e)
  })

  on('command.run', { command: names }, async $ => {
    const run = await $.process.run([`${$.plugin.root}/bin/launch`])

    return {
      text:
        run.exitCode === 0
          ? 'Screensaver on. Esc brings you back.'
          : `Screensaver failed: ${run.stderr.trim() || run.stdout.trim()}`,
    }
  })
}
