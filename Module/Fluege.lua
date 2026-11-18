-- Wegweiser: Reiter "Flüge". Alle Flugpunkte auf der Weltkarte (auch unentdeckte), Flugzeiten auf der Flugkarte,
-- ein Timer während des Flugs.
-- Daten: WW.quelle.fdb.travelData (ForeverDB.net, Daten\FDB_Fluege.lua):
--   nodes[id] = { Kontinent, Welt-X, Welt-Y, uiMap, x %, y %, Seite a/h/n, neu in Forever 1/0, Name (englisch) }
--   flights = "von>nach>Meter>Kupfer ..." (eine Richtung je Eintrag), measured = "von>nach>Sekunden>Flüge ..."
--   speeds.fly = Fluggeschwindigkeit (Meter/Sekunde)
-- Gemessen wird wie in ForeverDB FlightTimes.lua (GPL-3.0): TAXIMAP_OPENED (wo du bist), TakeTaxiNode per
-- hooksecurefunc (Ziel; nie ersetzt, nie selbst aufgerufen), dann UnitOnTaxi an bis aus = Flugzeit.
-- Gespeichert:
--   WW.db.fluege["von>nach"] = { n, summe, min, max }   (Knoten-IDs, Sekunden; alle Charaktere)
--   WW.db.flugNamen[id] = Name, wie der Client ihn zeigt (deutsch)
--   WW.charDb.fluege.bekannt[id] = true                (Flugpunkte, die dieser Charakter kennt)
local ADDON, WW = ...
local UI = WW.UI

local floor, max, min = math.floor, math.max, math.min

local F = {}
WW.Fluege = F

local REF = "WegweiserFluege"
local KREIS = "Interface\\AddOns\\Wegweiser\\Media\\Kreis"
local RING = "Interface\\AddOns\\Wegweiser\\Media\\Ring"
local KONTINENT_KARTE = { [0] = 1415, [1] = 1414 }   -- Östliche Königreiche, Kalimdor
local ABHEBEN, ZWISCHENSTOPP = 3, 3                   -- Sekunden für die Schätzung
local MIN_SEK, MAX_SEK = 5, 1800                      -- kürzere oder längere "Flüge" sind keine
local GROESSE = 18
local FARBE_BEKANNT = { 0.25, 0.9, 0.25 }
local FARBE_UNBEKANNT = { 0.55, 0.55, 0.55 }
local ZEIT_FARBE = { 0.94, 0.76, 0.35 }

WW.standardDB.fluege = {}
WW.standardDB.flugNamen = {}
WW.standardDB.flugTimer = {}
WW.standardCharDB.fluege = {
  karte = true,        -- Flugpunkte auf der Weltkarte
  unentdeckt = true,   -- auch Flugpunkte, die der Charakter noch nicht kennt (grau)
  zeiten = true,       -- Flugzeit im Tooltip der Flugkarte
  timer = true,        -- Timer während des Flugs
  bekannt = {},
}

local HBD, Pins
local gestartet = false
local panel

-- Aufruf mit pcall; gibt alle Rückgabewerte zurück (nil bei Fehler oder fehlender Funktion)
local function rufe(fn, ...)
  if not fn then return nil end
  local r = { pcall(fn, ...) }
  if not r[1] then return nil end
  return unpack(r, 2)
end

---------------------------------------------------------------------------
-- Daten
---------------------------------------------------------------------------
local function daten()
  local fdb = WW.quelle and WW.quelle.fdb
  local d = fdb and fdb.travelData
  if type(d) == "table" and type(d.nodes) == "table" then return d end
  return nil
end

local function knoten(id)
  local d = daten()
  local k = d and id and d.nodes[id]
  return type(k) == "table" and k or nil
end

local function einst() return WW.charDb and WW.charDb.fluege end

local function bekannt()
  local e = einst()
  if not e then return {} end
  if type(e.bekannt) ~= "table" then e.bekannt = {} end
  return e.bekannt
end

local function namenDB()
  if not WW.db then return {} end
  if type(WW.db.flugNamen) ~= "table" then WW.db.flugNamen = {} end
  return WW.db.flugNamen
end

local function zeitenDB()
  if not WW.db then return nil end
  if type(WW.db.fluege) ~= "table" then WW.db.fluege = {} end
  return WW.db.fluege
end

-- "a" (Allianz), "h" (Horde) oder nil
local function seite()
  local f = UnitFactionGroup and rufe(UnitFactionGroup, "player")
  if f == "Alliance" then return "a" elseif f == "Horde" then return "h" end
  return nil
end

-- Kann diese Seite den Flugpunkt nutzen? (eigene Fraktion oder neutral; ohne Fraktion: alle)
local function nutzbar(k, s)
  if not k then return false end
  return k[7] == "n" or s == nil or k[7] == s
end

-- "Sturmwind, Elwynn" -> "Sturmwind"
local function kurz(name)
  if type(name) ~= "string" or name == "" then return nil end
  return name:match("^([^,]+)") or name
