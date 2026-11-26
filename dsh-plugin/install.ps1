# 《旅行的大肥鱼》DSH 插件一键安装 / 卸载（Windows PowerShell 5.1 起）。
#   安装：双击「安装插件.bat」；卸载：双击「卸载插件.bat」（或 install.ps1 -Uninstall）
# 安装做的事（改之前先备份，改完检查，出错就还原）：
#   1. 把插件（index.js、package.json、places.json、lib\，有的话还有小家网页版 web\）拷到
#      <DSH>\local-plugins\dsh-living-dock\ 和 <DSH>\profiles\<配置>\node_modules\dsh-living-dock\
#   2. 配置的 package.json 的 dependencies 里加 "dsh-living-dock"
#   3. 配置的 cordis.patch.yml 末尾加一段 living-dock（带 6 位配对码和茶几纸条文件夹的位置；已经装过就保留原来的）
#   4. 把同一个配对码写进《旅行的大肥鱼》窗口的设置，打开窗口就能连上
# 不读、不改 DSH 里别的插件的设置、密钥、聊天和记忆。卸载只去掉本脚本加的东西，旅行记录和茶几纸条都留着。
# 测试用参数：-DshHome <假的 .dsh 文件夹> -GameUserDir <假的窗口设置文件夹>
param(
    [string]$DshHome = (Join-Path $env:USERPROFILE ".dsh"),
    [string]$DshProfile = "",
    [string]$GameUserDir = (Join-Path $env:APPDATA "旅行的大肥鱼"),
    [string]$PairCode = "",
    [switch]$Uninstall
)
$ErrorActionPreference = "Stop"
$Name = "dsh-living-dock"
$Begin = "# >>> living-dock (旅行的大肥鱼) — install.ps1 加的，卸载时会去掉"
$End = "# <<< living-dock"
$Utf8 = New-Object System.Text.UTF8Encoding $false

function Say($text) { Write-Host $text }
function Fail($text) { Write-Host ""; Write-Host "没装成：$text" -ForegroundColor Red; exit 1 }
function ReadText($path) { [System.IO.File]::ReadAllText($path) }
function WriteText($path, $text) { [System.IO.File]::WriteAllText($path, $text, $Utf8) }
function Backup($path) {
    $bak = "$path.bak-living-dock-" + (Get-Date -Format "yyyyMMdd-HHmmss")
    Copy-Item -LiteralPath $path -Destination $bak
    return $bak
}
function CheckJson($path, $bak) {
    try { ReadText $path | ConvertFrom-Json | Out-Null }
    catch { Copy-Item -LiteralPath $bak -Destination $path -Force; Fail "改完的 package.json 读不出来，已经还原（$bak）。" }
}

# ---- 找 DSH 和它的配置
if (-not (Test-Path -LiteralPath (Join-Path $DshHome "profiles"))) {
    Fail "没找到 DSH（$DshHome\profiles）。请先安装并打开一次 DSH。"
}
$profiles = @(Get-ChildItem -LiteralPath (Join-Path $DshHome "profiles") -Directory |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName "package.json") } | ForEach-Object { $_.Name })
if ($DshProfile -eq "") {
    if ($profiles.Count -eq 1) { $DshProfile = $profiles[0] }
    elseif ($profiles -contains "desktop") { $DshProfile = "desktop" }
    else { Fail ("有好几个 DSH 配置（" + ($profiles -join "、") + "），请用 -DshProfile <名字> 指定一个。") }
}
$Prof = Join-Path $DshHome "profiles\$DshProfile"
$Pkg = Join-Path $Prof "package.json"
$Yml = Join-Path $Prof "cordis.patch.yml"
if (-not (Test-Path -LiteralPath $Pkg)) { Fail "DSH 配置 $DshProfile 里没有 package.json。" }
$Targets = @((Join-Path $DshHome "local-plugins\$Name"), (Join-Path $Prof "node_modules\$Name"))
Say "DSH 配置：$Prof"

