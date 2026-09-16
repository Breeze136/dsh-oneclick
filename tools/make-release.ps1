<#
  打包发布 —— 生成给用户下载的 zip
  ==========================================================================
  为什么需要这个脚本，而不是「右键压缩整个文件夹」：
    1) VERSION.txt 是开发者更新记录（里面有「维护者要求」「为什么这么改」这类内部说明），
       不该出现在用户拿到的包里；但它得留在仓库里当变更记录 —— 所以是**排除**，不是删除。
    2) 本脚本自己（tools\make-release.ps1）同样是开发工具，一并排除。
    3) sha256.txt 必须**重新生成**：它登记的是「用户拿到的那一份」的校验值。
       忘了重算比没有这个文件更糟 —— 用户一核对就以为文件被人动过。
       而且它在包里、篡改者可以连它一起改，所以真正的防篡改要靠把哈希贴到包外
       （Release 正文 / README），本脚本会把 zip 的 SHA-256 打出来供你复制。

  用法：
      powershell -NoProfile -ExecutionPolicy Bypass -File tools\make-release.ps1
      powershell ... -File tools\make-release.ps1 -Version 1.1.1 -OutDir D:\发布
      powershell ... -File tools\make-release.ps1 -SkipCheck      # 跳过打包前校验（不建议）

  版本号：留空则读 VERSION.txt 首行的 vX.Y.Z；两者都没有则报错退出（不猜）。
#>
param(
  [string]$Version = '',
  [string]$OutDir  = '',
  [switch]$SkipCheck
)
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir   = Split-Path -Parent $ScriptDir

# 发布包里**不该有**的（相对路径，大小写不敏感）；sha256.txt 不在其中 —— 它是重新生成的
# .gitignore / .gitattributes 是仓库专用文件，用户拿到 zip 不需要它们，一并排除。
$ExcludeFiles = @('VERSION.txt', 'tools\make-release.ps1', '.gitignore', '.gitattributes')

function Get-Rel {
  param([string]$Base, [string]$Full)
  return $Full.Substring($Base.Length).TrimStart('\')
}

# ---------------------------------------------------------------- 版本号
if (-not $Version) {
  $vfile = Join-Path $RootDir 'VERSION.txt'
  if (Test-Path $vfile) {
    $first = (Get-Content $vfile -TotalCount 1 -Encoding UTF8)
    $m = [regex]::Match("$first", 'v(\d+\.\d+\.\d+)')
    if ($m.Success) { $Version = $m.Groups[1].Value }
  }
}
if (-not $Version) {
  Write-Host '  [失败] 读不到版本号：VERSION.txt 首行没有 vX.Y.Z，也没传 -Version' -ForegroundColor Red
  exit 1
}

# 版本号一致性：tools\install.ps1 里的 $PackageVersion 必须和 VERSION.txt 首行相同。
# 为什么查：VERSION.txt **不随发布包分发**，所以发布包里唯一的版本标识就是 install.ps1
# 里那个常量。两处不一致就会产出「包叫 v1.1.1、脚本自称 v1.1.0」的包 —— 用户报错时
# 你连他跑的是哪一版都问不清（他手里可能还躺着解压了两次的 "(1)" 目录）。
$installPs1 = Join-Path $RootDir 'tools\install.ps1'
if (Test-Path $installPs1) {
  $m2 = [regex]::Match((Get-Content $installPs1 -Raw -Encoding UTF8), '(?m)^\$PackageVersion\s*=\s*''([^'']+)''')
  if (-not $m2.Success) {
    Write-Host '  [失败] tools\install.ps1 里找不到 $PackageVersion 常量' -ForegroundColor Red
    exit 1
  }
  if ($m2.Groups[1].Value -ne $Version) {
    Write-Host ('  [失败] 版本号不一致：VERSION.txt = v' + $Version + '，install.ps1 = v' + $m2.Groups[1].Value) -ForegroundColor Red
    Write-Host '         两处必须一致后再打包。' -ForegroundColor Red
    exit 1
  }
  Write-Host ('  [完成] 版本号一致：v' + $Version) -ForegroundColor Green
}
if (-not $OutDir) { $OutDir = Join-Path (Split-Path -Parent $RootDir) '发布' }
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Force -Path $OutDir | Out-Null }
$zipPath = Join-Path $OutDir ('dsh-oneclick-v' + $Version + '.zip')

