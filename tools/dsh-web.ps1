<#
  DeepSeek Harness — launcher
  ==========================================================================
  桌面快捷方式背后跑的就是它：确保官方 DSH web 服务在跑，然后把浏览器打开。

  实测得来的关键事实（别改坏）：
    * 入口 URL 必须带 token：http://127.0.0.1:3080/?token=xxxx
      token 是「本进程」的、可以反复使用（dsh-client-connection 的 authorizeIndex
      拿它换 cookie，不消费 token）；浏览器第一次带着它进来后服务端会种一个
      30 天的 cookie，之后连干净 URL http://127.0.0.1:3080/ 都能进。
    * token 每次启动现生成、只写到 stdout，不落盘。所以这里把 dsh 的输出重定向到
      dsh-web.log，再从日志里把 URL 抓出来，存到 %LOCALAPPDATA%\DSH\session-url.txt。
    * 浏览器优先交给 dsh 自己开（**不加** --no-open）：它的交接失败会在日志里写明原因，
      而 PowerShell 的 Start-Process <url> 失败时是静默的 —— 用户看到的就是
      「双击了，什么也没发生」。只有日志显示 dsh 开失败了，我们才兜底再开一次。
    * 任何一条路走不通都要把完整 URL 打到窗口里：窗口里只印 http://127.0.0.1:3080
      （把 token 去掉）等于什么都没给用户。
    * 启动期间一直有输出：等端口最多 180 秒，每 10 秒报一次进度 —— 以前 120 秒
      一声不吭，用户以为卡死了。

  输出风格：面向用户的正式提示，不做教程式解说。
#>
$ErrorActionPreference = 'Continue'
# 没有控制台时（被别的程序带起来、输出被重定向）设置标题会抛异常，别让它变成红字
try { [Console]::Title = 'DeepSeek Harness' } catch { }

