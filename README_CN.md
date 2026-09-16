# dsh-oneclick

在 Windows 上一键装好**官方** DeepSeek Harness 网页版。

[English](README.md) | 简体中文

## 安装

**会用命令行** —— 什么都不用先下载：

```
npx dsh-oneclick
```

**不想碰命令行** —— [下载最新发行包](https://github.com/Breeze136/dsh-oneclick/releases/latest)，
解压到任意目录，双击 `install.cmd`。

两条路跑的是同一个安装器。这就是全部说明：重复运行即为更新，有新版就升级，已经装好的自动跳过。

## 为什么需要它

官方的手动安装路径对不写代码的人有几个硬坎：

- **先得有 Node.js** —— 没有它后面一步都走不了
- **DSH 命令行要装到 PATH 上**，否则 `dsh` 敲不出来
- **装插件需要 pnpm**，而 pnpm 本身又得先有 npm
- **知识库插件还依赖 Python** 和约 1.2 GB 的检索模型
- **网页版的入口 URL 带 token** —— 裸访问 `http://127.0.0.1:3080` 对没进过的浏览器返回 401；
  进过一次之后浏览器会拿到 30 天 cookie，之后就正常了。token 每次启动现生成、只打到终端里，
  所以命令行用户其实很难把它固定成一个能长期用的书签

这个安装器把这些一次做完，每个下载都校验哈希，最后留一个双击就能用的桌面快捷方式。

## 它做什么

| 步骤 | 动作 |
|---|---|
| 1 | **Node.js** —— 有现成的就用；没有就把官方 Windows 压缩包解压到 `%LOCALAPPDATA%\DSH\node`（不需要管理员权限，不动系统 PATH） |
| 2 | **DSH CLI + pnpm** —— `npm install -g @deepseek-ai/dsh pnpm`（官方命令行工具，自带网页版） |
| 3 | **快捷方式** —— 桌面生成「DeepSeek Harness」，双击启动网页版并打开浏览器 |
| 4 | **kb-rag 知识库（可选）** —— 装的时候问一句，回车＝装：`dsh plugin --profile web add dsh-kb-rag@<确切版本>`；回答 n 就整段跳过，只留官方 DSH |
| 5 | **引擎（跟着插件走）** —— 交给插件自带的 `scripts/install.ps1`，装 Python 依赖和约 1.2 GB 的检索模型 |

全部装在当前用户下，不需要管理员权限。不注册任何服务、不设开机自启，**也不会删除 `~/.dsh` 下已有的会话、工作区或凭据** —— 重跑只更新插件。

## 环境要求

- Windows 10 或更高，64 位
- 约 8 GB 可用磁盘（Node、DSH、Python 环境、模型加起来）
- 能上网。官方源慢的地方默认走镜像；国内默认是 npmmirror（npm 包）、腾讯云（pip）、hf-mirror（模型），**这些都是实测挑出来的，不是拍的**

## 命令行选项

双击 `install.cmd` 不需要任何参数。参数有两套写法，含义完全一样 —— 按你装的哪条路选一列即可：

| 想做什么 | `npx` 路线 | 发行包 |
|---|---|---|
| 只体检，不做任何改动 | `npx dsh-oneclick --check` | `install.cmd -CheckOnly` |
| 打印将要做什么，不下载不安装 | `npx dsh-oneclick --dry-run` | `install.cmd -DryRun` |
| 只测下载通道 | `npx dsh-oneclick --self-test` | `install.cmd -SelfTest` |
| 只装官方 DSH，不要 kb-rag 知识库 | `npx dsh-oneclick --no-plugin` | `install.cmd -SkipPlugin` |
| 跳过约 1.2 GB 的检索模型 | `npx dsh-oneclick --no-models` | `install.cmd -NoModels` |
| 不创建桌面快捷方式 | `npx dsh-oneclick --no-shortcut` | `install.cmd -NoShortcut` |
| 指定插件版本 | `npx dsh-oneclick --plugin-version 1.6.7` | `install.cmd -PluginVersion 1.6.7` |
| 所有提问都用默认答案 | `npx dsh-oneclick --yes` | `install.cmd -Yes` |
| 看完整列表 | `npx dsh-oneclick --help` | 见 `tools/install.ps1` 顶部的参数块 |

其余开关 —— `-SkipNode`、`-SkipDshCli`、`-SkipEngine`、`-WorkDir`、`-PipMirror`、
`-NpmRegistry`、`-NoPause` —— 两条路都有，名字就是参数块里那些；`npx` 也直接认
PowerShell 风格的写法。

## 离线 / 走镜像

安装器会优先看自己旁边的 `payload/` 目录。把官方 Node 压缩包
`node-v24.21.0-win-x64.zip` 放进去（会按官方 `SHASUMS256.txt` 里的 sha256 校验），
Node 就不会联网下载。其余组件仍然来自 npm。

## 发行压缩包

给不想碰命令行的人：解压后双击 `install.cmd` 即可，不需要先有 Node、也不需要开终端。
压缩包里额外带三份中文文档：

- `GETTING-STARTED.txt` —— 装之前看：装了什么、怎么用、出问题怎么办
- `MODEL-SETUP.txt` —— 装完看：第一次打开要填 API Key，去哪申请、怎么填、报错怎么查
- `NEXT-STEPS.txt` —— 装完之后照着一步步做

网盘、U 盘这类分发方式也走它。

在仓库根目录重新打包：

```
powershell -NoProfile -ExecutionPolicy Bypass -File tools\make-release.ps1
```

脚本会按**实际进包的文件**重算 `sha256.txt`，并把压缩包自身的 SHA-256 打出来 ——
那个值就是发布时该贴在下载旁边的那个。

## 装完之后

第一次打开会先让你接一个模型提供方（填 API 密钥），再选一个工作区。这两步的具体操作见 `MODEL-SETUP.txt`。

快捷方式启动的服务跑在一个**最小化的命令行窗口**里：

- 那个窗口就是服务本身，**关掉它 = 停止 DSH**
- 想看运行日志，点开它，或看 `%LOCALAPPDATA%\DSH\dsh-web.log`

## 边界与声明

这是一份**第三方辅助脚本**，不是 DeepSeek 官方发布的，运行它也不会让你的安装变成"官方版"。
它做的事情就是把官方发布的包按官方文档要求的方式装好（`npm install -g @deepseek-ai/dsh`）。

桌面快捷方式使用了 DeepSeek 的标识，目的是让人一眼看出它启动的是什么。
DeepSeek 的名称与标识归其权利人所有，图标的准确出处和授权说明见 `assets/ICON-SOURCE.txt`。

## 目录结构

```
bin.mjs                  npx 入口（参数翻译 + 交给 install.ps1）
package.json             npm 包清单（bin / files / 版本号）
install.cmd              发行包的双击入口
tools/install.ps1        安装逻辑
tools/dsh-web.ps1        桌面快捷方式背后的启动器
tools/make-release.ps1   打开发行压缩包
assets/                  图标与出处说明
payload/                 把官方 Node 压缩包放这里即可离线安装
GETTING-STARTED.txt      新手说明（中文）
MODEL-SETUP.txt          模型接入教程（中文）
NEXT-STEPS.txt           装完之后做什么（中文）
COMPAT.md                与 kb-rag 插件之间的依赖契约（包名 / profile / 引擎入口 / 参数）
sha256.txt               发行压缩包里每个文件的校验值
VERSION.txt              版本号与维护记录（两条分发路都不带它）
```

一份源码、两个分发口，各自只装自己需要的部分：npm 包多出 `bin.mjs` + `package.json`，
发行 zip 多出 `install.cmd` 和三份中文文档。`tools/make-release.ps1` 会把 npm 那两个文件
（连同 `VERSION.txt` 和它自己）排除在 zip 之外；`package.json` 的 `files` 列表则把维护者
专用的文件排除在 tarball 之外。脚本还会校验 `VERSION.txt`、`tools/install.ps1`、
`package.json` 三处版本号一致，不一致就拒绝打包。

## 许可证

MIT —— 见 `LICENSE`。
