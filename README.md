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

**[Download the latest release](https://github.com/Breeze136/dsh-oneclick/releases/latest)**,
unzip it anywhere, and double-click `install.cmd`.

That is the whole manual. Re-running it updates whatever is out of date and
skips everything else.

> **`npx dsh-oneclick` does not work yet.** The package has not been published to
> npm, so that command currently returns 404. The release download above is the
> supported route until it is published.

## What it does

| Step | Action |
|---|---|
| 1 | **Node.js** — uses an existing install; if there is none, unpacks the official Windows zip into `%LOCALAPPDATA%\DSH\node` (no administrator rights, system `PATH` untouched) |
| 2 | **DSH CLI + pnpm** — `npm install -g @deepseek-ai/dsh pnpm` (official CLI, ships the web app) |
| 3 | **Shortcut** — a desktop shortcut named *DeepSeek Harness* that starts the web app and opens the browser |
| 4 | **kb-rag knowledge base (optional)** — asked once during the run; Enter installs it (`dsh plugin --profile web add dsh-kb-rag@<resolved version>`), `n` skips it and leaves you with plain official DSH |
| 5 | **Engine (only with the plugin)** — delegates to the plugin's own `scripts/install.ps1` for Python dependencies and the ~1.2 GB of retrieval models |

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

Double-clicking `install.cmd` needs no arguments. To pass flags, open a terminal
in the unzipped folder and run it with PowerShell-style names:

```
install.cmd -CheckOnly              # inspect only, change nothing
install.cmd -DryRun                 # print the plan, install nothing
install.cmd -SkipPlugin             # official DSH only, no kb-rag
install.cmd -NoModels               # skip the ~1.2 GB of retrieval models
install.cmd -NoShortcut             # do not create the desktop shortcut
install.cmd -PluginVersion 1.6.7
install.cmd -Yes                    # never prompt
```

The rest — `-SkipNode`, `-SkipDshCli`, `-SkipEngine`, `-SelfTest`, `-WorkDir`,
`-PipMirror`, `-NpmRegistry`, `-NoPause` — are listed in the parameter block at
the top of `tools/install.ps1`.

Once the package reaches npm, `npx dsh-oneclick --check` and the other
`--`-style spellings do the same thing without the download.

## Offline or mirrored install

The installer checks `payload/` next to itself first. Drop
`node-v24.21.0-win-x64.zip` (the official Node zip, sha256 verified against the
official `SHASUMS256.txt`) there and Node will not be downloaded. Everything
else still comes from npm.

## The release archive

The zip is the supported distribution route: unzip it and double-click
`install.cmd`. It carries the same installer plus three short Chinese guides —
`GETTING-STARTED.txt`, `MODEL-SETUP.txt` and `NEXT-STEPS.txt` — and it is also
the route for file-sharing sites and USB sticks, where `npx` is not an option.

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
install.cmd              double-click entry (the route this repository ships)
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
VERSION.txt              version number + maintainer change log (not shipped in the archive)
```

The release archive ships only the subset a double-click user needs. The npm
package files (`bin.mjs`, `package.json`) are not in this repository and the
package is not on npm, so there is nothing to `npx` yet — see [Install](#install).

The three beginner guides (and the installer's own comments) are written in
Chinese because that is the audience the release archive is built for; this
README is English and `README_CN.md` is Chinese.

## License

MIT — see `LICENSE`.
