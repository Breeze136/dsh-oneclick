# dsh-oneclick ↔ kb-rag 依赖契约

安装器（`dsh-oneclick`）负责把**官方 DSH web** 装好，并**可选**地装 kb-rag 知识库插件
（npm 包 `dsh-kb-rag`）。两者是独立的发布物，各有各的版本号与发布节奏 ——
这份文件写清安装器依赖插件的**全部**接触点。改插件之前先看这里。

## 安装器依赖的 4 个点

| # | 依赖 | 安装器里的位置 | 插件侧的要求 |
|---|---|---|---|
| 1 | npm 包名 `dsh-kb-rag` | `tools/install.ps1` 的 `$PluginName` | 包名不能改，改了安装器就找不到 |
| 2 | profile 名 `web` | `$ProfileName` | 插件要能装在 `%USERPROFILE%\.dsh\profiles\web` 下 |
| 3 | 插件自带的引擎安装脚本 `scripts/install.ps1` | `Install-Engine` 里的 `$PluginDir\scripts\install.ps1` | 必须随包发布，并接受下面那组参数 |
| 4 | 引擎自检的输出形状 | `Test-EngineSelfCheck` | `python kb_engine.py stats` 的 JSON 里要有 `"ok": true` 和 `"engine": "<版本>"` |

## 引擎安装脚本的调用契约

安装器这样调它（见 `Install-Engine`）：

```
powershell -NoProfile -ExecutionPolicy Bypass -File "<插件目录>\scripts\install.ps1" `
  -Profile web -Yes -SkipNode -SkipDsh -Mirror <pip 镜像> [-Models | -NoModels]
```

* 退出码 `0` = 成功。非 0 时安装器会换 pip 镜像重试（腾讯云 → 清华 → 阿里云），
  仍然失败才把整步标记为失败。
* `-SkipNode` / `-SkipDsh`：Node 与 DSH CLI 由安装器负责，引擎脚本不要再碰它们。
* 只用**具名参数**传值，别依赖参数顺序。
* 子进程的 stdin 被接到 `NUL`：PS 5.1 在 UTF-8 控制台下会给管道加 BOM，
  引擎会直接报 `Unexpected UTF-8 BOM`（kb-rag 的 `docs/install-winerror123-fix.md` 有完整分析）。
  引擎脚本不要假设 stdin 可读。
* 引擎脚本本身要存成 **UTF-8 带 BOM**，否则 PS 5.1 读中文会乱码。

## 版本策略

* 安装器**不用** `@latest` 装插件：先查 registry 的 `dist-tags.latest`，再用确切版本号装
  （`dsh-kb-rag@1.6.7`）。原因：pnpm 的 `minimumReleaseAge` 会把 `@latest` 降级到"够老"的
  那个版本，表现为"看起来装成功、实际版本没变"（kb-rag 仓库 `AGENTS.md` 记录的坑）。
* 查不到版本号时退回 `@latest`，并提示"若装完版本没变，请重跑"。
* 安装器不设插件版本上限：插件发新版即视为可升级。**破坏性改动必须落在这份契约里。**

## 出错时的既定行为（兜底已写好，改契约前先读）

* 没装插件（用户选 n，或第 3 步失败）→ 第 4 步直接跳过并在汇总表标注原因，
  不再硬跑一遍最后报"找不到引擎安装脚本"。
* 找不到 `scripts/install.ps1` → 明确报"插件没装上"，并提示可以把该脚本放进安装包的
  `vendor\` 目录当离线回退。
* 引擎脚本非 0 退出 → 换镜像重试；若日志里出现 `Unexpected UTF-8 BOM`，
  会单独跑一次引擎自检，通过就按成功处理（那多半是 PowerShell 管道的锅，不是引擎坏了）。

## 离线回退

`vendor\install.ps1`：若存在，则插件目录里找不到引擎安装脚本时改用它。
这个目录**不打进发行包**（发行包只有双击用户需要的部分），只在需要做离线包时手工放入。
