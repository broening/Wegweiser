# Wegweiser: Daten aus den anderen Addons holen.
# Laeuft in Windows PowerShell 5.1. Doppelklick auf "Daten-aktualisieren.cmd" startet dieses Skript.
#
# Was es tut:
#   1. Liest Datendateien aus ForeverDB, ForeverDB_Helper, ForeverDungeonMap und Gathercraft.
#   2. Schreibt sie nach Wegweiser\Daten. Jede Quelle bekommt ihren eigenen Bereich (WW.quelle.<kurz>),
#      damit gleiche Namen (z. B. "dungeons") sich nicht ueberschreiben.
#   3. Kopiert die Dungeon-Karten (Bilder).
#   4. Schreibt Daten\Version.lua mit dem Stand jeder Quelle.
# Fehlt eine Quelle, bleibt die alte Kopie stehen.
#
# Optionen (fuer GitHub, siehe .github\workflows\release.yml):
#   -AddOns <Ordner>  dort liegen die Quell-Addons (Standard: der AddOns-Ordner neben Wegweiser)
#   -Streng           jede Warnung bricht mit Fehler ab (Exit-Code 1)
# Pfade nutzen "/", damit das Skript auch unter PowerShell 7 auf Linux laeuft.
param([string]$AddOns, [switch]$Streng)

$ErrorActionPreference = 'Stop'
$wegweiser = Split-Path -Parent $PSScriptRoot
$addons    = if ($AddOns) { $AddOns } else { Split-Path -Parent $wegweiser }
$daten     = Join-Path $wegweiser 'Daten'
$karten    = Join-Path $daten 'Karten'
$utf8      = New-Object System.Text.UTF8Encoding $false

New-Item -ItemType Directory -Force $daten  | Out-Null
New-Item -ItemType Directory -Force $karten | Out-Null

# Quelle -> Kurzname, Addon-Ordner, Dateien (Quelle, Ziel)
$quellen = @(
    @{ kurz = 'fdb'; addon = 'ForeverDB'; dateien = @(
        @('Data/Meta.lua',         'FDB_Meta.lua'),
        @('Data/Items.lua',        'FDB_Items.lua'),
        @('Data/Recipes.lua',      'FDB_Rezepte.lua'),
        @('Data/SearchNames.lua',  'FDB_Namen.lua'),
        @('Data/Gather.lua',       'FDB_Sammeln.lua'),
        @('Data/QuestClassic.lua', 'FDB_Quests.lua'),
        @('Data/QuestForever.lua', 'FDB_Quests_Forever.lua'),
        @('Data/Gear.lua',         'FDB_Ausruestung.lua'),
        @('Data/GearSources.lua',  'FDB_Ausruestung_Quellen.lua'),
        @('Data/Talents.lua',      'FDB_Talente.lua'),
        @('Data/Travel.lua',       'FDB_Fluege.lua'),
        @('Data/RouteMaps.lua',    'FDB_Schiffe.lua')
    ) },
    @{ kurz = 'helper'; addon = 'ForeverDB_Helper'; dateien = @(
        ,@('Data/Dungeons.lua', 'Helper_Dungeons.lua')
    ) },
    @{ kurz = 'fdm'; addon = 'ForeverDungeonMap'; dateien = @(
        @('Data/DungeonMaster_Data.lua',    'FDM_Quests.lua'),
        @('Data/DungeonMaster_Curated.lua', 'FDM_Korrekturen.lua'),
        @('Media/Maps/Maps.lua',            'FDM_Karten.lua'),
        @('Media/Maps/Guides.lua',          'FDM_Karten_Neu.lua')
    ) },
    @{ kurz = 'gc'; addon = 'Gathercraft'; dateien = @(
        ,@('Data/NodeNames.lua', 'GC_Namen.lua')
    ) }
)

