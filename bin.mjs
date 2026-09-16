#!/usr/bin/env node
// dsh-oneclick - npx entry point.
//
// `npx dsh-oneclick` installs (or updates) the official DeepSeek Harness web app
// on Windows. This file is only a thin, portable front door: it translates the
// bash-style flags npx users type into the PowerShell switch names that
// tools/install.ps1 declares, then hands over with stdio inherited so the user
// sees the installer's own progress output live.
//
// Why a forwarder instead of running the work here: the installer needs to
// spawn native tools (npm, node, python, cmd) and inherit the console; doing
// that from Node only adds a layer that can swallow output or break the console
// code page, which is exactly what makes the engine step fail (see the notes in
// tools/install.ps1 about `chcp 65001` and the UTF-8 BOM).
//
// This file is deliberately pure ASCII, like install.cmd: no editor can
// mis-guess its encoding, and no byte-order mark can end up in front of the
// shebang above. All Chinese user-facing text lives in tools/install.ps1, which
// is saved as UTF-8 with a BOM for exactly that reason.
//
// The release zip ships the same tools/install.ps1 without this file; there the
// user double-clicks install.cmd and passes the PowerShell names directly.
import { spawnSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const here = dirname(fileURLToPath(import.meta.url))
const installer = join(here, 'tools', 'install.ps1')

if (process.platform !== 'win32') {
  console.error('dsh-oneclick: this installer targets Windows only.')
  console.error('On macOS or Linux, install DSH directly:  npm install -g @deepseek-ai/dsh')
  process.exit(1)
}

/** bash-style flag -> PowerShell parameter (value-carrying flags included). */
const FLAG_MAP = {
  '--check': '-CheckOnly',
  '--self-test': '-SelfTest',
  '--dry-run': '-DryRun',
  '--no-shortcut': '-NoShortcut',
  '--no-models': '-NoModels',
  '--no-plugin': '-SkipPlugin',
  '--no-dsh': '-SkipDshCli',
  '--no-node': '-SkipNode',
  '--skip-node': '-SkipNode',
  '--skip-dsh': '-SkipDshCli',
  '--skip-plugin': '-SkipPlugin',
  '--skip-engine': '-SkipEngine',
  '--yes': '-Yes',
  '-y': '-Yes',
  '--no-pause': '-NoPause',
  '--plugin-version': '-PluginVersion',
  '--pip-mirror': '-PipMirror',
  '--npm-registry': '-NpmRegistry',
  '--work-dir': '-WorkDir'
}

/** Flags that take the following argv entry as their value. */
const VALUE_FLAGS = ['-PluginVersion', '-PipMirror', '-NpmRegistry', '-WorkDir']

const argv = process.argv.slice(2)

if (argv.includes('--help') || argv.includes('-h')) {
  console.log(`dsh-oneclick - one-click installer for DeepSeek Harness (Windows)

Usage:
  npx dsh-oneclick [options]

Options:
  --check                 Inspect the machine only; change nothing
  --dry-run               Print what would happen; download and install nothing
  --self-test             Test the download channels only
  --no-shortcut           Do not create the desktop shortcut
  --no-models             Skip pre-downloading the ~1.2 GB of retrieval models
  --no-plugin             Install official DSH only; skip the kb-rag plugin
  --no-dsh                Do not install or update the DSH CLI
  --no-node               Do not touch Node.js
  --skip-engine           Do not touch the plugin's Python engine
  --plugin-version <v>    Install a specific plugin version (default: latest)
  --pip-mirror <url>      pip index to use
  --npm-registry <url>    npm registry to use
  --work-dir <path>       Where to keep the installer's working files
  --yes, -y               Answer yes to every prompt
  --no-pause              Do not wait for Enter when finished
  --help, -h              Show this text

PowerShell-style names (-CheckOnly, -SkipPlugin, ...) are accepted as-is, so the
same flags work when calling tools/install.ps1 or install.cmd directly.

What it installs: Node.js (only if missing), @deepseek-ai/dsh, pnpm, the
optional dsh-kb-rag plugin with its Python dependencies and retrieval models,
and a desktop shortcut that launches the DSH web app. Everything lands in the
current user's profile; no administrator rights are required, and nothing under
the DSH home directory is ever deleted. Re-running it updates whatever is out of
date and skips the rest.

Prefer not to touch a terminal? The same installer also ships as a zip you can
unzip and double-click:  https://github.com/Breeze136/dsh-oneclick/releases`)
  process.exit(0)
}

const psArgs = []
for (let i = 0; i < argv.length; i += 1) {
  const mapped = FLAG_MAP[argv[i]]
  if (mapped === undefined) {
    psArgs.push(argv[i])
    continue
  }
  psArgs.push(mapped)
  // Value-carrying flags keep their value in the next position
  if (VALUE_FLAGS.includes(mapped) && argv[i + 1] !== undefined) {
    psArgs.push(argv[++i])
  }
}

const result = spawnSync(
  'powershell',
  ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', installer, ...psArgs],
  { stdio: 'inherit', shell: false }
)

if (result.error !== undefined) {
  if (result.error.code === 'ENOENT') {
    console.error('dsh-oneclick: powershell was not found on PATH.')
    process.exit(127)
  }
  throw result.error
}
process.exit(result.status ?? 1)
