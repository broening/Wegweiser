# Wegweiser: entscheidet, ob eine neue Version noetig ist (fuer GitHub, siehe .github\workflows\release.yml).
# Laeuft nach Daten-aktualisieren.ps1. Laeuft in Windows PowerShell 5.1 und PowerShell 7.
#
# Regeln:
#   - Die Version in Wegweiser.toc hat noch keinen Tag (z. B. v0.2.0)  -> Release "v0.2.0"
#   - Sonst: die Daten haben sich geaendert                            -> Release "v0.2.0-202611180417"
#   - Sonst: kein Release
# Der Fingerabdruck der Daten steht in Werkzeuge/daten-stand.txt (Version.lua zaehlt nicht mit,
# weil sie die Uhrzeit enthaelt). Bei einem Release schreibt das Skript den neuen Fingerabdruck dort hinein.
# Ausgabe: tag=... und grund=... nach $env:GITHUB_OUTPUT (falls gesetzt) und auf den Bildschirm.

$ErrorActionPreference = 'Stop'
$wegweiser = Split-Path -Parent $PSScriptRoot
$daten     = Join-Path $wegweiser 'Daten'
$standDatei = Join-Path $PSScriptRoot 'daten-stand.txt'

# Version aus der .toc
$basis = $null
foreach ($zeile in [System.IO.File]::ReadAllLines((Join-Path $wegweiser 'Wegweiser.toc'))) {
    if ($zeile -match '^##\s*Version:\s*(.+)$') { $basis = $Matches[1].Trim() }
}
if (-not $basis -or $basis -notmatch '^\d+\.\d+\.\d+$') { throw "Wegweiser.toc: '## Version: X.Y.Z' fehlt oder ist kein X.Y.Z ($basis)." }

# Fingerabdruck der Daten: Pfad + SHA256 jeder Datei, sortiert
$sha = [System.Security.Cryptography.SHA256]::Create()
$teile = foreach ($f in (Get-ChildItem -Recurse -File $daten | Where-Object { $_.Name -ne 'Version.lua' })) {
    $rel = $f.FullName.Substring($daten.Length + 1).Replace('\', '/')
    $h = [BitConverter]::ToString($sha.ComputeHash([System.IO.File]::ReadAllBytes($f.FullName))).Replace('-', '')
    "$rel $h"
}
$teile = $teile | Sort-Object
if (-not $teile) { throw "Daten-Ordner ist leer: $daten" }
$alles = [System.Text.Encoding]::UTF8.GetBytes(($teile -join "`n"))
$neu = [BitConverter]::ToString($sha.ComputeHash($alles)).Replace('-', '').ToLower()
$alt = if (Test-Path $standDatei) { ([System.IO.File]::ReadAllText($standDatei)).Trim() } else { '' }

$tagBasis = "v$basis"
$gibtTag = [bool](git -C $wegweiser tag -l $tagBasis)
$tag = ''; $grund = ''
if (-not $gibtTag) {
    $tag = $tagBasis; $grund = "Neue Version $basis"
} elseif ($neu -ne $alt) {
    $tag = "$tagBasis-" + (Get-Date).ToUniversalTime().ToString('yyyyMMddHHmm'); $grund = 'Neue Daten'
}

if ($tag) {
    [System.IO.File]::WriteAllText($standDatei, "$neu`n", (New-Object System.Text.UTF8Encoding $false))
    Write-Host "Release: $tag ($grund)" -ForegroundColor Green
} else {
    Write-Host "Kein Release: Version $basis hat einen Tag, Daten unveraendert."
}
if ($env:GITHUB_OUTPUT) {
    Add-Content -Path $env:GITHUB_OUTPUT -Value "tag=$tag"
    Add-Content -Path $env:GITHUB_OUTPUT -Value "grund=$grund"
}