# ---------------------------------------------------------------- 卸载
if ($Uninstall) {
    $pkgText = ReadText $Pkg
    if ($pkgText -match '"dsh-living-dock"') {
        $bak = Backup $Pkg
        $nl = if ($pkgText.Contains("`r`n")) { "`r`n" } else { "`n" }
        $lines = $pkgText -split "\r?\n" | Where-Object { $_ -notmatch '^\s*"dsh-living-dock"\s*:' }
        $out = ($lines -join $nl) -replace ',(\s*\})', '$1'
        WriteText $Pkg $out
        CheckJson $Pkg $bak
        Say "package.json：去掉了 dsh-living-dock（备份 $bak）"
    }
    if (Test-Path -LiteralPath $Yml) {
        $ymlText = ReadText $Yml
        $i = $ymlText.IndexOf($Begin)
        if ($i -ge 0) {
            $j = $ymlText.IndexOf($End, $i)
            if ($j -lt 0) { Fail "cordis.patch.yml 里 living-dock 那段的结尾标记不见了，请手动删掉那段。" }
            $bak = Backup $Yml
            $after = $ymlText.Substring($j + $End.Length).TrimStart("`r", "`n")
            WriteText $Yml ($ymlText.Substring(0, $i).TrimEnd() + $(if ($after) { [Environment]::NewLine + $after } else { [Environment]::NewLine }))
            Say "cordis.patch.yml：去掉了 living-dock 那段（备份 $bak）"
        } elseif ($ymlText -match 'id:\s*living-dock') {
            Say "cordis.patch.yml 里的 living-dock 不是本脚本加的，没有动它，请手动删掉。"
        }
    }
    foreach ($t in $Targets) {
        if (Test-Path -LiteralPath $t) { Remove-Item -LiteralPath $t -Recurse -Force; Say "删掉了 $t" }
    }
    Say ""
    Say "卸载好了。重启 DSH 后生效。旅行记录和茶几纸条都还在。"
    exit 0
}

# ---------------------------------------------------------------- 安装
$Src = $PSScriptRoot
foreach ($f in @("index.js", "package.json", "places.json", "lib")) {
    if (-not (Test-Path -LiteralPath (Join-Path $Src $f))) { Fail "安装包不完整，缺 $f（要和 install.ps1 放在同一个文件夹）。" }
}
$Web = Join-Path $Src "web"
$HasWeb = Test-Path -LiteralPath (Join-Path $Web "index.html")

# 1. 拷插件（若以前装过旧版，先把旧插件代码备份一份，不碰旅行记录和配对码）
$OldLocal = $Targets[0]
if (Test-Path -LiteralPath (Join-Path $OldLocal "package.json")) {
    $CodeBak = "$OldLocal.bak-" + (Get-Date -Format "yyyyMMdd-HHmmss")
    New-Item -ItemType Directory -Force -Path (Join-Path $CodeBak "lib") | Out-Null
    foreach ($cf in @("index.js", "package.json", "places.json")) {
        if (Test-Path -LiteralPath (Join-Path $OldLocal $cf)) {
            Copy-Item -LiteralPath (Join-Path $OldLocal $cf) -Destination $CodeBak -Force
        }
    }
    if (Test-Path -LiteralPath (Join-Path $OldLocal "lib")) {
        Copy-Item -Path (Join-Path $OldLocal "lib\*") -Destination (Join-Path $CodeBak "lib") -Force
    }
    Say "旧版插件代码已备份：$CodeBak"
}
foreach ($t in $Targets) {
    New-Item -ItemType Directory -Force -Path (Join-Path $t "lib") | Out-Null
    Copy-Item -LiteralPath (Join-Path $Src "index.js"), (Join-Path $Src "package.json"), (Join-Path $Src "places.json") -Destination $t -Force
    Copy-Item -Path (Join-Path $Src "lib\*.js") -Destination (Join-Path $t "lib") -Force
    if ($HasWeb) {
        if (Test-Path -LiteralPath (Join-Path $t "web")) { Remove-Item -LiteralPath (Join-Path $t "web") -Recurse -Force }
        Copy-Item -LiteralPath $Web -Destination (Join-Path $t "web") -Recurse -Force
    }
}
Say "插件拷好了：$($Targets -join '、')$(if ($HasWeb) { '（带小家网页版）' } else { '（没有小家网页版，只能用窗口版）' })"

