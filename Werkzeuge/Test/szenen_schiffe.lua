-- SZENE: Schiffe - Vorbereitung (Horde, Zeit, Position)
__S2 = { t = 1700000000, pos = nil }
__S2.altFraktion = UnitFactionGroup
UnitFactionGroup = function() return "Horde", "Horde" end
__S2.altServerZeit = GetServerTime
GetServerTime = function() return __S2.t end
UnitPosition = function() if __S2.pos then return __S2.pos[2], __S2.pos[3], 0, __S2.pos[1] end end
UnitOnTaxi = function() return false end
__WW.db.fahrplan = {}
__WW.charDb.schiffe.anzeige = true
-- Position setzen (Kontinent, Welt-X, Welt-Y) und einen Takt laufen lassen
function __STEHE(c, x, y, sek)
  __S2.pos = { c, x, y }
  if sek then __S2.t = __S2.t + sek end
  __UPDATE(5)
end
function __FAHRPLAN_TEXT()
  local f = WegweiserFahrplan
  if not (f and f:IsShown()) then return nil end
  local t = {}
  for _, z in ipairs(f.zeilen or {}) do
    if z:IsShown() then t[#t + 1] = z.text:GetText() or "" end
  end
  return table.concat(t, " | ")
end

-- SZENE: Schiffe - am Zeppelinturm von Orgrimmar: noch nicht geeicht
__STEHE(1, 1325, -4645)
local text = __FAHRPLAN_TEXT()
if not text then error("Fahrplan nicht sichtbar am Zeppelinturm") end
if not text:find("Zeppelin nach Unterstadt: noch nicht geeicht") then error("Text falsch: " .. text) end
if not text:find("nach Grom'gol") then error("Zweiter Zeppelin fehlt: " .. text) end
__LOG[#__LOG + 1] = "Schiffe: " .. text

-- SZENE: Schiffe - Eichen mit 'Legt ab', dann Countdown
local knopf
for _, z in ipairs(WegweiserFahrplan.zeilen) do
  if z.link and z.link.id == "zeppelin-orgrimmar-undercity" then knopf = z.ab end
end
if not (knopf and knopf:IsShown()) then error("Knopf 'Legt ab' fehlt") end
knopf:Click()
local f = __WW.db.fahrplan["zeppelin-orgrimmar-undercity"]
if not (f and f.anker == __S2.t) then error("Eichung nicht gespeichert") end
__STEHE(1, 1325, -4645, 100)
local text = __FAHRPLAN_TEXT()
if not text:find("Zeppelin nach Unterstadt: Abfahrt in 3:44") then error("Countdown falsch: " .. text) end
__STEHE(1, 1325, -4645, 180)
local text = __FAHRPLAN_TEXT()
if not text:find("Zeppelin nach Unterstadt: liegt am Steg %- fährt in 0:44") then error("Am Steg falsch: " .. text) end
__LOG[#__LOG + 1] = "Schiffe: " .. text

-- SZENE: Schiffe - weg vom Steg: Anzeige weg
__STEHE(1, 1600, -4400, 5)
if __FAHRPLAN_TEXT() then error("Fahrplan sichtbar, obwohl weit weg") end

-- SZENE: Schiffe - automatisch: Abfahrt Orgrimmar, Ankunft Grom'gol (Ladebildschirm dazwischen)
__STEHE(1, 1349, -4652, 10)
local ab = __S2.t
__S2.pos = nil
__UPDATE(5)
__STEHE(0, -12430, 205, 80)
local f = __WW.db.fahrplan["zeppelin-orgrimmar-gromgol"]
if not f then error("Ankunft nicht erkannt") end
-- Abfahrt in Orgrimmar = Ankunft - Fahrzeit (72 s)
if math.abs(f.anker - (__S2.t - 72)) > 1 then error("Anker falsch: " .. f.anker .. " statt " .. (__S2.t - 72)) end
local text = __FAHRPLAN_TEXT()
if not (text and text:find("Zeppelin nach Orgrimmar")) then error("Am Grom'gol-Turm keine Anzeige: " .. tostring(text)) end
__LOG[#__LOG + 1] = "Schiffe: " .. text

-- SZENE: Schiffe - nach 30 Min. "ca.", nach 2 Std. "ungenau", Liste im Reiter
__STEHE(0, -12430, 205, 31 * 60)
local text = __FAHRPLAN_TEXT() or ""
if not text:find("Zeppelin nach Orgrimmar: [^|]*ca%. %d") then error("Nach 30 Min. ohne 'ca.': " .. text) end
if text:find("ungenau") then error("Nach 30 Min. schon 'ungenau': " .. text) end
__STEHE(0, -12430, 205, 2 * 3600)
local text = __FAHRPLAN_TEXT() or ""
if not text:find("ungenau") then error("Alte Eichung nicht markiert: " .. text) end
local liste = __WW.Schiffe.eintraege()
local alles = {}
for _, e in ipairs(liste) do alles[#alles + 1] = tostring(e.text or e.info) end
alles = table.concat(alles, " | ")
if not alles:find("Zeppelin zwischen Orgrimmar und Unterstadt") then error("Liste ohne Zeppelin: " .. alles) end
if alles:find("Schiff zwischen Menethil und Theramore") then error("Allianz-Schiff in der Horde-Liste") end
if not alles:find("ungenau") then error("Liste ohne Hinweis auf alte Eichung: " .. alles) end
__WW:Oeffnen("fluege")

-- SZENE: Schiffe - Einstellung aus: keine Anzeige
__WW.charDb.schiffe.anzeige = false
__STEHE(0, -12430, 205, 5)
if __FAHRPLAN_TEXT() then error("Fahrplan trotz Einstellung aus") end
__WW.charDb.schiffe.anzeige = true

-- SZENE: Schiffe - Rueckstellen vor den Pruef-Szenen
UnitFactionGroup = function() return "Alliance", "Allianz" end
IsSwimming = function() return __S2.schwimmt end
IsMounted = function() return false end
__WW.db.fahrplan = {}
__S2.pos = nil
__UPDATE(5)
function __LINK(id) for _, l in ipairs(__WW.quelle.fdb.routeLinks) do if l.id == id then return l end end end

-- SZENE: Schiffe - Schwimmen zur Mondfederfeste ist keine Ankunft
__STEHE(1, -4203, 3284.5, 10)
__S2.schwimmt = true
__STEHE(1, -4260, 2950, 60)
__STEHE(1, -4310, 2650, 60)
__S2.schwimmt = false
__STEHE(1, -4345, 2447, 60)
if __WW.db.fahrplan["boat-feathermoon"] then error("Schwimmen als Fähre geeicht") end

-- SZENE: Schiffe - echte Fahrt Auberdine - Rut'theran wird erkannt
__STEHE(1, 6595, 759.5, 300)
__STEHE(1, 7560, 890, 40)
__STEHE(1, 8530, 1022, 40)
local f = __WW.db.fahrplan["boat-auberdine-ruttheran"]
if not (f and math.abs(f.anker - (__S2.t - 80)) <= 1) then error("Echte Fahrt nicht erkannt") end

-- SZENE: Schiffe - Ruhestein nach dem Steg ist keine Fahrt
UnitFactionGroup = function() return "Horde", "Horde" end
__STEHE(1, 1325, -4645, 300)
__FEUER("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-1", 8690)
__S2.pos = nil
__UPDATE(5)
__STEHE(0, 2070, 265, 100)
if __WW.db.fahrplan["zeppelin-orgrimmar-undercity"] then error("Ruhestein als Zeppelinfahrt geeicht") end

-- SZENE: Schiffe - Umlauf: Grenzen, keine falsche Nachschaerfung, Neustart der Phase
local L = __LINK("zeppelin-orgrimmar-undercity")
local P0 = 2 * L.wait
__WW.db.fahrplan[L.id] = { anker = 1000, P = P0 * 1.5, n = 1, zeit = 1000 }
local p = __WW.Schiffe.periode(L)
if math.abs(p - P0 * 1.1) > 0.01 then error("Umlauf nicht begrenzt: " .. p) end
__WW.db.fahrplan[L.id] = nil
__WW.Schiffe.eiche(L, "a", "ab", 10000)
-- 10 Umläufe + 15 %: passt nicht sicher -> P bleibt
__WW.Schiffe.eiche(L, "a", "ab", 10000 + 10 * P0 + 0.15 * P0)
local e = __WW.db.fahrplan[L.id]
if e.P and math.abs(e.P - P0) > 0.01 then error("Umlauf falsch nachgeschärft: " .. e.P) end
-- weit daneben (40 %): Phase neu, P bleibt
__WW.Schiffe.eiche(L, "a", "ab", 10000 + 20 * P0 + 0.55 * P0)
local e = __WW.db.fahrplan[L.id]
if math.abs(e.anker - (10000 + 20 * P0 + 0.55 * P0)) > 0.01 then error("Anker nicht neu gesetzt") end
if e.P and math.abs(e.P - P0) > 0.01 then error("Umlauf bei Neustart geändert: " .. e.P) end
-- Ankunft in A (= Abfahrt in B vor 'ride'): Anker mit dem neuen P
__WW.db.fahrplan[L.id] = { anker = 50000, P = P0 * 1.02, n = 1, zeit = 50000 }
local T = 50000 + 2.5 * P0 * 1.02 + 3 + L.ride
__WW.Schiffe.eiche(L, "a", "an", T)
local e = __WW.db.fahrplan[L.id]
local erwartet = (T - L.ride) - __WW.Schiffe.periode(L) / 2
if math.abs(e.anker - erwartet) > 0.01 then error("Anker nach Ankunft falsch: " .. e.anker .. " statt " .. erwartet) end

-- SZENE: Schiffe - Zuruecksetzen in der Liste, Liste zaehlt im Reiter herunter
local L = __LINK("zeppelin-orgrimmar-undercity")
__WW.Schiffe.eiche(L, "a", "ab", __S2.t)
local knopf
for _, e in ipairs(__WW.Schiffe.eintraege()) do
  if e.aktion and e.knopf and tostring(e.text):find("Orgrimmar und Unterstadt") then knopf = e end
end
if not knopf then error("Kein Knopf 'Zurücksetzen' in der Liste") end
__WW:Oeffnen("fluege")
local function zeile()
  for _, f in ipairs(__FRAMES) do
    if f.__typ == "FontString" and type(f.__text) == "string" and f.__text:find("ab Orgrimmar in") then return f.__text end
  end
end
local vorher = zeile()
if not vorher then error("Fahrplan nicht in der Liste des Reiters") end
__S2.t = __S2.t + 7
__UPDATE(8)
local nachher = zeile()
if nachher == vorher then error("Liste zählt nicht herunter: " .. tostring(nachher)) end
knopf.aktion()
if __WW.db.fahrplan[L.id] then error("Zurücksetzen hat nichts gelöscht") end

-- SZENE: Schiffe - Aufraeumen
__S2.pos = nil
__UPDATE(5)
UnitFactionGroup = __S2.altFraktion
GetServerTime = __S2.altServerZeit
UnitPosition, UnitOnTaxi, IsSwimming, IsMounted = nil, nil, nil, nil
