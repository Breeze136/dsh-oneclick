<#
  DSH 一键装 —— 官方 DeepSeek Harness web（可选装 kb-rag 文献知识库）
  Windows PowerShell 5.1+
  ==========================================================================
  目标：新手双击同目录的「install.cmd」，装完得到一个能用的「官方 DeepSeek Harness
        web 端」+ 桌面快捷方式；kb-rag 本地文献知识库插件是**可选项**（会问一句，
        回车＝装，回答 n ＝只装 DSH 本体）。

  脚本做的事（全是新手自己在命令行里会敲的那些命令，没有花活）：

    1) Node.js   —— 有就用系统自带的；没有就下官方 zip 解压到用户目录（免管理员）
    2) dsh CLI   —— npm install -g @deepseek-ai/dsh   （官方 CLI，自带 web 端）
       pnpm      —— npm install -g pnpm               （dsh plugin 内部要转调它）
    3) 快捷方式  —— 桌面「DeepSeek Harness」双击即启动 dsh web 并打开浏览器

  下面两步只在装了 kb-rag 时才有意义（用户选 n 就整段跳过）：
    4) 插件      —— dsh plugin --profile web add dsh-kb-rag@<版本>
    5) 引擎      —— 复用插件自带的 scripts/install.ps1（Python 依赖 + 模型，走国内镜像）

  可反复运行：第二次运行就是「更新」（查 npm 最新版，比本地新就升级）。

  说明：
    * 目标目录/数据目录与官方一致 —— DSH_HOME = %USERPROFILE%\.dsh
    * 全部装在当前用户下，不需要管理员权限
    * 下载一律多通道 + 哈希校验（Node 的 sha256 取自官方 SHASUMS256.txt）
    * 本文件必须存成「UTF-8 带 BOM」，否则 PowerShell 5.1 读中文会乱码
    * 编码相关的坑见 kb-rag 项目 docs/install-winerror123-fix.md
    * 与 kb-rag 之间的依赖契约（包名/profile/引擎入口/参数）见同目录上一层的 COMPAT.md

  常用开关：
    -CheckOnly   只体检，不做任何改动
    -SelfTest    只测下载通道，不安装
    -DryRun      只打印将要做什么
    -SkipNode / -SkipDshCli / -SkipPlugin / -SkipEngine / -NoShortcut
    -NoModels    跳过模型预下载
    -Yes         所有提问都用默认答案（＝装插件、下精排模型）
    -NoPause     结束时不等回车
#>
[CmdletBinding()]
param(
  [string]$WorkDir       = '',
  [string]$PluginVersion = '',
  [string]$PipMirror     = '',
  [string]$NpmRegistry   = '',
  [switch]$NoModels,
  [switch]$SkipNode,
  [switch]$SkipDshCli,
  [switch]$SkipPlugin,
  [switch]$SkipEngine,
  [switch]$NoShortcut,
  [switch]$CheckOnly,
  [switch]$SelfTest,
  [switch]$DryRun,
  [switch]$Yes,
  [switch]$NoPause
)

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

# ---- 编码：每个赋值都有原因，改动前先读 kb-rag 项目 docs/install-winerror123-fix.md ----
# 1) $OutputEncoding：PS 5.1 默认 ASCII，中文用户名路径经管道送给 python 会静默变成 "?"，
#    引擎报 WinError 123。必须 UTF-8 且**不带 BOM**（引擎用 raw.decode("utf-8") 严格解析）。
$OutputEncoding = New-Object System.Text.UTF8Encoding($false)
# 2) [Console]::OutputEncoding 改的是**共享控制台**代码页：设成 65001 后，子 PowerShell 在
#    65001 下写原生命令管道会多带 BOM，上游 install.ps1 的引擎冒烟测试就假失败。
#    所以 CJK 代码页下不动它；只有非 CJK（英文系统）才切 UTF-8 保证中文可读。
$cjkCodePages = @(936, 950, 932, 949, 51932, 51936, 52936)
$consoleCp = 0
try { $consoleCp = [Console]::OutputEncoding.CodePage } catch { }
if ($cjkCodePages -notcontains $consoleCp) {
  try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }
}

# ----------------------------------------------------------------- 常量
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir   = Split-Path -Parent $ScriptDir
$UserAgent = 'DSH-Newbie-Installer/2.0'
# 项目地址：结尾的「求 star」和「有问题去 issue」都由它派生（issues 就是 + '/issues'）。
# 只改这一行就能换仓库。
# 注意：一键装自己的仓库（dsh-oneclick）目前还没有，所以这里先指向这个包真正在装的
# 那个项目（Breeze136/dsh-kb-rag，仓库存在、Issues 开着）。等一键装独立建仓后改这里。
# 千万别指一个不存在的地址：新手点开是 404，比不引导还糟。
$RepoUrl = 'https://github.com/Breeze136/dsh-kb-rag'

# 安装包版本。VERSION.txt 不随发布包分发（打包脚本会排除它），所以版本号必须在这里也有一份，
# 并且**要和 VERSION.txt 首行一致** —— tools\make-release.ps1 打包前会校验这一点，不一致就
# 拒绝打包。为什么值得单列一行：用户手里可能同时存在解压了几次的两三个文件夹
#（"…(1)"、"(2)"），报错时你得先问清楚"你跑的是哪个版本"。
$PackageVersion = '1.1.1'

# 官方 CLI 与目标目录（与官方文档/官方启动方式一致）
$DshNpmPkg   = '@deepseek-ai/dsh'
$DshHome     = Join-Path $env:USERPROFILE '.dsh'   # 官方默认数据目录（会话/工作区/凭据都在里面）
$ProfileName = 'web'
$PluginName  = 'dsh-kb-rag'
$WebPort     = 3080

# 我们自己的安装前缀（便携 Node、启动器、图标都放这儿）
$Prefix  = Join-Path $env:LOCALAPPDATA 'DSH'
$NodeDir = Join-Path $Prefix 'node'

# Node：优先用系统已装的；没有才下这个（版本+哈希取自官方 SHASUMS256.txt）
$NodeVersion   = 'v24.21.0'
$NodeZipSha256 = '158f7685b44de51f6c0df1d153526cbcd3e1bc739a8dfc607721cef75de9e541'
$NodeZipSize   = 37618919
$NodeUrls = @(
  "https://registry.npmmirror.com/-/binary/node/$NodeVersion/node-$NodeVersion-win-x64.zip",
  "https://npmmirror.com/mirrors/node/$NodeVersion/node-$NodeVersion-win-x64.zip",
  "https://nodejs.org/dist/$NodeVersion/node-$NodeVersion-win-x64.zip"
)

# npm 源（实测 npmmirror 稳定且快）
$NpmRegistries = @('https://registry.npmmirror.com', '')

# pip 镜像实测：腾讯云 7.30 MB/s > 清华 6.25 MB/s
$PipMirrors = @(
  'https://mirrors.cloud.tencent.com/pypi/simple',
  'https://pypi.tuna.tsinghua.edu.cn/simple',
  'https://mirrors.aliyun.com/pypi/simple'
)
$HfEndpoint = 'https://hf-mirror.com'

$PythonVersion = '3.12.10'
$PythonUrls = @(
  'https://mirrors.huaweicloud.com/python/3.12.10/python-3.12.10-amd64.exe',
  'https://registry.npmmirror.com/-/binary/python/3.12.10/python-3.12.10-amd64.exe',
  'https://www.python.org/ftp/python/3.12.10/python-3.12.10-amd64.exe'
)
$PythonSize = 26964224
# Python 安装包的官方校验值（两个都指向同一个文件 python-3.12.10-amd64.exe）：
#   * sha256 ← 发布时随包发布的 SPDX SBOM：
#     https://www.python.org/ftp/python/3.12.10/python-3.12.10-amd64.exe.spdx.json
#     （python.org 的下载页只列 MD5，SHA256 只在 SBOM 里；zip 版才有 windows-3.12.10.json 的 sha256）
#   * md5    ← 下载页 https://www.python.org/downloads/release/python-31210/ 的 MD5 checksum 列
# 两个都给：Test-Download 里只要有一个对得上就放行，抄错一个也不会把好文件拦下来。
$PythonSha256 = '67b5635e80ea51072b87941312d00ec8927c4db9ba18938f7ad2d27b328b95fb'
$PythonMd5    = '5eddb0b6f12c852725de071ae681dde4'

$WorkDir = if ($WorkDir) { $WorkDir } else { Join-Path $env:LOCALAPPDATA 'DSH一键装' }
$LogDir  = Join-Path $WorkDir '日志'
$DlDir   = Join-Path $WorkDir '下载缓存'

$Steps = @()
$FailCount = 0
$script:WantModels = $true
$script:WantPlugin = $true   # 第 3 步会问用户要不要装 kb-rag；默认装（回车＝装）

