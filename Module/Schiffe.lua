-- Wegweiser: Fahrplan für Schiffe und Zeppeline. Wann legt das nächste ab?
-- Daten: WW.quelle.fdb.routeLinks (ForeverDB.net, Daten\FDB_Schiffe.lua):
--   { id, kind = "boat"|"zeppelin"|..., name, side = "A"|"H"|"", a = {c, x, y}, b = {c, x, y}, wait, ride }
--   a/b: Welt-Koordinaten der beiden Stege (wie UnitPosition: x nach Norden, y nach Westen; c = Kontinent).
--   ride = Fahrzeit (s). wait = ride + 60 bei allen Einträgen; ForeverDB rechnet "wait + ride" als Reisezeit,
--   wait ist also die mittlere Wartezeit = halbe Umlaufzeit. Daraus das Modell hier:
--     Umlauf P = 2 * wait. Abfahrt in A zur Zeit T, Ankunft in B bei T + ride, Abfahrt in B bei T + P/2,
--     Ankunft in A bei T + P/2 + ride, nächste Abfahrt in A bei T + P. Liegezeit am Steg = P/2 - ride.
-- Die Lage (wann genau es abfährt) kennt kein Addon: sie kommt aus einer Eichung.
--   - von Hand: am Steg "Legt ab" oder "Kommt an" klicken
--   - automatisch: du warst an Steg A und bist kurz danach (Fahrzeit) an Steg B derselben Linie -> Ankunft
-- Gespeichert für alle Charaktere (Serverzeit): WW.db.fahrplan[id] = { anker = Abfahrt in A, P, n, zeit }
local ADDON, WW = ...
local UI = WW.UI

local floor, max, min, sqrt = math.floor, math.max, math.min, math.sqrt

local S = {}
WW.Schiffe = S

local NAH_ANZEIGE = 150   -- Meter: Fahrplan zeigen
local NAH_EICHEN = 80     -- Meter: Knöpfe zum Eichen
local NAH_STEG = 60       -- Meter: "war am Steg" (für die automatische Eichung)
local NAH_ANKUNFT = 40    -- Meter: "ist angekommen"
local UNSCHARF = 30 * 60  -- Eichung älter: Zeit mit "ca." (2 * wait ist nur eine Faustregel)
local ALT = 2 * 3600      -- Eichung älter: "ungenau" (ein paar Sekunden Fehler je Umlauf summieren sich)
local ABWEICHUNG_LINIE = 150   -- Meter: so weit darf der Weg neben der Linie zwischen den Stegen liegen
local MAX_ZEILEN = 4

WW.standardDB.fahrplan = {}
WW.standardDB.fahrplanPos = {}
WW.standardCharDB.schiffe = { anzeige = true }

-- Deutsche Namen: Titel, Steg A, Steg B, Art
local NAMEN = {
  ["boat-menethil-theramore"] = { "Schiff zwischen Menethil und Theramore", "Menethil", "Theramore", "Schiff" },
  ["boat-menethil-auberdine"] = { "Schiff zwischen Menethil und Auberdine", "Menethil", "Auberdine", "Schiff" },
  ["boat-auberdine-ruttheran"] = { "Schiff zwischen Auberdine und Rut'theran", "Auberdine", "Rut'theran", "Schiff" },
  ["boat-bootybay-ratchet"] = { "Schiff zwischen Beutebucht und Ratschet", "Beutebucht", "Ratschet", "Schiff" },
  ["zeppelin-orgrimmar-undercity"] = { "Zeppelin zwischen Orgrimmar und Unterstadt", "Orgrimmar", "Unterstadt", "Zeppelin" },
  ["zeppelin-orgrimmar-gromgol"] = { "Zeppelin zwischen Orgrimmar und Grom'gol", "Orgrimmar", "Grom'gol", "Zeppelin" },
  ["zeppelin-gromgol-undercity"] = { "Zeppelin zwischen Grom'gol und Unterstadt", "Grom'gol", "Unterstadt", "Zeppelin" },
  ["boat-feathermoon"] = { "Fähre zur Mondfederfeste", "Mondfederfeste", "Küste von Feralas", "Fähre" },
  ["boat-stormwind-auberdine"] = { "Schiff zwischen Sturmwind und Auberdine", "Sturmwind", "Auberdine", "Schiff" },
  ["boat-riverglades-tanaris"] = { "Schiff zwischen Tanaris und den Riverglades", "Tanaris", "Riverglades", "Schiff" },
  ["zeppelin-zephras-silverpine"] = { "Luftschiff zwischen Silberwald und Zephras", "Silberwald", "Zephras", "Luftschiff" },
  ["zeppelin-zephras-thunderbluff"] = { "Luftschiff zwischen Donnerfels und Zephras", "Donnerfels", "Zephras", "Luftschiff" },
  ["boat-auberdine-southshore"] = { "Schiff zwischen Süderstade und Auberdine", "Süderstade", "Auberdine", "Schiff" },
}
local ART = { boat = "Schiff", zeppelin = "Zeppelin" }

