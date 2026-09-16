# dsh-oneclick

English | [简体中文](README_CN.md)

One-click Windows installer for the **official** DeepSeek Harness web app.

It exists because the manual path has a few sharp edges that stop non-technical
users: you need Node.js before anything else works, the DSH CLI has to be on
`PATH`, plugins need pnpm, the knowledge-base plugin needs Python plus ~1.2 GB of
retrieval models, and the web app's entry URL carries a per-process token that a
plain `http://127.0.0.1:3080` bookmark cannot reproduce (a browser that has never
visited gets 401; after the first visit a 30-day cookie makes it work). This
installer does all of it, verifies every download, and leaves a desktop shortcut
that just works.

## Install

**With a terminal** — nothing to download first:

```
npx dsh-oneclick
```

**Without one** — [download the latest release](https://github.com/Breeze136/dsh-oneclick/releases/latest),
unzip it anywhere, and double-click `install.cmd`.

Either route runs the same installer. That is the whole manual: re-running it
updates whatever is out of date and skips everything else.

Part-way through, it offers the author's own `dsh-kb-rag` knowledge-base plugin.
That offer is a recommendation, not a requirement — answering `n` is a normal
choice, not a degraded install. [What it does](#what-it-does) spells out exactly
what changes either way.

## What it does

| Step | Action |
|---|---|
| 1 | **Node.js** — uses an existing install; if there is none, unpacks the official Windows zip into `%LOCALAPPDATA%\DSH\node` (no administrator rights, system `PATH` untouched) |
| 2 | **DSH CLI + pnpm** — `npm install -g @deepseek-ai/dsh pnpm` (official CLI, ships the web app) |
| 3 | **Shortcut** — a desktop shortcut named *DeepSeek Harness* that starts the web app and opens the browser |
| 4 | **kb-rag knowledge base — offered, not required** — this plugin is the installer author's other open-source project, so the installer recommends it and asks once (`dsh plugin --profile web add dsh-kb-rag@<resolved version>`). Enter installs it; `n` skips it and leaves you with plain official DSH |
| 5 | **Engine (only with the plugin)** — delegates to the plugin's own `scripts/install.ps1` for Python dependencies and the ~1.2 GB of retrieval models |

Steps 4 and 5 are the only ones that are about **the author's own work rather than
DeepSeek's**. The recommendation is genuine, but so is the opt-out: answering `n`
gives you exactly the official setup, changes nothing else in the run, and the
installer will not ask again unless you run it again.

Everything is installed per-user. No service is registered, nothing is added to
startup, and no existing session, workspace or credential under `~/.dsh` is ever
deleted — re-running only updates the plugin.

## Requirements

- Windows 10 or later, 64-bit
- About 8 GB of free disk space (Node, DSH, the Python environment and models)
- An internet connection. Mirrors are used where the official host is slow;
  in mainland China the defaults are npmmirror (packages), Tencent (pip) and
  hf-mirror (models), all measured rather than guessed.

## Options

Double-clicking `install.cmd` needs no arguments. Flags come in two spellings
that mean exactly the same thing — pick whichever route you installed by:

| What you want | `npx` route | release archive |
|---|---|---|
| inspect the machine only, change nothing | `npx dsh-oneclick --check` | `install.cmd -CheckOnly` |
| print the plan, install nothing | `npx dsh-oneclick --dry-run` | `install.cmd -DryRun` |
| test the download channels only | `npx dsh-oneclick --self-test` | `install.cmd -SelfTest` |
| official DSH only, no kb-rag | `npx dsh-oneclick --no-plugin` | `install.cmd -SkipPlugin` |
| skip the ~1.2 GB of retrieval models | `npx dsh-oneclick --no-models` | `install.cmd -NoModels` |
| do not create the desktop shortcut | `npx dsh-oneclick --no-shortcut` | `install.cmd -NoShortcut` |
| pin the plugin version | `npx dsh-oneclick --plugin-version 1.6.7` | `install.cmd -PluginVersion 1.6.7` |
| never prompt | `npx dsh-oneclick --yes` | `install.cmd -Yes` |
| the full list | `npx dsh-oneclick --help` | see the parameter block at the top of `tools/install.ps1` |

The remaining switches — `-SkipNode`, `-SkipDshCli`, `-SkipEngine`, `-WorkDir`,
`-PipMirror`, `-NpmRegistry`, `-NoPause` — exist in both routes under the names
shown in that parameter block; `npx` accepts the PowerShell spellings as-is.

## Offline or mirrored install

The installer checks `payload/` next to itself first. Drop
`node-v24.21.0-win-x64.zip` (the official Node zip, sha256 verified against the
official `SHASUMS256.txt`) there and Node will not be downloaded. Everything
else still comes from npm.

## The release archive

For handing this to someone who would rather not touch a terminal, use the zip:
unzip it and double-click `install.cmd`. It carries the same installer plus
three short Chinese guides — `GETTING-STARTED.txt`, `MODEL-SETUP.txt` and
`NEXT-STEPS.txt` — and it is also the route for file-sharing sites and USB
sticks, where `npx` is not an option.

Rebuild it from the repository root with:

```
powershell -NoProfile -ExecutionPolicy Bypass -File tools\make-release.ps1
```

The script regenerates `sha256.txt` for exactly the files that go into the
archive and prints the archive's own SHA-256, which is the value to publish
alongside the download.

## After installing

The first launch asks for a model provider and an API key, then for a workspace.
`MODEL-SETUP.txt` in the release archive walks through both, including where to
create the key. The shortcut's server runs in a minimized console window;
closing that window stops the server.

## Scope and disclaimers

This is a third-party helper script. It is **not** published by DeepSeek, and
running it does not make your installation "official" — it installs the official
packages through their official channels (`npm install -g @deepseek-ai/dsh`),
which is what the official documentation asks you to do.

The desktop shortcut uses the DeepSeek mark so that the icon identifies what it
launches. DeepSeek's names and marks belong to their owner; see
`assets/ICON-SOURCE.txt` for the exact provenance of the icon file and its
license note.

## Layout

```
bin.mjs                  npx entry point (flag translation + hand-off to install.ps1)
package.json             npm package manifest (bin, files, version)
install.cmd              double-click entry for the release archive
tools/install.ps1        the installer
tools/dsh-web.ps1        launcher behind the desktop shortcut
tools/make-release.ps1   builds the release archive
assets/                  icon + its provenance
payload/                 drop the official Node zip here for an offline install
GETTING-STARTED.txt      beginner guide (Chinese)
MODEL-SETUP.txt          model/API-key walkthrough (Chinese)
NEXT-STEPS.txt           what to do right after the installer finishes (Chinese)
COMPAT.md                contract with the kb-rag plugin (package name, profile, engine entry, flags)
sha256.txt               hashes of every file in the release archive
VERSION.txt              version number + maintainer change log (not shipped in either route)
```

One repository, two distribution routes, each shipping only what its audience
needs: the npm package adds `bin.mjs` + `package.json`, the release archive adds
`install.cmd` and the Chinese guides. `tools/make-release.ps1` excludes the npm
files (and `VERSION.txt`, and itself) from the zip; `package.json`'s `files`
list excludes the maintainer-only files from the tarball. A version-consistency
check keeps `VERSION.txt`, `tools/install.ps1` and `package.json` in step, and
refuses to build when they disagree.

The three beginner guides (and the installer's own comments) are written in
Chinese because that is the audience the release archive is built for; this
README is English and `README_CN.md` is Chinese.

## License

MIT — see `LICENSE`.