Write-Host ''
Write-Host ('  DSH 一键装 —— 打包 v' + $Version) -ForegroundColor Cyan
Write-Host ('  源目录：' + $RootDir)
Write-Host ('  输出  ：' + $zipPath)
Write-Host ''

# ---------------------------------------------------------------- 打包前校验
$manifest = Join-Path $RootDir 'sha256.txt'
if (-not (Test-Path $manifest)) { Write-Host '  [失败] 找不到 sha256.txt' -ForegroundColor Red; exit 1 }
$entries = @()
foreach ($line in [System.IO.File]::ReadAllLines($manifest, [System.Text.Encoding]::UTF8)) {
  if (-not $line.Trim()) { continue }
  $p = $line -split '\s+', 2
  $entries += [pscustomobject]@{ Hash = $p[0].ToLower(); Rel = $p[1].Trim() }
}
if (-not $SkipCheck) {
  $bad = @()
  foreach ($e in $entries) {
    $f = Join-Path $RootDir $e.Rel
    if (-not (Test-Path $f)) { $bad += ('缺失：' + $e.Rel); continue }
    $h = (Get-FileHash $f -Algorithm SHA256).Hash.ToLower()
    if ($h -ne $e.Hash) { $bad += ('哈希不符：' + $e.Rel) }
  }
  if ($bad.Count) {
    Write-Host '  [失败] 打包前校验不通过 —— 清单与文件不一致，先修好再打包：' -ForegroundColor Red
    $bad | ForEach-Object { Write-Host ('         ' + $_) -ForegroundColor Red }
    exit 1
  }
  Write-Host ('  [完成] 打包前校验通过（' + $entries.Count + ' 个文件与 sha256.txt 一致）') -ForegroundColor Green
}

# ---------------------------------------------------------------- 编码检查
# 这个检查是**踩过坑才加的**：本脚本第一版由编辑器写成「无 BOM 的 UTF-8」，Windows
# PowerShell 5.1 会按 ANSI 读它，中文全变乱码、直接语法错误跑不起来。
# 规则：.ps1/.txt/.md 必须有 UTF-8 BOM；install.cmd 相反 —— 必须纯 ASCII 且无 BOM
#（cmd.exe 按 OEM 代码页解析，带 BOM 反而出错）；.ico 等二进制跳过。
$encBad = @()
foreach ($f in (Get-ChildItem $RootDir -Recurse -File)) {
  if ($f.Extension -eq '.ico') { continue }
  $rel = Get-Rel -Base $RootDir -Full $f.FullName
  $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
  $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
  $nonAscii = $false
  foreach ($x in $bytes) { if ($x -gt 0x7F) { $nonAscii = $true; break } }
  switch ($f.Extension.ToLower()) {
    '.ps1'  { if (-not $hasBom) { $encBad += ('缺 UTF-8 BOM（PS 5.1 会按 ANSI 读，中文全乱码）：' + $rel) } }
    '.txt'  { if (-not $hasBom) { $encBad += ('缺 UTF-8 BOM：' + $rel) } }
    '.md'   { if (-not $hasBom) { $encBad += ('缺 UTF-8 BOM：' + $rel) } }
    '.cmd'  {
      if ($hasBom) { $encBad += ('不该带 BOM（cmd.exe 按 OEM 代码页解析）：' + $rel) }
      if ($nonAscii) { $encBad += ('含非 ASCII 字节（cmd 里会乱码）：' + $rel) }
    }
    default { if ($nonAscii -and -not $hasBom) { $encBad += ('含中文但无 BOM：' + $rel) } }
  }
}
if ($encBad.Count) {
  Write-Host '  [失败] 编码检查不通过：' -ForegroundColor Red
  $encBad | ForEach-Object { Write-Host ('         ' + $_) -ForegroundColor Red }
  exit 1
}
Write-Host '  [完成] 编码检查通过（.ps1/.txt/.md 均带 UTF-8 BOM；install.cmd 纯 ASCII）' -ForegroundColor Green