# ----------------------------------------------------------------- 输出
function Say  { param([string]$m) Write-Host ('  ' + $m) }
function Info { param([string]$m) Write-Host ('  [信息] ' + $m) -ForegroundColor Gray }
function Ok   { param([string]$m) Write-Host ('  [完成] ' + $m) -ForegroundColor Green }
function Warn { param([string]$m) Write-Host ('  [注意] ' + $m) -ForegroundColor Yellow }
function Bad  { param([string]$m) Write-Host ('  [失败] ' + $m) -ForegroundColor Red }
function Skip { param([string]$m) Write-Host ('  [跳过] ' + $m) -ForegroundColor DarkGray }
function Head {
  param([string]$m)
  Write-Host ''
  Write-Host ('=' * 64) -ForegroundColor DarkGray
  Write-Host ('  ' + $m) -ForegroundColor Cyan
  Write-Host ('=' * 64) -ForegroundColor DarkGray
}
function Step {
  param([string]$m)
  Write-Host ''
  Write-Host ('-- ' + $m) -ForegroundColor Cyan
}
# 结尾给一句：觉得好用点个 Star / 有问题去 Issues 问一句。
#   - 装成功才提 Star（-AskStar）：装失败了还推销很讨厌；但**失败时更该给 Issues 链接**，
#     新手默认行为是忍着用或者直接卸载，不会想到去提问。
#   - 失败时把日志路径直接写进这句里（-LogPath）：维护者最需要的就是它；它单独一行放在
#     最下面时，用户根本不知道"那就是要贴的东西"。
#   - URL 单独占一行：终端里长地址经常被折行，夹在句子中间就没法复制了。
#   - 配色分开：成功时压暗（DarkGray + Cyan），它只是句引导，不该抢报错的优先级；
#     失败时提亮（Gray + White）—— 那时红字已经打完了，最后这屏最有用的就是这个链接。
function Show-ProjectHint {
  param([switch]$AskStar, [string]$LogPath = '')
  if ($AskStar) {
    Write-Host ''
    Write-Host '  本项目为免费开源项目。如果对你有帮助，欢迎在 GitHub 上点一个 Star（无需注册）：' -ForegroundColor DarkGray
    Write-Host ('    ' + $RepoUrl) -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  安装过程中遇到问题，或有功能建议，可在此反馈：' -ForegroundColor DarkGray
    Write-Host ('    ' + $RepoUrl + '/issues') -ForegroundColor Cyan
    return
  }
  Write-Host ''
  Write-Host '  如遇安装失败，请携带以下两项信息在此提问：' -ForegroundColor Gray
  Write-Host '    ① 窗口中红色的 [失败] 行   ② 下方日志文件' -ForegroundColor Gray
  Write-Host ('    ' + $RepoUrl + '/issues') -ForegroundColor White
  if ($LogPath) { Write-Host ('    ' + $LogPath) -ForegroundColor Gray }
}
function Pad-Display {
  param([string]$Text, [int]$Width)
  # 中文是双宽字符，PadRight 按字符数补空格会错位，这里按显示宽度补。
  $w = 0
  foreach ($ch in $Text.ToCharArray()) {
    $code = [int]$ch
    $wide = (($code -ge 0x1100 -and $code -le 0x115F) -or
             ($code -ge 0x2E80 -and $code -le 0xA4CF) -or
             ($code -ge 0xAC00 -and $code -le 0xD7A3) -or
             ($code -ge 0xF900 -and $code -le 0xFAFF) -or
             ($code -ge 0xFE30 -and $code -le 0xFE6F) -or
             ($code -ge 0xFF00 -and $code -le 0xFF60) -or
             ($code -ge 0xFFE0 -and $code -le 0xFFE6))
    if ($wide) { $w = $w + 2 } else { $w = $w + 1 }
  }
  $pad = $Width - $w
  if ($pad -lt 0) { $pad = 0 }
  return $Text + (' ' * $pad)
}
function Ask-YesNo {
  param([string]$Question, [bool]$DefaultYes = $true)
  if ($Yes) { return $DefaultYes }
  $hint = '[Y/n]'
  if (-not $DefaultYes) { $hint = '[y/N]' }
  try { $a = Read-Host ('  ' + $Question + ' ' + $hint) } catch { return $DefaultYes }
  if ([string]::IsNullOrWhiteSpace($a)) { return $DefaultYes }
  if ($a -match '^(y|yes|Y|YES|Yes|是|好)$') { return $true }
  if ($a -match '^(n|no|N|NO|No|不|否)$') { return $false }
  return $DefaultYes
}
function Record {
  param([string]$Name, [string]$State, [string]$Detail = '')
  $script:Steps += [pscustomobject]@{ 项目 = $Name; 结果 = $State; 说明 = $Detail }
  if ($State -eq '失败') { $script:FailCount = $script:FailCount + 1 }
}
# 等某个检查变成真，超时才放弃。
# 为什么要这个：装完立刻验证一次容易误判 —— 杀软实时扫描、慢盘、写缓存都会让
# 刚写好的文件短暂「看不见」，于是明明装成功了却报失败，用户重跑一次又好了。
# 所有「装完之后要验证」的地方都走这里，别再单次判断。
# 给了 $What 就在等待期间转圈 + 报已等待秒数（见下面的转圈工具箱）；不给就是静默等待。
# $PollMs 按检查本身的代价挑：读文件 250ms 没问题，Find-Python 那种要起进程的必须给 5000。
function Wait-For {
  param([scriptblock]$Test, [int]$Seconds = 20, [string]$What = '', [int]$PollMs = 250, [int]$FrameMs = 120, [switch]$Force)
  $animate = ($What -ne '') -and (Test-SpinConsole -Force:$Force)
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $frame = 0; $nextFrame = 0.0
  while ($true) {
    $v = & $Test
    if ($v) { if ($animate) { Clear-SpinLine }; return $v }
    if ($sw.Elapsed.TotalSeconds -ge $Seconds) { if ($animate) { Clear-SpinLine }; return $null }
    if ($animate -and $sw.Elapsed.TotalMilliseconds -ge $nextFrame) {
      Write-SpinFrame -What $What -Frame $frame -Seconds $sw.Elapsed.TotalSeconds
      $frame++
      $nextFrame = $sw.Elapsed.TotalMilliseconds + $FrameMs
    }
    Start-Sleep -Milliseconds $PollMs
  }
}

