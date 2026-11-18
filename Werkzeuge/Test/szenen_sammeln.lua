-- SZENE: Sammeln - Vorbereitung (Einstellungen, Elwynn, Beute-API)
local e = __WW.charDb.sammeln
e.an, e.minikarte, e.weltkarte, e.nurKoennen, e.grau, e.nurForever, e.meldung = true, true, true, true, false, false, true
e.typ = {}
__WW.db.sammelFunde = {}
__S = { chat = {}, ort = { 0.4, 0.6 } }
__S.altPrint = print
__S.altSpell = C_Spell.GetSpellName
print = function(...)
  local t = {}
  for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
  __S.chat[#__S.chat + 1] = table.concat(t, " ")
end
__S.altPos = C_Map.GetPlayerMapPosition
C_Map.GetPlayerMapPosition = function()
  local x, y = __S.ort[1], __S.ort[2]
  return { x = x, y = y, GetXY = function() return x, y end }
end
-- Beutefenster nachbilden: __S.beute = { quelle = GUID, items = { itemID, ... } }
GetNumLootItems = function() return __S.beute and #__S.beute.items or 0 end
GetLootSlotLink = function(s) local i = __S.beute and __S.beute.items[s] return i and ("|cffffffff|Hitem:" .. i .. "::::::::|h[x]|h|r") end
GetLootSourceInfo = function(s) return __S.beute and __S.beute.quelle, 1 end
UnitGUID = function() return nil end
UnitIsDead = function() return false end
function __SAMMLE(zauber, quelle, items)
  __S.beute = { quelle = quelle, items = items }
  __FEUER("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-1-2-3-" .. zauber, zauber)
  __FEUER("LOOT_READY", false)
  __FEUER("LOOT_OPENED", false)
  __S.beute = nil
  __FEUER("LOOT_CLOSED")
  __UPDATE(2)
end
__KARTE = 1429
__FEUER("ZONE_CHANGED_NEW_AREA")
__UPDATE(2)
__S.pins0 = __PINS_MINI or 0
__LOG[#__LOG + 1] = "Sammeln: Minikarte vorher " .. __S.pins0

-- SZENE: Sammeln - Kupfer abbauen speichert den Fundort
__SAMMLE(2575, "GameObject-0-4170-0-12-1731-0000ABCDEF", { 2770, 2835 })
local s = __WW.db.sammelFunde[1429] and __WW.db.sammelFunde[1429][30]
if s ~= "b4go" then error("Kupfer-Fundort nicht gespeichert, gefunden: " .. tostring(s)) end
if (__PINS_MINI or 0) ~= __S.pins0 + 1 then error("Minikarte nicht neu gebaut: " .. tostring(__PINS_MINI) .. " statt " .. (__S.pins0 + 1)) end
local meldung = __S.chat[#__S.chat] or ""
if not meldung:find("Neuer Fundort gespeichert") or not meldung:find("Kupfervorkommen") then error("Keine Chatmeldung: " .. meldung) end
__LOG[#__LOG + 1] = "Sammeln: " .. meldung

-- SZENE: Sammeln - derselbe Fundort zweimal wird nicht doppelt gespeichert
local chatVorher = #__S.chat
__S.ort = { 0.4021, 0.6013 }   -- 0,24 % daneben
__SAMMLE(2575, "GameObject-0-4170-0-12-1731-0000ABCDEF", { 2770 })
local s = __WW.db.sammelFunde[1429][30]
if s ~= "b4go" then error("Doppelter Fundort gespeichert: " .. tostring(s)) end
if #__S.chat ~= chatVorher then error("Chatmeldung trotz bekanntem Fundort") end

-- SZENE: Sammeln - Fundort aus den Daten wird nicht gespeichert
__S.ort = { 0.165, 0.720 }     -- Classic-Punkt 163/719
__SAMMLE(2575, "GameObject-0-4170-0-12-1731-0000ABCDEF", { 2770 })
if __WW.db.sammelFunde[1429][30] ~= "b4go" then error("Bekannter Daten-Punkt gespeichert: " .. __WW.db.sammelFunde[1429][30]) end

-- SZENE: Sammeln - nur nach Item (keine Lootquelle), Name per Zaubername
__S.ort = { 0.05, 0.05 }
GetLootSourceInfo = function() return nil end
C_Spell.GetSpellName = function(id) if id == 999001 then return "Bergbau" end return "Zauber" .. tostring(id) end
__SAMMLE(999001, nil, { 2770 })
local s = __WW.db.sammelFunde[1429][30]
if #s ~= 8 then error("Fundort per Item/Name nicht gespeichert: " .. s) end
GetLootSourceInfo = function(s) return __S.beute and __S.beute.quelle, 1 end

-- SZENE: Sammeln - Kürschnern (NPC aus der Lootquelle) und unbekanntes Tier
__S.ort = { 0.7, 0.2 }
__SAMMLE(8613, "Creature-0-4170-0-12-2966-0000ABCDEF", { 2318 })
if not (__WW.db.sammelFunde[1429][48]) then error("Kürschner-Fundort (Battleboar) fehlt") end
__S.ort = { 0.75, 0.25 }
__SAMMLE(8613, "Creature-0-4170-0-12-123456-0000ABCDEF", { 2318 })
if not (__WW.db.sammelFunde[1429][0]) then error("Unbekanntes Tier nicht gespeichert") end

-- SZENE: Sammeln - neues Kraut, das die Daten nicht kennen
__S.ort = { 0.3, 0.3 }
__SAMMLE(2366, "GameObject-0-4170-0-12-999999-0000ABCDEF", { 99999 })
if not (__WW.db.sammelFunde[1429][-1]) then error("Unbekanntes Kraut nicht gespeichert") end

-- SZENE: Sammeln - Leichenbeute ohne Sammelzauber speichert nichts
local vorher = 0
for _, s in pairs(__WW.db.sammelFunde[1429]) do vorher = vorher + #s end
__S.ort = { 0.9, 0.9 }
__S.beute = { quelle = "Creature-0-4170-0-12-2966-0000ABCDEF", items = { 2770 } }
__FEUER("LOOT_OPENED", false)
-- Bergbau, aber dann kommt nur die Beute einer Leiche: gehört nicht dazu
__FEUER("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-1", 2575)
__FEUER("LOOT_OPENED", false)
__S.beute = nil
__UPDATE(2)
local nachher = 0
for _, s in pairs(__WW.db.sammelFunde[1429]) do nachher = nachher + #s end
if nachher ~= vorher then error("Leichenbeute als Fundort gespeichert") end

-- SZENE: Sammeln - ohne Position (Instanz) nichts speichern
local altBest = C_Map.GetBestMapForUnit
C_Map.GetBestMapForUnit = function() return nil end
__SAMMLE(2575, "GameObject-0-4170-0-12-1731-0000ABCDEF", { 2770 })
C_Map.GetBestMapForUnit = altBest

-- SZENE: Sammeln - Reiter zeigt eigene Fundorte, Tooltip, Löschen
__WW:Oeffnen("sammeln")
local gefunden = false
for _, f in ipairs(__FRAMES) do
  if f.__typ == "FontString" and type(f.__text) == "string" and f.__text:find("^Eigene Fundorte: %d") then
    gefunden = true
    __LOG[#__LOG + 1] = "Sammeln: " .. f.__text
  end
end
if not gefunden then error("Anzeige 'Eigene Fundorte' fehlt") end
for _, f in ipairs(__FRAMES) do
  if f.quelle == "e" and f.__scripts.OnEnter then f.__scripts.OnEnter(f) break end
end
local d = StaticPopupDialogs.WEGWEISER_FUNDORTE_LOESCHEN
if not (d and d.OnAccept) then error("Rückfrage zum Löschen fehlt") end
d.OnAccept()
if next(__WW.db.sammelFunde) then error("Eigene Fundorte nicht gelöscht") end

-- SZENE: Sammeln - Angelorte: Nadeln nach Gebietsstufe, Tooltip, "Wo lohnt es sich" fuer Angeln
do
  local e = __WW.charDb.sammeln
  local altF = __WW.Fertigkeiten
  local altTyp = e.typ
  __WW.Fertigkeiten = function()
    local t = altF()
    t["Angeln"] = { rang = 60, max = 75 }
    return t
  end
  __FEUER("SKILL_LINES_CHANGED")
  __UPDATE(2)
  __KARTE = 1429   -- Elwynn: Angelstufe 25, Schwarm (43) und Angelplaetze (641)
  -- Nadeln: mit Angeln mehr als ohne
  e.typ = { fish = false }
  __WW.SammelnAktualisieren()
  local ohne = __PINS_MINI or 0
  e.typ = {}   -- ohne eigene Wahl: an, weil Angeln gelernt ist
  __WW.SammelnAktualisieren()
  local mit = __PINS_MINI or 0
  if mit <= ohne then error("Angelorte fehlen auf der Minikarte: ohne " .. ohne .. ", mit " .. mit) end
  -- Tooltip einer Angel-Nadel: Gebietsstufe, Farbe, Quelle
  local pin
  for _, f in ipairs(__FRAMES) do if (f.artID == 641 or f.artID == 43) and f.__scripts.OnEnter then pin = f end end
  if not pin then error("keine Angel-Nadel gebaut") end
  local zeilen = {}
  local altAdd = GameTooltip.AddLine
  GameTooltip.AddLine = function(self, t, ...) zeilen[#zeilen + 1] = tostring(t) return altAdd(self, t, ...) end
  pin.__scripts.OnEnter(pin)
  GameTooltip.AddLine = altAdd
  local t = table.concat(zeilen, " | ")
  __ENTHAELT(t, "ab 25 entkommt kein Fisch", "Tooltip: Gebietsstufe")
  __ENTHAELT(t, "Deine Fertigkeit: 60", "Tooltip: eigene Stufe")
  __ENTHAELT(t, "kein Fisch entkommt", "Tooltip: gruen bei 60 in Elwynn")
  -- Reiter: Kopf "Angeln 60", gruene Gebiete zuerst, Elwynn dabei
  __WW:Oeffnen("sammeln")
  local liste
  for _, f in ipairs(__FRAMES) do
    if f.eintraege then
      for _, x in ipairs(f.eintraege) do if x.kopf and tostring(x.text):find("Angeln 60", 1, true) then liste = f end end
    end
  end
  if not liste then error("Reiter Sammeln: Kopf 'Angeln 60' fehlt") end
  local nachKopf, elwynn, ersteFarbeGelb = false, false, nil
  for _, x in ipairs(liste.eintraege) do
    if x.kopf then nachKopf = tostring(x.text):find("Angeln", 1, true) ~= nil
    elseif nachKopf and x.m then
      if x.m == 1429 then elwynn = true end
      if ersteFarbeGelb == nil then ersteFarbeGelb = tostring(x.text):find("ffff00", 1, true) ~= nil end
    end
  end
  if not elwynn then error("Elwynn fehlt in den Angel-Gebieten") end
  if ersteFarbeGelb then error("Angel-Gebiete: gelbe vor gruenen") end
  -- aufraeumen
  __WW.Fertigkeiten = altF
  e.typ = altTyp
  __FEUER("SKILL_LINES_CHANGED")
  __UPDATE(2)
end

-- SZENE: Sammeln - Aufräumen
print = __S.altPrint
C_Spell.GetSpellName = __S.altSpell
C_Map.GetPlayerMapPosition = __S.altPos
GetNumLootItems, GetLootSlotLink, GetLootSourceInfo, UnitGUID, UnitIsDead, __SAMMLE = nil, nil, nil, nil, nil, nil

-- SZENE: Sammeln - Berufe ueber C_SkillInfo (Forever) und Ersatz ueber die alten Funktionen
local f = __WW.Fertigkeiten()
-- mockwow: Kraeuterkunde zweimal (120 und 125), Bergbau 80
if not (f["Kräuterkunde"] and f["Kräuterkunde"].rang == 125 and f["Kräuterkunde"].max == 150) then
  error("Kräuterkunde aus C_SkillInfo: höchster Wert erwartet, war " .. tostring(f["Kräuterkunde"] and f["Kräuterkunde"].rang))
end
if not (f["Bergbau"] and f["Bergbau"].rang == 80) then error("Bergbau aus C_SkillInfo fehlt") end
__WW:Oeffnen("sammeln")
local gezeigt
for _, fs in ipairs(__FRAMES) do
  if fs.__typ == "FontString" and type(fs.__text) == "string" and fs.__text:find("125 / 150", 1, true) then gezeigt = fs.__text end
end
if not gezeigt then error("Reiter Sammeln zeigt die Kräuterkunde-Stufe 125 / 150 nicht") end
-- Classic-Client: kein C_SkillInfo, aber die alten globalen Funktionen
local altSI = C_SkillInfo
C_SkillInfo = nil
GetNumSkillLines = function() return 2 end
GetSkillLineInfo = function(i) if i == 1 then return "Berufe", true end return "Bergbau", false, false, 42, 0, 0, 75 end
f = __WW.Fertigkeiten()
C_SkillInfo, GetNumSkillLines, GetSkillLineInfo = altSI, nil, nil
if not (f["Bergbau"] and f["Bergbau"].rang == 42 and f["Bergbau"].max == 75) then error("Ersatz über GetSkillLineInfo klappt nicht") end
-- Zaubernamen und Geld ueber die neuen Funktionen
if __WW.SpellName(2575) ~= "Zauber2575" then error("WW.SpellName über C_Spell: " .. tostring(__WW.SpellName(2575))) end
if __WW.Geld(64600) ~= "64600c" then error("WW.Geld über C_CurrencyInfo: " .. tostring(__WW.Geld(64600))) end
local altCI = C_CurrencyInfo
C_CurrencyInfo = nil
local text = __WW.Geld(64600)
C_CurrencyInfo = altCI
if text ~= "6g 46s" then error("WW.Geld ohne Münz-Funktion: " .. tostring(text)) end
