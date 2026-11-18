-- Szenen fuer Auktion.lua: Preisverlauf, Schnaeppchen, zu teuer, Uhrzeit-Tipps, Tooltip, Blizzard-Marken.
-- SZENE: Auktion - Vorbereiten (Uhr und Angebote nachgebaut)
function __GLEICH(ist, soll, was)
  if ist ~= soll then error((was or "?") .. ": erwartet " .. tostring(soll) .. ", war " .. tostring(ist), 2) end
end
function __ENTHAELT(text, teil, was)
  if type(text) ~= "string" or not text:find(teil, 1, true) then
    error((was or "?") .. ": '" .. tostring(teil) .. "' fehlt in '" .. tostring(text) .. "'", 2)
  end
end
__ECHTZEIT = __ECHTZEIT or time
__T = os.time{ year = 2026, month = 11, day = 17, hour = 6, min = 0 }
time = function(t) if t then return os.time(t) end return __T end
__G = 1000
GetTime = function() return __G end
local db = __WW.db
db.ah["Forever|Alliance"] = nil
db.ahVerlauf["Forever|Alliance"] = nil
db.ah.scanStunden = {}
db.ah.bereinigt = 0
db.ah.letzterScan = 0
__ANG = {}
C_AuctionHouse.GetNumReplicateItems = function() return #__ANG end
C_AuctionHouse.GetReplicateItemInfo = function(i)
  local a = __ANG[i + 1]
  return "x", 0, a[2], 1, true, 1, "", 0, 0, a[3], 0, false, nil, nil, nil, 0, a[1]