function Lies-Version($addonOrdner, $name) {
    $toc = Join-Path $addonOrdner "$name.toc"
    if (-not (Test-Path $toc)) { return $null }
    foreach ($zeile in [System.IO.File]::ReadAllLines($toc)) {
        if ($zeile -match '^##\s*Version:\s*(.+)$') { return $Matches[1].Trim() }
    }
    return $null
}

$kopf = "local _, WW = ...`nWW.quelle = WW.quelle or {}`nWW.quelle.KURZ = WW.quelle.KURZ or {}`nlocal ns = WW.quelle.KURZ"
$versionen = @{}
$fehler = 0

foreach ($q in $quellen) {
    $ordner = Join-Path $addons $q.addon
    if (-not (Test-Path $ordner)) {
        Write-Host "FEHLT: $($q.addon) ist nicht installiert. Alte Daten bleiben." -ForegroundColor Yellow
        $fehler++
        continue
    }
    $versionen[$q.addon] = Lies-Version $ordner $q.addon
    foreach ($d in $q.dateien) {
        $von = Join-Path $ordner $d[0]
        $nach = Join-Path $daten $d[1]
        if (-not (Test-Path $von)) {
            Write-Host "FEHLT: $($q.addon)/$($d[0]). Alte Kopie bleibt." -ForegroundColor Yellow
            $fehler++
            continue
        }
        $text = [System.IO.File]::ReadAllText($von, $utf8)
        $neuerKopf = $kopf.Replace('KURZ', $q.kurz)
        if ($text -match '(?m)^local _, ns = \.\.\.\s*$') {
            $text = [regex]::Replace($text, '(?m)^local _, ns = \.\.\.\s*$', $neuerKopf, 1)
        } elseif ($text -match '(?m)^GathercraftNodeNames = \{') {
            $text = [regex]::Replace($text, '(?m)^GathercraftNodeNames = \{', ($neuerKopf + "`nns.nodeNames = {"), 1)
        } else {
            Write-Host "UNBEKANNT: $($d[0]) hat ein neues Format. Alte Kopie bleibt." -ForegroundColor Red
            $fehler++
            continue
        }
        $tmp = "$nach.neu"
        [System.IO.File]::WriteAllText($tmp, $text, $utf8)
        Move-Item -Force $tmp $nach
        Write-Host "OK: $($d[1])"
    }
}

# Dungeon-Karten (Bilder)
$bilder = Join-Path $addons 'ForeverDungeonMap/Media/Maps'
if (Test-Path $bilder) {
    $anzahl = 0
    foreach ($b in Get-ChildItem -Path $bilder -Filter '*.tga') {
        $ziel = Join-Path $karten $b.Name
        if (-not (Test-Path $ziel) -or (Get-Item $ziel).Length -ne $b.Length -or (Get-Item $ziel).LastWriteTime -lt $b.LastWriteTime) {
            Copy-Item -Force $b.FullName $ziel
            $anzahl++
        }
    }
    Write-Host "OK: $anzahl Karten-Bilder neu kopiert."
}

# Version.lua
$stand = Get-Date -Format 'yyyy-MM-dd HH:mm'
$zeilen = @("-- Von Werkzeuge\Daten-aktualisieren.ps1 geschrieben. Nicht von Hand aendern.",
            "local _, WW = ...",
            "WW.datenStand = { erstellt = `"$stand`", quellen = {")
foreach ($k in ($versionen.Keys | Sort-Object)) {
    $v = $versionen[$k]; if (-not $v) { $v = '?' }
    $zeilen += "  [`"$k`"] = `"$v`","
}
$zeilen += "} }"
[System.IO.File]::WriteAllText((Join-Path $daten 'Version.lua'), ($zeilen -join "`n") + "`n", $utf8)

Write-Host ""
if ($fehler -eq 0) {
    Write-Host "Fertig. Im Spiel /reload eingeben." -ForegroundColor Green
} else {
    Write-Host "Fertig mit $fehler Warnung(en). Im Spiel /reload eingeben." -ForegroundColor Yellow
    if ($Streng) { exit 1 }
}