local gestartet = false

local function rufe(fn, ...)
  if not fn then return nil end
  local r = { pcall(fn, ...) }
  if not r[1] then return nil end
  return unpack(r, 2)
end

local function einst() return WW.charDb and WW.charDb.schiffe end
function S.an()
  local e = einst()
  return e ~= nil and e.anzeige ~= false
end
function S.setzeAn(an)
  local e = einst()
  if e then e.anzeige = an and true or false end
  if S.takt then S.takt() end
end

local function fahrplanDB()
  if not WW.db then return nil end
  if type(WW.db.fahrplan) ~= "table" then WW.db.fahrplan = {} end
  return WW.db.fahrplan
end

function S.uhr(s)
  s = floor((tonumber(s) or 0) + 0.5)
  if s < 0 then s = 0 end
  return string.format("%d:%02d", floor(s / 60), s % 60)
end

local function andere(seite) return seite == "a" and "b" or "a" end

---------------------------------------------------------------------------
-- Linien
---------------------------------------------------------------------------
-- Schiffe und Zeppeline, die diese Fraktion nutzen kann (Aufzüge, Bahn, Portal: kein Fahrplan)
function S.linien()
  local fdb = WW.quelle and WW.quelle.fdb
  local alle = fdb and fdb.routeLinks
  local aus = {}
  if type(alle) ~= "table" then return aus end
  local f = UnitFactionGroup and rufe(UnitFactionGroup, "player")
  local seite = (f == "Alliance" and "A") or (f == "Horde" and "H") or nil
  for _, L in ipairs(alle) do
    if type(L) == "table" and (L.kind == "boat" or L.kind == "zeppelin") and type(L.a) == "table"
      and type(L.b) == "table" and (tonumber(L.wait) or 0) > 0 and tonumber(L.ride) then
      if L.side == nil or L.side == "" or seite == nil or L.side == seite then aus[#aus + 1] = L end
    end
  end
  return aus
end

function S.titel(L)
  local n = NAMEN[L.id]
  return n and n[1] or (L.name or L.id or "?")
end
function S.steg(L, seite)
  local n = NAMEN[L.id]
  if n then return seite == "a" and n[2] or n[3] end
  local a, b = tostring(L.name or ""):match("between (.-) and (.+)$")
  return (seite == "a" and a or b) or (seite == "a" and "A" or "B")
end
function S.art(L)
  local n = NAMEN[L.id]
  return n and n[4] or ART[L.kind] or "Schiff"
end

-- Umlaufzeit: gemessen (nachgeschärft), aber nie mehr als 10 % neben 2 * wait (Faustregel der Daten)
local function grundPeriode(L) return 2 * (tonumber(L.wait) or 0) end
local function begrenzt(L, p)
  local p0 = grundPeriode(L)
  return max(0.9 * p0, min(1.1 * p0, p))
end
local function periode(L)
  local f = fahrplanDB()
  local e = f and f[L.id]
  local p = type(e) == "table" and tonumber(e.P)
  return p and begrenzt(L, p) or grundPeriode(L)
end
S.periode = periode
local function liegezeit(L) return max(0, periode(L) / 2 - (tonumber(L.ride) or 0)) end

-- Nächste Abfahrt am Steg seite ab jetzt (Serverzeit) und der Eintrag, oder nil (nicht geeicht)
function S.naechsteAbfahrt(L, seite, jetzt)
  local f = fahrplanDB()
  local e = f and f[L.id]
  if type(e) ~= "table" or not tonumber(e.anker) then return nil end
  local P = periode(L)
  if P <= 0 then return nil end
  local basis = e.anker + (seite == "b" and P / 2 or 0)
  local k = math.ceil((jetzt - basis) / P)
  local t = basis + k * P
  if t < jetzt then t = t + P end
  return t, e
end

-- Eichung: art "ab" = legt jetzt am Steg seite ab, "an" = kommt jetzt am Steg seite an.
function S.eiche(L, seite, art, jetzt)
  local f = fahrplanDB()
  if not (f and L and L.id) then return nil end
  jetzt = jetzt or GetServerTime()
  local P = periode(L)
  local ride = tonumber(L.ride) or 0
  local abSeite, abZeit
  if art == "an" then
    abSeite, abZeit = andere(seite), jetzt - ride
  else
    abSeite, abZeit = seite, jetzt
  end
  local e = type(f[L.id]) == "table" and f[L.id] or { n = 0 }
  local vorlaeufig = abZeit - (abSeite == "b" and P / 2 or 0)
  if tonumber(e.anker) then
    local diff = vorlaeufig - e.anker
    local k = floor(diff / P + 0.5)
    local rest = math.abs(diff - k * P)
    if rest > 0.2 * P then
      -- weit neben der Vorhersage (Serverneustart, anderer Layer?): Phase neu, Umlauf nicht anfassen
    elseif k >= 1 and rest < 0.05 * P then
      -- Umlauf nachschärfen, aber nur wenn genau eine Umlaufzahl in die Grenzen passt
      local p0, passend = grundPeriode(L), 0
      for kk = max(1, k - 3), k + 3 do
        local pk = diff / kk
        if pk >= 0.9 * p0 and pk <= 1.1 * p0 then passend = passend + 1 end
      end
      if passend == 1 then
        local gewicht = min(1, k / 20)
        e.P = begrenzt(L, P + (diff / k - P) * gewicht)
      end
    end
  end
  -- Anker mit dem (neuen) Umlauf
  P = tonumber(e.P) and begrenzt(L, e.P) or P
  e.anker = abZeit - (abSeite == "b" and P / 2 or 0)
  e.zeit, e.n = jetzt, (tonumber(e.n) or 0) + 1
  f[L.id] = e
  return e
end

function S.zuruecksetzen(L)
  local f = fahrplanDB()
  if f and L and L.id then f[L.id] = nil end
end

---------------------------------------------------------------------------
-- Wo bist du? (Welt-Koordinaten wie in den Daten)
---------------------------------------------------------------------------
local function spielerPos()
  local x, y, _, inst = rufe(rawget(_G, "UnitPosition"), "player")
  if tonumber(x) and tonumber(y) and tonumber(inst) then return tonumber(inst), tonumber(x), tonumber(y) end
  -- Ersatz: Kartenposition über die Kartenrahmen der Daten
  if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
  local m = rufe(C_Map.GetBestMapForUnit, "player")
  local karten = WW.quelle and WW.quelle.fdb and WW.quelle.fdb.routeMaps
  local t = m and type(karten) == "table" and karten[m]
  if type(t) ~= "table" then return nil end
  local pos = rufe(C_Map.GetPlayerMapPosition, m, "player")
  if type(pos) ~= "table" then return nil end
  local px, py
  if pos.GetXY then px, py = pos:GetXY() else px, py = pos.x, pos.y end
  px, py = tonumber(px), tonumber(py)
  if not (px and py) then return nil end
  return t.c, t.t - py * t.h, t.l - px * t.w
end

---------------------------------------------------------------------------
-- Anzeige am Steg
---------------------------------------------------------------------------
local fenster
local BREITE, ZEILE = 470, 22

local function baueFenster()
  if fenster then return fenster end
  fenster = CreateFrame("Frame", "WegweiserFahrplan", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  fenster:SetSize(BREITE, 40)
  fenster:SetFrameStrata("MEDIUM")
  fenster:SetClampedToScreen(true)
  fenster:SetMovable(true)
  fenster:EnableMouse(true)
  fenster:RegisterForDrag("LeftButton")
  fenster:SetScript("OnDragStart", fenster.StartMoving)
  fenster:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    if WW.db then WW.db.fahrplanPos.pos = { p, rp, x, y } end
  end)
  local pos = WW.db and WW.db.fahrplanPos and WW.db.fahrplanPos.pos
  if type(pos) == "table" and pos[1] then
    fenster:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
  else
    fenster:SetPoint("TOP", UIParent, "TOP", 0, -170)
  end
  if fenster.SetBackdrop then
    fenster:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    fenster:SetBackdropColor(0.04, 0.06, 0.12, 0.85)
    fenster:SetBackdropBorderColor(0.4, 0.6, 0.9, 0.6)
  end
  fenster.titel = UI.Text(fenster, "klein", 0.62, 0.64, 0.7)
  fenster.titel:SetPoint("TOPLEFT", 8, -5)
  fenster.titel:SetText("Fahrplan (geschätzt, Daten von ForeverDB.net) - ziehen zum Verschieben")
  fenster.zeilen = {}
  for i = 1, MAX_ZEILEN do
    local z = CreateFrame("Frame", nil, fenster)
    z:SetSize(BREITE - 12, ZEILE)
    z:SetPoint("TOPLEFT", 6, -18 - (i - 1) * ZEILE)
    z.text = UI.Text(z)
    z.text:SetPoint("LEFT", z, "LEFT", 2, 0)
    z.text:SetPoint("RIGHT", z, "RIGHT", -150, 0)
    if z.text.SetWordWrap then z.text:SetWordWrap(false) end
    z.an = UI.Knopf(z, "Kommt an", 72, function(self)
      local zeile = self:GetParent()
      if zeile.link then
        S.eiche(zeile.link, zeile.seite, "an")
        WW:Print("Fahrplan geeicht: " .. S.titel(zeile.link) .. " (Ankunft " .. S.steg(zeile.link, zeile.seite) .. ")")
        S.takt()
      end
    end)
    z.an:SetPoint("RIGHT", z, "RIGHT", 0, 0)
    z.ab = UI.Knopf(z, "Legt ab", 72, function(self)
      local zeile = self:GetParent()
      if zeile.link then
        S.eiche(zeile.link, zeile.seite, "ab")
        WW:Print("Fahrplan geeicht: " .. S.titel(zeile.link) .. " (Abfahrt " .. S.steg(zeile.link, zeile.seite) .. ")")
        S.takt()
      end
    end)
    z.ab:SetPoint("RIGHT", z.an, "LEFT", -4, 0)
    z:Hide()
    fenster.zeilen[i] = z
  end
  fenster.hinweis = UI.Text(fenster, "klein", 0.8, 0.8, 0.8)
  fenster.hinweis:SetWidth(BREITE - 16)
  fenster:Hide()
  return fenster
end

function S.alterText(sek)
  sek = tonumber(sek) or 0
  if sek < 3600 then return "vor " .. max(1, floor(sek / 60)) .. " Min." end
  if sek < 2 * 86400 then return "vor " .. floor(sek / 3600) .. " Std." end
  return "vor " .. floor(sek / 86400) .. " Tagen"
end

-- Text einer Zeile: was am Steg seite der Linie L als Nächstes passiert
function S.zeilenText(L, seite, jetzt)
  local kopf = S.art(L) .. " nach " .. S.steg(L, andere(seite)) .. ": "
  local t, e = S.naechsteAbfahrt(L, seite, jetzt)
  if not t then return kopf .. "noch nicht geeicht", false end
  local rest = t - jetzt
  local alter = jetzt - (tonumber(e.zeit) or 0)
  local ca = alter > UNSCHARF and "ca. " or ""
  local text
  if rest <= liegezeit(L) then
    text = kopf .. "liegt am Steg - fährt in " .. ca .. S.uhr(rest)
  else
    text = kopf .. "Abfahrt in " .. ca .. S.uhr(rest)
  end
  if alter > ALT then
    text = text .. WW.f("orange", " - ungenau (geeicht " .. S.alterText(alter) .. ")")
  end
  return text, true
end

-- nah = { { L, seite, dist } } oder nil: Fenster füllen oder verstecken
function S.zeige(nah, jetzt)
  if not (nah and #nah > 0 and S.an()) then
    if fenster then fenster:Hide() end
    return
  end
  baueFenster()
  table.sort(nah, function(x, y) return x.dist < y.dist end)
  local n, ungeeicht, gesehen = 0, false, {}
  for _, e in ipairs(nah) do
    if n < MAX_ZEILEN and not gesehen[e.L.id] then
      gesehen[e.L.id] = true
      n = n + 1
      local z = fenster.zeilen[n]
      z.link, z.seite = e.L, e.seite
      local text, geeicht = S.zeilenText(e.L, e.seite, jetzt)
      if not geeicht then ungeeicht = true end
      z.text:SetText(text)
      local knoepfe = e.dist <= NAH_EICHEN
      z.ab:SetShown(knoepfe)
      z.an:SetShown(knoepfe)
      z:Show()
    end
  end
  for i = n + 1, MAX_ZEILEN do
    local z = fenster.zeilen[i]
    z.link, z.seite = nil, nil
    z:Hide()
  end
  local hoehe = 22 + n * ZEILE
  fenster.hinweis:ClearAllPoints()
  fenster.hinweis:SetPoint("TOPLEFT", fenster, "TOPLEFT", 8, -hoehe)
  if ungeeicht then
    fenster.hinweis:SetText("Noch nicht geeicht: warte auf das nächste, dann 'Legt ab' oder 'Kommt an' klicken. "
      .. "Fährst du mit, eicht Wegweiser selbst.")
    fenster.hinweis:Show()
    hoehe = hoehe + 28
  else
    fenster.hinweis:Hide()
  end
  fenster:SetHeight(hoehe + 4)
  fenster:Show()
end

---------------------------------------------------------------------------
-- Takt: jede Sekunde Position prüfen, Ankunft erkennen, Anzeige auffrischen
---------------------------------------------------------------------------
local zuletzt = {}        -- [id .. seite] = Serverzeit, zuletzt am Steg (gelöscht, sobald es keine Fahrt sein kann)
local zuletztLinie = {}   -- [id .. seite] = Linie (für die Prüfung unterwegs)

-- Abstand des Punkts (x, y) zur Strecke von a nach b
local function abstandZurStrecke(a, b, x, y)
  local dx, dy = b.x - a.x, b.y - a.y
  local l2 = dx * dx + dy * dy
  local u = l2 > 0 and ((x - a.x) * dx + (y - a.y) * dy) / l2 or 0
  u = max(0, min(1, u))
  local px, py = a.x + u * dx, a.y + u * dy
  return sqrt((x - px) ^ 2 + (y - py) ^ 2)
end

-- Unterwegs (nicht mehr am Steg): Schwimmen, Reittier oder ein Umweg = keine Schiffsfahrt
local function pruefeUnterwegs(c, x, y, jetzt)
  local schwimmt = rufe(rawget(_G, "IsSwimming")) and true or false
  local reitet = rufe(rawget(_G, "IsMounted")) and true or false
  for schluessel, zeit in pairs(zuletzt) do
    if zeit < jetzt then
      local L = zuletztLinie[schluessel]
      local weg = schwimmt or reitet or not L
      if not weg and tonumber(L.a.c) == tonumber(L.b.c) and tonumber(L.a.c) == c then
        local laenge = sqrt((L.b.x - L.a.x) ^ 2 + (L.b.y - L.a.y) ^ 2)
        if abstandZurStrecke(L.a, L.b, x, y) > max(ABWEICHUNG_LINIE, 0.15 * laenge) then weg = true end
      end
      if weg then
        zuletzt[schluessel] = nil
        zuletztLinie[schluessel] = nil
      end
    end
  end
end

-- Ruhestein, Flug, Tod: was danach kommt, ist keine Schiffsfahrt
function S.vergissFahrt()
  wipe(zuletzt)
  wipe(zuletztLinie)
end

local function pruefeAnkunft(L, seite, jetzt)
  local schluessel = L.id .. andere(seite)
  local ab = zuletzt[schluessel]
  if not ab then return end
  local ride = tonumber(L.ride) or 0
  local dauer = jetzt - ab
  -- Gleicher Kontinent: man sieht die ganze Fahrt, also eng. Anderer Kontinent: Ladebildschirm, also weiter.
  local gleich = tonumber(L.a.c) == tonumber(L.b.c)
  local von, bis = ride * 0.85, ride + 30
  if not gleich then von, bis = ride * 0.5, ride + 120 end
  if dauer >= von and dauer <= bis then
    zuletzt[schluessel] = nil
    zuletztLinie[schluessel] = nil
    S.eiche(L, seite, "an", jetzt)
    WW:Print("Fahrplan geeicht: " .. S.titel(L) .. " (Ankunft " .. S.steg(L, seite) .. ")")
  end
end

function S.takt()
  if not gestartet then return end
  local jetzt = GetServerTime and GetServerTime() or time()
  local c, x, y = spielerPos()
  if rufe(rawget(_G, "UnitOnTaxi"), "player") then
    S.vergissFahrt()
    S.zeige(nil)
    return
  end
  if not c then
    S.zeige(nil)
    return
  end
  pruefeUnterwegs(c, x, y, jetzt)
  local nah = {}
  for _, L in ipairs(S.linien()) do
    for _, seite in ipairs({ "a", "b" }) do
      local d = L[seite]
      if tonumber(d.c) == c and tonumber(d.x) and tonumber(d.y) then
        local dist = sqrt((d.x - x) ^ 2 + (d.y - y) ^ 2)
        if dist <= NAH_ANKUNFT then pruefeAnkunft(L, seite, jetzt) end
        if dist <= NAH_STEG then
          zuletzt[L.id .. seite] = jetzt
          zuletztLinie[L.id .. seite] = L
        end
        if dist <= NAH_ANZEIGE then nah[#nah + 1] = { L = L, seite = seite, dist = dist } end
      end
    end
  end
  S.zeige(nah, jetzt)
end

local uhrwerk = CreateFrame("Frame")
local takt = 0
uhrwerk:SetScript("OnUpdate", function(_, vergangen)
  takt = takt + (vergangen or 0)
  if takt < 1 then return end
  takt = 0
  local ok, err = pcall(S.takt)
  if not ok and geterrorhandler then geterrorhandler()(err) end
end)

WW:BeimStart(function() gestartet = true end)

-- Ruhestein (8690) oder ein anderer Teleport direkt nach dem Steg ist keine Fahrt
local TELEPORT = { [8690] = true, [556] = true, [3561] = true, [3562] = true, [3563] = true, [3565] = true,
  [3566] = true, [3567] = true, [18960] = true }
WW:Event("UNIT_SPELLCAST_SUCCEEDED", function(unit, a2, a3, a4, a5)
  if unit ~= "player" then return end
  local id = tonumber(a3) or tonumber(a5)
  if id and TELEPORT[id] then S.vergissFahrt() end
end)
WW:Event("PLAYER_DEAD", function() S.vergissFahrt() end)

---------------------------------------------------------------------------
-- Liste für den Reiter "Flüge"
---------------------------------------------------------------------------

function S.eintraege()
  local aus = {}
  local jetzt = GetServerTime and GetServerTime() or time()
  local linien = S.linien()
  table.sort(linien, function(x, y) return S.titel(x) < S.titel(y) end)
  aus[#aus + 1] = { kopf = true, text = "Schiffe und Zeppeline (Fahrplan, geschätzt)" }
  if #linien == 0 then
    aus[#aus + 1] = { info = "Keine Daten (Daten\\FDB_Schiffe.lua)." }
    return aus
  end
  for _, L in ipairs(linien) do
    aus[#aus + 1] = { text = S.titel(L) }
    local ta = S.naechsteAbfahrt(L, "a", jetzt)
    local tb, e = S.naechsteAbfahrt(L, "b", jetzt)
    if not ta then
      aus[#aus + 1] = { info = "    noch nicht geeicht" }
    else
      local alter = jetzt - (tonumber(e.zeit) or 0)
      local ca = alter > UNSCHARF and "ca. " or ""
      local text = "    ab " .. S.steg(L, "a") .. " in " .. ca .. S.uhr(ta - jetzt) .. ", ab " .. S.steg(L, "b")
        .. " in " .. ca .. S.uhr(tb - jetzt) .. "  " .. WW.f("grau", "(geeicht " .. S.alterText(alter) .. ")")
      if alter > ALT then text = text .. WW.f("orange", " ungenau - bitte neu eichen") end
      aus[#aus + 1] = { text = text }
      -- die Titelzeile bekommt den Knopf "Zurücksetzen"
      local titel = aus[#aus - 1]
      titel.knopf = "Zurücksetzen"
      titel.aktion = function()
        S.zuruecksetzen(L)
        WW:Print("Fahrplan zurückgesetzt: " .. S.titel(L))
      end
    end
  end
  return aus
end
