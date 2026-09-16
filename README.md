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

```
npx dsh-oneclick
```

That is the whole manual. Re-running it updates whatever is out of date and
skips everything else.

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

```
npx dsh-oneclick --check              # inspect only, change nothing
npx dsh-oneclick --dry-run            # print the plan, install nothing
npx dsh-oneclick --no-plugin          # official DSH only, no kb-rag
npx dsh-oneclick --no-models          # skip the ~1.2 GB of retrieval models
npx dsh-oneclick --no-shortcut        # do not create the desktop shortcut
npx dsh-oneclick --plugin-version 1.6.7
npx dsh-oneclick --yes                # never prompt
npx dsh-oneclick --help               # the full list
```

## Offline or mirrored install

The installer checks `payload/` next to itself first. Drop
`node-v24.21.0-win-x64.zip` (the official Node zip, sha256 verified against the
official `SHASUMS256.txt`) there and Node will not be downloaded. Everything
else still comes from npm.

## The release zip

For handing this to someone who would rather not touch a terminal, use the
release archive instead: unzip it and double-click `install.cmd`. The archive
carries the same installer plus two short guides — `GETTING-STARTED.txt` and
`MODEL-SETUP.txt` — and it is the distribution route for file-sharing sites
where `npx` is not an option.

Build it with:

```
npm run build:release
```

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
bin.mjs                  npx entry point (flag translation + hand-off)
install.cmd              double-click entry for the release zip
tools/install.ps1        the installer
tools/dsh-web.ps1        launcher behind the desktop shortcut
assets/                  icon + its provenance
GETTING-STARTED.txt      beginner guide (Chinese)
MODEL-SETUP.txt          model/API-key walkthrough (Chinese)
tools/dev/               maintainer scripts (release build, icon generator)
COMPAT.md                contract with the kb-rag plugin (package name, profile, engine entry, flags)
```

The release zip ships only the subset a double-click user needs (no `bin.mjs`,
no `tools/dev/`).

The two beginner guides (and the installer's own comments) are written in Chinese
because that is the audience the release zip is built for; this README and
`bin.mjs` are English.

## License

MIT — see `LICENSE`.