# ----------------------------------------------------------------- 转圈动画
# 干等的时候让窗口有动静（\ | / - 循环 + 已等待时间），否则新手会以为卡死、直接关窗口
# ——「装了一半」多半是这么来的。触发方式：Wait-For 传 $What、Wait-ProcessWithSpin。
# 两条实现约束（都踩过）：
#   1) 必须用 [Console]::Write 直接写控制台，**不能**用 Write-Host：Start-Transcript 会把
#      主机输出全量记进日志文件，转圈每秒八帧会把日志刷成几万行，日志就没法发给维护者了。
#   2) 输出被重定向 / 没有真控制台时（被别的程序带起来、在管道里跑）不画动画，静默跳过，
#      和脚本里 [Console]::IsInputRedirected 那几处同一个道理。自测/演示用 -Force 强开。
function Test-SpinConsole {
  param([switch]$Force)
  if ($Force) { return $true }
  try { if ([Console]::IsOutputRedirected) { return $false } } catch { return $false }
  return $true
}
function Format-WaitSpan {
  param([double]$Seconds)
  # 用 Floor 不用 [int]：[int] 是四舍五入，8.6 秒会显示成「9 秒」、59.9 秒会显示成「60 秒」——
  # 等待计时器提前报数会让人以为时钟不准，宁可保守地向下取整。
  $whole = [math]::Floor($Seconds)
  if ($whole -ge 60) {
    return (([math]::Floor($whole / 60)).ToString() + ' 分 ' + ([int]($whole % 60)).ToString() + ' 秒')
  }
  return (([int]$whole).ToString() + ' 秒')
}
# 画一帧。$script:SpinLastLen 记住上一帧长度：新帧比旧帧短时补空格，否则会留下残字。
function Write-SpinFrame {
  param([string]$What, [int]$Frame, [double]$Seconds)
  $chars = @('\', '|', '/', '-')
  $line = '  ' + $chars[$Frame % 4] + ' ' + $What + ' … 已等待 ' + (Format-WaitSpan $Seconds)
  $pad = ''
  if ($script:SpinLastLen -gt $line.Length) { $pad = ' ' * ($script:SpinLastLen - $line.Length) }
  $script:SpinLastLen = $line.Length
  try { [Console]::Write("`r" + $line + $pad) } catch { $script:SpinLastLen = 0 }
}
# 把动画那行擦掉，好让后面的正常输出从行首开始打。
function Clear-SpinLine {
  if ($script:SpinLastLen -gt 0) {
    try { [Console]::Write("`r" + (' ' * $script:SpinLastLen) + "`r") } catch { }
    $script:SpinLastLen = 0
  }
}
$script:SpinLastLen = 0
# 等一个子进程结束，期间转圈。替代 Start-Process -Wait —— 那个只能干等，窗口一片死寂。
# Python 静默安装要一两分钟，是脚本里最长的一段无声等待。
function Wait-ProcessWithSpin {
  param([System.Diagnostics.Process]$Process, [string]$What = '处理中', [int]$FrameMs = 120, [switch]$Force)
  if (-not $Process) { return }
  $animate = Test-SpinConsole -Force:$Force
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $frame = 0; $nextFrame = 0.0
  while (-not $Process.HasExited) {
    if ($animate -and $sw.Elapsed.TotalMilliseconds -ge $nextFrame) {
      Write-SpinFrame -What $What -Frame $frame -Seconds $sw.Elapsed.TotalSeconds
      $frame++
      $nextFrame = $sw.Elapsed.TotalMilliseconds + $FrameMs
    }
    Start-Sleep -Milliseconds 120
  }
  # HasExited 为真时 WaitForExit 立即返回：确保 ExitCode 已经填好，调用方才能读
  try { $Process.WaitForExit() } catch { }
  if ($animate) { Clear-SpinLine }
}

# ----------------------------------------------------------------- 哈希 / 下载
function Get-Sha256Of { param([string]$Path) return (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLower() }
function Get-Md5Of { param([string]$Path) return (Get-FileHash -Path $Path -Algorithm MD5).Hash.ToLower() }
# 校验「这个下载结果能不能用」，按优先级来：
#   1) 给了官方校验值：sha256 / md5 里只要有一个对得上就算过。
#      两个都给时互为兜底 —— 万一其中一个抄错了，另一个还能把正确的文件放行。
#   2) 只给了大小：比字节数。半个文件、镜像返回的 HTML 错误页都会在这儿被挡下来。
#   3) 什么都没有：只能「存在即通过」——这是老行为，**不要再让新的下载走这条路**。
# 教训：python 安装包当初就没给校验值，于是上次中断留下的半个 exe 会被当成完好的安装包直接执行。
# （原来那个「没给哈希就返回 true」的 Test-FileHash 已经删掉了，别再写回来。）
function Test-Download {
  param([string]$Path, [string]$Sha256 = '', [string]$Md5 = '', [long]$ExpectBytes = 0)
  if (-not (Test-Path $Path)) { return $false }
  if ($Sha256 -or $Md5) {
    if ($Sha256 -and (Get-Sha256Of $Path) -eq $Sha256.ToLower()) { return $true }
    if ($Md5 -and (Get-Md5Of $Path) -eq $Md5.ToLower()) { return $true }
    return $false
  }
  if ($ExpectBytes -gt 0) { return ((Get-Item -LiteralPath $Path).Length -eq $ExpectBytes) }
  return $true
}
function Show-Progress {
  param([string]$What, [long]$Done, [long]$Total, [double]$Secs, [switch]$Finish)
  $mb = $Done / 1MB
  $speed = 0.0
  if ($Secs -gt 0.2) { $speed = $mb / $Secs }
  $line = ''
  if ($Total -gt 0) {
    $tmb = $Total / 1MB
    $pct = [int](100 * $Done / $Total)
    $line = '  {0}  {1:N1}/{2:N1} MB ({3}%)  {4:N1} MB/s' -f $What, $mb, $tmb, $pct, $speed
  } else {
    $line = '  {0}  {1:N1} MB  {2:N1} MB/s' -f $What, $mb, $speed
  }
  if ($line.Length -lt 72) { $line = $line.PadRight(72) }
  Write-Host ("`r" + $line) -NoNewline
  if ($Finish) { Write-Host '' }
}
function Save-UrlStream {
  param([string]$Url, [string]$Out, [long]$ExpectBytes = 0, [string]$What = '文件')
  $req = $null; $resp = $null; $fs = $null; $in = $null
  try {
    $req = [System.Net.HttpWebRequest]::Create($Url)
    $req.UserAgent = $UserAgent
    $req.Timeout = 30000
    $req.ReadWriteTimeout = 300000
    $req.AllowAutoRedirect = $true
    $resp = $req.GetResponse()
  } catch {
    Warn ('连接失败：' + $_.Exception.Message)
    if ($resp) { $resp.Close() }
    return $false
  }
  try {
    $total = [long]$resp.ContentLength
    if ($total -le 0) { $total = $ExpectBytes }
    $in = $resp.GetResponseStream()
    $fs = New-Object System.IO.FileStream($Out, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    $buf = New-Object byte[] 262144
    $sum = [long]0
    $lastTick = [long]0
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($true) {
      $n = $in.Read($buf, 0, $buf.Length)
      if ($n -le 0) { break }
      $fs.Write($buf, 0, $n)
      $sum = $sum + $n
      if (($sw.ElapsedMilliseconds - $lastTick) -ge 1000) {
        $lastTick = $sw.ElapsedMilliseconds
        Show-Progress -What $What -Done $sum -Total $total -Secs $sw.Elapsed.TotalSeconds
      }
    }
    Show-Progress -What $What -Done $sum -Total $total -Secs $sw.Elapsed.TotalSeconds -Finish
    if ($total -gt 0 -and $sum -ne $total) {
      Warn ('下载不完整：期望 {0:N0} 字节，实际 {1:N0} 字节' -f $total, $sum)
      return $false
    }
    return ($sum -gt 0)
  } catch {
    Warn ('下载中断：' + $_.Exception.Message)
    return $false
  } finally {
    if ($fs) { $fs.Close() }
    if ($in) { $in.Close() }
    if ($resp) { $resp.Close() }
  }
}
function Save-UrlCurl {
  param([string]$Url, [string]$Out)
  $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
  if (-not $curl) { return $false }
  Info '改用 curl.exe 重试'
  & $curl.Source -L --fail --retry 2 --connect-timeout 20 -o $Out $Url 2>&1 | Out-Null
  if ($LASTEXITCODE -eq 0 -and (Test-Path $Out)) { return $true }
  return $false
}
function Get-Remote {
  param([string[]]$Urls, [string]$Out, [string]$Sha256 = '', [string]$Md5 = '', [long]$ExpectBytes = 0, [string]$What = '文件')
  if (Test-Path $Out) {
    if (Test-Download -Path $Out -Sha256 $Sha256 -Md5 $Md5 -ExpectBytes $ExpectBytes) {
      Skip ($What + ' 此前已下载且校验通过')
      return $true
    }
    Warn ($What + ' 文件已存在但校验不符，删除后重新下载')
    Remove-Item $Out -Force -ErrorAction SilentlyContinue
  }
  if ($DryRun) { Info ('[演练] 将下载 ' + $What + ' ← ' + $Urls[0]); return $true }
  foreach ($u in $Urls) {
    Info ('下载 ' + $What + ' ← ' + $u)
    $got = Save-UrlStream -Url $u -Out $Out -ExpectBytes $ExpectBytes -What $What
    if (-not $got) { $got = Save-UrlCurl -Url $u -Out $Out }
    if ($got) {
      if (Test-Download -Path $Out -Sha256 $Sha256 -Md5 $Md5 -ExpectBytes $ExpectBytes) {
        Ok ($What + ' 下载完成，完整性校验通过')
        try { Unblock-File -Path $Out -ErrorAction SilentlyContinue } catch { }
        return $true
      }
      Bad ($What + ' 校验不通过，改用下一通道重试')
      Remove-Item $Out -Force -ErrorAction SilentlyContinue
    } else {
      Warn '该通道失败，改用下一通道'
    }
  }
  return $false
}

# ----------------------------------------------------------------- 体检
function Get-FreeSpaceGB {
  param([string]$Path)
  try {
    $drive = (Split-Path -Qualifier $Path)
    $d = Get-CimInstance Win32_LogicalDisk -Filter ("DeviceID='" + $drive + "'") -ErrorAction Stop
    if ($d -and $d.FreeSpace) { return [math]::Round($d.FreeSpace / 1GB, 1) }
  } catch { }
  try {
    $letter = (Split-Path -Qualifier $Path).TrimEnd(':')
    $di = New-Object System.IO.DriveInfo($letter)
    if ($di.IsReady) { return [math]::Round($di.AvailableFreeSpace / 1GB, 1) }
  } catch { }
  return -1
}
function Get-TotalRamGB {
  try {
    $cs = Get-CimInstance Win32_ComputerSystem -Property TotalPhysicalMemory -ErrorAction Stop
    if ($cs -and $cs.TotalPhysicalMemory) { return [math]::Round($cs.TotalPhysicalMemory / 1GB, 1) }
  } catch { }
  return 0
}

# ----------------------------------------------------------------- Node
function Get-NodeExe {
  # 只要真正的 node.exe，而且不能是别的软件塞进来的：
  # PATH 上可能先命中 DSH Desktop 在 .desktop-bin 放的 node.cmd 垫片，或它内置的
  # node.exe（...\DSH Desktop\resources\app\node_modules\node\bin\node.exe）。
  # 那些跟着别人的安装目录走，对方一卸载/移动就失效，不能当成本机的 Node。
  $cands = @()
  $cands += (Join-Path $NodeDir 'node.exe')                              # 我们自己装的便携版
  foreach ($pf in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
    if ($pf) { $cands += (Join-Path $pf 'nodejs\node.exe') }             # 官方安装器默认位置
  }
  $cands += (Join-Path $env:LOCALAPPDATA 'Programs\nodejs\node.exe')
  $c = Get-Command node.exe -ErrorAction SilentlyContinue
  if ($c) { $cands += $c.Source }
  $c2 = Get-Command node -ErrorAction SilentlyContinue
  if ($c2) { $cands += $c2.Source }
  foreach ($p in $cands) {
    if (-not $p) { continue }
    if ($p -notmatch '\.exe$') { continue }
    if ($p -match '\\\.desktop-bin\\') { continue }
    if ($p -match 'DSH Desktop') { continue }
    if ($p -match '\\dsh-desktop\\') { continue }
    if (Test-Path $p) { return $p }
  }
  return $null
}
function Get-NodeVersion {
  param([string]$Exe)
  if (-not $Exe) { return $null }
  try {
    $v = & $Exe --version 2>$null
    if ($v -and "$v" -match '^v?\d+\.') { return ("$v").Trim() }
    return $null
  } catch { return $null }
}
function Install-PortableNode {
  # 官方 zip，解压到用户目录，不动系统 PATH（免管理员）。
  $zip = Join-Path $DlDir ("node-$NodeVersion-win-x64.zip")
  # 随包离线：payload\ 里放了同一个 zip 就直接用，不联网（仍然要过 sha256）
  $localZip = Join-Path $RootDir ('payload\node-' + $NodeVersion + '-win-x64.zip')
  if ((Test-Path $localZip) -and -not (Test-Path $zip)) {
    Info ('发现随包自带的 Node 压缩包：' + $localZip)
    Copy-Item $localZip $zip -Force
  }
  if (-not (Get-Remote -Urls $NodeUrls -Out $zip -Sha256 $NodeZipSha256 -ExpectBytes $NodeZipSize -What ('Node.js ' + $NodeVersion))) {
    return $null
  }
  if ($DryRun) { Info ('[演练] 将解压到 ' + $NodeDir); return $null }
  Info ('解压到 ' + $NodeDir)
  $tmp = Join-Path $DlDir ('node-unzip-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
  try {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    Expand-Archive -Path $zip -DestinationPath $tmp -Force
    $inner = @(Get-ChildItem $tmp -Directory | Select-Object -First 1)
    if ($inner.Count -eq 0) { Bad '解压后未找到 node 目录'; return $null }
    # 目的地是 %LOCALAPPDATA%\DSH\node，而它的父目录（我们的安装前缀 %LOCALAPPDATA%\DSH）
    # 在这一步之前还不存在 —— 那个目录原本是第 5 步建快捷方式时才建的。
    # Move-Item 不会替你补父目录：父目录缺了就报「未能找到路径中的某个部分」
    # （DirectoryNotFoundException）。而且这是**非终止**错误，外层 catch 抓不到，
    # 于是日志会自相矛盾：先打「[完成] Node.js 已就位」，紧接着「[失败] Node.js 安装失败」。
    if (-not (Test-Path $Prefix)) { New-Item -ItemType Directory -Force -Path $Prefix -ErrorAction Stop | Out-Null }
    Remove-Item -Recurse -Force $NodeDir -ErrorAction SilentlyContinue
    $innerPath = $inner[0].FullName
    Move-Item -LiteralPath $innerPath -Destination $NodeDir -Force -ErrorAction Stop
    # 没报错 ≠ 真的就位（例如旧目录没删干净时，源目录会被塞进 $NodeDir 里面去）：验一下再报成功
    if (-not (Test-Path (Join-Path $NodeDir 'node.exe'))) { throw ('Node 文件未就位：' + (Join-Path $NodeDir 'node.exe')) }
    Ok ('Node.js 已就位：' + $NodeDir)
  } catch {
    Bad ('解压/就位失败：' + $_.Exception.Message)
    return $null
  } finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
  }
  $exe = Join-Path $NodeDir 'node.exe'
  if (Test-Path $exe) { return $exe }
  return $null
}

# ----------------------------------------------------------------- dsh CLI
function Get-NpmCmd {
  param([string]$NodeExe)
  if (-not $NodeExe) { return $null }
  $dir = Split-Path -Parent $NodeExe
  foreach ($n in @('npm.cmd', 'npm')) {
    $p = Join-Path $dir $n
    if (Test-Path $p) { return $p }
  }
  $c = Get-Command npm -ErrorAction SilentlyContinue
  if ($c) { return $c.Source }
  return $null
}
function Get-NpmPrefix {
  param([string]$Npm, [string]$NodeExe)
  try {
    $p = & $Npm prefix -g 2>$null
    if ($p) { return ("$p").Trim() }
  } catch { }
  return (Join-Path $env:APPDATA 'npm')
}
function Get-InstalledDshVersion {
  param([string]$NpmPrefix)
  if (-not $NpmPrefix) { return $null }
  $pj = Join-Path $NpmPrefix 'node_modules\@deepseek-ai\dsh\package.json'
  if (-not (Test-Path $pj)) { return $null }
  try { return (Get-Content $pj -Raw -Encoding UTF8 | ConvertFrom-Json).version } catch { return $null }
}
function Get-LatestDshVersion {
  param([string]$Npm, [string]$Registry)
  return (Get-LatestNpmVersion -Npm $Npm -Package $DshNpmPkg -Registry $Registry)
}
# 取某个 npm 包的最新版本号。
# 优先直接读 registry 的 packument（dist-tags.latest）—— 比 fork 一个 npm 进程更稳，
# 也不受本机 npm 配置影响；镜像可能滞后，所以两个源都问，取较高的那个。
# 这一点对插件尤其重要：直接用 `@latest` 会被 pnpm 的 minimumReleaseAge 策略「降级」到
# 上一个够老的版本，表现为看似装成功、其实什么都没变（见 kb-rag 仓库 AGENTS.md）。
function Get-PackumentLatest {
  param([string]$Package, [string]$Registry)
  if (-not $Registry) { return $null }
  $url = $Registry.TrimEnd('/') + '/' + ($Package -replace '/', '%2F')
  # 重试两次：进程里第一次 HTTPS 调用偶发失败（TLS 冷启动 / 镜像抖动），重试一次基本都能过。
  for ($attempt = 1; $attempt -le 2; $attempt++) {
    try {
      $j = Invoke-RestMethod -Uri $url -Headers @{ 'User-Agent' = $UserAgent } -TimeoutSec 20 -ErrorAction Stop
      $v = $j.'dist-tags'.latest
      if ($v -and "$v" -match '^\d+\.\d+') { return ("$v").Trim() }
      $script:LastPackumentError = ('响应里没有 dist-tags.latest ← ' + $url)
      return $null
    } catch {
      $script:LastPackumentError = ($_.Exception.Message + '  ← ' + $url)
      if ($attempt -eq 1) { Start-Sleep -Milliseconds 800 }
    }
  }
  return $null
}
# ---- 版本比较：必须自己写，不能用 [version] ----
# .NET 的 System.Version 不接受「0.1.5-rc.1」这种预发布后缀，直接抛异常。
# 而官方 dsh 目前全线是预发布版（0.1.5-rc.1 / 0.1.6-alpha.1），用 [version] 会让
# 版本查询和「有没有新版本」判断永远失效（表现为查不到最新版、永远显示已是最新）。
function ConvertTo-SemverParts {
  param([string]$Version)
  if (-not $Version) { return $null }
  $m = [regex]::Match($Version, '^v?(\d+)(?:\.(\d+))?(?:\.(\d+))?(?:[-+]([0-9A-Za-z\.\-]+))?')
  if (-not $m.Success) { return $null }
  $major = [int]$m.Groups[1].Value
  $minor = 0
  $patch = 0
  if ($m.Groups[2].Success) { $minor = [int]$m.Groups[2].Value }
  if ($m.Groups[3].Success) { $patch = [int]$m.Groups[3].Value }
  $pre = ''
  if ($m.Groups[4].Success) { $pre = $m.Groups[4].Value }
  return [pscustomobject]@{ Major = $major; Minor = $minor; Patch = $patch; Pre = $pre }
}
function Compare-Semver {
  param([string]$Left, [string]$Right)
  # 返回 1（左新）/ 0（相同）/ -1（右新），遵循 semver：同号预发布 < 正式版
  $a = ConvertTo-SemverParts -Version $Left
  $b = ConvertTo-SemverParts -Version $Right
  if (-not $a -and -not $b) { return 0 }
  if (-not $a) { return -1 }
  if (-not $b) { return 1 }
  if ($a.Major -ne $b.Major) { if ($a.Major -lt $b.Major) { return -1 } else { return 1 } }
  if ($a.Minor -ne $b.Minor) { if ($a.Minor -lt $b.Minor) { return -1 } else { return 1 } }
  if ($a.Patch -ne $b.Patch) { if ($a.Patch -lt $b.Patch) { return -1 } else { return 1 } }
  if ((-not $a.Pre) -and $b.Pre) { return 1 }
  if ($a.Pre -and (-not $b.Pre)) { return -1 }
  if ($a.Pre -eq $b.Pre) { return 0 }
  $pa = @($a.Pre -split '\.')
  $pb = @($b.Pre -split '\.')
  $max = [Math]::Max($pa.Count, $pb.Count)
  for ($i = 0; $i -lt $max; $i++) {
    if ($i -ge $pa.Count) { return -1 }
    if ($i -ge $pb.Count) { return 1 }
    $x = $pa[$i]; $y = $pb[$i]
    $xn = 0; $yn = 0
    $xIsNum = [int]::TryParse($x, [ref]$xn)
    $yIsNum = [int]::TryParse($y, [ref]$yn)
    if ($xIsNum -and $yIsNum) {
      if ($xn -ne $yn) { if ($xn -lt $yn) { return -1 } else { return 1 } }
    } elseif ($xIsNum) {
      return -1
    } elseif ($yIsNum) {
      return 1
    } else {
      $c = [string]::CompareOrdinal($x, $y)
      if ($c -ne 0) { if ($c -lt 0) { return -1 } else { return 1 } }
    }
  }
  return 0
}
function Get-LatestNpmVersion {
  param([string]$Npm, [string]$Package, [string]$Registry)
  $found = @()
  $regs = @()
  if ($Registry) { $regs += $Registry }
  $regs += $NpmRegistries
  foreach ($reg in ($regs | Select-Object -Unique)) {
    $v = Get-PackumentLatest -Package $Package -Registry $reg
    if ($v) { $found += $v }
  }
  # HTTP 都不通时，退回问 npm 自己（本机 npm 配了私有源之类的情况）
  if ($found.Count -eq 0 -and $Npm) {
    foreach ($reg in ($regs | Select-Object -Unique)) {
      try {
        $a = @('view', $Package, 'version')
        if ($reg) { $a += @('--registry', $reg) }
        $v = & $Npm @a 2>$null
        if ($v -and "$v" -match '^\d+\.\d+') { $found += ("$v").Trim() }
      } catch { }
    }
  }
  $best = $null
  foreach ($v in $found) {
    if ($null -eq $best -or (Compare-Semver -Left $v -Right $best) -gt 0) { $best = $v }
  }
  return $best
}
function Install-DshCli {
  param([string]$Npm, [string]$Registry)
  # 换源重试：npm 这一步是全脚本里最"一次性"的环节（几百个包，冷启动 DNS/TLS 抖一下
  # 就整步失败，而第二次运行靠 npm 缓存又能过）。失败就自动换下一个源再试一次。
  $regs = @($Registry)
  foreach ($r in $NpmRegistries) { if ($r -ne $Registry) { $regs += $r } }
  foreach ($r in ($regs | Select-Object -Unique)) {
    $a = @('install', '-g', ($DshNpmPkg + '@latest'), 'pnpm@latest', '--no-fund', '--no-audit')
    if ($r) { $a += @('--registry', $r) }
    if ($DryRun) { Info ('[演练] 将执行：npm ' + ($a -join ' ')); return $true }
    Info ('正在执行：npm ' + ($a -join ' '))
    & $Npm @a 2>&1 | ForEach-Object { Write-Host ('    ' + $_) -ForegroundColor DarkGray }
    if ($LASTEXITCODE -eq 0) { return $true }
    Warn ('npm 失败（退出码 ' + $LASTEXITCODE + '），改用下一源重试')
  }
  return $false
}

# ----------------------------------------------------------------- 插件
function Get-InstalledPlugin {
  $p = Join-Path $DshHome ('profiles\' + $ProfileName + '\node_modules\' + $PluginName + '\package.json')
  if (-not (Test-Path $p)) { return $null }
  try { return (Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}
function Install-Plugin {
  param([string]$NodeExe, [string]$NpmPrefix, [string]$Registry, [string]$Version = '')
  $binJs = Join-Path $NpmPrefix 'node_modules\@deepseek-ai\dsh\lib\bin.js'
  if (-not (Test-Path $binJs)) { Bad ('未找到 dsh CLI：' + $binJs); return $false }
  if (-not (Test-Path $DshHome)) {
    if ($DryRun) { Info ('[演练] 将创建 ' + $DshHome) }
    else { New-Item -ItemType Directory -Force -Path $DshHome | Out-Null }
  }
  $spec = $PluginName
  if ($Version) { $spec = "$PluginName@$Version" }
  $oldHome = $env:DSH_HOME
  $oldPath = $env:PATH
  $oldReg  = $env:npm_config_registry
  # 和 npm 那步一样换源重试：pnpm 第一次要建 store、拉包，网络抖一下就会整步失败
  $regs = @($Registry)
  foreach ($r in $NpmRegistries) { if ($r -ne $Registry) { $regs += $r } }
  try {
    $env:DSH_HOME = $DshHome
    # dsh plugin 内部会 spawn('pnpm', ...)，所以全局 npm 目录必须在 PATH 上
    $env:PATH = $NpmPrefix + ';' + (Split-Path -Parent $NodeExe) + ';' + $env:PATH
    foreach ($r in ($regs | Select-Object -Unique)) {
      if ($r) { $env:npm_config_registry = $r } else { Remove-Item Env:\npm_config_registry -ErrorAction SilentlyContinue }
      if ($DryRun) {
        Info ('[演练] 将执行：node ' + $binJs + ' plugin --profile ' + $ProfileName + ' add ' + $spec)
        return $true
      }
      Info ('正在执行：dsh plugin --profile ' + $ProfileName + ' add ' + $spec)
      & $NodeExe $binJs plugin --profile $ProfileName add $spec 2>&1 |
        ForEach-Object { Write-Host ('    ' + $_) -ForegroundColor DarkGray }
      if ($LASTEXITCODE -eq 0) { return $true }
      Warn ('插件安装失败（退出码 ' + $LASTEXITCODE + '），改用下一源重试')
    }
    return $false
  } finally {
    $env:DSH_HOME = $oldHome
    $env:PATH = $oldPath
    if ($oldReg) { $env:npm_config_registry = $oldReg } else { Remove-Item Env:\npm_config_registry -ErrorAction SilentlyContinue }
  }
}

# ----------------------------------------------------------------- Python / 引擎
function Test-PythonExe {
  param([string]$Exe)
  if (-not $Exe) { return $null }
  try {
    $out = & $Exe -c "import sys; print('%d.%d' % sys.version_info[:2])" 2>$null
    if (-not $out) { return $null }
    $parts = ("$out").Trim() -split '\.'
    if ($parts.Count -lt 2) { return $null }
    $num = [int]$parts[0] * 100 + [int]$parts[1]
    if ($num -lt 309) { return $null }
    return ("$out").Trim()
  } catch { return $null }
}
function Find-Python {
  $cands = @()
  $alias = @()   # Microsoft Store 的 App Execution Alias：真 Python 不在时它只是个空壳，放最后再试
  foreach ($name in @('python', 'python3', 'py')) {
    $c = Get-Command $name -ErrorAction SilentlyContinue
    if (-not $c) { continue }
    if ($c.Source -match '\\WindowsApps\\') { $alias += $c.Source; continue }
    $cands += $c.Source
  }
  # 注册表：官方安装器会在这儿登记（HKLM=为所有用户装，HKCU=仅当前用户）。
  # 这是最权威的一处 —— 官方安装器默认**不勾**「Add python.exe to PATH」，
  # 只认 PATH 的话，明明装了 Python 也会被判成「本机没有 Python」，
  # 于是白跑一遍自动安装（用户遇到过的「第一次报错第二次就好」）。
  foreach ($hive in @('HKLM:\SOFTWARE\Python\PythonCore', 'HKCU:\SOFTWARE\Python\PythonCore', 'HKLM:\SOFTWARE\WOW6432Node\Python\PythonCore')) {
    if (-not (Test-Path $hive)) { continue }
    foreach ($k in @(Get-ChildItem $hive -ErrorAction SilentlyContinue)) {
      $props = Get-ItemProperty -Path (Join-Path $k.PSPath 'InstallPath') -ErrorAction SilentlyContinue
      if (-not $props) { continue }
      if ($props.ExecutablePath) { $cands += $props.ExecutablePath; continue }
      $dir = $props.'(default)'
      if ($dir) {
        $e = Join-Path $dir 'python.exe'
        if (Test-Path $e) { $cands += $e }
      }
    }
  }
  foreach ($base in @(
      (Join-Path $env:LOCALAPPDATA 'Programs\Python'),
      (Join-Path $env:ProgramData 'Anaconda3'),
      (Join-Path $env:USERPROFILE 'anaconda3'),
      (Join-Path $env:USERPROFILE 'miniconda3')
    )) {
    if (Test-Path $base) {
      $exe = Join-Path $base 'python.exe'
      if (Test-Path $exe) { $cands += $exe }
      $sub = @(Get-ChildItem $base -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'Python3*' })
      foreach ($s in $sub) {
        $e = Join-Path $s.FullName 'python.exe'
        if (Test-Path $e) { $cands += $e }
      }
    }
  }
  # 「为所有用户安装」的默认位置（C:\Program Files\Python3xx）+ 老的 C:\Python3xx。
  # 之前只扫了 %LOCALAPPDATA%\Programs\Python 和硬编码的 C:\Python31x，这里全补上。
  foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, 'C:\')) {
    if (-not $root -or -not (Test-Path $root)) { continue }
    $sub = @(Get-ChildItem $root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'Python3*' })
    foreach ($s in $sub) {
      $e = Join-Path $s.FullName 'python.exe'
      if (Test-Path $e) { $cands += $e }
    }
  }
  foreach ($c in @(($cands + $alias) | Select-Object -Unique)) {
    $v = Test-PythonExe -Exe $c
    if ($v) { return [pscustomobject]@{ Exe = $c; Version = $v } }
  }
  return $null
}
function Ensure-Python {
  $py = Find-Python
  if ($py) { Ok ('已找到 Python ' + $py.Version + '：' + $py.Exe); return $py }
  Warn '本机未安装 Python 3.9+（知识库引擎需要）'
  if ($DryRun) { Info ('[演练] 将静默安装 Python ' + $PythonVersion); return $null }
  if (-not (Ask-YesNo ('是否现在自动安装 Python ' + $PythonVersion + '（约 26MB，安装到当前用户，无需管理员权限）？') $true)) {
    Bad '已跳过 Python 安装：知识库检索功能将不可用'
    return $null
  }
  $exe = Join-Path $DlDir ('python-' + $PythonVersion + '-amd64.exe')
  if (-not (Get-Remote -Urls $PythonUrls -Out $exe -Sha256 $PythonSha256 -Md5 $PythonMd5 -ExpectBytes $PythonSize -What 'Python 安装包')) {
    Bad 'Python 安装包下载失败'
    return $null
  }
  Info '正在静默安装 Python（当前用户）…'
  try {
    $a = @('/quiet', 'InstallAllUsers=0', 'PrependPath=1', 'Include_launcher=0', 'Include_test=0', 'Include_doc=0', 'SimpleInstall=1')
    # 不用 Start-Process -Wait：那个只能干等。Python 静默安装要一两分钟，期间窗口一声不吭，
    # 新手以为卡死就关窗口 —— 装了一半的 Python 比没装更难查。改成轮询 + 转圈 + 已等待时间。
    $p = Start-Process -FilePath $exe -ArgumentList $a -PassThru
    Wait-ProcessWithSpin -Process $p -What '正在静默安装 Python'
    Info ('Python 安装程序退出码：' + $p.ExitCode)
  } catch {
    Bad ('Python 安装失败：' + $_.Exception.Message)
    return $null
  }
  # 安装器收尾、杀软扫描都可能让 python.exe 晚几秒才可见 —— 轮询等一会儿再下结论。
  # （只等 3 秒就报错，正是「第一次报错、第二次就好」的典型来源。）
  # 这一分钟同样不能是死寂的：给 $What 就会转圈 + 报秒数。
  # Find-Python 要起进程逐个探测，别按默认 250ms 轮询（60 秒会探测 240 次），保持 5 秒一次。
  $py = Wait-For { Find-Python } -Seconds 60 -What '等待 Python 安装完成' -PollMs 5000
  if ($py) { Ok ('Python ' + $py.Version + ' 安装完成：' + $py.Exe); return $py }
  Bad '安装程序已结束，但仍未找到 Python；请手动安装后重新运行本脚本'
  return $null
}
function Invoke-EngineScript {
  param([string]$Installer, [string[]]$Arguments)
  # 加 "< NUL"：上游冒烟测试会把 JSON 写进 python 的 stdin，而 PS 5.1 在 UTF-8 控制台下
  # 写这个管道会多带 BOM，引擎直接报 Unexpected UTF-8 BOM。把子进程 stdin 从控制台摘开即可。
  $quoted = @()
  foreach ($a in $Arguments) {
    if ($a -match '[\s"]') { $quoted += ('"' + $a + '"') } else { $quoted += $a }
  }
  $line = 'powershell ' + ($quoted -join ' ') + ' < NUL'
  $script:LastEngineOutput = ''
  & cmd.exe /c $line 2>&1 | ForEach-Object {
    $script:LastEngineOutput += ("$_" + "`n")
    Write-Host ('    ' + $_) -ForegroundColor DarkGray
  }
  return $LASTEXITCODE
}
function Test-EngineSelfCheck {
  param([string]$PluginDir, [string]$PythonExe)
  $engine = Join-Path $PluginDir 'kb_engine.py'
  if (-not (Test-Path $engine)) { return $false }
  $py = $PythonExe
  if (-not $py) {
    $found = Find-Python
    if (-not $found) { return $false }
    $py = $found.Exe
  }
  $smokeDir = Join-Path ([System.IO.Path]::GetTempPath()) ('kbrag-selfcheck-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
  $reqFile = Join-Path ([System.IO.Path]::GetTempPath()) ('kbrag-req-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.json')
  $body = '{"kb_root":"' + ($smokeDir -replace '\\', '/') + '"}'
  try {
    [IO.File]::WriteAllText($reqFile, $body, (New-Object System.Text.UTF8Encoding($false)))
    $line = '"' + $py + '" "' + $engine + '" stats < "' + $reqFile + '"'
    $out = & cmd.exe /c $line 2>&1 | Out-String
    if ("$out" -match '"ok"\s*:\s*true') {
      $ver = '?'
      $m = [regex]::Match("$out", '"engine"\s*:\s*"([^"]+)"')
      if ($m.Success) { $ver = $m.Groups[1].Value }
      Info ('引擎自检通过（engine v' + $ver + '）')
      return $true
    }
    Warn ('引擎自检输出异常：' + ("$out").Trim())
    return $false
  } catch {
    Warn ('引擎自检执行失败：' + $_.Exception.Message)
    return $false
  } finally {
    Remove-Item $reqFile -Force -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force $smokeDir -ErrorAction SilentlyContinue
  }
}
function Install-Engine {
  param([string]$PluginDir, [string]$PythonExe)
  $script:LastEngineFailReason = ''
  $installer = Join-Path $PluginDir 'scripts\install.ps1'
  if (-not (Test-Path $installer)) {
    $installer = Join-Path $RootDir 'vendor\install.ps1'
    if (-not (Test-Path $installer)) {
      if ($DryRun) {
        Info '[演练] 插件安装完成后，此处将调用其自带的 scripts\install.ps1 安装依赖与模型'
        return $true
      }
      # 这条失败几乎总是第 3 步（插件）没成功导致的 —— 说清楚，别让人以为引擎脚本本身丢了
      Bad ('未找到引擎安装脚本：' + (Join-Path $PluginDir 'scripts\install.ps1'))
      Say '  该脚本随插件一同安装：第 3 步未成功时，此处必然找不到。'
      Say ('  请先解决第 3 步再重新运行；也可将插件自带的 scripts\install.ps1 放入 ' + (Join-Path $RootDir 'vendor') + ' 作为离线回退。')
      $script:LastEngineFailReason = '未找到引擎安装脚本（插件未安装成功）'
      return $false
    }
    Info '使用随包附带的引擎安装脚本'
  } else {
    Info '使用插件自带的引擎安装脚本（与已安装版本一致）'
  }
  $mirror = $PipMirror
  if (-not $mirror) { $mirror = $PipMirrors[0] }
  $env:HF_ENDPOINT = $HfEndpoint
  Info ('pip 镜像：' + $mirror)
  Info ('模型镜像：' + $HfEndpoint)

  $engineArgs = @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $installer,
    '-Profile', $ProfileName, '-Yes', '-SkipNode', '-SkipDsh',
    '-Mirror', $mirror
  )
  if ($script:WantModels) { $engineArgs += '-Models' } else { $engineArgs += '-NoModels' }

  if ($DryRun) { Info ('[演练] 将执行：powershell ' + ($engineArgs -join ' ') + ' < NUL'); return $true }

  $code = Invoke-EngineScript -Installer $installer -Arguments $engineArgs
  if ($code -eq 0) { return $true }

  if ($script:LastEngineOutput -match 'Unexpected UTF-8 BOM') {
    Warn '上游冒烟测试报告 UTF-8 BOM：这是 PowerShell 管道的编码问题，并非引擎故障'
    if (Test-EngineSelfCheck -PluginDir $PluginDir -PythonExe $PythonExe) {
      Warn '引擎本身正常，按成功处理'
      return $true
    }
  }
  Warn ('引擎安装脚本退出码 ' + $code)
  $script:LastEngineFailReason = ('引擎安装脚本退出码 ' + $code + '（pip 源或网络问题，可更换镜像后重新运行）')
  foreach ($m in $PipMirrors) {
    if ($m -eq $mirror) { continue }
    Warn ('更换 pip 镜像重试：' + $m)
    $retryArgs = @()
    for ($i = 0; $i -lt $engineArgs.Count; $i++) {
      if ($engineArgs[$i] -eq '-Mirror') { $retryArgs += @('-Mirror', $m); $i++ }
      else { $retryArgs += $engineArgs[$i] }
    }
    if ((Invoke-EngineScript -Installer $installer -Arguments $retryArgs) -eq 0) { return $true }
  }
  return $false
}

# ----------------------------------------------------------------- 快捷方式
function New-Shortcuts {
  param([string]$NodeExe, [string]$NpmPrefix)
  if ($DryRun) { Info '[演练] 将创建桌面快捷方式与启动器'; return }
  if (-not (Test-Path $Prefix)) { New-Item -ItemType Directory -Force -Path $Prefix | Out-Null }

  # 图标与启动器放到固定位置（快捷方式不能指向安装包目录，用户可能把它删了）
  # 图标用 DeepSeek 官方图标（deepseek.com 的 favicon，品牌蓝 #4D6BFE），
  # 已重打成 16~256 多尺寸，小尺寸下不会糊。
  # 文件名别改回 dsh-icon.ico：那个路径曾被鲸鱼娘图标占用过，Windows 图标缓存按路径记着旧图，
  # 内容换成官方图标后缓存不认，桌面会一直显示旧图标。换个新文件名才能让缓存失效。
  $icon = Join-Path $Prefix 'deepseek.ico'
  $srcIco = Join-Path $RootDir 'assets\deepseek.ico'
  if (Test-Path $srcIco) {
    Copy-Item $srcIco $icon -Force -ErrorAction SilentlyContinue
    try { Unblock-File -Path $icon -ErrorAction SilentlyContinue } catch { }
  }
  else { Warn '安装包中缺少 assets\deepseek.ico，快捷方式将使用系统默认图标' }

  $launcher = Join-Path $Prefix 'dsh-web.ps1'
  $srcLauncher = Join-Path $ScriptDir 'dsh-web.ps1'
  if (Test-Path $srcLauncher) {
    Copy-Item $srcLauncher $launcher -Force
    # 从网上下载的 zip 解压出来会带「来自 Internet」标记。-ExecutionPolicy Bypass 挡得住
    # 执行策略，但挡不住组策略/AppLocker 更严的机器 —— 去掉标记，省掉一类"点了没反应"。
    try { Unblock-File -Path $launcher -ErrorAction SilentlyContinue } catch { }
    # 把已解析好的路径写成配置，启动器优先用它（省得每次重新猜）
    $cfg = [pscustomobject]@{
      node      = $NodeExe
      npmPrefix = $NpmPrefix
      dshHome   = $DshHome
      port      = $WebPort
      writtenAt = (Get-Date).ToString('s')
    }
    $cfg | ConvertTo-Json | Set-Content -Path (Join-Path $Prefix 'launch.json') -Encoding UTF8
    Ok ('启动器已就位：' + $launcher)
  } else {
    Warn '安装包中缺少 tools\dsh-web.ps1，跳过启动器'
  }

  $sh = New-Object -ComObject WScript.Shell
  $desktop = [Environment]::GetFolderPath('Desktop')
  $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

  # ---------------------------------------------------------------------------
  # 只碰自己建的快捷方式。
  # 教训：早先的版本会无脑 CreateShortcut + Save，把**别人建的**快捷方式一起改掉了
  # —— 具体是把 DSH Desktop（第三方客户端，不是官方 DSH）的安装器建的「DSH Desktop」
  # 快捷方式（桌面 + 开始菜单各一个）的图标改成了我们的图。别人的快捷方式一律不准
  # 覆盖；同名但不是我们的，就换个名字，别动它。
  # ---------------------------------------------------------------------------
  function Test-ShortcutOurs {
    param([string]$Path, [string]$ExpectedTarget, [string]$ArgsLike = '')
    if (-not (Test-Path $Path)) { return $true }   # 不存在，可以放心建
    try {
      $existing = $sh.CreateShortcut($Path)
      if ($existing.TargetPath -ne $ExpectedTarget) { return $false }
      if ($ArgsLike -and ("$($existing.Arguments)" -notlike ('*' + $ArgsLike + '*'))) { return $false }
      return $true
    } catch { return $false }
  }

  if (Test-Path $launcher) {
    try {
      $lnk = Join-Path $desktop 'DeepSeek Harness.lnk'
      if (-not (Test-ShortcutOurs -Path $lnk -ExpectedTarget $psExe -ArgsLike 'dsh-web.ps1')) {
        Warn '桌面已存在同名快捷方式「DeepSeek Harness」，但并非本脚本创建：为避免误改，本次改用其他名称'
        $lnk = Join-Path $desktop 'DeepSeek Harness（网页版）.lnk'
      }
      $s = $sh.CreateShortcut($lnk)
      $s.TargetPath = $psExe
      $s.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $launcher + '"'
      $s.WorkingDirectory = $Prefix
      if (Test-Path $icon) { $s.IconLocation = $icon + ',0' }
      $s.Description = 'DeepSeek Harness'
      $s.Save()
      Ok ('桌面快捷方式：' + $lnk)
    } catch { Warn ('创建快捷方式失败：' + $_.Exception.Message) }
  }

  # 更新入口不单独建快捷方式：想更新就重新双击一次解压目录里的「install.cmd」。
  # （用户明确要求：更新不需要再占一个桌面图标）
}

# ================================================================= 主流程
$logFile = Join-Path $LogDir ('安装日志-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
if (-not $CheckOnly) {
  # $Prefix（%LOCALAPPDATA%\DSH）也在这里先建好：便携 Node、启动器、图标都落在里面，
  # 后面的步骤（含解压 Node）都假设它存在。
  foreach ($d in @($WorkDir, $DlDir, $LogDir, $Prefix)) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Force -Path $d -ErrorAction SilentlyContinue | Out-Null }
  }
  try { Start-Transcript -Path $logFile -Force | Out-Null } catch { }
}

Head 'DSH 一键装：官方 DeepSeek Harness web（kb-rag 知识库可选）'
Say '本脚本将安装以下内容（已安装的部分会自动跳过）：'
Say '   1. Node.js 运行时（仅在缺失时安装）'
Say '   2. 官方 DSH 命令行工具（含 web 端）+ pnpm'
Say '   3. 桌面快捷方式（双击即打开 DSH 网页界面）'
Write-Host ''
Say '以下两项供知识库（kb-rag 插件）使用，是否安装由你决定；第 3 步将进行询问：'
Say '直接回车表示安装（默认）；输入 n 表示只安装官方 DSH web，日后需要时重新运行本脚本即可。'
Say '   4. kb-rag 本地文献知识库插件（可读取论文并带引用回答）'
Say '   5. Python 环境、插件依赖、检索模型'
Write-Host ''
Say '全程约 8-15 分钟，主要耗时在下载。过程中请勿关闭窗口。'
if ($DryRun) { Warn '演练模式：仅打印将要执行的操作，不进行下载或安装' }
if ($CheckOnly) { Warn '体检模式：仅检查现状，不做任何改动' }

# ---- 开工前的自检：把「新手最容易踩、而且一踩就卡死」的三件事先查掉 ----
# 全部放在动手之前。等走到第 3 步才报「找不到引擎安装脚本」，用户根本不知道是自己解压不全。
Info ('安装包 v' + $PackageVersion + ' ｜ 运行位置：' + $RootDir)

# 1) 包是否完整。常见坏情况：解压中断、只把几个文件拖出来、被杀软删掉个别文件。
#    不致命 —— 缺图标只影响图标、缺文档完全不影响安装 —— 所以只警告不中止。
$needFiles = @('tools\install.ps1', 'tools\dsh-web.ps1', 'GETTING-STARTED.txt', 'MODEL-SETUP.txt', 'NEXT-STEPS.txt', 'assets\deepseek.ico')
$lackFiles = @()
foreach ($rel in $needFiles) { if (-not (Test-Path (Join-Path $RootDir $rel))) { $lackFiles += $rel } }
if ($lackFiles.Count) {
  Warn ('安装包不完整，缺少 ' + $lackFiles.Count + ' 个文件：' + ($lackFiles -join '、'))
  Warn '  多半是解压没完成，或只拖出来个别文件。建议重新完整解压一次再运行。'
  Warn '  （缺图标只影响图标、缺说明文档不影响安装，本次仍会继续。）'
}

# 2) 管理员运行。本脚本不需要管理员权限；真正的问题是：如果这台电脑平时用**另一个**账户
#    登录，提权后 %USERPROFILE% 变成管理员账户的，装好的快捷方式和 dsh 命令都落在那边，
#    用户在自己的桌面和命令行里什么都看不到 —— 然后就会来报「装了但找不到」。
$isAdmin = $false
try { $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) } catch { }
if ($isAdmin) {
  Warn '检测到以管理员身份运行 —— 本脚本不需要管理员权限。'
  Warn '  若这台电脑平时用另一个账户登录，装好的东西会落在当前管理员账户下，你在自己的桌面上看不到。'
  Warn '  建议关掉本窗口，直接双击 install.cmd（不要选「以管理员身份运行」）。'
}

# ---------------------------------------------------------------- 0 体检
Step '第 0 步 / 体检'
try {
  $os = [Environment]::OSVersion.Version
  if ($os.Major -lt 10) { Warn ('Windows 版本偏低：' + $os) } else { Ok ('Windows ' + $os.Major + '.' + $os.Minor) }
} catch { }
$ram = Get-TotalRamGB
if ($ram -le 0) { Info '无法读取内存大小（不影响安装）' }
elseif ($ram -ge 8) { Ok ('内存 ' + $ram + ' GB') }
else { Warn ('内存仅 ' + $ram + ' GB，建议 8GB 以上（精排模型约 1.1GB，内存偏紧）') }
$free = Get-FreeSpaceGB -Path $env:LOCALAPPDATA
$spaceDrive = Split-Path -Qualifier $env:LOCALAPPDATA
if ($free -ge 0) {
  if ($free -ge 8) { Ok ($spaceDrive + ' 可用空间 ' + $free + ' GB') }
  elseif ($free -ge 5) { Warn ($spaceDrive + ' 可用空间 ' + $free + ' GB，够用但偏紧（全部安装约需 4GB）') }
  else { Bad ($spaceDrive + ' 可用空间只有 ' + $free + ' GB，很可能不足（建议先清理至 8GB 以上）'); if (-not (Ask-YesNo '是否继续？' $false)) { exit 1 } }
} else {
  Info '无法读取磁盘可用空间（不影响安装）'
}
$nodeNow = Get-NodeExe
if ($nodeNow) { Ok ('已有 Node.js ' + (Get-NodeVersion -Exe $nodeNow) + '：' + $nodeNow) } else { Info '尚未安装 Node.js（后续将自动安装）' }
$pyNow = Find-Python
if ($pyNow) { Ok ('已有 Python ' + $pyNow.Version) } else { Info '尚未安装 Python（后续将自动安装）' }
$plugNow = Get-InstalledPlugin
if ($plugNow) { Ok ('已有插件 ' + $plugNow.name + ' ' + $plugNow.version) } else { Info '尚未安装 kb-rag 插件' }
$hf = Join-Path $env:USERPROFILE '.cache\huggingface\hub'
if (Test-Path $hf) {
  $hfSize = [math]::Round((Get-ChildItem -Recurse -File $hf -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum / 1GB, 2)
  Info ('模型缓存已有约 ' + $hfSize + ' GB')
}

if ($CheckOnly) {
  Head '体检结束（未做任何改动）'
  try { Stop-Transcript | Out-Null } catch { }
  if (-not $NoPause -and -not [Console]::IsInputRedirected) { Read-Host '按回车关闭窗口' | Out-Null }
  exit 0
}

# ---------------------------------------------------------------- 自检
if ($SelfTest) {
  Head '自检：Node 下载通道 + npm 源'
  Say '仅下载并校验，不安装任何内容。'
  $zip = Join-Path $DlDir ("node-$NodeVersion-win-x64.zip")
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  if (Get-Remote -Urls $NodeUrls -Out $zip -Sha256 $NodeZipSha256 -ExpectBytes $NodeZipSize -What ('Node.js ' + $NodeVersion)) {
    $sw.Stop()
    $size = (Get-Item $zip).Length
    Ok ('下载 + 校验通过：{0:N0} 字节，用时 {1:N1} 秒（{2:N2} MB/s）' -f $size, $sw.Elapsed.TotalSeconds, ($size / 1MB / $sw.Elapsed.TotalSeconds))
  } else {
    Bad 'Node.js 下载通道全部失败'
  }
  $npmTmp = Get-NpmCmd -NodeExe (Get-NodeExe)
  if ($npmTmp) {
    $v = Get-LatestDshVersion -Npm $npmTmp -Registry ''
    if ($v) { Ok ($DshNpmPkg + ' 最新版：' + $v) } else { Warn '查询最新版失败（npm 源不可达）' }
  } else {
    Warn '未找到 npm，跳过 npm 源测试'
  }
  Head '自检结束'
  try { Stop-Transcript | Out-Null } catch { }
  if (-not $NoPause -and -not [Console]::IsInputRedirected) { Read-Host '按回车关闭窗口' | Out-Null }
  exit 0
}

# ---------------------------------------------------------------- 1 Node
Head '第 1 步 / Node.js 运行时'
$nodeExe = $null
if ($SkipNode) {
  Skip '按参数要求跳过 Node.js 步骤'
  $nodeExe = Get-NodeExe
  Record 'Node.js' '跳过' '命令行指定 -SkipNode'
} else {
  $nodeExe = Get-NodeExe
  $nodeVer = Get-NodeVersion -Exe $nodeExe
  if ($nodeExe -and $nodeVer) {
    Ok ('使用已有的 Node.js ' + $nodeVer)
    Record 'Node.js' '已就绪' ($nodeVer + '（系统已有）')
  } elseif ($DryRun) {
    # 演练：Install-PortableNode 在 DryRun 下只打印「将下载/将解压」然后返回 $null，
    # 那不是失败。当成失败的话，演练会在干净机器上输出一串红字并以退出码 1 结束，
    # 看起来像脚本坏了（而文档写的是「演练＝只打印将要做什么」）。
    Info ('[演练] 将下载并解压便携版 Node.js ' + $NodeVersion + ' 到 ' + $NodeDir)
    Record 'Node.js' '将安装' ('便携版 ' + $NodeVersion)
  } else {
    Info '未找到可用的 Node.js，将自动下载便携版'
    $nodeExe = Install-PortableNode
    if ($nodeExe) {
      $nodeVer = Get-NodeVersion -Exe $nodeExe
      Ok ('Node.js ' + $nodeVer + ' 已就位')
      Record 'Node.js' '已安装' ($nodeVer + '（便携版）')
    } else {
      Bad 'Node.js 安装失败：后续步骤无法继续'
      Record 'Node.js' '失败' '下载或解压失败'
    }
  }
}

# ---------------------------------------------------------------- 2 dsh CLI
Head '第 2 步 / 官方 DSH 命令行工具（含 web 端）'
$npmPrefix = ''
if (-not $nodeExe) {
  if ($DryRun) {
    # 演练：Node 是「上一步会装好」的东西，别报成失败
    Info ('[演练] 将执行：npm install -g ' + $DshNpmPkg + '@latest pnpm@latest')
    Record 'DSH CLI' '将安装' 'npm install -g（演练）'
  } else {
    Bad '未找到 Node.js，跳过'
    Record 'DSH CLI' '失败' '缺少 Node.js'
  }
} else {
  $npm = Get-NpmCmd -NodeExe $nodeExe
  if (-not $npm) {
    Bad '已找到 node，但未找到 npm'
    Record 'DSH CLI' '失败' '缺少 npm'
  } else {
    $npmPrefix = Get-NpmPrefix -Npm $npm -NodeExe $nodeExe
    $installed = Get-InstalledDshVersion -NpmPrefix $npmPrefix
    $reg = $NpmRegistry
    if (-not $reg) { $reg = $NpmRegistries[0] }
    $latest = Get-LatestDshVersion -Npm $npm -Registry $reg
    if ($latest) { Info ('npm 上的最新版：' + $latest) } else { Warn ('无法查询最新版：' + $script:LastPackumentError) }

    if ($SkipDshCli) {
      Skip '按参数要求跳过'
      Record 'DSH CLI' '跳过' '命令行指定 -SkipDshCli'
    } else {
      $need = $false
      if (-not $installed) {
        $need = $true
        Info '本机尚未安装，将进行安装'
      } else {
        Ok ('已安装 ' + $installed)
        if ($latest -and (Compare-Semver -Left $latest -Right $installed) -gt 0) {
          $need = $true
          Info ('发现新版本：' + $installed + ' → ' + $latest)
        } else {
          Skip ('已是最新（本机 ' + $installed + '）')
          Record 'DSH CLI' '已最新' ('v' + $installed)
        }
      }
      if ($need) {
        if (Install-DshCli -Npm $npm -Registry $reg) {
          # 装完别只看一眼：杀软/慢盘会让刚写好的文件短暂读不到，等它出现再报成功
          $after = Wait-For { Get-InstalledDshVersion -NpmPrefix $npmPrefix } -Seconds 20 -What '等待 DSH CLI 就位'
          if (-not $after) {
            Bad 'npm 报告安装完成，但全局目录中读不到 dsh 的版本号（可能被安全软件拦截）'
            Record 'DSH CLI' '失败' '安装后验证失败'
          } else {
            Ok ('DSH CLI 已就绪：v' + $after)
            Record 'DSH CLI' '已安装' ('v' + $after)
          }
        } else {
          Bad 'DSH CLI 安装失败（网络或 npm 源问题，可重新运行本脚本）'
          Record 'DSH CLI' '失败' 'npm install -g 失败'
        }
      }
    }
  }
}

# ---------------------------------------------------------------- 3 插件
Head '第 3 步 / 安装或更新 kb-rag 插件'
if ($SkipPlugin) {
  Skip '按参数要求跳过插件步骤'
  Record '插件 kb-rag' '跳过' '命令行指定 -SkipPlugin'
} elseif (-not (Ask-YesNo '是否安装 kb-rag 文献知识库插件？（直接回车表示安装；输入 n 表示只安装官方 DSH web，不含知识库功能）' $true)) {
  # 允许用户只要官方 DSH web：回车＝照旧装插件，回答 n ＝跳过插件（第 4 步的 Python/引擎也跟着跳过）
  $script:WantPlugin = $false
  Skip '已选择只安装官方 DSH web；日后如需知识库功能，重新运行本脚本并在本步骤回车即可'
  Record '插件 kb-rag' '跳过' '用户选择不装'
} elseif (-not $nodeExe -or -not $npmPrefix) {
  if ($DryRun) {
    # 演练：dsh CLI 会在第 2 步装好，这里只说明将要执行什么
    $v = $PluginVersion
    if (-not $v) { $v = Get-LatestNpmVersion -Package $PluginName -Registry $NpmRegistry }
    if (-not $v) { $v = '最新版' }
    Info ('[演练] 将执行：dsh plugin --profile ' + $ProfileName + ' add ' + $PluginName + '@' + $v)
    Record '插件 kb-rag' '将安装' ($PluginName + '@' + $v + '（演练）')
  } else {
    Bad '缺少 dsh CLI，无法安装插件'
    Record '插件 kb-rag' '失败' '缺少 dsh CLI'
  }
} else {
  $before = Get-InstalledPlugin
  # 钉住确切版本：直接用 @latest 会被 pnpm 的 minimumReleaseAge 降级到"够老"的那个，
  # 看起来装成功、实际版本没变（kb-rag 仓库 AGENTS.md 记录的坑）。
  $pkgVersion = $PluginVersion
  if (-not $pkgVersion) {
    $npmForPlugin = Get-NpmCmd -NodeExe $nodeExe
    $pkgVersion = Get-LatestNpmVersion -Npm $npmForPlugin -Package $PluginName -Registry $NpmRegistry
    if ($pkgVersion) {
      Info ('插件最新版：' + $pkgVersion + '（按确切版本安装，避免被 pnpm 的发布年龄策略降级）')
    } else {
      Warn '无法查询插件最新版号，改用 @latest（若安装后版本未变化，请重新运行）'
      $pkgVersion = 'latest'
    }
  }
  if (Install-Plugin -NodeExe $nodeExe -NpmPrefix $npmPrefix -Registry $NpmRegistry -Version $pkgVersion) {
    if ($DryRun) {
      Info '[演练] 跳过插件安装'
      if ($pkgVersion -eq 'latest') { Record '插件 kb-rag' '将安装' '最新版' }
      else { Record '插件 kb-rag' '将安装' ('v' + $pkgVersion) }
    } else {
    # 装完轮询等它出现：一次读不到就断言失败，是「第一次报错第二次就好」的另一大来源
    $after = Wait-For { Get-InstalledPlugin } -Seconds 20 -What '等待插件写入 profile'
    if ($after) {
      if ($before -and $before.version -eq $after.version) { Skip ('已经是 ' + $after.version) }
      else { Ok ('插件已就绪：' + $after.name + ' ' + $after.version) }
      Record '插件 kb-rag' '已就绪' ('v' + $after.version)
    } else {
      Bad '命令已执行完毕，但 profile 中未找到插件；请将日志提供给维护者'
      Record '插件 kb-rag' '失败' '安装后未找到'
    }
    }
  } else {
    Bad '插件安装失败（网络或 npm 源问题，可重新运行本脚本）'
    Record '插件 kb-rag' '失败' 'dsh plugin add 失败'
  }
}

# ---------------------------------------------------------------- 4 引擎
Head '第 4 步 / Python 环境与引擎依赖'
$pluginDir = Join-Path $DshHome ('profiles\' + $ProfileName + '\node_modules\' + $PluginName)
if ($SkipEngine) {
  Skip '按参数要求跳过引擎步骤'
  Record 'Python 引擎' '跳过' '命令行指定 -SkipEngine'
} elseif (-not $script:WantPlugin) {
  Skip '按你的选择：未安装 kb-rag 插件，因此无需安装 Python 与引擎依赖'
  Record 'Python 引擎' '跳过' '用户选择不装插件'
} elseif (-not $DryRun -and -not (Get-InstalledPlugin)) {
  # 插件没装上（第 3 步失败）→ Python/torch/模型都没有意义，整步跳过。
  # 以前会硬着头皮往下跑，最后只报一句「找不到引擎安装脚本」，把真正的根因盖掉了。
  Skip '未安装 kb-rag 插件，跳过 Python 与引擎依赖'
  Record 'Python 引擎' '跳过' '未安装 kb-rag 插件'
} else {
  $py = Ensure-Python
  if (-not $py -and $DryRun) {
    # 演练：Ensure-Python 只打印「将静默安装 Python」然后返回 $null，那不是失败
    Record 'Python 引擎' '将安装' ('Python ' + $PythonVersion + ' + 引擎依赖（演练）')
    Info '[演练] 装好 Python 后，这里会调用插件自带的 scripts\install.ps1 装依赖和模型'
  } elseif (-not $py) {
    Record 'Python 引擎' '失败' '未找到可用的 Python'
    Say '  可手动安装 Python 后重新运行本脚本：https://www.python.org/downloads/'
  } else {
    if ($NoModels) {
      $script:WantModels = $false
      Info '按参数要求：跳过模型预下载（首次检索时引擎会自动下载）'
      Record '检索模型' '跳过' '命令行指定 -NoModels'
    } else {
      $embedDir  = Join-Path $env:USERPROFILE '.cache\huggingface\hub\models--BAAI--bge-small-zh-v1.5'
      $rerankDir = Join-Path $env:USERPROFILE '.cache\huggingface\hub\models--BAAI--bge-reranker-base'
      $modelNote = '基础 + 精排模型均已缓存'
      if (Test-Path $embedDir) { Ok '基础检索模型已缓存（95MB）' } else { Info '需要下载基础检索模型（95MB）' }
      if (Test-Path $rerankDir) {
        Ok '精排模型已缓存（约 1.1GB）'
      } else {
        Write-Host ''
        Say '知识库有两种检索模式：'
        Say '   - 基础模式：可检索到文献，速度较快，模型仅需 95MB'
        Say '   - 精排模式：检索更准确（跨文献问答质量明显更好），但需额外下载 1.1GB 模型'
        # 别写「不装就用不了插件」——那是假的：精排不可用时引擎会降级继续（kb_engine.py
        # 检索路径 try/except 后附一句「精排不可用」），所以要说清**真实**的损失，
        # 真话比吓唬更有说服力，也不会让用户跳过之后回来质疑文档。
        Say '建议一并下载。跳过将产生两个后果：'
        Say '   - 这约 1.2GB（基础 95MB + 精排 1.1GB）将推迟到首次检索时下载：需在会话中等待，网络受限时还可能失败；'
        Say '   - 精排不可用时，引擎不再判断「库中是否存在相关内容」：'
        Say '     提问库外内容时不会提示「无关」，仅返回分数，排序质量也明显下降。'
        $want = Ask-YesNo '是否现在一并下载精排模型？（直接回车表示下载；输入 n 表示以后再说）' $true
        $script:WantModels = $want
        if (-not $want) {
          Warn '已选择跳过：约 1.2GB 将推迟到首次检索时下载（网络受限时可能失败）'
          Warn '  且精排不可用：将失去「无关判定」，排序质量下降。如需补下载：重新运行本脚本，在第 4 步回车。'
          $modelNote = '未预下载（首次检索时自动下载约 1.2GB）'
        } else {
          $modelNote = '基础 + 精排模型已下载'
        }
      }
      Record '检索模型' '已就绪' $modelNote
    }
    Write-Host ''
    Info '开始安装引擎依赖（torch 等，约 200MB，本步骤耗时最长）…'
    if (Install-Engine -PluginDir $pluginDir -PythonExe $py.Exe) {
      if ($DryRun) {
        Info '[演练] 跳过实际安装'
        Record 'Python 引擎' '将安装' ('Python ' + $py.Version)
      } else {
        Ok '引擎依赖安装完成，冒烟测试通过'
        Record 'Python 引擎' '已就绪' ('Python ' + $py.Version)
      }
    } else {
      # 用 Install-Engine 记下的真实原因：只说「install.ps1 未成功」会把「插件没装上」
      # 这种根因藏起来，用户看不出该去修哪一步。
      $why = $script:LastEngineFailReason
      if (-not $why) { $why = 'install.ps1 未成功' }
      Bad ('引擎依赖安装失败：' + $why)
      Record 'Python 引擎' '失败' $why
    }
  }
}

# ---------------------------------------------------------------- 5 快捷方式
Head '第 5 步 / 桌面快捷方式'
if ($NoShortcut) {
  Skip '按参数要求不创建快捷方式'
} elseif (-not $nodeExe) {
  if ($DryRun) {
    Skip '[演练] 本机尚未安装 Node.js；实际安装执行到本步骤时将创建桌面快捷方式'
    Record '桌面快捷方式' '将创建' 'DeepSeek Harness（演练）'
  } else {
    Skip '未找到 Node.js，跳过'
  }
} else {
  New-Shortcuts -NodeExe $nodeExe -NpmPrefix $npmPrefix
  if ($DryRun) { Record '桌面快捷方式' '将创建' 'DeepSeek Harness' }
  else { Record '桌面快捷方式' '已创建' 'DeepSeek Harness' }
}

# ---------------------------------------------------------------- 汇总
Head '安装完成，本次结果如下'
foreach ($s in $Steps) {
  $color = 'Gray'
  if ($s.结果 -eq '失败') { $color = 'Red' }
  elseif ($s.结果 -match '已安装|已就绪|已创建|已最新') { $color = 'Green' }
  elseif ($s.结果 -eq '跳过') { $color = 'DarkGray' }
  elseif ($s.结果 -match '将') { $color = 'Yellow' }
  Write-Host ('   ' + (Pad-Display $s.项目 20) + (Pad-Display $s.结果 12) + $s.说明) -ForegroundColor $color
}

Write-Host ''
if ($DryRun) {
  Write-Host '  演练结束：以上为实际安装将执行的操作；本次未下载、安装或修改任何内容。' -ForegroundColor Cyan
} elseif ($FailCount -eq 0) {
  Write-Host '  后续使用步骤：' -ForegroundColor Cyan
  Say '1) 双击桌面上的「DeepSeek Harness」：将自动打开浏览器进入 DSH 界面'
  Say '   （首次启动需等待数秒；如需停止服务，关闭最小化的命令行窗口即可）'
  Say '2) 首次打开需填写「API 密钥」，这是最常见的卡点，请按以下步骤操作：'
  # 原来这里只打印一个裸路径、没有任何说明，夹在编号步骤中间看不出那是什么 —— 补上说明文字
  Say ('   详细文件在 ' + (Join-Path $RootDir 'MODEL-SETUP.txt'))
  Say '   简要步骤：打开 https://platform.deepseek.com/ → 注册并登录 → 充值 →'
  Say '             创建「API keys」→ 复制 sk- 开头的密钥 →'
  Say '             粘贴到 DSH 的「API 密钥」输入框（前后不要留空格）→ 点击「接入并继续」'
  if (Get-InstalledPlugin) {
    Say '3) 选择一个「工作区」（未选择时输入框为灰色不可用），建议新建目录并命名为 workspace，例如 D:\workspace'
    Say '4) 新建会话，直接输入：把 D:\我的论文 里的 PDF 加进知识库（换成你自己的文献目录）'
    Say '   （用 Zotero 管理文献的话，直接说：把 Zotero 文件夹入库）'
    Say '5) 之后提问「我库里关于 XXX 的文献怎么说」，回答会附带引用'
  } else {
    Say '3) 选择一个「工作区」（未选择时输入框为灰色不可用），之后即可正常使用'
    Say '4) 本次未安装 kb-rag 文献知识库插件；需要时重新运行 install.cmd，'
    Say '   在第 3 步直接回车（默认为安装），完成后即具备知识库功能'
  }
  Write-Host ''
  Say '更新 DSH 或插件：重新运行本安装包中的「install.cmd」即可'
  Say '（因此请保留本解压后的文件夹；不再需要时可删除）'
} else {
  Write-Host ('  有 ' + $FailCount + ' 项未成功。请按上方红色提示处理后重新运行本脚本（已完成的部分会自动跳过）。') -ForegroundColor Yellow
  Say '  提示：此类失败多由网络波动或安全软件拦截导致，重新运行 install.cmd 通常即可解决。'
}
Write-Host ''
if ($FailCount -eq 0 -and -not $DryRun) {
  Say '以上步骤的详细说明见同目录文件：'
  Say ('   ' + (Join-Path $RootDir 'NEXT-STEPS.txt'))
  Say '   （和 GETTING-STARTED.txt、MODEL-SETUP.txt 放在一起）'
  # 装成功了才求 Star；Issues 两种情况下都给
  Show-ProjectHint -AskStar
} elseif (-not $DryRun -and $FailCount -gt 0) {
  # 失败时只给 Issues，并把日志路径一起给它 —— 这时用户最需要的是「拿什么去哪问」
  Show-ProjectHint -LogPath $logFile
}

if ($FailCount -gt 0 -and -not $DryRun) {
  # 失败时日志路径已经在上面那条提示里给过了（那里才是用户会读的地方），别重复；
  # 而且这时**不能**说缓存可以删 —— 重跑最省事的就是它，Node/Python 那几十 MB 不用重下。
  Say ('下载缓存：' + $DlDir + '（建议保留：重新运行时将直接复用，无需重新下载）')
} else {
  Say ('完整日志：' + $logFile)
  Say ('下载缓存：' + $DlDir + '（确认安装完成后可整体删除）')
}

try { Stop-Transcript | Out-Null } catch { }
if (-not $NoPause -and -not [Console]::IsInputRedirected) { Write-Host ''; Read-Host '按回车关闭窗口' | Out-Null }

# 显式给退出码：powershell -File 会把「最后一个原生命令的退出码」当成脚本退出码，
# 不写这一行的话，成功也可能被 .cmd 判成失败（新手会看到一句莫名其妙的报错）。
if ($FailCount -gt 0) { exit 1 }
exit 0