$Prefix  = Join-Path $env:LOCALAPPDATA 'DSH'
$DshHome = Join-Path $env:USERPROFILE '.dsh'
$Port    = 3080
# 运行日志：**每次启动一个文件**（v1.1.3 起）。
# 原来固定叫 dsh-web.log，而且启动时先 Remove-Item 再重定向覆盖 —— 后果是：
# 用户第一次启动失败（日志里有原因）→ 再双击一次 → **证据没了**，求助时只能拿到最后一次。
# 时间戳命名后每次都是独立证据；配合下面的保留策略，也不会无限堆积。
# Get-UrlFromLog 读的就是本次这个文件（见 Get-NewestLog 的说明），所以抓 URL 不受影响。
$LogPath = Join-Path $Prefix ('dsh-web-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
$UrlPath = Join-Path $Prefix 'session-url.txt'
$LogKeep = 10    # 最多保留几个运行日志（按修改时间倒序）

function Write-Head {
  Write-Host ''
  Write-Host '  DeepSeek Harness' -ForegroundColor White
  Write-Host '  ----------------------------------------------------------' -ForegroundColor DarkGray
}
function Write-Field {
  param([string]$Name, [string]$Value)
  Write-Host ('  ' + $Name.PadRight(6)) -NoNewline -ForegroundColor DarkGray
  Write-Host $Value -ForegroundColor Gray
}
function Write-Ok   { param([string]$m) Write-Host ('  [ ok ] ' + $m) -ForegroundColor Green }
function Write-Info { param([string]$m) Write-Host ('  [ .. ] ' + $m) -ForegroundColor Gray }
function Write-Fail { param([string]$m) Write-Host ('  [fail] ' + $m) -ForegroundColor Red }
function Write-Note { param([string]$m) Write-Host ('  ' + $m) -ForegroundColor DarkGray }

# ---------------------------------------------------------------- 解析路径
$nodeExe = $null
$npmPrefix = $null
$cfgPath = Join-Path $Prefix 'launch.json'
if (Test-Path $cfgPath) {
  try {
    $cfg = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($cfg.node -and (Test-Path $cfg.node)) { $nodeExe = $cfg.node }
    if ($cfg.npmPrefix) { $npmPrefix = $cfg.npmPrefix }
    if ($cfg.dshHome) { $DshHome = $cfg.dshHome }
    if ($cfg.port) { $Port = [int]$cfg.port }
  } catch { }
}
function Resolve-Node {
  param([string]$known)
  if ($known -and (Test-Path $known)) { return $known }
  foreach ($p in @(
      (Join-Path $Prefix 'node\node.exe'),
      (Join-Path $env:ProgramFiles 'nodejs\node.exe'),
      (Join-Path ${env:ProgramFiles(x86)} 'nodejs\node.exe'),
      (Join-Path $env:LOCALAPPDATA 'Programs\nodejs\node.exe')
    )) { if ($p -and (Test-Path $p)) { return $p } }
  $c = Get-Command node.exe -ErrorAction SilentlyContinue
  if ($c -and $c.Source -notmatch 'DSH Desktop|\.desktop-bin') { return $c.Source }
  return $null
}
function Resolve-BinJs {
  param([string]$prefix)
  $cands = @()
  if ($prefix) { $cands += (Join-Path $prefix 'node_modules\@deepseek-ai\dsh\lib\bin.js') }
  $cands += (Join-Path $env:APPDATA 'npm\node_modules\@deepseek-ai\dsh\lib\bin.js')
  $cands += (Join-Path $Prefix 'node\node_modules\@deepseek-ai\dsh\lib\bin.js')
  foreach ($c in $cands) { if (Test-Path $c) { return $c } }
  return $null
}
function Test-PortUp {
  param([int]$p)
  try { $c = New-Object System.Net.Sockets.TcpClient; $c.Connect('127.0.0.1', $p); $c.Close(); return $true } catch { return $false }
}
function Test-EntryUrl {
  param([string]$u)
  if (-not $u) { return $false }
  try {
    $r = Invoke-WebRequest -Uri $u -UseBasicParsing -TimeoutSec 6 -ErrorAction Stop
    return ($r.StatusCode -ge 200 -and $r.StatusCode -lt 400)
  } catch { return $false }
}
# 找最近一次的运行日志。用途：服务已经在跑时（本次没有新日志），从上次的日志里抓入口 URL。
# 排序按文件名倒序即可 —— 文件名就是 yyyyMMdd-HHmmss，字典序等于时间序，比逐个 stat 便宜。
function Get-NewestLog {
  $cands = @(Get-ChildItem -Path (Join-Path $Prefix 'dsh-web-*.log') -ErrorAction SilentlyContinue |
             Sort-Object Name -Descending)
  if ($cands.Count -gt 0) { return $cands[0].FullName }
  return ''
}
# 保留最近 $LogKeep 个日志，更早的删掉（含旧的固定名 dsh-web.log，它不再产生）。
# 不删正在写的那一个。
function Remove-OldLogs {
  $keep = @(Get-ChildItem -Path (Join-Path $Prefix 'dsh-web-*.log') -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending | Select-Object -First $LogKeep | ForEach-Object { $_.FullName })
  Get-ChildItem -Path (Join-Path $Prefix 'dsh-web-*.log') -ErrorAction SilentlyContinue | ForEach-Object {
    if ($keep -notcontains $_.FullName -and $_.FullName -ne $LogPath) {
      Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
    }
  }
  # 旧版本留下的固定名日志：内容已被新日志取代，清掉避免和新行为混淆
  Remove-Item -LiteralPath (Join-Path $Prefix 'dsh-web.log') -Force -ErrorAction SilentlyContinue
}
# 从某个服务日志里把带 token 的入口 URL 抓出来（服务每次启动都会打一行）
# 不给 -Path 就查本次的日志；服务已在运行时传最近一个日志的路径（见调用处）。
function Get-UrlFromLog {
  param([string]$Path = '')
  if (-not $Path) { $Path = $LogPath }
  if (-not (Test-Path $Path)) { return '' }
  $raw = Get-Content $Path -Raw -ErrorAction SilentlyContinue
  if (-not $raw) { return '' }
  $m = [regex]::Match("$raw", 'http://127\.0\.0\.1:\d+/\?token=[A-Za-z0-9_\-]+')
  if ($m.Success) { return $m.Value }
  return ''
}
# 开浏览器：两条路依次试，都不行就把 URL 明确打出来让用户自己粘。
# 只走一条路的话，在没设默认浏览器 / 被安全软件拦的机器上就是「什么也没发生」。
function Open-Url {
  param([string]$Url)
  if (-not $Url) { return $false }
  $opened = $false
  try { Start-Process $Url -ErrorAction Stop; $opened = $true } catch { }
  if (-not $opened) {
    try {
      & cmd.exe /c ('start "" "' + $Url + '"') 2>$null
      if ($LASTEXITCODE -eq 0) { $opened = $true }
    } catch { }
  }
  if (-not $opened) {
    Write-Note '  Could not open a browser automatically. Please open this URL yourself:'
    Write-Note ('    ' + $Url)
  }
  return $opened
}

$nodeExe = Resolve-Node -known $nodeExe
$binJs = Resolve-BinJs -prefix $npmPrefix

Write-Head

if (-not $nodeExe -or -not $binJs) {
  Write-Fail 'DSH or Node.js was not found.'
  if (-not $nodeExe) { Write-Note '  Node.js is missing.' }
  if (-not $binJs) { Write-Note ('  DSH is not installed under ' + $Prefix) }
  Write-Host ''
  Write-Note '  Repair it by running "install.cmd" from the installer folder.'
  Write-Host ''
  Read-Host '  Press Enter to close'
  exit 1
}

Write-Field 'home' $DshHome
Write-Field 'port' $Port
Write-Field 'log'  $LogPath
Write-Host ''

# ---------------------------------------------------------------- 已在运行
if (Test-PortUp -p $Port) {
  $url = ''
  # 依次找：上次存下来的 → 服务日志里的 → 干净 URL（浏览器里可能已经有 30 天 cookie）
  # 注意这里用 Get-NewestLog：本次的时间戳日志是**刚建的空文件**，正在跑的那个服务的 URL
  # 在它自己那次启动的日志里。不换成"最近一个"就会永远抓不到。
  $saved = ''
  if (Test-Path $UrlPath) { $saved = (Get-Content $UrlPath -Raw -Encoding UTF8).Trim() }
  if ($saved -and (Test-EntryUrl -u $saved)) { $url = $saved }
  if (-not $url) {
    $newest = Get-NewestLog
    if ($newest) {
      $fromLog = Get-UrlFromLog -Path $newest
      if ($fromLog -and (Test-EntryUrl -u $fromLog)) { $url = $fromLog }
    }
  }
  if (-not $url) {
    $clean = 'http://127.0.0.1:' + $Port + '/'
    if (Test-EntryUrl -u $clean) { $url = $clean }
  }
  if ($url) {
    if ($url -like '*token=*') { try { Set-Content -Path $UrlPath -Value $url -Encoding UTF8 } catch { } }
    Write-Ok 'Already running.'
    Open-Url -Url $url | Out-Null
    Write-Note ('  URL: ' + $url)
    Start-Sleep -Seconds 3
    exit 0
  }
  # 拿不到它的入口链接（最常见的原因：3080 上那个服务是你自己在命令行里启动的，
  # token 只打在了那个终端里，没落盘）。不在这儿死等 —— 往下走，换个空闲端口自己起一个。
  Write-Info ('Port ' + $Port + ' is in use, but its session link is not available.')
  Write-Note '  (A DSH server started by hand keeps its token in that terminal window.)'
  Write-Note '  Starting a separate one on a free port so this shortcut still works.'
}

# ---------------------------------------------------------------- 启动
$env:DSH_HOME = $DshHome
# node 自己的目录和全局 npm 目录都放前面：dsh 里凡是按名字找 node/npm/pnpm 的地方
# 都得能找到（便携版 Node 不在系统 PATH 上）
if ($nodeExe) { $env:PATH = (Split-Path -Parent $nodeExe) + ';' + $env:PATH }
if ($npmPrefix) { $env:PATH = $npmPrefix + ';' + $env:PATH }
if (-not (Test-Path $Prefix)) { New-Item -ItemType Directory -Force -Path $Prefix | Out-Null }
# 不再 Remove-Item $LogPath：本次日志是新建的时间戳文件，天然不会覆盖历史。
# （被删掉的是**更早的**日志，由保留策略处理；这样上一次启动失败的证据还在。）
Remove-OldLogs
Remove-Item $UrlPath -Force -ErrorAction SilentlyContinue

# 3080 被别的程序 / 别的 DSH 占着、而我们又拿不到它的入口链接时，让系统分一个空闲端口，
# 保证桌面图标永远能开（--port 0 = 让操作系统挑）。dsh 会把真实端口打进那行 URL，我们照抓。
$portArg = ''
if (Test-PortUp -p $Port) {
  $portArg = ' --port 0'
}
Write-Info 'Starting local server (the first start can take a while)...'

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = 'cmd.exe'
# 故意不带 --no-open：让 dsh 自己开浏览器（它的交接失败会在日志里写明原因）
$psi.Arguments = '/c title "DeepSeek Harness" && "' + $nodeExe + '" "' + $binJs + '" web' + $portArg + ' > "' + $LogPath + '" 2>&1'
$psi.WindowStyle = 'Minimized'
$psi.UseShellExecute = $true
try {
  [System.Diagnostics.Process]::Start($psi) | Out-Null
} catch {
  Write-Fail ('Could not start the server: ' + $_.Exception.Message)
  Read-Host '  Press Enter to close'
  exit 1
}

# 等入口 URL 出现在日志里：最多 180 秒，但每 10 秒报一次进度，别让用户以为卡死了。
# 等 URL 比「探测端口」更准 —— 端口可能是系统分配的（--port 0），而且 URL 一出现就说明
# 服务真的起来、可以进了。
$startedAt = Get-Date
$deadline = $startedAt.AddSeconds(180)
$entry = ''
$lastNote = 0
while ((Get-Date) -lt $deadline -and -not $entry) {
  Start-Sleep -Milliseconds 700
  $entry = Get-UrlFromLog
  if ($entry) { break }
  $elapsed = [int]((Get-Date) - $startedAt).TotalSeconds
  if ($elapsed -ge ($lastNote + 10)) {
    $lastNote = $elapsed
    Write-Info ('still starting... ' + $elapsed + 's')
  }
}

Write-Host ''
if (-not $entry) {
  Write-Fail 'The server did not start within 180 seconds.'
  if (Test-Path $LogPath) {
    Write-Host ''
    Write-Note ('  Last lines of ' + $LogPath + ':')
    Get-Content $LogPath -Tail 12 -ErrorAction SilentlyContinue | ForEach-Object { Write-Note ('    ' + $_) }
  }
  Write-Host ''
  Write-Note '  You can also start it by hand to see the full output:'
  Write-Note ('    "' + $nodeExe + '" "' + $binJs + '" web')
  Write-Note '  Then run "install.cmd" again to repair the shortcut.'
  Write-Host ''
  Read-Host '  Press Enter to close'
  exit 1
}

# 拿到入口 URL 了：存下来（以后双击直接复用）+ 全量打印 + 看 dsh 自己有没有开成浏览器
$logText = ''
if (Test-Path $LogPath) { $logText = Get-Content $LogPath -Raw -ErrorAction SilentlyContinue }
try { Set-Content -Path $UrlPath -Value $entry -Encoding UTF8 } catch { }
Write-Ok 'Ready.'
Write-Note ('  URL: ' + $entry)
if ("$logText" -match 'could not open the default browser') {
  # 日志说 dsh 自己没开成浏览器 —— 兜底再开一次
  Write-Info 'The browser did not open automatically; opening it now...'
  Open-Url -Url $entry | Out-Null
}
Write-Host ''
Write-Note '  If the page does not appear, paste the URL above into your browser.'
Write-Note '  Closing the minimized "DeepSeek Harness" window stops the server.'
Start-Sleep -Seconds 4
exit 0
