@echo off
rem Doppelklick: holt neue Daten aus ForeverDB, Helper, DungeonMap und Gathercraft.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Werkzeuge\Daten-aktualisieren.ps1"
echo.
pause
