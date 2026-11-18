# Wegweiser: die Quell-Addons aus dem Internet holen (fuer GitHub, siehe .github\workflows\release.yml).
# Laeuft in Windows PowerShell 5.1 und PowerShell 7 (auch Linux).
#
# Was es tut:
#   1. ForeverDB + ForeverDB_Helper: Zip von https://foreverdb.net/downloads/ForeverDB.zip
#   2. Gathercraft: neueste "-forever.zip" von GitHub (pheenixlawl-ui/Gathercraft)
#   3. ForeverDungeonMap: hat keinen bekannten Download. Kopie aus Wegweiser\Quellen\ForeverDungeonMap.
# Danach liegen die Addons in -Ziel. Dann: Daten-aktualisieren.ps1 -AddOns <Ziel>
param([Parameter(Mandatory = $true)][string]$Ziel)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'   # macht Invoke-WebRequest in PS 5.1 viel schneller
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$wegweiser = Split-Path -Parent $PSScriptRoot
$agent     = 'Wegweiser-Build (WoW-Addon)'

if (Test-Path $Ziel) { Remove-Item -Recurse -Force $Ziel }
New-Item -ItemType Directory -Force $Ziel | Out-Null
$tmp = Join-Path $Ziel '_zips'
New-Item -ItemType Directory -Force $tmp | Out-Null

function Hole-Zip($url, $name) {
    $datei = Join-Path $tmp $name
    Write-Host "Lade $url"
    Invoke-WebRequest -UseBasicParsing -UserAgent $agent -Uri $url -OutFile $datei
    Expand-Archive -Force -Path $datei -DestinationPath $Ziel
}

# 1. ForeverDB (enthaelt die Ordner ForeverDB und ForeverDB_Helper)
Hole-Zip 'https://foreverdb.net/downloads/ForeverDB.zip' 'ForeverDB.zip'

# 2. Gathercraft
$kopf = @{ 'User-Agent' = $agent; 'Accept' = 'application/vnd.github+json' }
if ($env:GITHUB_TOKEN) { $kopf['Authorization'] = "Bearer $($env:GITHUB_TOKEN)" }
$rel = Invoke-RestMethod -UseBasicParsing -Headers $kopf -Uri 'https://api.github.com/repos/pheenixlawl-ui/Gathercraft/releases/latest'
$asset = $rel.assets | Where-Object { $_.name -like '*-forever.zip' } | Select-Object -First 1
if (-not $asset) { $asset = $rel.assets | Where-Object { $_.name -like '*.zip' } | Select-Object -First 1 }
if (-not $asset) { throw "Gathercraft $($rel.tag_name): keine Zip-Datei im Release." }
Hole-Zip $asset.browser_download_url $asset.name

# 3. ForeverDungeonMap (Kopie im Repo)
$fdm = Join-Path $wegweiser 'Quellen/ForeverDungeonMap'
if (-not (Test-Path $fdm)) { throw "Kopie fehlt: $fdm" }
Copy-Item -Recurse -Force $fdm (Join-Path $Ziel 'ForeverDungeonMap')

Remove-Item -Recurse -Force $tmp

# Kontrolle
$fehlt = @()
foreach ($a in 'ForeverDB', 'ForeverDB_Helper', 'Gathercraft', 'ForeverDungeonMap') {
    if (-not (Test-Path (Join-Path $Ziel "$a/$a.toc"))) { $fehlt += $a }
}
if ($fehlt.Count -gt 0) { throw "Nach dem Laden fehlt: $($fehlt -join ', ')" }
Write-Host "OK: alle Quell-Addons liegen in $Ziel" -ForegroundColor Green