# 2. package.json
$pkgText = ReadText $Pkg
if ($pkgText -match '"dsh-living-dock"') {
    Say "package.json：已经有 dsh-living-dock，没改"
} else {
    $entry = '"dsh-living-dock": "file:../../local-plugins/dsh-living-dock"'
    $bak = Backup $Pkg
    if ($pkgText -match '"dependencies"\s*:\s*\{\s*\}') {
        $out = $pkgText -replace '("dependencies"\s*:\s*\{)\s*\}', ('$1 ' + $entry + ' }')
    } elseif ($pkgText -match '"dependencies"\s*:\s*\{') {
        $out = ([regex]'("dependencies"\s*:\s*\{)(\s*)').Replace($pkgText, { param($m) $m.Groups[1].Value + $m.Groups[2].Value + $entry + "," + $m.Groups[2].Value }, 1)
    } else {
        $out = ([regex]'^\s*\{').Replace($pkgText, { param($m) $m.Value + ' "dependencies": { ' + $entry + ' },' }, 1)
    }
    WriteText $Pkg $out
    CheckJson $Pkg $bak
    Say "package.json：加了 dsh-living-dock（备份 $bak）"
}

# 3. cordis.patch.yml（已经有 living-dock 就保留它和它的配对码）
$ymlText = if (Test-Path -LiteralPath $Yml) { ReadText $Yml } else { "" }
if ($ymlText -match 'id:\s*living-dock') {
    $m = [regex]::Match($ymlText.Substring([regex]::Match($ymlText, 'id:\s*living-dock').Index), "pairCode:\s*['""]?(\d{4,8})")
    if ($m.Success) { $PairCode = $m.Groups[1].Value }
    Say "cordis.patch.yml：已经有 living-dock，没改"
} else {
    if ($PairCode -notmatch '^\d{6}$') { $PairCode = "{0:D6}" -f (Get-Random -Minimum 100000 -Maximum 999999) }
    # the real Documents folder (it may have been moved, e.g. to OneDrive); YAML single quotes take it as it is
    $NotesDir = Join-Path ([Environment]::GetFolderPath("MyDocuments")) "旅行的大肥鱼\茶几纸条"
    $nl = if ($ymlText.Contains("`r`n") -or $ymlText -eq "") { "`r`n" } else { "`n" }
    $block = @(
        $Begin,
        "- insert:",
        "    - id: living-dock",
        "      name: `"dsh-living-dock`"",
        "      config:",
        "        enabled: true",
        "        tools: true",
        "        port: 48960",
        "        beaconPort: 48961",
        "        findPort: 48962",
        "        pairCode: `"$PairCode`"",
        ("        notesDir: '" + $NotesDir.Replace("'", "''") + "'"),
        "        chatSessions:",
        "          - `"^onebot-private-`"",
        "        ignoreSessions:",
        "          - `"^onebot-group-`"",
        $End
    ) -join $nl
    if ($ymlText -ne "") { Backup $Yml | Out-Null }
    WriteText $Yml ($(if ($ymlText.Trim() -ne "") { $ymlText.TrimEnd() + $nl + $nl } else { "" }) + $block + $nl)
    Say "cordis.patch.yml：加了 living-dock"
}

# 4. 窗口的配对码
if ($PairCode -match '^\d{4,8}$') {
    New-Item -ItemType Directory -Force -Path $GameUserDir | Out-Null
    $cfg = Join-Path $GameUserDir "settings.cfg"
    $text = if (Test-Path -LiteralPath $cfg) { ReadText $cfg } else { "" }
    $line = "pair_code=`"$PairCode`""
    if ($text -match '(?m)^pair_code=.*$') { $text = $text -replace '(?m)^pair_code=.*$', $line }
    elseif ($text -match '(?m)^\[link\]\s*$') { $text = $text -replace '(?m)^\[link\]\s*$', "[link]`r`n$line" }
    else { $text = $text.TrimEnd() + $(if ($text.Trim() -ne "") { "`r`n`r`n" } else { "" }) + "[link]`r`n$line`r`n" }
    WriteText $cfg $text
    Say "窗口设置：配对码写好了"
}

Say ""
Say "装好了。配对码：$PairCode"
Say "接下来：1. 重启 DSH；2. 在 DSH 左边栏点「旅行的大肥鱼」就能看到小家（也可以打开《旅行的大肥鱼》窗口版，右下角小圆点变绿就是连上了）。"