end
-- daten = { {id, min, median}, ... }: je Item drei Angebote (eins zum Mindestpreis, zwei zum Medianpreis)
function __SCAN(stunde, minute, daten)
  __T = os.time{ year = 2026, month = 11, day = 17, hour = stunde, min = minute or 0 }
  __WW.db.ah.letzterScan = 0
  __ANG = {}
  for _, d in ipairs(daten) do
    __ANG[#__ANG + 1] = { d[1], 1, d[2] }
    __ANG[#__ANG + 1] = { d[1], 1, d[3] }
    __ANG[#__ANG + 1] = { d[1], 1, d[3] }
  end
  if not __WW.AH.Offen() then __FEUER("AUCTION_HOUSE_SHOW") end
  local ok, warum = __WW.AH.Scannen()
  if not ok then error("Scan nicht gestartet: " .. tostring(warum)) end
  __FEUER("REPLICATE_ITEM_LIST_UPDATE")
  __UPDATE(80)
  __GLEICH(__WW.AH.Status.phase, "fertig", "Scan fertig (" .. tostring(__WW.AH.Status.meldung) .. ")")
end
__SCAN(6, 0, { { 3001, 1000, 1000 }, { 3002, 2000, 2000 }, { 3003, 1000, 1000 }, { 3004, 500, 500 }, { 3005, 10, 10 }, { 3007, 10000, 10000 } })
__SCAN(7, 0, { { 3001, 1000, 1000 }, { 3002, 2000, 2000 }, { 3003, 1000, 1000 }, { 3004, 500, 500 }, { 3005, 10, 10 }, { 3007, 10000, 10000 } })
__SCAN(12, 0, { { 3001, 1250, 1250 }, { 3002, 2000, 2000 }, { 3003, 1000, 1000 }, { 3004, 500, 500 }, { 3005, 10, 10 }, { 3007, 10000, 10000 } })
__SCAN(19, 0, { { 3001, 1500, 1500 }, { 3002, 2000, 2000 }, { 3003, 1000, 1000 }, { 3004, 500, 500 }, { 3005, 10, 10 }, { 3007, 10000, 10000 } })
__SCAN(21, 0, { { 3001, 1500, 1500 }, { 3002, 1000, 2000 }, { 3003, 1500, 1500 }, { 3004, 500, 500 }, { 3005, 10, 10 }, { 3006, 100, 1000 }, { 3007, 5000, 10000 } })

-- rohe Angebote: { {id, anzahl, kaufpreis}, ... }
function __SCANROH(stunde, minute, roh)
  __T = os.time{ year = 2026, month = 11, day = 17, hour = stunde, min = minute or 0 }
  __WW.db.ah.letzterScan = 0
  __ANG = roh
  if not __WW.AH.Offen() then __FEUER("AUCTION_HOUSE_SHOW") end
  local ok, warum = __WW.AH.Scannen()
  if not ok then error("Scan nicht gestartet: " .. tostring(warum)) end
  __FEUER("REPLICATE_ITEM_LIST_UPDATE")
  __UPDATE(120)
  __GLEICH(__WW.AH.Status.phase, "fertig", "Scan fertig (" .. tostring(__WW.AH.Status.meldung) .. ")")
end

-- SZENE: Auktion - Speicherformat und Normalpreis
local vl = __WW.db.ahVerlauf["Forever|Alliance"]
if not vl then error("kein Verlauf gespeichert") end
local s = vl[3001]
if not s:match("^1233,5,%d+,1233;6:1000:1,7:1000:1,12:1250:1,19:1500:1,21:1500:1$") then error("Format 3001: " .. tostring(s)) end
if vl[3005] ~= nil then error("Item unter 50 Kupfer darf keinen Verlauf haben: " .. tostring(vl[3005])) end
local a = __WW.AH.Analyse(3005)
__GLEICH(a and a.normal, nil, "3005 ohne Normalpreis")
local b = __WW.AH.Analyse(3006)
__GLEICH(b.scans, 1, "3006 nur ein Scan")
__GLEICH(b.urteil, nil, "3006 ohne Urteil (zu wenig Scans)")
__GLEICH(math.floor(__WW.AH.Analyse(3003).normal + 0.5), 1100, "Normalpreis 3003 (EMA)")
local zeilen = 0
for _ in pairs(vl) do zeilen = zeilen + 1 end
__LOG[#__LOG + 1] = "Verlauf: " .. zeilen .. " Items, Beispiel 3001 = " .. s

-- SZENE: Auktion - Schnaeppchen und zu teuer
local l, bereit = __WW.AH.Schnaeppchen()
__GLEICH(#l, 2, "Anzahl Schnaeppchen")
__GLEICH(l[1].id, 3007, "groesste Ersparnis zuerst")
__GLEICH(l[2].id, 3002, "zweites Schnaeppchen")
__GLEICH(l[1].diff, 4000, "Ersparnis 3007 (zum ueblichen Mindestpreis 9000)")
__GLEICH(math.floor(l[2].abw * 100 + 0.5), -44, "Abweichung 3002")
__GLEICH(bereit, 5, "Items mit genug Scans")
local t, _ = __WW.AH.ZuTeuer()
__GLEICH(#t, 1, "Anzahl zu teuer")
__GLEICH(t[1].id, 3003, "zu teuer: 3003")
__GLEICH(math.floor(t[1].abw * 100 + 0.5), 36, "Aufschlag 3003")
__GLEICH(__WW.AH.Analyse(3001).urteil, nil, "3001 weder noch")
__GLEICH(__WW.AH.Analyse(3004).urteil, nil, "3004 stabil")
-- Schwellen aus den Einstellungen
__WW.db.ah.schnaeppchen = 0.4
__GLEICH(#(__WW.AH.Schnaeppchen()), 0, "Schnaeppchen bei 40 %")
__WW.db.ah.schnaeppchen = 0.7

-- SZENE: Auktion - Uhrzeit-Tipps
local text, echt = __WW.AH.ZeitTipp(3001)
__GLEICH(echt, true, "Tipp echt")
__GLEICH(text, "Kaufen am günstigsten: ca. 06–09 Uhr · Verkaufen am besten: ca. 19–22 Uhr (aus 5 Scans)", "Tipptext")
local t2, e2 = __WW.AH.ZeitTipp(3004)
__GLEICH(e2, false, "stabiler Preis hat keinen echten Tipp")
__ENTHAELT(t2, "kaum", "stabil")
local t3, e3 = __WW.AH.ZeitTipp(3006)
__GLEICH(e3, false, "zu wenig Daten")
__ENTHAELT(t3, "Noch zu wenig Daten für Uhrzeit-Tipps", "zu wenig")
local t4, e4 = __WW.AH.ZeitTipp(99999)
__ENTHAELT(t4, "zu wenig Daten", "unbekanntes Item")
local st = __WW.AH.ScanStunden()
__GLEICH(st[6], 1, "Scans um 6 Uhr")
__GLEICH(st[21], 1, "Scans um 21 Uhr")

-- SZENE: Auktion - 15-Minuten-Sperre bleibt
__T = os.time{ year = 2026, month = 11, day = 17, hour = 21, min = 5 }
local ok, warum = __WW.AH.Scannen()
__GLEICH(ok, false, "Scan innerhalb von 15 Minuten")
__ENTHAELT(warum, "15 Minuten", "Sperre")
__GLEICH(__WW.AH.Wartezeit() > 0, true, "Wartezeit laeuft")

-- SZENE: Auktion - eine Probe pro Stunde, Suchergebnisse als Zusatzprobe
__SCAN(21, 30, { { 3001, 1500, 1500 }, { 3002, 1000, 2000 }, { 3003, 1600, 1600 }, { 3004, 500, 500 }, { 3005, 10, 10 },
  { 3006, 100, 1000 }, { 3007, 5000, 10000 } })
local a = __WW.AH.Analyse(3001)
__GLEICH(a.scans, 6, "sechster Scan zaehlt")
__GLEICH(a.eimer[21][2], 1, "21 Uhr hoechstens eine Probe")
-- Suchergebnis um 23:10
__T = os.time{ year = 2026, month = 11, day = 17, hour = 23, min = 10 }
C_AuctionHouse.GetBrowseResults = function()
  return { { itemKey = { itemID = 3004 }, minPrice = 400, totalQuantity = 3 }, { itemKey = { itemID = 777777 }, minPrice = 5, totalQuantity = 1 } }
end
__FEUER("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
local a2 = __WW.AH.Analyse(3004)
__GLEICH(a2.scans, 6, "Suche aendert die Scan-Zahl nicht")
__GLEICH(a2.eimer[23] and a2.eimer[23][2], 1, "Probe um 23 Uhr")
__GLEICH(a2.eimer[23][1], 400, "Preis der Probe")
__GLEICH(__WW.db.ahVerlauf["Forever|Alliance"][777777], nil, "unbekanntes Item bekommt keinen Verlauf")
-- gleiche Stunde, 10 Sekunden spaeter: keine zweite Probe
__G = __G + 10
__T = os.time{ year = 2026, month = 11, day = 17, hour = 23, min = 40 }
__FEUER("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
__GLEICH(__WW.AH.Analyse(3004).eimer[23][2], 1, "23 Uhr bleibt bei einer Probe")

-- SZENE: Auktion - Tooltip
local zeilen = {}
GameTooltip.AddLine = function(self, text) zeilen[#zeilen + 1] = text end
local function tip(id)
  zeilen = {}
  local f = GameTooltip.__scripts.OnTooltipCleared
  if f then f(GameTooltip) end
  GameTooltip.__owner = nil
  __WW.AH.TooltipZeilen(GameTooltip, { id = id, type = 0 })
  return table.concat(zeilen, "\n")
end
local t2 = tip(3002)
__ENTHAELT(t2, "Normalpreis:", "Normalpreis in Tooltip")
__ENTHAELT(t2, "(aus 6 Scans)", "Scans in Tooltip")
__ENTHAELT(t2, "Gerade günstig (-39 %)", "guenstig im Tooltip")
local t3 = tip(3003)
__ENTHAELT(t3, "Gerade zu teuer (+33 %)", "teuer im Tooltip")
-- doppelter Aufruf ohne Leeren: nur einmal Zeilen
local anzahl = #zeilen
__WW.AH.TooltipZeilen(GameTooltip, { id = 3003, type = 0 })
__GLEICH(#zeilen, anzahl, "Zeilen nur einmal")
local t1 = tip(3001)
__ENTHAELT(t1, "06–09 Uhr", "Uhrzeit-Tipp im Tooltip")
local t4 = tip(3004)
if t4:find("Gerade", 1, true) then error("3004 darf weder guenstig noch teuer sein: " .. t4) end

-- SZENE: Auktion - Marken im Blizzard-Auktionshaus
AuctionHouseTableCellMinPriceMixin = { Populate = function(zelle, rowData) end }
__WW.AH.AnhaengenVersuchen()
local zelle = CreateFrame("Frame")
local function marke()
  for _, f in ipairs(__FRAMES) do
    if f.__typ == "FontString" and f.__parent == zelle then return f end
  end
end
AuctionHouseTableCellMinPriceMixin.Populate(zelle, { itemKey = { itemID = 3002 }, minPrice = 1000 })
local m = marke()
if not m then error("keine Marke erzeugt") end
__ENTHAELT(m.__text, "-39 %", "Marke guenstig")
__GLEICH(m.__shown, true, "Marke sichtbar")
AuctionHouseTableCellMinPriceMixin.Populate(zelle, { itemKey = { itemID = 3002 }, minPrice = 2000 })
__GLEICH(m.__shown, false, "Marke bei Normalpreis versteckt")
AuctionHouseTableCellMinPriceMixin.Populate(zelle, { itemKey = { itemID = 3003 }, minPrice = 1700 })
__ENTHAELT(m.__text, "+42 %", "Marke teuer")
-- kaputte Zeilen duerfen nichts werfen
AuctionHouseTableCellMinPriceMixin.Populate(zelle, nil)
AuctionHouseTableCellMinPriceMixin.Populate(zelle, { itemKey = 5 })
__WW.db.ah.ahMarken = false
AuctionHouseTableCellMinPriceMixin.Populate(zelle, { itemKey = { itemID = 3003 }, minPrice = 1700 })
__GLEICH(m.__shown, false, "Marken ausgeschaltet")
__WW.db.ah.ahMarken = true

-- SZENE: Auktion - Reiter, Ansichten und Streifen
__WW:Oeffnen("ah")
__UPDATE(8)
local function knopf(text)
  for _, f in ipairs(__FRAMES) do if f.__typ == "Button" and f.__text == text then return f end end
end
local function liste2()
  for _, f in ipairs(__FRAMES) do
    if f.eintraege and f.eintraege[1] and f.eintraege[1].normal then return f end
  end
end
__WW.db.ah.markt.kategorie = nil   -- "alle Knöpfe klicken" vorher kann eine Kategorie gewählt haben
local k = knopf("Schnäppchen")
if not k then error("Knopf Schnäppchen fehlt") end
k.__scripts.OnClick(k, "LeftButton")
local l2 = liste2()
if not l2 then error("Schnäppchen-Liste ist leer") end
__GLEICH(#l2.eintraege, 2, "Eintraege Schnaeppchen")
local k2 = knopf("Zu teuer")
k2.__scripts.OnClick(k2, "LeftButton")
l2 = liste2()
__GLEICH(#l2.eintraege, 1, "Eintraege zu teuer")
local k3 = knopf("Taschen")
k3.__scripts.OnClick(k3, "LeftButton")
__UPDATE(8)
local gefunden
for _, f in ipairs(__FRAMES) do
  if f.__typ == "FontString" and type(f.__text) == "string" and f.__text:find("Scans nach Uhrzeit", 1, true) then gefunden = f end
end
if not gefunden then error("Streifen mit Scan-Uhrzeiten fehlt") end
__ENTHAELT(gefunden.__text, ":2", "Streifen zeigt zwei Scans um 21 Uhr")
-- Klick auf Schnaeppchen/zu teuer ohne Daten darf nichts werfen
__WW.db.ah["Forever|Alliance"] = nil
k.__scripts.OnClick(k, "LeftButton")
k3.__scripts.OnClick(k3, "LeftButton")

-- SZENE: Auktion - Details im Items-Reiter zeigen Normalpreis und Uhrzeit-Tipp
__WW.db.ah["Forever|Alliance"] = { r = "Forever", f = "Alliance", t = __T, n = 1, z = 1, m = "replicate", i = { [2447] = "1000,1000,3" } }
__WW.db.ahVerlauf["Forever|Alliance"] = { [2447] = "1100,5,500000;6:1800:2,7:900:1,19:3000:2,20:1500:1" }
SlashCmdList.WEGWEISER("suche 2447")
__UPDATE(5)
local gefunden
for _, f in ipairs(__FRAMES) do
  if f.__typ == "FontString" and type(f.__text) == "string" and f.__text:find("Normalpreis:", 1, true) then gefunden = f end
end
if not gefunden then for _, f in ipairs(__FRAMES) do if f.__typ == "FontString" and type(f.__text) == "string" and (f.__text:find("Item-Nummer", 1, true)) then __LOG[#__LOG+1] = "DBG " .. f.__text end end error("Details ohne Normalpreis") end
__ENTHAELT(gefunden.__text, "Kaufen am günstigsten: ca. 06–09 Uhr · Verkaufen am besten: ca. 19–22 Uhr (aus 5 Scans)", "Tipp in Details")

-- SZENE: Auktion - Vergleich mit dem Mindestpreis, nicht mit dem Median
local db = __WW.db
db.ah["Forever|Alliance"] = nil
db.ahVerlauf["Forever|Alliance"] = nil
db.ah.scanStunden = {}
__WW.AH.Status.fraktion = "Alliance"
local function angebote(id, spec)
  local t = {}
  for _, x in ipairs(spec) do for i = 1, x[1] do t[#t + 1] = { id, 1, x[2] } end end
  return t
end
local function runde(stunde, a, b, c)
  local roh = {}
  for _, liste in ipairs({ a, b, c }) do for _, x in ipairs(liste) do roh[#roh + 1] = x end end
  __SCANROH(stunde, 0, roh)
end
-- 5 Angebote zu 6000, 10 zu 10000, 5 zu 14000 je Stueck: Mindestpreis 6000, Median 10000
local ruhig = { { 5, 6000 }, { 10, 10000 }, { 5, 14000 } }
local teurer = { { 5, 9000 }, { 10, 15000 }, { 5, 21000 } }
local billiger = { { 5, 3000 }, { 10, 10000 }, { 5, 14000 } }
for _, h in ipairs({ 6, 7, 12, 19 }) do runde(h, angebote(3101, ruhig), angebote(3102, ruhig), angebote(3103, ruhig)) end
runde(21, angebote(3101, ruhig), angebote(3102, teurer), angebote(3103, billiger))
local function ids(l) local m = {} for _, e in ipairs(l) do m[e.id] = e end return m end
local a1 = __WW.AH.Analyse(3101)
__GLEICH(a1.urteil, nil, "unveraenderter Markt ist weder guenstig noch teuer")
__GLEICH(math.floor(a1.normal + 0.5), 10000, "Normalpreis bleibt der Median")
__GLEICH(math.floor((a1.normalMin or -1) + 0.5), 6000, "normaler Mindestpreis")
local sch = ids((__WW.AH.Schnaeppchen()))
local teu = ids((__WW.AH.ZuTeuer()))
__GLEICH(sch[3101], nil, "3101 kein Schnaeppchen")
__GLEICH(teu[3101], nil, "3101 nicht zu teuer")
__GLEICH(sch[3103] ~= nil, true, "3103 ist ein Schnaeppchen")
__GLEICH(math.floor(sch[3103].abw * 100 + 0.5), -44, "Abweichung 3103 zum Mindestpreis")
__GLEICH(teu[3102] ~= nil, true, "3102 ist zu teuer (Mindestpreis +36 %)")
__GLEICH(sch[3102], nil, "3102 kein Schnaeppchen")
-- Tooltip
local zeilen = {}
GameTooltip.AddLine = function(self, text) zeilen[#zeilen + 1] = text end
local function tip(id)
  zeilen = {}
  local f = GameTooltip.__scripts.OnTooltipCleared
  if f then f(GameTooltip) end
  GameTooltip.__owner = nil
  __WW.AH.TooltipZeilen(GameTooltip, { id = id, type = 0 })
  return table.concat(zeilen, " | ")
end
__ENTHAELT(tip(3103), "Gerade günstig (-44 %)", "Tooltip guenstig")
__ENTHAELT(tip(3102), "Gerade zu teuer (+36 %)", "Tooltip teuer")
local t = tip(3101)
if t:find("Gerade", 1, true) then error("3101 darf kein Urteil haben: " .. t) end
-- Marken im Blizzard-Auktionshaus
local zelle = CreateFrame("Frame")
local function marke()
  for _, f in ipairs(__FRAMES) do if f.__typ == "FontString" and f.__parent == zelle then return f end end
end
AuctionHouseTableCellMinPriceMixin.Populate(zelle, { itemKey = { itemID = 3101 }, minPrice = 6000 })
local m = marke()
if m and m.__shown then error("Marke bei unveraendertem Markt: " .. tostring(m.__text)) end
AuctionHouseTableCellMinPriceMixin.Populate(zelle, { itemKey = { itemID = 3102 }, minPrice = 9000 })
m = marke()
if not m or not m.__shown then error("keine Marke fuer 3102") end
__ENTHAELT(m.__text, "+36 %", "Marke 3102")

-- SZENE: Auktion - Auktionshaus der anderen Fraktion (neutral) hat seine eigenen Preise
local db = __WW.db
local AH = __WW.AH
__T = os.time{ year = 2026, month = 11, day = 17, hour = 22, min = 0 }
db.ah["Forever|Alliance"] = { r = "Forever", f = "Alliance", t = __T, n = 1, z = 1, m = "replicate", i = { [3201] = "10000,10000,5" } }
db.ah["Forever|Neutral"] = { r = "Forever", f = "Neutral", t = __T, n = 1, z = 1, m = "replicate", i = { [3201] = "30000,30000,5" } }
db.ahVerlauf["Forever|Alliance"] = { [3201] = "10000,5,500000,10000;6:10000:1,7:10000:1,12:10000:1" }
db.ahVerlauf["Forever|Neutral"] = { [3201] = "30000,5,500000,30000;6:30000:1,7:30000:1,12:30000:1" }
local ZELLE = CreateFrame("Frame")
local function marke()
  for _, f in ipairs(__FRAMES) do if f.__typ == "FontString" and f.__parent == ZELLE then return f end end
end
-- am Allianz-Auktionshaus ist 30000 wirklich zu teuer
AH.Status.offen, AH.Status.fraktion = true, "Alliance"
local u, abw = AH.PreisUrteil(3201, 30000)
__GLEICH(u, "teuer", "Alliance-AH: 30000 ist zu teuer")
__GLEICH(math.floor(abw * 100 + 0.5), 200, "Aufschlag +200 %")
-- am neutralen Auktionshaus ist es normal
AH.Status.fraktion = "Neutral"
u = AH.PreisUrteil(3201, 30000)
__GLEICH(u, nil, "neutrales AH: 30000 ist normal")
__GLEICH((AH.Preis(3201)), 30000, "Preis kommt vom neutralen AH")
AuctionHouseTableCellMinPriceMixin.Populate(ZELLE, { itemKey = { itemID = 3201 }, minPrice = 30000 })
local m = marke()
if m and m.__shown then error("Marke am neutralen AH: " .. tostring(m.__text)) end
-- Schluessel von aussen
__GLEICH((AH.PreisUrteil(3201, 30000, "Forever|Alliance")), "teuer", "Schluessel Alliance")
__GLEICH((AH.PreisUrteil(3201, 30000, "Forever|Neutral")), nil, "Schluessel Neutral")
-- ohne offenes Auktionshaus: die eigene Fraktion
AH.Status.offen, AH.Status.fraktion = false, nil
__GLEICH((AH.PreisUrteil(3201, 30000)), "teuer", "geschlossen: eigene Fraktion")
AH.Status.offen, AH.Status.fraktion = true, "Alliance"

-- SZENE: Auktion - alte Verlaeufe ohne Mindestpreis werden beim naechsten Scan ergaenzt
local db = __WW.db
local AH = __WW.AH
db.ah["Forever|Neutral"] = nil
db.ahVerlauf["Forever|Neutral"] = nil
db.ahVerlauf["Forever|Alliance"] = { [3301] = "8000,5,500000;6:5000:1,7:5000:1,12:5000:1" }
db.ah["Forever|Alliance"] = { r = "Forever", f = "Alliance", t = __T, n = 1, z = 1, m = "replicate", i = { [3301] = "5000,8000,3" } }
local a = AH.Analyse(3301)
__GLEICH(a.normalMin, nil, "alter Verlauf ohne Mindestpreis")
__GLEICH(a.urteil, nil, "alter Verlauf: kein Urteil")
__SCANROH(8, 0, { { 3301, 1, 5000 }, { 3301, 1, 8000 }, { 3301, 1, 8000 } })
a = AH.Analyse(3301)
__GLEICH(math.floor((a.normalMin or -1) + 0.5), 5000, "Mindestpreis aus dem Scan uebernommen")
__GLEICH(a.scans, 6, "Scan gezaehlt")
__GLEICH(a.urteil, nil, "gleich nach dem Ergaenzen kein Urteil")

-- SZENE: Auktion - Gebuehren: Abzug je Auktionshaus, Einstellgebuehr, Kaution hoch
local db = __WW.db
local AH = __WW.AH
local alt = { offen = AH.Status.offen, fraktion = AH.Status.fraktion }
db.ah.dauer = 8
local function speicher(f, id, preis)
  db.ah["Forever|" .. f] = { r = "Forever", f = f, t = time(), n = 1, z = 1, m = "replicate", i = { [id] = preis } }
end
db.ah["Forever|Alliance"], db.ah["Forever|Neutral"] = nil, nil
AH.Status.offen, AH.Status.fraktion = false, nil
-- nur neutrale Preise, Auktionshaus zu: 15 % Abzug
speicher("Neutral", 3401, "10000,10000,5")
local f1, t1, e1, h1, info1 = AH.Bewertung(3401, 1)
__GLEICH(e1, 8500, "Neutral: 15 % Abzug")
__GLEICH(info1 and info1.fraktion, "Neutral", "Info nennt das neutrale AH")
__GLEICH(info1 and info1.abzug, 0.15, "Abzug 15 %")
-- Preise von der eigenen Seite: 5 %
speicher("Alliance", 3401, "10000,10000,5")
local _, _, e2, _, info2 = AH.Bewertung(3401, 1)
__GLEICH(e2, 9500, "Fraktion: 5 % Abzug")
__GLEICH(info2 and info2.fraktion, "Alliance", "Info nennt die Fraktion")
-- am neutralen Auktionshaus (offen) gilt dessen Abzug
AH.Status.offen, AH.Status.fraktion = true, "Neutral"
local _, _, e3 = AH.Bewertung(3401, 1)
__GLEICH(e3, 8500, "offenes neutrales AH: 15 %")
-- am Fraktions-Auktionshaus mit nur neutralen Preisen gilt der Fraktions-Abzug
db.ah["Forever|Alliance"] = nil
AH.Status.fraktion = "Alliance"
local _, _, e4 = AH.Bewertung(3401, 1)
__GLEICH(e4, 9500, "offenes Fraktions-AH: 5 %")

-- Einstellgebuehr (Haendlerpreis 150 im Mock)
local k = AH.Kaution(3401, 1, "Alliance")
__GLEICH(k, 30, "8 Std. Fraktion: 20 % von 150")
__GLEICH((AH.Kaution(3401, 10, "Alliance")), 300, "10 Stueck")
__GLEICH((AH.Kaution(3401, 1, "Neutral")), 150, "neutral: fuenffach")
db.ah.dauer = 24
__GLEICH((AH.Kaution(3401, 1, "Alliance")), 90, "24 Std.: 60 %")
db.ah.dauer = 2
__GLEICH((AH.Kaution(3401, 1, "Alliance")), 7, "2 Std.: 5 %")
db.ah.dauer = 8
-- liefert der Client die Einstellgebuehr selbst, gilt sie (nur bei offenem Auktionshaus)
C_AuctionHouse.CalculateCommodityDeposit = function(id, dauer, anzahl) return 777 end
AH.KautionCacheLeeren()
AH.Status.offen, AH.Status.fraktion = true, "Alliance"
__GLEICH((AH.Kaution(3401, 1, "Alliance")), 777, "Kaution vom Client")
AH.Status.offen = false
__GLEICH((AH.Kaution(3401, 1, "Alliance")), 30, "Auktionshaus zu: Formel")
C_AuctionHouse.CalculateCommodityDeposit = nil
AH.KautionCacheLeeren()

-- "Kaution hoch": die Einstellgebuehr frisst mehr als 20 % des Gewinns
AH.Status.offen, AH.Status.fraktion = true, "Alliance"
speicher("Alliance", 3402, "400,400,5")
db.ah.dauer = 8
local farbe, text = AH.Bewertung(3402, 100)
__GLEICH(farbe, "gruen", "8 Std.: Kaution 3000 von 23000 Gewinn")
__GLEICH(text, "AH lohnt", "Text gruen")
db.ah.dauer = 24
farbe, text = AH.Bewertung(3402, 100)
__GLEICH(farbe, "gelb", "24 Std.: Kaution 9000 ist zu viel")
__GLEICH(text, "Kaution hoch", "Text Kaution hoch")
db.ah.dauer = 2
farbe = AH.Bewertung(3402, 100)
__GLEICH(farbe, "gruen", "2 Std.: Kaution klein")
db.ah.dauer = 8

-- Tooltip nennt das Auktionshaus und die Einstellgebuehr
db.ah["Forever|Alliance"] = nil
speicher("Neutral", 3401, "10000,10000,5")
AH.Status.offen, AH.Status.fraktion = false, nil
local zeilen = {}
GameTooltip.AddLine = function(self, text) zeilen[#zeilen + 1] = text end
local f = GameTooltip.__scripts.OnTooltipCleared
if f then f(GameTooltip) end
GameTooltip.__owner = nil
AH.TooltipZeilen(GameTooltip, { id = 3401, type = 0 })
local t = table.concat(zeilen, " | ")
__ENTHAELT(t, "nach Gebühren", "Tooltip: nach Gebuehren")
__ENTHAELT(t, "(Neutral 15 %)", "Tooltip: Auktionshaus")
__ENTHAELT(t, "Einstellgebühr", "Tooltip: Einstellgebuehr")
__ENTHAELT(t, "weg, wenn es nicht verkauft wird", "Tooltip: Risiko")
AH.Status.offen, AH.Status.fraktion = alt.offen, alt.fraktion
db.ah["Forever|Neutral"] = nil

-- SZENE: Auktion - Rechtsklick "Mehr Information" (Wegweiser-Liste, Blizzard-AH, Taste)
do
  local function menueKlick()
    local m = _G.WegweiserMenue
    if not (m and m.__shown) then error("Menue nicht offen") end
    local k
    for _, b in ipairs(m.knoepfe) do if b.__shown and b.text.__text == "Mehr Information" then k = b end end
    if not k then error("Eintrag 'Mehr Information' fehlt") end
    k.__scripts.OnClick(k, "LeftButton")
    if m.__shown then error("Menue bleibt nach Klick offen") end
  end
  local function sucheText()
    for _, f in ipairs(__FRAMES) do
      if f.__typ == "EditBox" and f.__shown and f.__text ~= "" then return f.__text end
    end
  end
  local function erwarte(id, wo)
    if not __WW:IstOffen("items") then error(wo .. ": Reiter Items nicht offen") end
    local name = __WW.ItemName(id) or ("Item " .. id)
    if sucheText() ~= name then error(wo .. ": Suche ist '" .. tostring(sucheText()) .. "', erwartet '" .. name .. "'") end
  end
  -- 1. Wegweiser-Liste (Auktionshaus, Ansicht Taschen)
  __WW:Oeffnen("ah")
  __UPDATE(2)
  local liste
  for _, f in ipairs(__FRAMES) do
    if f.itemKlick and f.__shown and f.eintraege and f.eintraege[1] and f.zeilen[1].eintrag then liste = f end
  end
  if not liste then error("Liste mit Items im AH-Reiter fehlt") end
  local zeile = liste.zeilen[1]
  local id = tonumber(zeile.eintrag.id)
  zeile.__scripts.OnMouseUp(zeile, "LeftButton")
  if _G.WegweiserMenue and _G.WegweiserMenue.__shown then error("Linksklick oeffnet das Menue") end
  zeile.__scripts.OnMouseUp(zeile, "RightButton")
  menueKlick()
  erwarte(id, "Liste")
  -- 2. Blizzards Ergebniszeile: Preiszelle liegt auf der Zeile
  local zeileB = CreateFrame("Button", nil, UIParent)
  local zelle = CreateFrame("Frame", nil, zeileB)
  __WW.AH.MerkeZeile(zelle, { itemKey = { itemID = 2449 }, minPrice = 100 })
  __WW.AH.MerkeZeile(zelle, { itemKey = { itemID = 2450 }, minPrice = 100 })   -- Zeile neu befuellt: neues Item
  zeileB.__scripts.OnMouseUp(zeileB, "RightButton")
  menueKlick()
  erwarte(2450, "Blizzard-AH")
  -- 3. Taste ueber einem Item-Tooltip
  local altGet, altShown = GameTooltip.GetItem, GameTooltip.__shown
  GameTooltip.GetItem = function() return "x", "|cff|Hitem:2448::|h[x]|h|r" end
  GameTooltip.__shown = true
  if not __WW:ItemUnterMaus() then error("Taste: kein Item erkannt") end
  erwarte(2448, "Taste")
  GameTooltip.GetItem, GameTooltip.__shown = altGet, altShown
end

-- SZENE: Auktion - Filter-Fenster: Seltenheit, weisse Ausruestung, Stufe, nur nutzbare, alte Einstellung
do
  local AH = __WW.AH
  local altGII = C_Item.GetItemInfo
  -- id = { Qualitaet, benoetigte Stufe, Klasse }
  local info = { [9001] = { 0, 5, 4 }, [9002] = { 1, 5, 4 }, [9003] = { 1, 5, 7 }, [9004] = { 2, 20, 4 }, [9005] = { 4, 40, 2 } }
  C_Item.GetItemInfo = function(id)
    local x = info[tonumber(id)]
    if x then return "Item" .. id, "", x[1], 10, x[2], "", "", 1, "", 134400, 10, x[3], 0 end
    return altGII(id)
  end
  local liste = {}
  for id = 9001, 9005 do liste[#liste + 1] = { id = id, preis = 100, normal = 10000, menge = 1, abw = -0.99, diff = 9900 } end
  local mf = __WW.db.ah.markt
  local gesichert = {}
  for k, v in pairs(mf) do gesichert[k] = v end
  local function ids()
    local r = {}
    for _, e in ipairs(AH.MarktFiltern(liste, "schnaeppchen", "")) do r[#r + 1] = tostring(e.id) end
    return table.concat(r, ",")
  end
  local function neu() mf.q, mf.weissAus, mf.stufeVon, mf.stufeBis, mf.nutzbar, mf.qualitaet, mf.kategorie = nil, nil, nil, nil, nil, nil, nil end
  -- Standard: kein Grau, keine weisse Ruestung
  neu()
  __GLEICH(ids(), "9003,9004,9005", "Standard")
  __GLEICH(AH.FilterAnzahl(mf), 2, "Standard: 2 Filter aktiv")
  -- Seltenheit einzeln
  mf.q[2] = false
  __GLEICH(ids(), "9003,9005", "ohne Selten")
  mf.q[2] = true
  mf.weissAus = false
  __GLEICH(ids(), "9002,9003,9004,9005", "weisse Ausruestung erlaubt")
  -- Stufe von-bis (benoetigte Stufe)
  mf.stufeVon, mf.stufeBis = 10, 30
  __GLEICH(ids(), "9004", "Stufe 10-30")
  mf.stufeVon, mf.stufeBis = nil, nil
  -- nur nutzbare: Item 9005 kann die Klasse nicht tragen
  local QW = __WW.QW
  local altKann = QW.KannTragen
  QW.KannTragen = function(id) if tonumber(id) == 9005 then return false, "Test" end return nil end
  mf.nutzbar = true
  __GLEICH(ids(), "9002,9003,9004", "nur nutzbare")
  QW.KannTragen = altKann
  -- alte Einstellung vom Knopf "Zeige: ..." wird uebernommen
  neu()
  mf.qualitaet = "alle"
  __GLEICH(ids(), "9001,9002,9003,9004,9005", "alt: alle")
  neu()
  mf.qualitaet = "abGruen"
  __GLEICH(ids(), "9004,9005", "alt: ab Gruen")
  -- Filter-Fenster im Reiter: Knopf "Filter (n)" oeffnet es, Haken schalten die Einstellung
  neu()
  __WW:Oeffnen("ah")
  __UPDATE(1)
  local k
  for _, f in ipairs(__FRAMES) do if f.__typ == "Button" and f.__shown and tostring(f.__text):match("^Filter") then k = f end end
  if not k then
    for _, f in ipairs(__FRAMES) do if f.__typ == "Button" and f.__text == "Schnäppchen" then f.__scripts.OnClick(f, "LeftButton") end end
    for _, f in ipairs(__FRAMES) do if f.__typ == "Button" and f.__shown and tostring(f.__text):match("^Filter") then k = f end end
  end
  if not k then error("Knopf Filter fehlt") end
  k.__scripts.OnClick(k, "LeftButton")
  local fenster = _G.WegweiserAHFilter
  if not (fenster and fenster.__shown) then error("Filter-Fenster nicht offen") end
  local h
  for _, x in ipairs(fenster.haken) do if x.__typ == "CheckButton" and x.get and not x.get() and x == fenster.haken[1] then h = x end end
  if not h then error("Haken 'Nur nutzbare' fehlt") end
  h:SetChecked(true)
  h.__scripts.OnClick(h, "LeftButton")
  if not mf.nutzbar then error("Haken schaltet 'nur nutzbare' nicht") end
  __GLEICH(k.__text, "Filter (3)", "Aufschrift nach Haken")
  k.__scripts.OnClick(k, "LeftButton")
  if fenster.__shown then error("Filter-Fenster schliesst nicht") end
  for kk in pairs(mf) do mf[kk] = nil end
  for kk, v in pairs(gesichert) do mf[kk] = v end
  C_Item.GetItemInfo = altGII
end

-- SZENE: Auktion - Tagespreise, Preis-Grafik in den Item-Details, Reiter "Wegweiser" am Blizzard-AH
do
  local AH = __WW.AH
  -- 1. Voll-Scans vom 17.11. haben den niedrigsten Preis des Tages gebucht
  local tg = __WW.db.ahTage and __WW.db.ahTage["Forever|Alliance"]
  if not tg then error("keine Tagespreise gespeichert") end
  local heute = AH.TagNummer(os.time{ year = 2026, month = 11, day = 17, hour = 6 })
  __GLEICH(tg[3001], heute .. ":1000", "Tagespreis 3001 = Minimum des Tages")
  __GLEICH(tg[3005], nil, "Item ohne Verlauf bekommt keine Tagespreise")
  -- 2. Buchen: gleicher Tag kleiner -> ersetzt, groesser -> bleibt, neuer Tag -> angehaengt, alte Tage fallen weg
  local t = {}
  AH.TageBuchen(t, 1, 100, 500)
  AH.TageBuchen(t, 1, 100, 400)
  AH.TageBuchen(t, 1, 100, 450)
  __GLEICH(t[1], "100:400", "gleicher Tag: kleinster Preis")
  AH.TageBuchen(t, 1, 101, 600)
  __GLEICH(t[1], "100:400,101:600", "neuer Tag")
  AH.TageBuchen(t, 1, 129, 700)
  __GLEICH(t[1], "100:400,101:600,129:700", "Tag 129: Tag 100 ist noch im Fenster (30 Tage)")
  AH.TageBuchen(t, 1, 131, 800)
  __GLEICH(t[1], "129:700,131:800", "Tag 131: Tage 100 und 101 fallen weg")
  -- PC-Uhr einmal in der Zukunft (Tag 900), danach wieder richtig: der Zukunftstag faellt weg, nie mehr als 30 Tage
  local u = {}
  AH.TageBuchen(u, 1, 900, 500)
  for tag = 200, 260 do AH.TageBuchen(u, 1, tag, 100 + tag) end
  local n, vorTag, sortiert = 0, -1, true
  for tag in u[1]:gmatch("(%d+):%d+") do
    n = n + 1
    if tonumber(tag) <= vorTag then sortiert = false end
    vorTag = tonumber(tag)
  end
  __GLEICH(n, 30, "nach Uhr-Fehler: 30 Tage")
  __GLEICH(sortiert, true, "nach Uhr-Fehler: aufsteigend, ohne doppelte Tage")
  if u[1]:find("900:", 1, true) then error("Zukunftstag 900 bleibt stehen: " .. u[1]) end
  -- Uhr einen Tag zurueck: kein doppelter Tag, Reihenfolge bleibt
  local w = {}
  AH.TageBuchen(w, 1, 300, 100)
  AH.TageBuchen(w, 1, 301, 90)
  AH.TageBuchen(w, 1, 300, 80)
  __GLEICH(w[1], "300:80", "Uhr zurueck: Tag 301 liegt in der Zukunft und faellt weg, Tag 300 nimmt den kleineren Preis")
  -- 3. Grafikdaten und Grafik
  -- eigenes Item mit Verlauf (die Scans oben sind von spaeteren Szenen schon ueberschrieben)
  __WW.db.ahVerlauf["Forever|Alliance"][4242] = "1000,5,1,1000;6:2000:2"
  tg[4242] = heute .. ":1000"
  local d = AH.Grafikdaten(4242)
  if not d then error("keine Grafikdaten fuer 4242") end
  __GLEICH(#d.tage, 1, "ein Tag")
  __GLEICH(d.stunden[6], 1000, "6 Uhr: Mittel 1000")
  __GLEICH(d.stunden[3], nil, "3 Uhr: keine Daten")
  local g = __WW.UI.PreisGrafik(UIParent, 300)
  local vorher = __LINIEN or 0
  local ok = g:Setze({ tage = { { 98, 1000 }, { 99, 1200 }, { 100, 900 } }, stunden = { [6] = 1000, [20] = 1400 },
    normalMin = 1100, heute = 100 })
  __GLEICH(ok, true, "Grafik zeigt etwas")
  __GLEICH((__LINIEN or 0) - vorher, 2, "zwei Linienstuecke fuer drei Tage")
  __GLEICH(g:Setze(nil), false, "ohne Daten keine Grafik")
  __GLEICH(g:Setze({ tage = {}, stunden = {}, heute = 100 }), false, "leere Daten: keine Grafik")
  -- 4. Item-Details zeigen die Grafik
  __WW:ItemZeigen(4242)
  local sichtbar = false
  for _, f in ipairs(__FRAMES) do
    if f.Setze and f.__h == __WW.UI.GRAFIK_HOEHE and f.__shown and f ~= g then sichtbar = true end
  end
  if not sichtbar then error("Grafik in den Item-Details nicht sichtbar") end
  -- 5. Reiter "Wegweiser" am Blizzard-AH
  local ahf = CreateFrame("Frame", "AuctionHouseFrame", UIParent)
  _G.AuctionHouseFrame = ahf
  local tab = CreateFrame("Button", nil, ahf)
  ahf.Tabs = { tab }
  ahf.SetDisplayMode = function() end
  local k = AH.ReiterAmAHBauen()
  if not k then error("Reiter am AH nicht gebaut") end
  __GLEICH(k.__text, "Wegweiser", "Aufschrift")
  __GLEICH(AH.ReiterAmAHBauen(), k, "nur ein Reiter")
  k.__scripts.OnClick(k, "LeftButton")
  if not __WW:IstAngedockt(ahf) then error("Klick legt Wegweiser nicht ueber das AH") end
  if not __WW:IstOffen("ah") then error("Wegweiser zeigt nicht den Reiter Auktionshaus") end
  -- liegt rechts neben dem AH-Fenster (verdeckt Blizzards Reiter und den Knopf nicht)
  local wf = _G.WegweiserFenster
  local pt = wf.__points[1]
  if not (pt and pt[2] == ahf and pt[1] == "TOPLEFT" and pt[3] == "TOPRIGHT") then
    error("Wegweiser liegt nicht rechts neben dem AH-Fenster")
  end
  -- mit X geschlossen und neu geoeffnet: an der normalen Stelle, nicht mehr angedockt
  wf:Hide()
  __WW:Oeffnen("ah")
  if __WW:IstAngedockt() then error("nach Schliessen noch angedockt") end
  if wf.__points[1] and wf.__points[1][2] == ahf then error("nach Schliessen noch am AH-Fenster") end
  wf:Hide()
  k.__scripts.OnClick(k, "LeftButton")
  k.__scripts.OnClick(k, "LeftButton")
  if __WW:IstOffen() then error("zweiter Klick schliesst Wegweiser nicht") end
  k.__scripts.OnClick(k, "LeftButton")
  ahf:SetDisplayMode("kaufen")
  if not __WW:IstAngedockt() then error("Blizzard-Reiter gewaehlt: Wegweiser daneben muss offen bleiben") end
  k.__scripts.OnClick(k, "LeftButton")
  k.__scripts.OnClick(k, "LeftButton")
  local warOffen = AH.Offen()
  if not warOffen then __FEUER("AUCTION_HOUSE_SHOW") end
  __FEUER("AUCTION_HOUSE_CLOSED")
  if __WW:IstAngedockt() or __WW:IstOffen() then error("AH zu: Wegweiser bleibt ueber dem AH") end
  if warOffen then __FEUER("AUCTION_HOUSE_SHOW") end
  _G.AuctionHouseFrame = nil
end

-- SZENE: Auktion - Kategorie-Filter: eigene Liste, Blizzards AuctionCategories, Unterkategorie, Fenster
do
  local AH = __WW.AH
  local altGII = C_Item.GetItemInfo
  -- id = { Klasse, Unterklasse }
  local info = { [9101] = { 2, 0 }, [9102] = { 7, 5 }, [9103] = { 7, 6 }, [9104] = { 4, 1 } }
  C_Item.GetItemInfo = function(id)
    local x = info[tonumber(id)]
    if x then return "Item" .. id, "", 2, 10, 5, "", "", 1, "", 134400, 10, x[1], x[2], 0 end
    return altGII(id)
  end
  local mf = __WW.db.ah.markt
  local altKat = mf.kategorie
  local liste = {}
  for id = 9101, 9104 do liste[#liste + 1] = { id = id, preis = 100, normal = 10000, menge = 1, abw = -0.99, diff = 9900 } end
  local function ids(ansicht)
    local r = {}
    for _, e in ipairs(AH.MarktFiltern(liste, ansicht or "teuer", "")) do r[#r + 1] = tostring(e.id) end
    return table.concat(r, ",")
  end
  -- 1. eigene Liste (ohne Blizzards AH-Daten)
  _G.AuctionCategories = nil
  AH.KategorienNeu()
  local baum, quelle = AH.Kategorien()
  __GLEICH(quelle, "eigen", "ohne Blizzard-Daten: eigene Liste")
  if not AH.KategorieVon("Handwerkswaren") then error("Handwerkswaren fehlt in der eigenen Liste") end
  mf.kategorie = nil
  __GLEICH(ids(), "9101,9102,9103,9104", "alle Kategorien")
  mf.kategorie = "Handwerkswaren"
  __GLEICH(ids(), "9102,9103", "Handwerkswaren")
  mf.kategorie = "Waffen"
  __GLEICH(ids("verkaufen"), "9101", "Waffen (auch in Verkaufen)")
  -- 2. Blizzards Liste wird genommen, sobald es sie gibt; Oberkategorie ohne Filter nimmt die der Kinder
  _G.AuctionCategories = {
    { name = "Waffen", filters = { { classID = 2 } }, subCategories = { { name = "Einhand", filters = { { classID = 2, subClassID = 0 } } } } },
    { name = "Handwerkswaren", subCategories = {
      { name = "Stoff", filters = { { classID = 7, subClassID = 5 } } },
      { name = "Leder", filters = { { classID = 7, subClassID = 6 } } } } },
  }
  local _, q2 = AH.Kategorien()
  __GLEICH(q2, "blizzard", "Blizzards Liste")
  mf.kategorie = "Handwerkswaren/Stoff"
  __GLEICH(ids(), "9102", "Handwerkswaren > Stoff")
  mf.kategorie = "Handwerkswaren"
  __GLEICH(ids(), "9102,9103", "Oberkategorie = Filter der Kinder")
  mf.kategorie = "Handwerkswaren/Gibtsnicht"
  __GLEICH(ids(), "9102,9103", "unbekannte Unterkategorie: Oberkategorie")
  mf.kategorie = "Gibtsnicht"
  __GLEICH(ids(), "9101,9102,9103,9104", "unbekannte Kategorie: alle")
  -- 3. Fenster im Reiter: Knopf oeffnet die Liste, Klick waehlt und klappt auf
  mf.kategorie = nil
  __WW:Oeffnen("ah")
  for _, f in ipairs(__FRAMES) do if f.__typ == "Button" and f.__text == "Zu teuer" then f.__scripts.OnClick(f, "LeftButton") end end
  local k
  for _, f in ipairs(__FRAMES) do if f.__typ == "Button" and f.__shown and f.__text == "Kategorie: alle" then k = f end end
  if not k then error("Knopf 'Kategorie: alle' fehlt") end
  k.__scripts.OnClick(k, "LeftButton")
  local fe = _G.WegweiserAHKategorie
  if not (fe and fe.__shown) then error("Kategorie-Fenster nicht offen") end
  local function zeile(text)
    for _, z in ipairs(fe.zeilen) do if z.__shown and z.eintrag and z.eintrag.text == text then return z end end
  end
  local hw = zeile("Handwerkswaren")
  if not hw then error("Zeile Handwerkswaren fehlt") end
  hw.__scripts.OnClick(hw)
  __GLEICH(mf.kategorie, "Handwerkswaren", "Oberkategorie gewaehlt")
  local stoff = zeile("Stoff")
  if not stoff then error("Handwerkswaren klappt nicht auf (Stoff fehlt)") end
  stoff.__scripts.OnClick(stoff)
  __GLEICH(mf.kategorie, "Handwerkswaren/Stoff", "Unterkategorie gewaehlt")
  __GLEICH(k.__text, "Kategorie: Stoff", "Aufschrift")
  if fe.__shown then error("Fenster bleibt nach Unterkategorie offen") end
  -- Stoff steht rechts neben den Hauptkategorien (zwei Spalten), nicht darunter
  k.__scripts.OnClick(k, "LeftButton")
  local hw2, st2 = zeile("Handwerkswaren"), zeile("Stoff")
  if not (hw2 and st2) then error("Hauptkategorie oder Unterkategorie fehlt beim Wiederoeffnen") end
  if st2.__points[1][2] <= hw2.__points[1][2] then error("Unterkategorie nicht in der rechten Spalte") end
  -- nur ein Fenster offen: Filter oeffnen schliesst Kategorie und umgekehrt
  for _, f in ipairs(__FRAMES) do if f.__typ == "Button" and f.__text == "Schnäppchen" then f.__scripts.OnClick(f, "LeftButton") end end
  k.__scripts.OnClick(k, "LeftButton")
  local fk
  for _, f in ipairs(__FRAMES) do if f.__typ == "Button" and f.__shown and tostring(f.__text):match("^Filter") then fk = f end end
  if not fk then error("Knopf Filter fehlt") end
  fk.__scripts.OnClick(fk, "LeftButton")
  if fe.__shown then error("Kategorie-Fenster bleibt offen, wenn der Filter aufgeht") end
  if not _G.WegweiserAHFilter.__shown then error("Filter-Fenster nicht offen") end
  k.__scripts.OnClick(k, "LeftButton")
  if _G.WegweiserAHFilter.__shown then error("Filter-Fenster bleibt offen, wenn die Kategorie aufgeht") end
  -- Klick daneben schliesst
  __FEUER("GLOBAL_MOUSE_DOWN", "LeftButton")
  if fe.__shown then error("Klick daneben schliesst das Kategorie-Fenster nicht") end
  for _, f in ipairs(__FRAMES) do if f.__typ == "Button" and f.__text == "Taschen" then f.__scripts.OnClick(f, "LeftButton") end end
  if k.__shown then error("Kategorie-Knopf in der Taschen-Ansicht sichtbar") end
  -- aufraeumen
  mf.kategorie = altKat
  _G.AuctionCategories = nil
  AH.KategorienNeu()
  C_Item.GetItemInfo = altGII
end

-- SZENE: Auktion - Aufraeumen (Uhr zurueck)
time = __ECHTZEIT
GetTime = function() return os.clock() end

-- SZENE: Auktion - kurze Preise fuer schmale Spalten
do
  local alt = __WW.Geld
  __WW.Geld = function(k) return tostring(k) end
  __GLEICH(__WW.GeldKurz(9999), "9999", "unter 1 Gold: genau")
  __GLEICH(__WW.GeldKurz(1785649), "1785600", "ab 1 Gold: ohne Kupfer")
  __GLEICH(__WW.GeldKurz(1785699), "1785700", "ab 1 Gold: auf Silber gerundet")
  __GLEICH(__WW.GeldKurz(12345678), "12350000", "ab 1000 Gold: nur Gold")
  __GLEICH(__WW.GeldKurz(0), "-", "kein Preis")
  __WW.Geld = alt
end