# ---------------------------------------------------------------- 组装
$stage = Join-Path ([System.IO.Path]::GetTempPath()) ('dsh-rel-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$pkgDir = Join-Path $stage ('dsh-oneclick-v' + $Version)
try {
  New-Item -ItemType Directory -Force -Path $pkgDir | Out-Null
  $copied = 0; $skipped = @(); $gitSkipped = 0
  # 注意这里故意**不加 -Force**：隐藏文件（Windows 上 .git 默认带 Hidden 属性）不会被枚举，
  # 这正是我们要的。下面那条 .git 路径判断是双保险 —— 万一 .git 的 Hidden 属性被去掉了，
  # 递归枚举就会把整个版本库（含全部历史）打进用户下载的 zip 里，那是不可接受的。
  foreach ($f in (Get-ChildItem $RootDir -Recurse -File)) {
    $rel = Get-Rel -Base $RootDir -Full $f.FullName
    if ($rel -match '(^|\\)\.git(\\|$)') { $gitSkipped++; continue }
    if ($ExcludeFiles -contains $rel) { $skipped += $rel; continue }
    if ($f.Name -eq 'sha256.txt') { continue }        # 稍后重新生成
    $dest = Join-Path $pkgDir $rel
    $destDir = Split-Path -Parent $dest
    if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Force -Path $destDir | Out-Null }
    Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
    $copied++
  }
  if ($gitSkipped) { Write-Host ('  [跳过] .git 目录下的 ' + $gitSkipped + ' 个文件（版本库不进发布包）') -ForegroundColor DarkGray }
  if ($skipped.Count) { Write-Host ('  [跳过] 不随包发布：' + ($skipped -join '、')) -ForegroundColor DarkGray }

  # 重新生成清单（只登记包内文件，按相对路径排序；沿用原文件的 UTF-8 BOM + CRLF）
  $lines = @()
  foreach ($f in (Get-ChildItem $pkgDir -Recurse -File | Sort-Object FullName)) {
    $rel = Get-Rel -Base $pkgDir -Full $f.FullName
    if ($rel -eq 'sha256.txt') { continue }
    $lines += ((Get-FileHash $f.FullName -Algorithm SHA256).Hash.ToLower() + '  ' + $rel)
  }
  $nl = "`r`n"
  [System.IO.File]::WriteAllText((Join-Path $pkgDir 'sha256.txt'), (($lines -join $nl) + $nl), (New-Object System.Text.UTF8Encoding($true)))
  Write-Host ('  [完成] 清单已重新生成（' + $lines.Count + ' 条）') -ForegroundColor Green

  # ---------------------------------------------------------------- 压缩
  if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
  Compress-Archive -Path $pkgDir -DestinationPath $zipPath -CompressionLevel Optimal
} finally {
  Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------- 结果
$zi = Get-Item $zipPath
$zh = (Get-FileHash $zipPath -Algorithm SHA256).Hash.ToLower()
Write-Host ''
Write-Host ('  [完成] 打包结束：' + $zi.FullName) -ForegroundColor Green
Write-Host ('         大小：{0:N0} 字节（{1:N1} MB）' -f $zi.Length, ($zi.Length / 1MB))
Write-Host ('         SHA-256：' + $zh)
Write-Host ''
Write-Host '  下一步（发布时把下面这条一起贴出去，别只发 zip）：' -ForegroundColor Cyan
Write-Host ('         SHA-256  ' + $zh)
Write-Host ''