end

function F.name(id)
  local n = namenDB()[id]
  if n then return n end
  local k = knoten(id)
  return k and k[9] or ("Flugpunkt " .. tostring(id))
end

local zonenNamen = {}
local function zoneName(m)
  if not m then return nil end
  if zonenNamen[m] ~= nil then return zonenNamen[m] or nil end
  local info = C_Map and C_Map.GetMapInfo and rufe(C_Map.GetMapInfo, m)
  local name = type(info) == "table" and type(info.name) == "string" and info.name or false
  zonenNamen[m] = name
  return name or nil
end

function F.uhr(s)
  s = floor((tonumber(s) or 0) + 0.5)
  if s < 0 then s = 0 end
  return string.format("%d:%02d", floor(s / 60), s % 60)
end

---------------------------------------------------------------------------
-- Flugzeiten: eigene Messung, sonst Messung der Forever-Spieler, sonst Schätzung
---------------------------------------------------------------------------
local kanten   -- [von] = { { nach, meter, kupfer } }
local function baueKanten()
  if kanten then return kanten end
  kanten = {}
  local d = daten()
  local s = d and type(d.flights) == "string" and d.flights or ""
  for a, b, yd, cu in s:gmatch("(%d+)>(%d+)>(%d+)>(%d+)") do
    a, b, yd, cu = tonumber(a), tonumber(b), tonumber(yd), tonumber(cu)
    if not kanten[a] then kanten[a] = {} end
    local l = kanten[a]
    l[#l + 1] = { nach = b, yd = yd, kupfer = cu }
  end
  return kanten
end

-- Knoten, die kein Flugmeister sind: eine Gruppe, die nur untereinander verbunden ist und deren Flüge
-- alle 0 Kupfer kosten (die Türme der Östlichen Pestländer). Knoten ganz ohne Flüge bleiben (Daten fehlen nur).
local keinFlugmeister
local function baueKeinFlugmeister()
  if keinFlugmeister then return keinFlugmeister end
  keinFlugmeister = {}
  local k = baueKanten()
  local nachbarn = {}   -- ungerichtet
  local function verbinde(a, b, cu)
    if not nachbarn[a] then nachbarn[a] = {} end
    nachbarn[a][#nachbarn[a] + 1] = { b, cu }
  end
  for a, l in pairs(k) do
    for _, e in ipairs(l) do
      verbinde(a, e.nach, e.kupfer)
      verbinde(e.nach, a, e.kupfer)
    end
  end
  local gesehen = {}
  for start in pairs(nachbarn) do
    if not gesehen[start] then
      local gruppe, bezahlt, offen = {}, false, { start }
      gesehen[start] = true
      while #offen > 0 do
        local u = table.remove(offen)
        gruppe[#gruppe + 1] = u
        for _, nb in ipairs(nachbarn[u]) do
          if (tonumber(nb[2]) or 0) > 0 then bezahlt = true end
          if not gesehen[nb[1]] then
            gesehen[nb[1]] = true
            offen[#offen + 1] = nb[1]
          end
        end
      end
      if not bezahlt then
        for _, id in ipairs(gruppe) do keinFlugmeister[id] = true end
      end
    end
  end
  return keinFlugmeister
end

-- Ist das ein Flugmeister, den die Seite s nutzen kann?
local function flugmeister(id, s)
  local k = knoten(id)
  return k ~= nil and nutzbar(k, s) and not baueKeinFlugmeister()[id]
end

local gemessenCache = {}
local function gemessenForever(a, b)
  local key = a .. ">" .. b
  local treffer = gemessenCache[key]
  if treffer == nil then
    local d = daten()
    local raw = d and type(d.measured) == "string" and d.measured
    local s, n
    if raw then s, n = raw:match("%f[%d]" .. key .. ">(%d+)>(%d+)") end
    treffer = s and { tonumber(s), tonumber(n) } or false
    gemessenCache[key] = treffer
  end
  if treffer then return treffer[1], treffer[2] end
  return nil
end

-- Kürzeste Kette über Flugpunkte, die erlaubt(id) zulässt: Meter / Fluggeschwindigkeit + Zwischenstopps
local function kette(a, b, erlaubt)
  local k = baueKanten()
  local d = daten()
  local tempo = d and type(d.speeds) == "table" and tonumber(d.speeds.fly) or 32
  local best, fertig, stopps = { [a] = 0 }, {}, { [a] = 0 }
  for _ = 1, 600 do
    local u, bu
    for v, c in pairs(best) do
      if not fertig[v] and (not bu or c < bu) then u, bu = v, c end
    end
    if not u then return nil end
    if u == b then
      return floor(ABHEBEN + bu / tempo + ZWISCHENSTOPP * max(0, stopps[u] - 1) + 0.5)
    end
    fertig[u] = true
    for _, e in ipairs(k[u] or {}) do
      local c = bu + e.yd
      if (e.nach == b or erlaubt(e.nach)) and not fertig[e.nach] and (not best[e.nach] or c < best[e.nach]) then
        best[e.nach], stopps[e.nach] = c, stopps[u] + 1
      end
    end
  end
  return nil
end

-- Sekunden, Quelle ("du" | "forever" | "schaetzung"), Anzahl Flüge; nil wenn nichts bekannt
function F.zeit(a, b)
  a, b = tonumber(a), tonumber(b)
  if not (a and b) or a == b then return nil end
  local db = zeitenDB()
  local e = db and db[a .. ">" .. b]
  if type(e) == "table" and (tonumber(e.n) or 0) > 0 and tonumber(e.summe) then
    return e.summe / e.n, "du", e.n
  end
  local s, n = gemessenForever(a, b)
  if s then return s, "forever", n end
  if not (knoten(a) and knoten(b)) then return nil end
  local sd, bk = seite(), bekannt()
  s = kette(a, b, function(id) return bk[id] and true or false end)
    or kette(a, b, function(id) return nutzbar(knoten(id), sd) end)
  if s then return s, "schaetzung" end
  return nil
end

local function fluegeText(n)
  n = tonumber(n) or 1
  return n == 1 and "1 Flug" or (n .. " Flüge")
end

-- "1:20 (von dir gemessen, 3 Flüge)" / "1:18 (gemessen in Forever, 50 Flüge)" / "ca. 1:50 (geschätzt)"
function F.beschreibe(s, quelle, n)
  if not s then return "noch unbekannt" end
  if quelle == "du" then return F.uhr(s) .. " (von dir gemessen, " .. fluegeText(n) .. ")" end
  if quelle == "forever" then
    return F.uhr(s) .. " (gemessen in Forever" .. (n and (", " .. fluegeText(n)) or "") .. ")"
  end
  return "ca. " .. F.uhr(s) .. " (geschätzt)"
end

---------------------------------------------------------------------------
-- Flugkarte lesen: wo du bist, welche Ziele, welche Flugpunkte du kennst
---------------------------------------------------------------------------
F.slots = {}   -- Platz auf der Flugkarte -> { id, name, aktuell }
F.von = nil

local function lerne(id)
  local bk = bekannt()
  if id and knoten(id) and not bk[id] then
    bk[id] = true
    return 1
  end
  return 0
end

-- Flugpunkt zu einem Platz der alten Flugkarte: bekannter Name, englischer Name, sonst Position.
function F.findeKnoten(name, platz)
  local d = daten()
  if not d then return nil end
  local sd = seite()
  if name then
    for id, n in pairs(namenDB()) do
      if n == name and nutzbar(knoten(id), sd) then return id end
    end
    for id, k in pairs(d.nodes) do
      if type(k) == "table" and k[9] == name and nutzbar(k, sd) then return id end
    end
  end
  local x, y = rufe(rawget(_G, "TaxiNodePosition"), platz)
  local karte = tonumber((rufe(rawget(_G, "GetTaxiMapID"))))
  x, y = tonumber(x), tonumber(y)
  if x and y and karte and HBD and HBD.TranslateZoneCoordinates then
    local best, bd
    for id, k in pairs(d.nodes) do
      if type(k) == "table" and nutzbar(k, sd) and tonumber(k[4]) then
        local ok, kx, ky = pcall(HBD.TranslateZoneCoordinates, HBD, (tonumber(k[5]) or 0) / 100,
          (tonumber(k[6]) or 0) / 100, tonumber(k[4]), karte)
        if ok and kx and ky then
          local dd = (kx - x) ^ 2 + (ky - y) ^ 2
          if not bd or dd < bd then best, bd = id, dd end
        end
      end
    end
    if bd and bd < 0.02 * 0.02 then return best end
  end
  return nil
end

-- Liest die offene Flugkarte. Gibt die Zahl neu gelernter Flugpunkte zurück.
function F.liesFlugkarte()
  local liste, neu = {}, 0
  local namen = namenDB()
  local alle = C_TaxiMap and C_TaxiMap.GetAllTaxiNodes
  if alle then
    -- nur mit der Karte der Flugkarte (wie ForeverDB): die Karte des Gebiets liefert evtl. nur dessen Flugpunkte
    local tm = tonumber((rufe(rawget(_G, "GetTaxiMapID"))))
    local FS = Enum and rawget(Enum, "FlightPathState")
    if tm then
      local l = rufe(alle, tm)
      if type(l) == "table" then
        for _, e in ipairs(l) do
          local platz = type(e) == "table" and tonumber(e.slotIndex)
          if platz then
            local id = tonumber(e.nodeID)
            local st = e.state
            local aktuell = st == 0 or (type(FS) == "table" and st == FS.Current)
            local erreichbar = aktuell or st == 1 or (type(FS) == "table" and st == FS.Reachable)
            local name = kurz(e.name)
            liste[platz] = { id = id, name = name, aktuell = aktuell and true or false }
            if id and erreichbar then neu = neu + lerne(id) end
            if id and name then namen[id] = name end
          end
        end
      end
    end
  end
  -- weniger Ziele als die alte Flugkarte zählt: unvollständig, dann die alte API
  local plaetze = 0
  for _ in pairs(liste) do plaetze = plaetze + 1 end
  local alteAnzahl = rawget(_G, "NumTaxiNodes") and tonumber((rufe(NumTaxiNodes))) or 0
  if plaetze < alteAnzahl then liste = {} end
  -- ältere Flugkarte: Namen und Art je Platz
  if not next(liste) and rawget(_G, "NumTaxiNodes") then
    local anzahl = tonumber((rufe(NumTaxiNodes))) or 0
    for i = 1, anzahl do
      local name = kurz((rufe(rawget(_G, "TaxiNodeName"), i)))
      local typ = rufe(rawget(_G, "TaxiNodeGetType"), i)
      local id = F.findeKnoten(name, i)
      liste[i] = { id = id, name = name, aktuell = typ == "CURRENT" }
      if id and (typ == "CURRENT" or typ == "REACHABLE") then neu = neu + lerne(id) end
      if id and name then namen[id] = name end
    end
  end
  F.slots = liste
  F.von = nil
  for _, n in pairs(liste) do
    if n.aktuell then F.von = n end
  end
  return neu
end

-- Flugpunkte, die der Client als entdeckt meldet, auch fern vom Flugmeister (wenn es die Funktion gibt)
function F.scanKarten()
  local api = C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap
  if not api then return 0 end
  local neu, namen = 0, namenDB()
  for _, km in pairs(KONTINENT_KARTE) do
    local l = rufe(api, km)
    if type(l) == "table" then
      for _, e in ipairs(l) do
        local id = type(e) == "table" and tonumber(e.nodeID)
        if id then
          if e.isUndiscovered == false then neu = neu + lerne(id) end
          local name = kurz(e.name)
          if name and knoten(id) then namen[id] = name end
        end
      end
    end
  end
  return neu
end

---------------------------------------------------------------------------
-- Nadeln auf der Weltkarte (eigene, also auch unter dem Kartennebel)
---------------------------------------------------------------------------
local function pinBetreten(self)
  local id = self.knotenID
  local k = knoten(id)
  if not k then return end
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:AddLine("Flugpunkt: " .. F.name(id), 1, 1, 1)
  local zn = zoneName(tonumber(k[4]))
  if zn then GameTooltip:AddLine(zn, 0.7, 0.7, 0.7) end
  if self.bekannt then
    GameTooltip:AddLine("Bekannt", FARBE_BEKANNT[1], FARBE_BEKANNT[2], FARBE_BEKANNT[3])
  else
    GameTooltip:AddLine("Noch nicht entdeckt - Flugmeister ansprechen", 0.75, 0.75, 0.75)
  end
  if k[7] == "n" then GameTooltip:AddLine("Neutral: für beide Fraktionen", 1, 0.82, 0) end
  if tonumber(k[8]) == 1 then GameTooltip:AddLine("Neu in Forever", 0.2, 0.85, 0.8) end
  GameTooltip:AddLine("Daten von ForeverDB.net", 0.5, 0.5, 0.5)
  GameTooltip:Show()
end

local function pinVerlassen() GameTooltip:Hide() end

local function neuerPin()
  local pin = CreateFrame("Frame", nil, UIParent)
  pin:SetSize(GROESSE, GROESSE)
  -- Symbol wie im Spiel: der geflügelte Stiefel, ohne Ring und Hintergrund
  pin.icon = pin:CreateTexture(nil, "ARTWORK")
  pin.icon:SetAllPoints()
  pin:EnableMouse(true)
  if pin.SetMouseClickEnabled then pcall(pin.SetMouseClickEnabled, pin, false) end
  pin:SetScript("OnEnter", pinBetreten)
  pin:SetScript("OnLeave", pinVerlassen)
  pin:Hide()
  return pin
end

local pool = {}

-- Baut alle Flugpunkt-Nadeln neu (etwa 80; HereBeDragons zeigt sie auf Gebiets- und Kontinentkarte).
-- Gibt die Zahl der Nadeln zurück.
function F.baueNadeln()
  if not Pins then return 0 end
  Pins:RemoveAllWorldMapIcons(REF)
  local e, d = einst(), daten()
  if not (e and d and e.karte) then return 0 end
  local sd, bk = seite(), bekannt()
  local icon = "Interface\\Minimap\\Tracking\\FlightMaster"
  local flag = tonumber(rawget(_G, "HBD_PINS_WORLDMAP_SHOW_CONTINENT")) or 2
  local n = 0
  for id, k in pairs(d.nodes) do
    if type(k) == "table" and flugmeister(id, sd) then
      local kennt = bk[id] and true or false
      local m, x, y = tonumber(k[4]), tonumber(k[5]), tonumber(k[6])
      if (kennt or e.unentdeckt) and m and x and y and x >= 0 and x <= 100 and y >= 0 and y <= 100 then
        n = n + 1
        local pin = pool[n]
        if not pin then
          pin = neuerPin()
          pool[n] = pin
        end
        pin.knotenID, pin.bekannt = id, kennt
        pin.icon:SetTexture(icon)
        if pin.icon.SetDesaturated then pin.icon:SetDesaturated(not kennt) end
        -- unentdeckt: grau und etwas durchsichtig
        pin:SetAlpha(kennt and 1 or 0.6)
        local ok, err = pcall(Pins.AddWorldMapIconMap, Pins, REF, pin, m, x / 100, y / 100, flag)
        if not ok and geterrorhandler then geterrorhandler()(err) end
      end
    end
  end
  return n
end

local function neuGelernt(anzahl)
  if (anzahl or 0) > 0 then F.baueNadeln() end
  if panel and panel:IsShown() and panel.OnZeigen then pcall(panel.OnZeigen, panel) end
end

---------------------------------------------------------------------------
-- Flugzeit im Tooltip der Flugkarte
---------------------------------------------------------------------------
function F.tooltipZeile(platz)
  local e = einst()
  if e and e.zeiten == false then return nil end
  local nach = F.slots[tonumber(platz) or -1]
  if not nach or nach.aktuell or not (F.von and F.von.id and nach.id) then return nil end
  return "Flugzeit: " .. F.beschreibe(F.zeit(F.von.id, nach.id))
end

local function tooltipErgaenzen(platz)
  local zeile = F.tooltipZeile(platz)
  if zeile and GameTooltip then
    GameTooltip:AddLine(zeile, ZEIT_FARBE[1], ZEIT_FARBE[2], ZEIT_FARBE[3])
    GameTooltip:Show()
  end
end

---------------------------------------------------------------------------
-- Flug messen und Timer
---------------------------------------------------------------------------
F.unterwegs = nil   -- { von, nach, at, start, sek, quelle, n }
local treiber = CreateFrame("Frame")
treiber:Hide()

function F.nimm(platz)
  if not next(F.slots) then pcall(F.liesFlugkarte) end
  local nach = F.slots[tonumber(platz) or -1]
  if not nach then return end
  local s, q, n
  if F.von and F.von.id and nach.id then s, q, n = F.zeit(F.von.id, nach.id) end
  F.unterwegs = { von = F.von, nach = nach, at = GetTime(), sek = s, quelle = q, n = n }
  treiber:Show()
end

-- Speichert eine gemessene Flugzeit. Gibt den Schlüssel "von>nach" zurück oder nil.
function F.speichere(von, nach, sek)
  local db = zeitenDB()
  if not (db and von and nach and von.id and nach.id and sek) then return nil end
  if sek < MIN_SEK or sek > MAX_SEK then return nil end
  local key = von.id .. ">" .. nach.id
  local s = floor(sek + 0.5)
  local e = type(db[key]) == "table" and db[key] or { n = 0, summe = 0 }
  e.n, e.summe = (tonumber(e.n) or 0) + 1, (tonumber(e.summe) or 0) + s
  e.min = e.min and min(e.min, s) or s
  e.max = e.max and max(e.max, s) or s
  db[key] = e
  return key
end

-- Zwei Zeilen und Anteil (0..1) für den Timer, oder nil wenn kein Flug läuft
function F.timerText(t)
  local p = F.unterwegs
  if not (p and p.start) then return nil end
  t = t or GetTime()
  local wohin = (p.nach and (p.nach.name or (p.nach.id and F.name(p.nach.id)))) or "?"
  local vergangen = t - p.start
  local zeile1, anteil
  if p.sek and p.sek > 0 then
    local rest = p.sek - vergangen
    if rest > 0 then
      zeile1 = "Flug nach " .. wohin .. ": noch " .. F.uhr(rest)
    else
      zeile1 = "Flug nach " .. wohin .. ": Landung gleich"
    end
    anteil = max(0, min(1, vergangen / p.sek))
  else
    zeile1 = "Flug nach " .. wohin .. ": unterwegs " .. F.uhr(vergangen)
  end
  local zeile2
  if p.quelle == "du" then
    zeile2 = "Von dir gemessen (" .. fluegeText(p.n) .. ")"
  elseif p.quelle == "forever" then
    zeile2 = "Gemessen von Forever-Spielern"
  elseif p.sek then
    zeile2 = "Geschätzt aus Weglänge und Fluggeschwindigkeit"
  else
    zeile2 = "Zeit noch unbekannt - wird jetzt gemessen"
  end
  return zeile1, zeile2, anteil
end

local timer
local BALKEN_BREITE = 258
local function baueTimer()
  if timer then return timer end
  timer = CreateFrame("Frame", "WegweiserFlugTimer", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  timer:SetSize(BALKEN_BREITE + 2, 36)
  timer:SetFrameStrata("MEDIUM")
  timer:SetClampedToScreen(true)
  timer:SetMovable(true)
  timer:EnableMouse(true)
  timer:RegisterForDrag("LeftButton")
  timer:SetScript("OnDragStart", timer.StartMoving)
  timer:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    if WW.db then WW.db.flugTimer.pos = { p, rp, x, y } end
  end)
  local pos = WW.db and WW.db.flugTimer and WW.db.flugTimer.pos
  if type(pos) == "table" and pos[1] then
    timer:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
  else
    timer:SetPoint("TOP", UIParent, "TOP", 0, -120)
  end
  if timer.SetBackdrop then
    timer:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    timer:SetBackdropColor(0.04, 0.06, 0.12, 0.85)
    timer:SetBackdropBorderColor(ZEIT_FARBE[1], ZEIT_FARBE[2], ZEIT_FARBE[3], 0.6)
  end
  timer.balken = timer:CreateTexture(nil, "ARTWORK")
  timer.balken:SetPoint("BOTTOMLEFT", timer, "BOTTOMLEFT", 1, 1)
  timer.balken:SetHeight(3)
  timer.balken:SetColorTexture(ZEIT_FARBE[1], ZEIT_FARBE[2], ZEIT_FARBE[3], 0.9)
  timer.text = timer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  timer.text:SetPoint("TOP", timer, "TOP", 0, -4)
  timer.unter = timer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  timer.unter:SetPoint("TOP", timer.text, "BOTTOM", 0, -1)
  timer.unter:SetTextColor(0.62, 0.64, 0.7)
  timer:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Flug-Timer", 1, 1, 1)
    GameTooltip:AddLine("Ziehen: verschieben. Ausschalten: /ww, Reiter Flüge.", 0.8, 0.8, 0.8)
    GameTooltip:Show()
  end)
  timer:SetScript("OnLeave", pinVerlassen)
  timer:Hide()
  return timer
end

function F.zeigeTimer(t)
  local e = einst()
  local z1, z2, anteil = F.timerText(t)
  if not (z1 and e and e.timer ~= false) then
    if timer then timer:Hide() end
    return
  end
  baueTimer()
  timer.text:SetText(z1)
  timer.unter:SetText(z2)
  if anteil then
    timer.balken:SetWidth(max(1, BALKEN_BREITE * anteil))
    timer.balken:Show()
  else
    timer.balken:Hide()
  end
  timer:Show()
end

-- Abflug und Landung über UnitOnTaxi
function F.pruefe(t)
  local p = F.unterwegs
  if not p then
    treiber:Hide()
    return
  end
  t = t or GetTime()
  local imFlug = rufe(rawget(_G, "UnitOnTaxi"), "player") and true or false
  if not p.start then
    if imFlug then
      p.start = t
    elseif t - p.at > 15 then
      F.unterwegs = nil   -- der Flug hat nie begonnen (kein Gold, Fenster zu)
    end
  elseif not imFlug then
    F.unterwegs = nil
    F.speichere(p.von, p.nach, t - p.start)
    if panel and panel:IsShown() and panel.OnZeigen then pcall(panel.OnZeigen, panel) end
  end
  F.zeigeTimer(t)
  if not F.unterwegs then treiber:Hide() end
end

local takt = 0
treiber:SetScript("OnUpdate", function(_, vergangen)
  takt = takt + (vergangen or 0)
  if takt < 0.25 then return end
  takt = 0
  local ok, err = pcall(F.pruefe)
  if not ok and geterrorhandler then geterrorhandler()(err) end
end)

---------------------------------------------------------------------------
-- Haken in die Flugkarte (einmal, sobald es die Funktionen gibt)
---------------------------------------------------------------------------
local hakenTaxi, hakenKarte, hakenNehmen
function F.hakeEin()
  if not hooksecurefunc then return end
  if not hakenNehmen and type(rawget(_G, "TakeTaxiNode")) == "function" then
    hakenNehmen = pcall(hooksecurefunc, "TakeTaxiNode", function(platz) pcall(F.nimm, platz) end)
  end
  if not hakenTaxi and type(rawget(_G, "TaxiNodeOnButtonEnter")) == "function" then
    hakenTaxi = pcall(hooksecurefunc, "TaxiNodeOnButtonEnter", function(knopf)
      pcall(function() tooltipErgaenzen(knopf and knopf.GetID and knopf:GetID()) end)
    end)
  end
  local mixin = rawget(_G, "FlightMap_FlightPointPinMixin")
  if not hakenKarte and type(mixin) == "table" and type(mixin.OnMouseEnter) == "function" then
    hakenKarte = pcall(hooksecurefunc, mixin, "OnMouseEnter", function(pin)
      pcall(function() tooltipErgaenzen(pin and pin.taxiNodeData and pin.taxiNodeData.slotIndex) end)
    end)
  end
end

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------
WW:BeimStart(function()
  if LibStub then
    HBD = LibStub("HereBeDragons-2.0", true)
    Pins = LibStub("HereBeDragons-Pins-2.0", true)
  end
  gestartet = true
  F.hakeEin()
  pcall(F.scanKarten)
  F.baueNadeln()
end)

WW:Event("ADDON_LOADED", function(name)
  if name == "Blizzard_FlightMap" or name == "Blizzard_TaxiFrame" then F.hakeEin() end
end)

WW:Event("TAXIMAP_OPENED", function()
  if not gestartet then return end
  F.hakeEin()
  neuGelernt(F.liesFlugkarte())
end)

WW:Event("ZONE_CHANGED_NEW_AREA", function()
  if not gestartet then return end
  local neu = F.scanKarten()
  if neu > 0 then neuGelernt(neu) end
end)

WW:Event("PLAYER_CONTROL_LOST", function() if F.unterwegs then F.pruefe() end end)
WW:Event("PLAYER_CONTROL_GAINED", function() if F.unterwegs then F.pruefe() end end)

---------------------------------------------------------------------------
-- Reiter "Flüge"
---------------------------------------------------------------------------
local function eintraege()
  local aus = {}
  local d = daten()
  local sd, bk = seite(), bekannt()

  -- gemessene Flugzeiten
  local zeiten = {}
  for key, e in pairs(zeitenDB() or {}) do
    local a, b = tostring(key):match("^(%d+)>(%d+)$")
    if a and type(e) == "table" and (tonumber(e.n) or 0) > 0 then
      zeiten[#zeiten + 1] = { a = tonumber(a), b = tonumber(b), e = e }
    end
  end
  for _, z in ipairs(zeiten) do z.text = F.name(z.a) .. " > " .. F.name(z.b) end
  table.sort(zeiten, function(x, y) return x.text < y.text end)
  aus[#aus + 1] = { kopf = true, text = "Deine gemessenen Flugzeiten (" .. #zeiten .. ")" }
  if #zeiten == 0 then
    aus[#aus + 1] = { info = "Noch keine. Wegweiser misst jeden Flug, den du nimmst." }
  end
  for _, z in ipairs(zeiten) do
    local e = z.e
    local spanne = (e.min and e.max and e.min ~= e.max) and (", " .. F.uhr(e.min) .. " bis " .. F.uhr(e.max)) or ""
    aus[#aus + 1] = { text = z.text .. "  " .. WW.f("gelb", F.uhr(e.summe / e.n))
      .. WW.f("grau", "  (" .. fluegeText(e.n) .. spanne .. ")") }
  end

  -- bekannte Flugpunkte
  local liste = {}
  for id in pairs(bk) do
    local k = knoten(id)
    if k and not baueKeinFlugmeister()[id] then
      liste[#liste + 1] = { id = id, name = F.name(id), zone = zoneName(tonumber(k[4])) or "" }
    end
  end
  table.sort(liste, function(x, y)
    if x.zone ~= y.zone then return x.zone < y.zone end
    return x.name < y.name
  end)
  local alle = 0
  if d then
    for id, k in pairs(d.nodes) do
      if type(k) == "table" and flugmeister(id, sd) then alle = alle + 1 end
    end
  end
  aus[#aus + 1] = { kopf = true, text = "Bekannte Flugpunkte (" .. #liste .. " von " .. alle .. ")" }
  if #liste == 0 then
    aus[#aus + 1] = { info = "Noch keine. Sprich einen Flugmeister an: dann merkt sich Wegweiser alle," }
    aus[#aus + 1] = { info = "die dieser Charakter schon kennt." }
  end
  for _, n in ipairs(liste) do
    aus[#aus + 1] = { text = n.name .. "  " .. WW.f("grau", n.zone) }
  end
  if not d then aus[#aus + 1] = { info = "Keine Flugdaten gefunden (Daten\\FDB_Fluege.lua)." } end
  -- Schiffe und Zeppeline (Module\Schiffe.lua)
  if WW.Schiffe and WW.Schiffe.eintraege then
    local ok, schiffe = pcall(WW.Schiffe.eintraege)
    if ok and type(schiffe) == "table" then
      for _, x in ipairs(schiffe) do aus[#aus + 1] = x end
    end
  end
  return aus
end

WW:Reiter("fluege", "Flüge", 5, function(p)
  local e = einst()
  if not e then
    local t = UI.Text(p)
    t:SetPoint("TOPLEFT", 4, -4)
    t:SetText("Gespeicherte Daten fehlen. Bitte /reload.")
    return
  end
  panel = p

  local titel = UI.Text(p, "gross")
  titel:SetPoint("TOPLEFT", 4, -4)
  titel:SetText("Flüge")

  local haken = {}
  local vorher = titel
  local function neuerHaken(text, get, set)
    local h = UI.Haken(p, text, get, function(an)
      set(an)
      F.baueNadeln()
    end)
    h:SetPoint("TOPLEFT", vorher, "BOTTOMLEFT", 0, (vorher == titel) and -6 or 2)
    h.get = get
    haken[#haken + 1] = h
    vorher = h
  end
  neuerHaken("Flugpunkte auf der Weltkarte", function() return e.karte end, function(an) e.karte = an end)
  neuerHaken("Auch unentdeckte Flugpunkte (grau)", function() return e.unentdeckt end, function(an) e.unentdeckt = an end)
  neuerHaken("Flugzeit auf der Flugkarte", function() return e.zeiten ~= false end, function(an) e.zeiten = an end)
  neuerHaken("Flug-Timer beim Fliegen", function() return e.timer ~= false end, function(an)
    e.timer = an
    F.zeigeTimer()
  end)
  neuerHaken("Fahrplan-Anzeige am Steg (Schiffe, Zeppeline)",
    function() return WW.Schiffe and WW.Schiffe.an() end,
    function(an) if WW.Schiffe then WW.Schiffe.setzeAn(an) end end)

  local zuruecksetzen = UI.Knopf(p, "Timer-Position zurücksetzen", 200, function()
    if WW.db then WW.db.flugTimer.pos = nil end
    if timer then
      timer:ClearAllPoints()
      timer:SetPoint("TOP", UIParent, "TOP", 0, -120)
    end
  end)
  zuruecksetzen:SetPoint("TOPLEFT", vorher, "BOTTOMLEFT", 4, -8)

  local info = UI.Text(p, "klein", 0.8, 0.8, 0.8)
  info:SetPoint("TOPLEFT", zuruecksetzen, "BOTTOMLEFT", -4, -12)
  info:SetWidth(320)
  info:SetSpacing(2)
  info:SetText(
    "Die Weltkarte zeigt alle Flugpunkte deiner Fraktion und die neutralen, auch wo die Karte noch nicht "
    .. "aufgedeckt ist. Grün: kennst du. Grau: noch nicht entdeckt.\n"
    .. "Welche du kennst, merkt sich Wegweiser, sobald du einen Flugmeister ansprichst.\n"
    .. "Flugzeit: erst deine eigene Messung, dann die von Forever-Spielern, sonst geschätzt "
    .. "(Weglänge geteilt durch Fluggeschwindigkeit).\n"
    .. "Schiffe und Zeppeline: Am Steg zeigt ein Fenster die nächste Abfahrt. Einmal eichen: "
    .. "'Legt ab' oder 'Kommt an' klicken, oder einfach mitfahren.\n"
    .. "Daten von ForeverDB.net.")

  local LINKS = 344
  local t3 = UI.Text(p, "gross")
  t3:SetPoint("TOPLEFT", LINKS, -4)
  t3:SetText("Flüge, Schiffe und Zeppeline")

  local liste = UI.Liste(p, WW.INHALT_BREITE - LINKS, p:GetHeight() - 30, 18,
    function(z)
      z.text = UI.Text(z)
      if z.text.SetWordWrap then z.text:SetWordWrap(false) end
      z.text:SetPoint("LEFT", z, "LEFT", 4, 0)
      z.text:SetPoint("RIGHT", z, "RIGHT", -4, 0)
      -- Knopf am Zeilenende (z. B. "Zurücksetzen" beim Fahrplan): Eintrag mit knopf = Text, aktion = Funktion
      z.knopf = UI.Knopf(z, "", 100, function(self)
        local ein = self:GetParent().eintrag
        if ein and ein.aktion then
          pcall(ein.aktion)
          if panel and panel.OnZeigen then pcall(panel.OnZeigen, panel) end
        end
      end)
      z.knopf:SetHeight(16)
      z.knopf:SetPoint("RIGHT", z, "RIGHT", -2, 0)
      z.knopf:Hide()
    end,
    function(z, ein)
      z.text:ClearAllPoints()
      z.text:SetPoint("LEFT", z, "LEFT", ein.kopf and 2 or 16, 0)
      z.text:SetPoint("RIGHT", z, "RIGHT", ein.knopf and -106 or -4, 0)
      if ein.knopf then
        z.knopf:SetText(ein.knopf)
        z.knopf:Show()
      else
        z.knopf:Hide()
      end
      if ein.kopf then
        z.text:SetText(WW.f("titel", ein.text or ""))
      elseif ein.info then
        z.text:SetText(WW.f("grau", ein.info))
      else
        z.text:SetText(ein.text or "")
      end
    end)
  liste:SetPoint("TOPLEFT", LINKS, -26)

  function p:OnZeigen()
    for _, h in ipairs(haken) do h:SetChecked(h.get() and true or false) end
    liste:Setze(eintraege())
  end

  -- Fahrplan-Zeiten zählen herunter: jede Sekunde neu füllen, solange der Reiter offen ist
  -- (OnUpdate läuft nur bei sichtbarem Reiter; die Bildlaufposition bleibt)
  local seitLetztem = 0
  p:SetScript("OnUpdate", function(_, vergangen)
    seitLetztem = seitLetztem + (vergangen or 0)
    if seitLetztem < 1 then return end
    seitLetztem = 0
    local ok, neu = pcall(eintraege)
    if ok and type(neu) == "table" then
      liste.eintraege = neu
      liste:Aktualisiere()
    end
  end)
end, "einstellungen")
