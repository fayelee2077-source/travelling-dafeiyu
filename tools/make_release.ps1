# 打《旅行的大肥鱼》Windows 发布包：build\旅行的大肥鱼_v<版本>\ 和同名 .zip（build\ 不进 git）。
#   powershell -ExecutionPolicy Bypass -File tools\make_release.ps1 -Version 0.1
# 包里：旅行的大肥鱼.exe（导出设置 dafeiyu-windows，只带免费版要的图）、DSH插件\（插件 + 小家网页版 web\ + 一键安装 / 卸载）、
# 说明.txt、许可和署名.txt、Godot许可.txt（release\ 里的原文，{VERSION} 换成版本号）。
param([Parameter(Mandatory = $true)][string]$Version)
$ErrorActionPreference = "Stop"
$Root = Split-Path $PSScriptRoot -Parent
$Name = "旅行的大肥鱼_v$Version"
$Out = Join-Path $Root "build\$Name"
$Zip = "$Out.zip"
$Utf8Bom = New-Object System.Text.UTF8Encoding $true

foreach ($p in @("assets\ai_home\world.json", "assets\travel\places.json")) {
    if (-not (Test-Path -LiteralPath (Join-Path $Root $p))) { throw "缺 $p（这些图不进 git，要先生成）" }
}
# a window opened from the old package must not lose its folder halfway (11-16 it did: the exe was in use)
$OldExe = Join-Path $Out "旅行的大肥鱼.exe"
if (Get-Process | Where-Object { $_.Path -eq $OldExe }) { throw "$OldExe 正开着：先关掉它，或者换个版本号再打包" }
if (Test-Path -LiteralPath $Out) { Remove-Item -LiteralPath $Out -Recurse -Force }
if (Test-Path -LiteralPath $Zip) { Remove-Item -LiteralPath $Zip -Force }
New-Item -ItemType Directory -Force -Path (Join-Path $Out "DSH插件\lib") | Out-Null

# Windows PowerShell 5.1 hands non-ASCII arguments to programs garbled: export under an ASCII name, then rename
$Exe = Join-Path $Root "build\dafeiyu_windows\dafeiyu.exe"
if (Test-Path -LiteralPath $Exe) { Remove-Item -LiteralPath $Exe -Force }
New-Item -ItemType Directory -Force -Path (Split-Path $Exe) | Out-Null
Push-Location $Root
try {
    godot_console --headless --path . --import | Out-Null
    godot_console --headless --path . --export-release "dafeiyu-windows" "build/dafeiyu_windows/dafeiyu.exe" | Out-Null
} finally { Pop-Location }
if (-not (Test-Path -LiteralPath $Exe)) { throw "导出失败" }
Move-Item -LiteralPath $Exe -Destination (Join-Path $Out "旅行的大肥鱼.exe")

$Plugin = Join-Path $Root "dsh-plugin"
Copy-Item -LiteralPath (Join-Path $Plugin "index.js"), (Join-Path $Plugin "package.json"), (Join-Path $Plugin "places.json"),
    (Join-Path $Plugin "install.ps1"), (Join-Path $Plugin "安装插件.bat"), (Join-Path $Plugin "卸载插件.bat") -Destination (Join-Path $Out "DSH插件")
Copy-Item -Path (Join-Path $Plugin "lib\*.js") -Destination (Join-Path $Out "DSH插件\lib")

# the little home's web version (the page in DSH), inside the plugin (补充条款五·修订二)
$WebOut = Join-Path $Root "build\dafeiyu_web"
if (Test-Path -LiteralPath $WebOut) { Remove-Item -LiteralPath $WebOut -Recurse -Force }
New-Item -ItemType Directory -Force -Path $WebOut | Out-Null
Push-Location $Root
try { godot_console --headless --path . --export-release "dafeiyu-web" "build/dafeiyu_web/index.html" | Out-Null } finally { Pop-Location }
if (-not (Test-Path -LiteralPath (Join-Path $WebOut "index.html"))) { throw "网页版导出失败" }
Copy-Item -LiteralPath $WebOut -Destination (Join-Path $Out "DSH插件\web") -Recurse

foreach ($f in @("说明.txt", "许可和署名.txt", "Godot许可.txt")) {
    $text = [System.IO.File]::ReadAllText((Join-Path $Root "release\$f")).Replace("{VERSION}", $Version) -replace "(?<!\r)\n", "`r`n"
    [System.IO.File]::WriteAllText((Join-Path $Out $f), $text, $Utf8Bom)
}

Compress-Archive -Path $Out -DestinationPath $Zip
Write-Host "好了：$Zip"
Get-ChildItem -LiteralPath $Out -Recurse -File | ForEach-Object {
    "{0,8:N1} KB  {1}" -f ($_.Length / 1KB), $_.FullName.Substring($Out.Length + 1)
}
"{0:N1} MB  {1}" -f ((Get-Item -LiteralPath $Zip).Length / 1MB), (Split-Path $Zip -Leaf)
