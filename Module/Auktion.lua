-- Wegweiser: Reiter "Auktionshaus". Voll-Scan, Preise, "AH oder Händler?", Farben in Taschen und Tooltips.
-- Scan nach dem Vorbild von ForeverDB\Auctions.lua (GPL-3.0, angepasst):
--   1. C_AuctionHouse.ReplicateItems (Hauptweg), 2. QueryAuctionItems getAll (Ersatz).
-- Gespeichert in WW.db.ah["<Realm>|<Alliance|Horde|Neutral>"] = { r, f, t (Zeit), n (Angebote), z (Items), m (Weg),
--   i = { [itemID] = "min,median,menge" } }   Preise in Kupfer pro Stück.
-- Einstellungen liegen im selben Eintrag WW.db.ah (Schlüssel ohne "|").
-- Öffentlich: WW.AH.Preis(id), WW.AH.Bewertung(id, anzahl, gebunden), WW.AH.Scannen(), WW.AH.Wartezeit() ...
local ADDON, WW = ...
local UI = WW.UI

WW.standardDB.ah = {
  faktor = 1.5,           -- AH-Erlös muss mindestens so viel mal Händlerpreis sein ...
  mindestGewinn = 2000,   -- ... und mindestens so viel Kupfer mehr bringen (20 Silber)
  taschenFarben = true,   -- "Farben in Taschen"
  tooltip = true,         -- AH-Zeilen im Tooltip
  autoScan = false,       -- beim Öffnen des Auktionshauses von selbst scannen
  taschenBank = false,    -- Ansicht "Taschen": auch die zuletzt gesehene Bank dieses Charakters zeigen
  dauer = 8,              -- Laufzeit (Stunden: 2, 8 oder 24), für die die Einstellgebühr gerechnet wird
  letzterScan = 0,        -- Zeit des letzten Voll-Scans (für die 15-Minuten-Sperre)
  schnaeppchen = 0.7,     -- "günstig": aktueller Mindestpreis höchstens so viel vom Normalpreis
  zuTeuer = 1.3,          -- "zu teuer": aktueller Mindestpreis mindestens so viel vom Normalpreis
  ahMarken = true,        -- Marken "-35 %" / "+40 %" in Blizzards Auktionshaus
  scanStunden = {},       -- [Uhrzeit 0-23] = Anzahl Voll-Scans zu dieser Stunde
  bereinigt = 0,          -- Zeit der letzten Aufräumrunde im Preisverlauf
  -- einzelne Tooltip-Zeilen (Reiter "Einstellungen"); tooltip = false schaltet alle ab
  tt = { preis = true, menge = true, urteil = true, kaution = true, normal = true, zeit = true },
  -- Filter der Ansichten "Schnäppchen" / "Zu teuer": ersparnis = Mindest-Ersparnis in Prozent (0 = alle)
  -- Filter-Fenster (nur "Schnäppchen"): q[0..5] = Seltenheit zeigen, weissAus = keine weißen Waffen/Rüstungen,
  -- stufeVon/stufeBis = benötigte Stufe, nutzbar = nur was deine Klasse tragen kann. Siehe AH.FilterEinst.
  markt = { bezahlbar = false, ersparnis = 0, nurMeine = false },
}
-- Preisverlauf: WW.db.ahVerlauf["<Realm>|<Fraktion>"][itemID] = "normal,scans,letzteStunde;h:summe:n,h:summe:n,..."
--   normal = Normalpreis (Kupfer), scans = Anzahl Scans, letzteStunde = Stunden seit 1970 (UTC),
--   h:summe:n = Tagesstunde (0-23, Ortszeit), Summe der Mindestpreise, Anzahl Proben (höchstens eine pro Stunde)
WW.standardDB.ahVerlauf = {}
-- Tagespreise für die Grafik: WW.db.ahTage["<Realm>|<Fraktion>"][itemID] = "tag:min,tag:min,..."
--   tag = Tagesnummer (Tage seit 1970, Ortszeit), min = niedrigster Mindestpreis an dem Tag (Voll-Scan und Suche).
--   Nur Items mit Preisverlauf, höchstens TAGE_MAX Tage.
WW.standardDB.ahTage = {}

local AH = {}
WW.AH = AH

-- Gebühren des Auktionshauses (Classic, WoW Forever):
--   Abzug vom Verkaufspreis: Fraktions-Auktionshaus 5 %, neutrales (Goblin-)Auktionshaus 15 %.
--   Einstellgebühr (Kaution): Anteil des Händlerpreises je Stück - Fraktions-AH 5 % (2 Std.), 20 % (8 Std.),
--   60 % (24 Std.); neutrales AH das Fünffache; mindestens 1 Kupfer. Weg, wenn die Auktion nicht verkauft wird.
--   Quelle: https://conquestcapped.com/guides/wow-forever/wow-forever-auction-house/ (Abzug laut Client-Tabellen
--   vom 13.11. geprüft; die Prozentwerte der Kaution sind dort als Classic-Regel genannt, im Spiel noch zu prüfen;
--   ähnliche Werte für Classic: https://www.wowhead.com/classic/guide/classic-auction-house-economy).
--   Retail (nur zum Vergleich, 12/24/48 Std.): https://warcraft.wiki.gg/wiki/Deposit_fee
-- Liefert der Client C_AuctionHouse.CalculateCommodityDeposit selbst einen Wert, gilt der (nur bei offenem AH).
local ABZUG = { Alliance = 0.05, Horde = 0.05, Neutral = 0.15 }
local KAUTION_ANTEIL = { [2] = 0.05, [8] = 0.20, [24] = 0.60 }
local KAUTION_NEUTRAL = 5
local KAUTION_HOCH = 0.20       -- Kaution über diesem Anteil des Gewinns: "Kaution hoch"
local SCAN_ABSTAND = 15 * 60    -- Sekunden zwischen Voll-Scans
local MAX_ITEMS = 40000         -- verschiedene Items pro Scan
local LESEN_PRO_BILD = 300      -- Angebote, die pro Bild gelesen werden
local RECHNEN_PRO_BILD = 600    -- Items, die pro Bild ausgewertet werden
local RUHE = 1.5                -- Sekunden ohne neue Ergebnisse, bevor gelesen wird
local ZEITLIMIT = 45            -- Sekunden Wartezeit auf das Auktionshaus
local MAX_SPEICHER = 6          -- gespeicherte Auktionshäuser (Realm und Fraktion)
local MIN_VERLAUF_PREIS = 50    -- Kupfer: billigere Items bekommen keinen Verlauf (spart Platz)
local MIN_SCANS = 3             -- Scans, bevor "günstig"/"zu teuer" gilt
local MIN_STUNDEN = 3           -- verschiedene Tagesstunden für Uhrzeit-Tipps
local VERLAUF_TAGE = 30         -- Items, die so lange fehlen, fliegen aus dem Verlauf
local TAGE_MAX = 30             -- Tage in der Preis-Grafik
local EIMER_MAX = 20            -- Proben pro Stunde; darüber wird halbiert (neuere zählen mehr)
local NORMAL_GEWICHT = 0.2      -- Gewicht des neuen Scans im Normalpreis (ab dem 4. Scan)
local NEUTRAL_ORTE = {
  ["Booty Bay"] = true, ["Gadgetzan"] = true, ["Everlook"] = true,
  ["Beutebucht"] = true, ["Ewige Warte"] = true,
}

local RGB = {
  gruen = { 0.25, 1, 0.25 },
  gelb  = { 1, 0.82, 0 },
  rot   = { 1, 0.25, 0.25 },
  grau  = { 0.6, 0.6, 0.6 },
}
AH.RGB = RGB

---------------------------------------------------------------------------
-- Kleine Hilfen
---------------------------------------------------------------------------
local issecret = issecretvalue or function() return false end
local function pass(ok, ...) if ok then return ... end end
local function try(f, ...)
  if type(f) ~= "function" then return nil end
  return pass(pcall(f, ...))
end
local function zahl(v)
  if v == nil or issecret(v) then return nil end
  v = tonumber(v)
  if not v or v ~= v or v < 0 then return nil end
  return v
end
local function imKampf() return InCombatLockdown and InCombatLockdown() and true or false end

local function einstellungen()
  return WW.db and WW.db.ah
end

local FRAKTION_DE = { Alliance = "Allianz", Horde = "Horde", Neutral = "neutral" }
local FRAKTION_NAME = { Alliance = "Fraktion", Horde = "Fraktion", Neutral = "Neutral" }

local function vor(sekunden)
  sekunden = tonumber(sekunden) or 0
  if sekunden < 90 then return "gerade eben" end
  if sekunden < 3600 then return ("vor %d Min."):format(math.floor(sekunden / 60 + 0.5)) end
  if sekunden < 2 * 86400 then return ("vor %d Std."):format(math.floor(sekunden / 3600 + 0.5)) end
  return ("vor %d Tagen"):format(math.floor(sekunden / 86400 + 0.5))
end

local meinRealm
local function realmName()
  if meinRealm then return meinRealm end
  local r = GetRealmName and GetRealmName()
  if type(r) ~= "string" or issecret(r) or r == "" then return nil end
  r = r:gsub("[%c|]", "")
  if r == "" then return nil end
  meinRealm = r
  return r
end

local function eigeneFraktion()
  local f = UnitFactionGroup and UnitFactionGroup("player")
  if f == "Alliance" or f == "Horde" then return f end
  return "Neutral"
end

-- Das Auktionshaus, an dem du stehst: Fraktion des Auktionators (Goblin = neutral), sonst Ort, sonst deine Seite.
local function ahFraktion()
  local f = try(UnitFactionGroup, "npc")
  if f == "Alliance" or f == "Horde" or f == "Neutral" then return f end
  if try(UnitExists, "npc") == true and f == nil then return "Neutral" end
  local ort = try(GetSubZoneText)
  if type(ort) == "string" and NEUTRAL_ORTE[ort] then return "Neutral" end
  return eigeneFraktion()
end

-- Inhalt eines Taschenplatzes: itemID, Anzahl, gebunden (oder nil bei leerem Platz)
local function slotInfo(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo then
    local info = try(C_Container.GetContainerItemInfo, bag, slot)
    if type(info) == "table" and info.itemID then
      return info.itemID, info.stackCount or 1, info.isBound and true or false
    end
    return nil
  end
  if GetContainerItemInfo then
    local _, anz, _, _, _, _, link, _, _, id, gebunden = try(GetContainerItemInfo, bag, slot)
    if not id and type(link) == "string" then id = tonumber(link:match("item:(%d+)")) end
    if id then return id, anz or 1, gebunden and true or false end
  end
  return nil
end

local function slotAnzahl(bag)
  local f = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
  return tonumber(try(f, bag)) or 0
end

-- Behälter-Nummern der Taschen und der Bank. Die Nummern kommen aus Enum.BagIndex, wenn es das gibt
-- (moderne Ordnung: Materialtasche 5, Bankfächer ab 6, Bank-Reiter); sonst aus den klassischen Zahlen.
-- Gemeinsam für alle Module (auch Inventar.lua ruft das erst zur Laufzeit auf).
local function indexZahl(name)
  local e = Enum and Enum.BagIndex
  local v = type(e) == "table" and e[name]
  return type(v) == "number" and v or nil
end

-- Liste der Taschen-Behälter: Rucksack, Taschen 1-4 und (falls vorhanden) die Materialtasche
function WW.TaschenIDs()
  local out = {}
  if indexZahl("Backpack") then
    out[1] = indexZahl("Backpack")
    for i = 1, 4 do
      local n = indexZahl("Bag_" .. i)
      if n then out[#out + 1] = n end
    end
    local r = indexZahl("ReagentBag")
    if r then out[#out + 1] = r end
    return out
  end
  local n = tonumber(NUM_TOTAL_EQUIPPED_BAG_SLOTS) or tonumber(NUM_BAG_SLOTS) or 4
  for bag = 0, n do out[#out + 1] = bag end
  return out
end

-- Liste der Bank-Behälter und eine Menge der Behälter, die eine eigene Tasche im Ausrüstungsplatz haben:
-- ids, mitTasche. Bank-Reiter (Enum.BagIndex.CharacterBankTab_n), wenn das Hauptfach keine Plätze hat
-- oder es keine Bankfächer (BankBag_n) gibt. Forever (17.11.): kein "Bank"/"BankBag_n" im Enum,
-- CharacterBankTab_1..9 = 6..14, Behälter -1 hat 32 leere Plätze (wird trotzdem mitgelesen).
function WW.BankIDs()
  local out, mitTasche = {}, {}
  local haupt = indexZahl("Bank") or -1
  local tab1 = indexZahl("CharacterBankTab_1")
  if tab1 and (slotAnzahl(haupt) == 0 or not indexZahl("BankBag_1")) then
    if slotAnzahl(haupt) > 0 then out[1] = haupt end
    for i = 1, 12 do
      local n = indexZahl("CharacterBankTab_" .. i)
      if not n then break end
      out[#out + 1] = n
    end
    return out, mitTasche
  end
  out[1] = haupt
  if indexZahl("BankBag_1") then
    for i = 1, 12 do
      local n = indexZahl("BankBag_" .. i)
      if not n then break end
      out[#out + 1] = n
      mitTasche[n] = true
    end
    return out, mitTasche
  end
  local erste = (tonumber(NUM_TOTAL_EQUIPPED_BAG_SLOTS) or tonumber(NUM_BAG_SLOTS) or 4) + 1
  for bag = erste, erste + (tonumber(NUM_BANKBAGSLOTS) or 7) - 1 do
    out[#out + 1] = bag
    mitTasche[bag] = true
  end
  return out, mitTasche
end

local function itemSymbol(id)
  local t = WW.GetItemIcon(id)
  return t or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function qualitaetsCode(q)
  local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q or 1]
  if c and c.r then
    return ("|cff%02x%02x%02x"):format(math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5), math.floor(c.b * 255 + 0.5))
  end
  return "|cffffffff"
end

local function setzeAktiv(knopf, an)
  if knopf.SetEnabled then knopf:SetEnabled(an and true or false)
  elseif an then knopf:Enable() else knopf:Disable() end
end

---------------------------------------------------------------------------
-- Preise nachschlagen
---------------------------------------------------------------------------
local function parse(s)
  if type(s) ~= "string" then return nil end
  local a, b, c = s:match("^(%d+),(%d+),(%d+)$")
  if not a then return nil end
  return tonumber(a), tonumber(b), tonumber(c)
end

local S   -- Scan-Zustand (unten gefüllt); hier schon bekannt, damit scanListe das offene Auktionshaus kennt

-- Schlüssel des Auktionshauses, an dem du gerade stehst ("Realm|Alliance/Horde/Neutral"), sonst nil
local function offenerSchluessel()
  if S and S.offen and S.fraktion then
    local r = realmName()
    if r then return r .. "|" .. S.fraktion end
  end
  return nil
end

-- Gespeicherte Scans dieses Realms: erst das offene Auktionshaus, dann deine Seite, dann neutral.
local function scanListe()
  local db = einstellungen()
  local realm = realmName()
  if not db or not realm then return {} end
  local liste, schon = {}, {}
  local function dazu(key)
    local st = db[key]
    if not schon[key] and type(st) == "table" and type(st.i) == "table" then
      schon[key] = true
      liste[#liste + 1] = st
    end
  end
  local offen = offenerSchluessel()
  if offen then dazu(offen) end
  local eigen = eigeneFraktion()
  dazu(realm .. "|" .. eigen)
  if eigen ~= "Neutral" then dazu(realm .. "|Neutral") end
  return liste
end

-- min, median, menge, alterInSekunden, speicher (Kupfer pro Stück) oder nil
local function preisUndSpeicher(itemID)
  itemID = tonumber(itemID)
  if not itemID then return nil end
  local liste = scanListe()
  for i = 1, #liste do
    local st = liste[i]
    local lo, med, menge = parse(st.i[itemID])
    if lo then return lo, med, menge, math.max(0, time() - (tonumber(st.t) or 0)), st end
  end
  return nil
end

-- min, median, menge, alterInSekunden  (Kupfer pro Stück) oder nil
function AH.Preis(itemID)
  local lo, med, menge, alter = preisUndSpeicher(itemID)
  return lo, med, menge, alter
end

-- Nach welchen Regeln würdest du verkaufen? Am offenen Auktionshaus gilt dessen Fraktion,
-- sonst die des Auktionshauses, aus dem der Preis stammt.
local function gebuehrFraktion(st)
  if S and S.offen and S.fraktion then return S.fraktion end
  if type(st) == "table" and ABZUG[st.f] then return st.f end
  return eigeneFraktion()
end

local kautionCache = {}
function AH.KautionCacheLeeren() kautionCache = {} end

-- Einstellgebühr (Kupfer) für anzahl Stück bei der eingestellten Laufzeit; zweiter Wert: "Client" oder "Formel"
function AH.Kaution(itemID, anzahl, fraktion)
  itemID = tonumber(itemID)
  anzahl = math.max(1, math.floor(tonumber(anzahl) or 1))
  if not itemID then return 0, "Formel" end
  local db = einstellungen()
  local dauer = db and tonumber(db.dauer) or 8
  if not KAUTION_ANTEIL[dauer] then dauer = 8 end
  fraktion = fraktion or eigeneFraktion()
  local offen = (S and S.offen) and "o" or "z"
  local key = itemID .. ":" .. anzahl .. ":" .. dauer .. ":" .. fraktion .. ":" .. offen
  local c = kautionCache[key]
  if c then return c[1], c[2] end
  local wert, quelle
  -- Der Client rechnet selbst (Handelswaren; Laufzeit-Nummer 1/2/3 = 2/8/24 Std.)
  local C = type(C_AuctionHouse) == "table" and C_AuctionHouse or nil
  if offen == "o" and C and type(C.CalculateCommodityDeposit) == "function" then
    local nr = (dauer == 2 and 1) or (dauer == 8 and 2) or 3
    local ok, v = pcall(C.CalculateCommodityDeposit, itemID, nr, anzahl)
    if ok and type(v) == "number" and v > 0 and v == v then wert, quelle = math.floor(v), "Client" end
  end
  if not wert then
    local verkauf = tonumber((select(11, WW.GetItemInfo(itemID)))) or 0
    local faktor = KAUTION_ANTEIL[dauer] * (fraktion == "Neutral" and KAUTION_NEUTRAL or 1)
    wert, quelle = math.max(1, math.floor(verkauf * anzahl * faktor)), "Formel"
  end
  kautionCache[key] = { wert, quelle }
  return wert, quelle
end

-- farbeSchluessel ("gruen"|"gelb"|"rot"|"grau"), kurztext, erloesAH, erloesHaendler, info
-- erloesAH = Preis nach dem Abzug des Auktionshauses (5 % oder neutral 15 %); info = { fraktion, abzug, kaution,
-- dauer, einheit } (Kaution: Einstellgebühr für diese Stückzahl, weg wenn nicht verkauft).
-- anzahl (Standard 1): Erlöse gelten für so viele Stück; gebunden = true: nicht handelbar.
function AH.Bewertung(itemID, anzahl, gebunden)
  itemID = tonumber(itemID)
  anzahl = math.max(1, math.floor(tonumber(anzahl) or 1))
  if not itemID then return "grau", "kein AH-Preis", 0, 0 end
  local _, _, _, _, _, _, _, _, _, _, verkauf, _, _, bindTyp = WW.GetItemInfo(itemID)
  local haendler = (verkauf or 0) * anzahl
  if gebunden or bindTyp == 1 or bindTyp == 4 then return "grau", "gebunden", 0, haendler end
  local lo, med, _, _, st = preisUndSpeicher(itemID)
  local einheit = (med and med > 0) and med or lo
  if not einheit or einheit <= 0 then return "grau", "kein AH-Preis", 0, haendler end
  local fraktion = gebuehrFraktion(st)
  local abzug = ABZUG[fraktion] or 0.05
  local erloes = math.floor(einheit * anzahl * (1 - abzug))
  local db = einstellungen()
  local info = { fraktion = fraktion, abzug = abzug, einheit = einheit, dauer = db and tonumber(db.dauer) or 8 }
  if verkauf == nil then return "grau", "lädt", erloes, 0, info end
  info.kaution = AH.Kaution(itemID, anzahl, fraktion)
  local faktor = db and tonumber(db.faktor) or 1.5
  local mindest = db and tonumber(db.mindestGewinn) or 2000
  if erloes > haendler then
    if erloes >= haendler * faktor and erloes - haendler >= mindest then
      if info.kaution > (erloes - haendler) * KAUTION_HOCH then
        return "gelb", "Kaution hoch", erloes, haendler, info
      end
      return "gruen", "AH lohnt", erloes, haendler, info
    end
    return "gelb", "knapp", erloes, haendler, info
  end
  return "rot", "Händler", erloes, haendler, info
end

---------------------------------------------------------------------------
-- Preisverlauf: Normalpreis, günstig / zu teuer, Uhrzeit-Tipps
---------------------------------------------------------------------------
local function runden(x) return math.floor(x + 0.5) end

local function verlaufTabelle(key, anlegen)
  local v = WW.db and WW.db.ahVerlauf
  if type(v) ~= "table" or not key then return nil end
  local t = v[key]
  if type(t) ~= "table" and anlegen then t = {}; v[key] = t end
  return type(t) == "table" and t or nil
end

local function speicherSchluessel(st)
  return tostring(st.r or "?") .. "|" .. tostring(st.f or "?")
end

-- "normal,scans,stunde,normalMin;h:summe:n,..." -> normal, scans, stunde, eimer ({ [h] = { summe, n } }), normalMin
-- normal = Durchschnitt der Mediane (Anzeige "Normalpreis"), normalMin = Durchschnitt der Mindestpreise
-- (Vergleichsbasis für günstig / zu teuer). Alte Einträge ohne normalMin: normalMin = nil.
local function verlaufLesen(s)
  if type(s) ~= "string" then return nil end
  local normal, scans, stunde, nm, rest = s:match("^(%d+),(%d+),(%d+),?(%d*);?(.*)$")
  if not normal then return nil end
  local eimer = {}
  for h, summe, n in rest:gmatch("(%d+):(%d+):(%d+)") do
    h = tonumber(h)
    if h <= 23 then eimer[h] = { tonumber(summe), tonumber(n) } end
  end
  return tonumber(normal), tonumber(scans), tonumber(stunde), eimer, tonumber(nm)
end

local function verlaufSchreiben(normal, scans, stunde, eimer, normalMin)
  local kopf
  if normalMin then kopf = ("%.0f,%d,%d,%.0f"):format(normal, scans, stunde, normalMin)
  else kopf = ("%.0f,%d,%d"):format(normal, scans, stunde) end
  local teile
  for h = 0, 23 do
    local b = eimer[h]
    if b and b[2] > 0 then
      teile = teile or {}
      teile[#teile + 1] = ("%d:%.0f:%d"):format(h, b[1], b[2])
    end
  end
  if teile then return kopf .. ";" .. table.concat(teile, ",") end
  return kopf
end

---------------------------------------------------------------------------
-- Tagespreise (Grafik "Preisverlauf")
---------------------------------------------------------------------------
local function tageTabelle(key, anlegen)
  local v = WW.db and WW.db.ahTage
  if type(v) ~= "table" and anlegen and WW.db then v = {}; WW.db.ahTage = v end
  if type(v) ~= "table" or not key then return nil end
  local t = v[key]
  if type(t) ~= "table" and anlegen then t = {}; v[key] = t end
  return type(t) == "table" and t or nil
end

-- Tagesnummer des Kalendertags (Ortszeit). Mittag statt Mitternacht: Sommerzeit verschiebt nichts.
local function tagNummer(zeit)
  local t = date("*t", zeit or time())
  return math.floor(time({ year = t.year, month = t.month, day = t.day, hour = 12 }) / 86400)
end
AH.TagNummer = tagNummer

-- "tag:preis,..." -> { { tag, preis }, ... } (aufsteigend)
local function tageLesen(s)
  local out = {}
  if type(s) ~= "string" then return out end
  for tag, preis in s:gmatch("(%d+):(%d+)") do out[#out + 1] = { tonumber(tag), tonumber(preis) } end
  return out
end

-- Mindestpreis für heute buchen: gleicher Tag -> der kleinere Preis bleibt.
-- Sonst neu aufbauen: nur Tage im Fenster (heute - 29 bis heute), jeder Tag einmal, aufsteigend.
-- So bleibt der Eintrag klein, auch wenn die PC-Uhr einmal vor- oder zurückging.
local function tageBuchen(tg, id, tag, preis)
  preis = math.floor((tonumber(preis) or 0) + 0.5)
  tag = tonumber(tag)
  if preis <= 0 or not tag then return end
  local s = tg[id]
  if type(s) == "string" and s ~= "" then
    -- schneller Weg: mehrere Scans am selben Tag
    local kopf, letzterTag, letzterPreis = s:match("^(.-)(%d+):(%d+)$")
    if tonumber(letzterTag) == tag then
      if preis < tonumber(letzterPreis) then tg[id] = kopf .. tag .. ":" .. preis end
      return
    end
  end
  local grenze = tag - TAGE_MAX + 1
  local proTag = { [tag] = preis }
  for _, e in ipairs(tageLesen(s)) do
    local t, p = e[1], e[2]
    if t >= grenze and t <= tag and p > 0 and (not proTag[t] or p < proTag[t]) then proTag[t] = p end
  end
  local tage = {}
  for t in pairs(proTag) do tage[#tage + 1] = t end
  table.sort(tage)
  local teile = {}
  for i, t in ipairs(tage) do teile[i] = t .. ":" .. proTag[t] end
  tg[id] = table.concat(teile, ",")
end
AH.TageBuchen = tageBuchen   -- für Tests

-- Eine Probe (Mindestpreis) in die Tagesstunde buchen.
local function probeBuchen(eimer, stunde, preis)
  local b = eimer[stunde]
  if not b then b = { 0, 0 }; eimer[stunde] = b end
  b[1], b[2] = b[1] + preis, b[2] + 1
  if b[2] > EIMER_MAX then
    b[1] = b[1] / b[2] * (EIMER_MAX / 2)
    b[2] = EIMER_MAX / 2
  end
end

-- Ein Scan-Ergebnis für ein Item buchen: Normalpreis nachziehen, Stunden-Probe, Zeitstempel.
-- Höchstens eine Probe pro Item und Stunde. stempel = Stunden seit 1970, stunde = Tagesstunde (Ortszeit).
local function mittelnach(alt, scans, neu)
  if not alt or scans == 0 then return neu end
  if scans < MIN_SCANS then return (alt * scans + neu) / (scans + 1) end
  return alt * (1 - NORMAL_GEWICHT) + neu * NORMAL_GEWICHT
end

local function verlaufBuchen(vl, id, lo, med, stempel, stunde)
  local normal, scans, letzte, eimer, normalMin = verlaufLesen(vl[id])
  if not normal then
    if med < MIN_VERLAUF_PREIS then return end
    normal, scans, letzte, eimer, normalMin = med, 0, 0, {}, nil
  end
  normal = mittelnach(normal, scans, med)
  -- alter Eintrag ohne normalMin: beginnt mit dem Mindestpreis dieses Scans
  normalMin = mittelnach(normalMin, scans, lo)
  scans = math.min(scans + 1, 9999)
  if letzte ~= stempel then probeBuchen(eimer, stunde, lo) end
  vl[id] = verlaufSchreiben(normal, scans, stempel, eimer, normalMin)
end

-- Leichte Zusatzprobe aus Blizzards Suchergebnissen (Normalpreis und Scan-Zahl bleiben).
-- Nur für Items, die schon einen Verlauf haben.
local function probeAusSuche(vl, id, preis, stempel, stunde, tg)
  local normal, scans, letzte, eimer, normalMin = verlaufLesen(vl[id])
  if normal and tg then tageBuchen(tg, id, tagNummer(), preis) end
  if not normal or letzte == stempel then return end
  probeBuchen(eimer, stunde, preis)
  vl[id] = verlaufSchreiben(normal, scans, stempel, eimer, normalMin)
end

-- Verläufe ohne gespeicherten Scan entfernen; einmal pro Tag Items, die länger als VERLAUF_TAGE fehlen.
local function verlaufAufraeumen(db, jetztStempel)
  local alle = WW.db and WW.db.ahVerlauf
  if type(alle) ~= "table" then return end
  local grenze = jetztStempel - VERLAUF_TAGE * 24
  local gruendlich = (tonumber(db.bereinigt) or 0) + 86400 <= time()
  for key, vl in pairs(alle) do
    if type(db[key]) ~= "table" or type(vl) ~= "table" then
      alle[key] = nil
    elseif gruendlich then
      for id, s in pairs(vl) do
        local letzte = type(s) == "string" and tonumber(s:match("^%d+,%d+,(%d+)"))
        if not letzte or letzte < grenze then vl[id] = nil end
      end
    end
  end
  -- Tagespreise: nur für Auktionshäuser und Items, die noch einen Verlauf haben
  local tage = WW.db and WW.db.ahTage
  if type(tage) == "table" then
    for key, tg in pairs(tage) do
      local vl = type(alle[key]) == "table" and alle[key] or nil
      if not vl or type(tg) ~= "table" then
        tage[key] = nil
      elseif gruendlich then
        for id in pairs(tg) do if not vl[id] then tg[id] = nil end end
      end
    end
  end
  if gruendlich then db.bereinigt = time() end
end

-- normal, scans, stunde, eimer, speicher, normalMin für ein Item.
-- key (optional): "Realm|Fraktion". Ohne key: am offenen Auktionshaus nur dessen Verlauf (neutrale und Fraktions-Preise
-- unterscheiden sich), sonst der erste Scan-Speicher, der das Item kennt.
local function verlaufFuer(itemID, key)
  key = key or offenerSchluessel()
  if key then
    local vl = verlaufTabelle(key)
    local normal, scans, stunde, eimer, nm = verlaufLesen(vl and vl[itemID])
    if normal then
      local db = einstellungen()
      return normal, scans, stunde, eimer, db and db[key], nm
    end
    return nil
  end
  local liste = scanListe()
  for i = 1, #liste do
    local vl = verlaufTabelle(speicherSchluessel(liste[i]))
    local normal, scans, stunde, eimer, nm = verlaufLesen(vl and vl[itemID])
    if normal then return normal, scans, stunde, eimer, liste[i], nm end
  end
  return nil
end

-- Urteil für einen Mindestpreis: "guenstig", "teuer" oder nil; dazu Abweichung (-0.35 = 35 % unter dem üblichen
-- Mindestpreis), Normalpreis (Median-Durchschnitt), Scans, üblicher Mindestpreis. Verglichen wird mit dem
-- üblichen MINDESTpreis (normalMin), nicht mit dem Median. Das Urteil gilt erst ab MIN_SCANS Scans und wenn
-- der Eintrag einen üblichen Mindestpreis hat. key (optional): "Realm|Fraktion".
function AH.PreisUrteil(itemID, preis, key)
  itemID, preis = tonumber(itemID), tonumber(preis)
  if not itemID or not preis or preis <= 0 then return nil end
  local normal, scans, _, _, _, nm = verlaufFuer(itemID, key)
  if not normal or normal <= 0 then return nil end
  if not nm or nm <= 0 then return nil, nil, normal, scans end
  local abw = preis / nm - 1
  local urteil
  if scans >= MIN_SCANS then
    local db = einstellungen()
    local lo = db and tonumber(db.schnaeppchen) or 0.7
    local hi = db and tonumber(db.zuTeuer) or 1.3
    if preis <= nm * lo then urteil = "guenstig"
    elseif preis >= nm * hi then urteil = "teuer" end
  end
  return urteil, abw, normal, scans, nm
end

-- Alles zu einem Item aus dem letzten Scan und dem Verlauf, oder nil (kein Preis bekannt):
-- { min, median, menge, alter, normal, normalMin, scans, abw, urteil, eimer }
function AH.Analyse(itemID)
  local lo, med, menge, alter = AH.Preis(itemID)
  if not lo then return nil end
  local a = { min = lo, median = med, menge = menge, alter = alter }
  local normal, scans, _, eimer, _, nm = verlaufFuer(itemID)
  if normal then
    a.normal, a.scans, a.eimer, a.normalMin = normal, scans, eimer, nm
    a.urteil, a.abw = AH.PreisUrteil(itemID, lo)
  end
  return a
end

-- Günstigstes und teuerstes 3-Stunden-Fenster (Startstunden) und deren mittlere Preise.
-- Ohne genug Daten: nil, anzahlStunden.
local function zeitFenster(eimer)
  local preis, n = {}, 0
  for h = 0, 23 do
    local b = eimer[h]
    if b and b[2] > 0 then preis[h] = b[1] / b[2]; n = n + 1 end
  end
  if n < MIN_STUNDEN then return nil, n end
  local kauf, kaufP, verk, verkP
  for h = 0, 23 do
    if preis[h] then
      local summe, anz = 0, 0
      for d = 0, 2 do
        local x = preis[(h + d) % 24]
        if x then summe = summe + x; anz = anz + 1 end
      end
      local mittel = summe / anz
      if not kaufP or mittel < kaufP then kauf, kaufP = h, mittel end
      if not verkP or mittel > verkP then verk, verkP = h, mittel end
    end
  end
  return kauf, verk, kaufP, verkP
end

-- Text mit Uhrzeit-Tipps und ok (true = echte Tipps, false = zu wenig Daten oder kaum Schwankung)
function AH.ZeitTipp(itemID)
  local normal, scans, _, eimer = verlaufFuer(itemID)
  local wenig = "Noch zu wenig Daten für Uhrzeit-Tipps – öfter zu verschiedenen Zeiten scannen."
  if not normal then return wenig, false end
  local kauf, verk, kaufP, verkP = zeitFenster(eimer)
  if not kauf then return wenig, false end
  if verkP <= kaufP * 1.05 then
    return ("Der Preis schwankt über den Tag kaum (aus %d Scans)."):format(scans), false
  end
  return ("Kaufen am günstigsten: ca. %02d–%02d Uhr · Verkaufen am besten: ca. %02d–%02d Uhr (aus %d Scans)"):format(
    kauf, (kauf + 3) % 24, verk, (verk + 3) % 24, scans), true
end

-- Daten für die Grafik: { tage = { {tag, preis}, ... }, stunden = { [0..23] = mittlerer Mindestpreis },
-- normalMin, heute } oder nil (kein Verlauf). Gleicher Speicher wie die übrigen Preise (offenes AH zuerst).
function AH.Grafikdaten(itemID)
  itemID = tonumber(itemID)
  if not itemID then return nil end
  local normal, scans, _, eimer, speicher, nm = verlaufFuer(itemID)
  if not normal then return nil end
  -- gleicher Speicher wie verlaufFuer: offenes Auktionshaus, sonst der Scan-Speicher, der das Item kennt
  local key = offenerSchluessel() or (type(speicher) == "table" and speicherSchluessel(speicher)) or nil
  local tg = tageTabelle(key)
  local stunden = {}
  for h = 0, 23 do
    local b = eimer and eimer[h]
    if b and b[2] > 0 then stunden[h] = b[1] / b[2] end
  end
  return { tage = tageLesen(tg and tg[itemID]), stunden = stunden, normalMin = nm, normal = normal,
    scans = scans, heute = tagNummer() }
end

-- Listen für den Reiter: Items, deren Mindestpreis aus dem letzten Scan weit unter ("guenstig") oder über
-- ("teuer") dem üblichen Mindestpreis liegt. Einträge: { id, preis, normal (= üblicher Mindestpreis), menge, abw, diff }.
-- Gibt liste, anzahlMitGenugScans zurück.
local function marktListe(art)
  local st = scanListe()[1]
  local out, bereit = {}, 0
  if not st then return out, 0 end
  local vl = verlaufTabelle(speicherSchluessel(st))
  if not vl then return out, 0 end
  local db = einstellungen()
  local lo = db and tonumber(db.schnaeppchen) or 0.7
  local hi = db and tonumber(db.zuTeuer) or 1.3
  for id, eintrag in pairs(st.i) do
    local s = vl[id]
    if s then
      local scans, nm = s:match("^%d+,(%d+),%d+,(%d+)")
      local normal = tonumber(nm)   -- üblicher Mindestpreis (alte Einträge ohne ihn zählen erst nach dem nächsten Scan)
      scans = tonumber(scans)
      if normal and scans and scans >= MIN_SCANS and normal > 0 then
        bereit = bereit + 1
        local preis, _, menge = parse(eintrag)
        if preis and preis > 0 then
          local treffer
          if art == "guenstig" then treffer = preis <= normal * lo else treffer = preis >= normal * hi end
          if treffer then
            out[#out + 1] = { id = id, preis = preis, normal = normal, menge = menge or 0,
              abw = preis / normal - 1, diff = math.abs(normal - preis) }
          end
        end
      end
    end
  end
  table.sort(out, function(a, b)
    if a.diff ~= b.diff then return a.diff > b.diff end
    return a.id < b.id
  end)
  for i = #out, 2001, -1 do out[i] = nil end
  return out, bereit
end
function AH.Schnaeppchen() return marktListe("guenstig") end

-- Kleinschreibung mit deutschen Umlauten (string.lower kennt nur A-Z)
function WW.Klein(t)
  return (tostring(t or ""):lower():gsub("\195\132", "\195\164"):gsub("\195\150", "\195\182"):gsub("\195\156", "\195\188"))
end

-- Filter-Fenster für "Schnäppchen" (wie Blizzards Filter): Seltenheit, Stufe, nur nutzbare.
-- Graue Items und weiße Waffen/Rüstungen sind meist Händler-Müll: ihr "üblicher" AH-Preis kommt von
-- Angeboten, die keiner kauft. Darum sind sie am Anfang aus.
AH.SELTENHEIT = { [0] = "Schlecht", "Verbreitet", "Selten", "Rar", "Episch", "Legendär" }
local Q_STANDARD = { [0] = false, true, true, true, true, true }

-- Filter-Einstellungen mit Standardwerten. Alte Einstellung "qualitaet" (Knopf "Zeige: ...") wird übernommen.
function AH.FilterEinst(mf)
  if type(mf.q) ~= "table" then
    mf.q = {}
    for i = 0, 5 do mf.q[i] = Q_STANDARD[i] end
    mf.weissAus = true
    local alt = mf.qualitaet
    if alt == "alle" then mf.q[0], mf.weissAus = true, false
    elseif alt == "ohneGrau" then mf.weissAus = false
    elseif alt == "abGruen" then mf.q[1] = false end
    mf.qualitaet = nil
  end
  if mf.weissAus == nil then mf.weissAus = true end
  return mf
end

-- Wie viele Filter schränken die Liste ein? (für die Aufschrift "Filter (n)")
function AH.FilterAnzahl(mf)
  AH.FilterEinst(mf)
  local n = 0
  for i = 0, 5 do if not mf.q[i] then n = n + 1 end end
  if mf.weissAus then n = n + 1 end
  if tonumber(mf.stufeVon) or tonumber(mf.stufeBis) then n = n + 1 end
  if mf.nutzbar then n = n + 1 end
  return n
end

-- Darf das Item in die Liste? Unbekannte Werte (Item noch nicht im Cache) lassen es durch.
function AH.FilterPasst(id, mf)
  AH.FilterEinst(mf)
  local ok, _, _, q, _, minStufe, _, _, _, _, _, _, klasse = pcall(WW.GetItemInfo, id)
  q, minStufe = ok and tonumber(q) or nil, ok and tonumber(minStufe) or nil
  if q and q >= 0 and q <= 5 and mf.q[q] == false then return false end
  local von, bis = tonumber(mf.stufeVon), tonumber(mf.stufeBis)
  if minStufe and ((von and minStufe < von) or (bis and minStufe > bis)) then return false end
  if mf.weissAus and q == 1 then
    klasse = ok and tonumber(klasse) or nil
    if not klasse then
      local gii = C_Item and C_Item.GetItemInfoInstant
      if type(gii) == "function" then
        local ok2, _, _, _, _, _, k = pcall(gii, id)
        klasse = ok2 and tonumber(k) or nil
      end
    end
    if klasse == 2 or klasse == 4 then return false end   -- weiße Waffe (2) oder Rüstung (4)
  end
  if mf.nutzbar and WW.QW and WW.QW.KannTragen then
    local ok3, kann = pcall(WW.QW.KannTragen, id)
    if ok3 and kann == false then return false end   -- nil = kein Ausrüstungsteil: bleibt
  end
  return true
end

-- Kategorien wie in Blizzards Auktionshaus (Waffen, Rüstung, Handwerkswaren > Stoff ...).
-- Am besten Blizzards eigene Liste AuctionCategories (nur gelesen, nie geändert; da, sobald das AH einmal
-- offen war). Sonst eine eigene aus den Item-Klassen des Clients.
-- Baum: { { name, filter = { {klasse, unterklasse, platz}, ... }, kinder = { ... } }, ... }
local KLASSEN = { 2, 4, 1, 0, 7, 6, 11, 9, 12, 15 }   -- Reihenfolge wie bei Blizzard
local KLASSE_DE = { [0] = "Verbrauchbare Gegenstände", [1] = "Behälter", [2] = "Waffen", [4] = "Rüstung",
  [6] = "Munition", [7] = "Handwerkswaren", [9] = "Rezepte", [11] = "Köcher", [12] = "Questgegenstände",
  [15] = "Verschiedenes" }
local katBaum, katQuelle

local function filterAus(f)
  local raus = {}
  for _, x in ipairs(type(f) == "table" and f or {}) do
    if type(x) == "table" and tonumber(x.classID) then
      raus[#raus + 1] = { tonumber(x.classID), tonumber(x.subClassID), tonumber(x.inventoryType) }
    end
  end
  return raus
end

local function ausBlizzard(liste, tiefe)
  local raus = {}
  for _, k in ipairs(liste) do
    if type(k) == "table" and type(k.name) == "string" then
      local knoten = { name = k.name, filter = filterAus(k.filters) }
      if tiefe < 2 and type(k.subCategories) == "table" then knoten.kinder = ausBlizzard(k.subCategories, tiefe + 1) end
      -- Oberkategorie ohne eigene Filter: Filter der Kinder zusammen
      if #knoten.filter == 0 and knoten.kinder then
        for _, kind in ipairs(knoten.kinder) do
          for _, f in ipairs(kind.filter) do knoten.filter[#knoten.filter + 1] = f end
        end
      end
      if #knoten.filter > 0 then raus[#raus + 1] = knoten end
    end
  end
  return raus
end

local function eigenerBaum()
  local klassenName = (C_Item and C_Item.GetItemClassInfo) or rawget(_G, "GetItemClassInfo")
  local unterName = (C_Item and C_Item.GetItemSubClassInfo) or rawget(_G, "GetItemSubClassInfo")
  local raus = {}
  for _, c in ipairs(KLASSEN) do
    local ok, n = false, nil
    if type(klassenName) == "function" then ok, n = pcall(klassenName, c) end
    local knoten = { name = (ok and type(n) == "string" and n ~= "") and n or KLASSE_DE[c], filter = { { c } } }
    if type(unterName) == "function" then
      local kinder = {}
      for s = 0, 20 do
        local ok2, un = pcall(unterName, c, s)
        if ok2 and type(un) == "string" and un ~= "" then kinder[#kinder + 1] = { name = un, filter = { { c, s } } } end
      end
      if #kinder > 1 then knoten.kinder = kinder end
    end
    raus[#raus + 1] = knoten
  end
  return raus
end

-- Baum der Kategorien und Quelle ("blizzard" | "eigen"). Blizzards Liste wird genommen, sobald es sie gibt.
function AH.Kategorien()
  if katQuelle ~= "blizzard" then
    local b = rawget(_G, "AuctionCategories")
    if type(b) == "table" and #b > 0 then
      local ok, baum = pcall(ausBlizzard, b, 1)
      if ok and #baum > 0 then katBaum, katQuelle = baum, "blizzard" end
    end
  end
  if not katBaum then katBaum, katQuelle = eigenerBaum(), "eigen" end
  return katBaum, katQuelle
end
function AH.KategorienNeu() katBaum, katQuelle = nil, nil end   -- für Tests

-- Kategorie aus dem gespeicherten Pfad "Name" oder "Name/Unterkategorie", oder nil (= alle)
function AH.KategorieVon(pfad)
  if type(pfad) ~= "string" or pfad == "" then return nil end
  local oben, unten = pfad:match("^([^/]+)/?(.*)$")
  for _, k in ipairs((AH.Kategorien())) do
    if k.name == oben then
      if unten == "" then return k end
      for _, kind in ipairs(k.kinder or {}) do if kind.name == unten then return kind end end
      return k   -- Unterkategorie gibt es nicht mehr: Oberkategorie
    end
  end
  return nil
end

-- Klasse, Unterklasse, Platz (Inventartyp) eines Items, oder nil (unbekannt)
local function itemKlasse(id)
  local gii = C_Item and C_Item.GetItemInfoInstant
  local klasse, unter
  if type(gii) == "function" then
    local ok, _, _, _, _, _, k, u = pcall(gii, id)
    if ok then klasse, unter = tonumber(k), tonumber(u) end
  end
  if not klasse then
    local ok, _, _, _, _, _, _, _, _, _, _, _, k, u = pcall(WW.GetItemInfo, id)
    if ok then klasse, unter = tonumber(k), tonumber(u) end
  end
  local platz
  local git = C_Item and C_Item.GetItemInventoryTypeByID
  if type(git) == "function" then
    local ok, p = pcall(git, id)
    if ok then platz = tonumber(p) end
  end
  return klasse, unter, platz
end

-- Gehört das Item zur Kategorie? Ohne Kategorie: ja. Unbekannte Klasse: ja (lieber zeigen als verstecken).
function AH.KategoriePasst(id, kat)
  if not kat then return true end
  local klasse, unter, platz = itemKlasse(id)
  if not klasse then return true end
  for _, f in ipairs(kat.filter or {}) do
    if f[1] == klasse and (f[2] == nil or f[2] == unter) and (f[3] == nil or platz == nil or f[3] == platz) then
      return true
    end
  end
  return false
end

-- Filter der Ansichten "Schnäppchen" / "Zu teuer" (Einstellungen in WW.db.ah.markt)
function AH.MarktFiltern(liste, ansicht, text)
  local db = einstellungen()
  local mf = db and type(db.markt) == "table" and db.markt or {}
  local gm = rawget(_G, "GetMoney")
  local okG, wertG = false, nil
  if type(gm) == "function" then okG, wertG = pcall(gm) end
  local gold = okG and tonumber(wertG) or nil
  local ersparnis = (tonumber(mf.ersparnis) or 0) / 100
  local besitz = (ansicht == "teuer" and mf.nurMeine and WW.AHHandel) and WW.AHHandel.BesitzAlle() or nil
  local kat = AH.KategorieVon(mf.kategorie)   -- nil = alle Kategorien
  text = WW.Klein(text or "")
  local raus = {}
  for _, e in ipairs(liste) do
    local ok = true
    if text ~= "" then
      local name = WW.Klein(WW.ItemName(e.id) or "")
      local en = WW.quelle and WW.quelle.fdb and WW.quelle.fdb.searchItemNames and WW.quelle.fdb.searchItemNames[e.id]
      ok = name:find(text, 1, true) or (type(en) == "string" and WW.Klein(en):find(text, 1, true)) or tostring(e.id) == text
    end
    if ok and ansicht == "schnaeppchen" then
      if mf.bezahlbar and gold and e.preis > gold then ok = false end
      if ok and ersparnis > 0 and -(e.abw or 0) < ersparnis then ok = false end
      if ok and not AH.FilterPasst(e.id, mf) then ok = false end
    end
    if ok and besitz then ok = (besitz[e.id] or 0) > 0 end
    if ok and kat and not AH.KategoriePasst(e.id, kat) then ok = false end
    if ok then raus[#raus + 1] = e end
  end
  return raus
end
function AH.ZuTeuer() return marktListe("teuer") end

-- Ansicht "Verkaufen": alle ungebundenen Items in den Taschen mit AH-Preis.
-- Einträge: { id, preis (Vorschlag je Stück), normal (üblicher Mindestpreis), menge, boden (Untergrenze je Stück),
--   erloes (alle, nach Abzug und Kaution), haendler (alle), farbe, text, zurGrenze (Vorschlag = Untergrenze) }.
-- Untergrenze: BODEN_ANTEIL vom üblichen Mindestpreis, nie weniger als beim Händler (nach Abzug und Kaution).
-- mf.nurLohnt (Standard an): nur grün/gelb. mf.geschuetzt: auch Items, die das Urteil behalten will.
local BODEN_ANTEIL = 0.8
AH.BODEN_ANTEIL = BODEN_ANTEIL
function AH.VerkaufListe(mf)
  mf = mf or {}
  local out = {}
  local H = WW.AHHandel
  if not (H and H.BesitzAlle) then return out end
  local ok, besitz = pcall(H.BesitzAlle)
  if not ok or type(besitz) ~= "table" then return out end
  local U = WW.Urteil
  for id, anzahl in pairs(besitz) do
    local lo = AH.Preis(id)
    local geschuetzt = U and U.Geschuetzt and select(2, pcall(U.Geschuetzt, id)) == true
    if lo and lo > 0 and anzahl > 0 and (mf.geschuetzt or not geschuetzt) then
      local farbe, text, _, haendler, info = AH.Bewertung(id, anzahl, false)
      local lohnt = farbe == "gruen" or farbe == "gelb"
      if farbe ~= "grau" and type(info) == "table" and (lohnt or mf.nurLohnt == false) then
        local _, _, _, _, _, nm = verlaufFuer(id)
        nm = (tonumber(nm) and nm > 0) and nm or lo
        local abzug = tonumber(info.abzug) or 0.05
        local kaution = tonumber(info.kaution) or 0
        local verkaufStueck = (tonumber(haendler) or 0) / anzahl
        local boden = math.max(math.floor(nm * BODEN_ANTEIL),
          math.ceil((verkaufStueck + kaution / anzahl) / (1 - abzug)))
        local vorschlag = H.EinstellPreis and H.EinstellPreis(lo) or lo
        local zurGrenze = false
        if not vorschlag or vorschlag < boden then
          vorschlag = H.GrenzPreis and H.GrenzPreis(boden) or boden
          zurGrenze = true
        end
        -- scanMin = roher Mindestpreis aus dem Scan (preis ist schon der Vorschlag, 1 Silber darunter)
        out[#out + 1] = { id = id, preis = vorschlag, scanMin = lo, normal = nm, menge = anzahl, boden = boden,
          erloes = math.floor(vorschlag * anzahl * (1 - abzug)) - kaution, haendler = haendler or 0,
          farbe = farbe, text = text, zurGrenze = zurGrenze, geschuetzt = geschuetzt }
      end
    end
  end
  table.sort(out, function(a, b)
    local ga, gb = a.erloes - a.haendler, b.erloes - b.haendler
    if ga ~= gb then return ga > gb end
    return a.id < b.id
  end)
  return out
end

-- Wie oft wurde zu welcher Tagesstunde gescannt? { [0..23] = anzahl }
function AH.ScanStunden()
  local db = einstellungen()
  return db and type(db.scanStunden) == "table" and db.scanStunden or {}
end

---------------------------------------------------------------------------
-- Scan
---------------------------------------------------------------------------
S = { phase = "leer", offen = false, fertig = 0, gesamt = 0 }
AH.Status = S
local fahrer = CreateFrame("Frame")
local agg, schluesselZahl            -- itemID -> { u = { {preisProStueck, anzahl}, ... }, menge }
local verstrichen = 0
local zuhoerer = {}

local function benachrichtige()
  for i = 1, #zuhoerer do pcall(zuhoerer[i]) end
end

local function api()
  local C = type(C_AuctionHouse) == "table" and C_AuctionHouse or nil
  if C and type(C.ReplicateItems) == "function" and type(C.GetNumReplicateItems) == "function"
     and type(C.GetReplicateItemInfo) == "function" then
    return "replicate"
  end
  -- Ersatz für Classic-Clients (Forever hat diese alten Funktionen nicht)
  if WW.Alt("QueryAuctionItems") and WW.Alt("GetNumAuctionItems") and WW.Alt("GetAuctionItemInfo") then
    return "getall"
  end
  return nil
end

-- Sekunden bis zum nächsten erlaubten Voll-Scan (0 = jetzt)
function AH.Wartezeit()
  local db = einstellungen()
  local letzter = db and tonumber(db.letzterScan) or 0
  return math.max(0, letzter + SCAN_ABSTAND - time())
end

local function laeuft() return S.phase == "warten" or S.phase == "lesen" or S.phase == "rechnen" end
function AH.Laeuft() return laeuft() end
function AH.Offen() return S.offen end

local function scheitern(text)
  agg = nil
  S.phase, S.meldung, S.pause = "fehler", text, false
  S.vl = nil
  fahrer:SetScript("OnUpdate", nil)
  benachrichtige()
end

local function hinzu(id, anz, kauf)
  id, anz, kauf = zahl(id), zahl(anz), zahl(kauf)
  if not id or id < 1 or id > 10000000 or id % 1 ~= 0 or not anz or anz < 1 then return end
  anz = math.min(math.floor(anz), 10000)
  local a = agg[id]
  if not a then
    if schluesselZahl >= MAX_ITEMS then return end
    schluesselZahl = schluesselZahl + 1
    a = { u = {}, menge = 0 }
    agg[id] = a
  end
  a.menge = a.menge + anz
  if kauf and kauf > 0 then
    local u = a.u
    u[#u + 1] = { kauf / anz, anz }
  end
end

-- niedrigster und mittlerer Preis (jedes Stück zählt einzeln)
local function zusammenfassen(a)
  local u = a.u
  table.sort(u, function(x, y) return x[1] < y[1] end)
  local gesamt = 0
  for i = 1, #u do gesamt = gesamt + u[i][2] end
  local halb, lauf, med = gesamt / 2, 0, u[#u][1]
  for i = 1, #u do
    lauf = lauf + u[i][2]
    if lauf >= halb then med = u[i][1]; break end
  end
  return math.max(1, math.floor(u[1][1] + 0.5)), math.max(1, math.floor(med + 0.5))
end

local function bereinigen(db)
  local liste = {}
  for k, v in pairs(db) do
    if type(k) == "string" and k:find("|", 1, true) and type(v) == "table" then
      liste[#liste + 1] = { k, tonumber(v.t) or 0 }
    end
  end
  if #liste > MAX_SPEICHER then
    table.sort(liste, function(x, y) return x[2] > y[2] end)
    for i = MAX_SPEICHER + 1, #liste do db[liste[i][1]] = nil end
  end
end

local function abschliessen()
  local db = einstellungen()
  local zaehler = S.zaehler or 0
  agg = nil
  S.ids = nil
  if not db then return scheitern("Die Daten sind noch nicht geladen.") end
  if zaehler == 0 then
    return scheitern("Keine Angebote mit Sofortkaufpreis gefunden. Es wurde nichts gespeichert.")
  end
  local key = S.realm .. "|" .. S.scanFraktion
  db[key] = { r = S.realm, f = S.scanFraktion, t = time(), n = S.gesamt, z = zaehler, m = S.modus, i = S.items }
  bereinigen(db)
  S.items, S.vl, S.tg = nil, nil, nil
  if type(db.scanStunden) ~= "table" then db.scanStunden = {} end
  db.scanStunden[S.tagesstunde or 0] = (db.scanStunden[S.tagesstunde or 0] or 0) + 1
  pcall(verlaufAufraeumen, db, S.stempel or math.floor(time() / 3600))
  S.phase, S.pause = "fertig", false
  S.meldung = ("%d Angebote gelesen, Preise für %d Items gespeichert."):format(S.gesamt, zaehler)
  fahrer:SetScript("OnUpdate", nil)
  WW:Print(("Auktionshaus gescannt: %d Items (%d Angebote), %s."):format(zaehler, S.gesamt, FRAKTION_DE[S.scanFraktion] or S.scanFraktion))
  benachrichtige()
  if AH.TaschenAktualisieren then AH.TaschenAktualisieren() end
end

local function lesen()
  local bis = math.min(S.gesamt, S.fertig + LESEN_PRO_BILD)
  for i = S.fertig, bis - 1 do
    if S.modus == "replicate" then
      -- name, texture, count, quality, usable, level, levelType, minBid, minIncrement, buyout, bid, highBidder, bidder,
      -- owner, ownerFullName, saleStatus, itemID  (Verkäufer und Bieter werden nie gelesen oder gespeichert)
      local ok, _, _, anz, _, _, _, _, _, _, kauf, _, _, _, _, _, _, id = pcall(C_AuctionHouse.GetReplicateItemInfo, i)
      if ok then hinzu(id, anz, kauf) end
    else
      local ok, _, _, anz, _, _, _, _, _, _, kauf, _, _, _, _, _, _, id = pcall(WW.Alt("GetAuctionItemInfo"), "list", i + 1)
      if ok then hinzu(id, anz, kauf) end
    end
  end
  S.fertig = bis
end

local function rechnen()
  local liste, pos = S.ids, S.pos
  local bis = math.min(#liste, pos + RECHNEN_PRO_BILD - 1)
  for i = pos, bis do
    local id = liste[i]
    local a = agg[id]
    if a and #a.u > 0 then
      local lo, med = zusammenfassen(a)
      -- %.0f: Preise können sehr groß sein
      S.items[id] = ("%.0f,%.0f,%.0f"):format(lo, med, a.menge)
      S.zaehler = S.zaehler + 1
      if S.vl then pcall(verlaufBuchen, S.vl, id, lo, med, S.stempel, S.tagesstunde) end
      if S.tg and S.vl and S.vl[id] then pcall(tageBuchen, S.tg, id, S.tag, lo) end
    end
    agg[id] = nil
  end
  S.pos = bis + 1
  S.fertig = bis
  S.gesamt2 = #liste
end

local function beiUpdate(_, dt)
  verstrichen = verstrichen + (tonumber(dt) or 0)
  if S.phase ~= "rechnen" then
    if not S.offen then
      return scheitern("Das Auktionshaus wurde vor dem Ende des Scans geschlossen. Öffne es erneut (nach der 15-Minuten-Sperre).")
    end
    if imKampf() then
      if not S.pause then S.pause = true; benachrichtige() end
      return
    end
    S.pause = false
  end
  if S.phase == "warten" then
    if S.letztesUpdate and verstrichen - S.letztesUpdate >= RUHE then
      local n
      if S.modus == "replicate" then
        n = try(C_AuctionHouse.GetNumReplicateItems)
      else
        local anzeige, gesamt = try(WW.Alt("GetNumAuctionItems"), "list")
        n = gesamt or anzeige
      end
      n = zahl(n) or 0
      if n == 0 then
        return scheitern("Das Auktionshaus hat keine Angebote geschickt. Es ist leer, oder das Spiel erlaubt den Voll-Scan noch nicht.")
      end
      S.phase, S.gesamt, S.fertig, S.meldung = "lesen", math.floor(n), 0, nil
      benachrichtige()
    elseif verstrichen - S.gestartet > ZEITLIMIT then
      return scheitern("Das Auktionshaus antwortet nicht. Versuche es nach der 15-Minuten-Sperre noch einmal.")
    end
  elseif S.phase == "lesen" then
    lesen()
    if S.fertig >= S.gesamt then
      local ids = {}
      for id in pairs(agg) do ids[#ids + 1] = id end
      S.ids, S.pos, S.items, S.zaehler, S.fertig = ids, 1, {}, 0, 0
      -- Preisverlauf dieses Auktionshauses; die Uhrzeit gilt für den ganzen Scan
      local jetzt = time()
      S.vl = verlaufTabelle(S.realm .. "|" .. S.scanFraktion, true)
      S.tg, S.tag = tageTabelle(S.realm .. "|" .. S.scanFraktion, true), tagNummer(jetzt)
      S.stempel, S.tagesstunde = math.floor(jetzt / 3600), tonumber(date("%H", jetzt)) or 0
      S.phase = "rechnen"
    end
    benachrichtige()
  elseif S.phase == "rechnen" then
    rechnen()
    if S.pos > #S.ids then return abschliessen() end
    benachrichtige()
  end
end

-- Kann jetzt gescannt werden? ok, warum nicht
function AH.KannScannen()
  if laeuft() then return false, "Ein Scan läuft schon." end
  if not S.offen then return false, "Öffne zuerst das Auktionshaus (sprich mit einem Auktionator)." end
  if imKampf() then return false, "Nicht im Kampf. Beende erst den Kampf." end
  local weg = api()
  if not weg then return false, "Dieser Client lässt Addons das Auktionshaus nicht lesen." end
  local warte = AH.Wartezeit()
  if warte > 0 then
    return false, ("Das Spiel erlaubt alle 15 Minuten einen Voll-Scan. Der nächste geht in %d Min. %02d Sek."):format(
      math.floor(warte / 60), math.floor(warte % 60))
  end
  if weg == "getall" and type(CanSendAuctionQuery) == "function" then
    local _, alle = try(CanSendAuctionQuery)
    if alle == false then return false, "Das Auktionshaus ist für einen Voll-Scan noch nicht bereit. Versuche es in einer Minute." end
  end
  if not realmName() then return false, "Das Spiel hat den Realm noch nicht gemeldet." end
  if not einstellungen() then return false, "Die Daten sind noch nicht geladen." end
  return true
end

-- Scan starten. Gibt ok, Text zurück.
function AH.Scannen()
  local ok, warum = AH.KannScannen()
  if not ok then
    S.meldung = warum
    benachrichtige()
    return false, warum
  end
  local db = einstellungen()
  local weg = api()
  agg, schluesselZahl = {}, 0
  verstrichen = 0
  S.modus, S.realm, S.scanFraktion = weg, realmName(), S.fraktion or ahFraktion()
  S.phase, S.fertig, S.gesamt, S.gestartet, S.letztesUpdate, S.pause = "warten", 0, 0, 0, nil, false
  S.meldung = "Frage das Auktionshaus nach allen Angeboten ..."
  db.letzterScan = time()
  local gesendet
  if weg == "replicate" then
    gesendet = pcall(C_AuctionHouse.ReplicateItems)
  else
    -- name, minLevel, maxLevel, page, usable, quality, getAll
    gesendet = pcall(WW.Alt("QueryAuctionItems"), "", nil, nil, 0, false, 0, true)
  end
  if not gesendet then
    db.letzterScan = 0
    scheitern("Das Spiel hat den Scan abgelehnt. Versuche es in einer Minute noch einmal.")
    return false, S.meldung
  end
  fahrer:SetScript("OnUpdate", beiUpdate)
  benachrichtige()
  return true
end

---------------------------------------------------------------------------
-- Blizzards Auktionshaus (Blizzard_AuctionHouseUI): Marken "-35 %" / "+40 %" neben dem Preis,
-- und leichte Preisproben aus den Suchergebnissen. Alles in pcall; kein SetScript auf Blizzard-Rahmen.
---------------------------------------------------------------------------
local marken = setmetatable({}, { __mode = "k" })   -- Tabellenzelle -> unser Text
local ahGehakt = false

-- Wird nach Blizzards Zelle:Populate(rowData, dataIndex) der Spalte "Mindestpreis" aufgerufen.
local function markiereZelle(zelle, rowData)
  local marke = marken[zelle]
  local text, urteil
  local db = einstellungen()
  if db and db.ahMarken and type(rowData) == "table" then
    local key = rowData.itemKey
    local id, preis = type(key) == "table" and zahl(key.itemID), zahl(rowData.minPrice)
    if id and preis then
      local u, abw = AH.PreisUrteil(id, preis)
      if u == "guenstig" then
        urteil, text = "gruen", ("%+d %%"):format(runden(abw * 100))
      elseif u == "teuer" then
        urteil, text = "rot", ("%+d %%"):format(runden(abw * 100))
      end
    end
  end
  if not text then
    if marke then marke:Hide() end
    return
  end
  if not marke then
    marke = zelle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    marke:SetPoint("LEFT", zelle, "LEFT", 4, 0)
    marken[zelle] = marke
  end
  marke:SetText(WW.f(urteil, text))
  marke:Show()
end
AH.MarkiereZelle = markiereZelle

-- Rechtsklick auf eine Ergebniszeile in Blizzards Auktionshaus: Menü "Mehr Information".
-- Die Zeile ist der Eltern-Rahmen der Preiszelle. Nur HookScript (kein SetScript), damit Kaufen nicht gestört wird.
local zeilenItem = setmetatable({}, { __mode = "k" })   -- Zeile -> itemID der zuletzt gezeigten Daten
local zeilenGehakt = setmetatable({}, { __mode = "k" })
local function merkeZeile(zelle, rowData)
  local zeile = zelle and zelle.GetParent and zelle:GetParent()
  if not zeile then return end
  local key = type(rowData) == "table" and rowData.itemKey
  zeilenItem[zeile] = type(key) == "table" and zahl(key.itemID) or nil
  if not zeilenGehakt[zeile] and zeile.HookScript then
    zeilenGehakt[zeile] = true
    zeile:HookScript("OnMouseUp", function(self, maus)
      if maus ~= "RightButton" then return end
      local id = zeilenItem[self]
      if id and WW.UI.ItemMenue then pcall(WW.UI.ItemMenue, id) end
    end)
  end
end
AH.MerkeZeile = merkeZeile

-- Haken in Blizzards Tabellenzelle anbringen, sobald sie da ist (Zellen entstehen erst bei der ersten Suche)
local function ahAnhaengen()
  if ahGehakt then return end
  local m = _G.AuctionHouseTableCellMinPriceMixin
  if type(m) == "table" and type(m.Populate) == "function" then
    hooksecurefunc(m, "Populate", function(zelle, rowData)
      pcall(markiereZelle, zelle, rowData)
      pcall(merkeZeile, zelle, rowData)
    end)
    ahGehakt = true
  end
end
-- Reiter "Wegweiser" unten an Blizzards Auktionshaus, neben "Kaufen", "Verkaufen", "Auktionen".
-- Eigener Knopf auf eigenem Rahmen: Blizzards Reiter und ihre Skripte bleiben unberührt (sonst kann
-- WoW das Kaufen blockieren). Klick legt das Wegweiser-Fenster (Reiter "Auktionshaus") rechts neben das AH-Fenster.
local ahReiter
local function ahReiterBauen()
  if ahReiter then return ahReiter end
  local ahf = rawget(_G, "AuctionHouseFrame")
  if type(ahf) ~= "table" or not ahf.GetObjectType then return nil end
  local k = WW.UI.Knopf(ahf, "Wegweiser", 110)
  k:SetFrameStrata("HIGH")
  -- rechts neben dem letzten Blizzard-Reiter, sonst unten links am Fenster
  local letzter
  if type(ahf.Tabs) == "table" then letzter = ahf.Tabs[#ahf.Tabs] end
  if type(letzter) == "table" and letzter.GetObjectType then
    k:SetPoint("LEFT", letzter, "RIGHT", 6, 0)
  else
    k:SetPoint("TOPLEFT", ahf, "BOTTOMLEFT", 330, 2)
  end
  k:SetScript("OnClick", function()
    if WW:IstAngedockt(ahf) then
      WW:Abdocken()
    else
      WW:OeffnenAn("ah", ahf)
    end
  end)
  k:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Wegweiser")
    GameTooltip:AddLine("Schnäppchen, Zu teuer, deine Taschen mit Preisen. Rechtsklick auf ein Item: Preis-Grafik. Noch ein Klick hier: Wegweiser schließen.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  k:SetScript("OnLeave", function() GameTooltip:Hide() end)
  ahReiter = k
  return k
end
AH.ReiterAmAHBauen = function() local ok, k = pcall(ahReiterBauen) return ok and k or nil end

function AH.AnhaengenVersuchen()
  pcall(ahAnhaengen)
  pcall(ahReiterBauen)
end

WW:Event("ADDON_LOADED", function(name)
  if name == "Blizzard_AuctionHouseUI" then pcall(ahAnhaengen) pcall(ahReiterBauen) end
end)
WW:BeimStart(function() pcall(ahAnhaengen) end)

-- Suchergebnisse: Mindestpreis als Stundenprobe, höchstens alle 3 Sekunden und nur für bekannte Items
local browseLetzte = -1000
local function browseErfassen()
  if not S.offen or not WW.db then return end
  local jetztZeit = GetTime and GetTime() or 0
  if jetztZeit - browseLetzte < 3 then return end
  browseLetzte = jetztZeit
  local C = type(C_AuctionHouse) == "table" and C_AuctionHouse or nil
  local ergebnisse = C and try(C.GetBrowseResults)
  if type(ergebnisse) ~= "table" then return end
  local realm, fraktion = realmName(), S.fraktion
  if not realm or not fraktion then return end
  local vl = verlaufTabelle(realm .. "|" .. fraktion)
  if not vl then return end
  local tg = tageTabelle(realm .. "|" .. fraktion, true)
  local jetzt = time()
  local stempel, stunde = math.floor(jetzt / 3600), tonumber(date("%H", jetzt)) or 0
  for i = 1, math.min(#ergebnisse, 400) do
    local r = ergebnisse[i]
    local key = type(r) == "table" and r.itemKey
    local id, preis = type(key) == "table" and zahl(key.itemID), type(r) == "table" and zahl(r.minPrice)
    if id and preis and preis > 0 and vl[id] then probeAusSuche(vl, id, runden(preis), stempel, stunde, tg) end
  end
end

---------------------------------------------------------------------------
-- Ereignisse: Auktionshaus auf/zu, Ergebnisse (eigener Rahmen: unbekannte Ereignisse stören nicht)
---------------------------------------------------------------------------
local function geoeffnet()
  if S.offen then return end
  S.offen = true
  S.fraktion = ahFraktion()
  S.pause = false
  AH.AnhaengenVersuchen()
  if S.phase == "fertig" or S.phase == "fehler" then S.phase = "leer"; S.meldung = nil end
  local db = einstellungen()
  if db and db.autoScan and AH.Wartezeit() == 0 then
    if C_Timer and C_Timer.After then
      -- kurz warten: Blizzards Fenster schickt zuerst seine eigene Suche
      C_Timer.After(2, function() if S.offen and not laeuft() then AH.Scannen() end end)
    end
  end
  benachrichtige()
end

local function geschlossen()
  if not S.offen then return end
  S.offen = false
  if WW.Abdocken then pcall(WW.Abdocken, WW) end   -- Wegweiser lag über dem AH-Fenster: zurück an seine Stelle
  S.fraktion = nil
  if S.phase == "warten" or S.phase == "lesen" then
    scheitern("Das Auktionshaus wurde vor dem Ende des Scans geschlossen. Öffne es erneut (nach der 15-Minuten-Sperre).")
  else
    benachrichtige()
  end
end

local ereignisse = CreateFrame("Frame")
for _, ev in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "REPLICATE_ITEM_LIST_UPDATE",
  "AUCTION_ITEM_LIST_UPDATE", "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
  "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" }) do
  pcall(ereignisse.RegisterEvent, ereignisse, ev)
end
ereignisse:SetScript("OnEvent", function(_, ev, arg1)
  if ev == "AUCTION_HOUSE_SHOW" then
    geoeffnet()
  elseif ev == "AUCTION_HOUSE_CLOSED" then
    geschlossen()
  elseif ev == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" or ev == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
    local typ = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.Auctioneer or 21
    if arg1 == typ then
      if ev == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then geoeffnet() else geschlossen() end
    end
  elseif ev == "REPLICATE_ITEM_LIST_UPDATE" then
    if S.phase == "warten" and S.modus == "replicate" then S.letztesUpdate = verstrichen end
  elseif ev == "AUCTION_ITEM_LIST_UPDATE" then
    if S.phase == "warten" and S.modus == "getall" then S.letztesUpdate = verstrichen end
  elseif ev == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or ev == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
    pcall(browseErfassen)
  end
end)

WW:Befehl("scan", "Auktionshaus scannen", function()
  local ok, warum = AH.Scannen()
  if not ok and warum then WW:Print(warum) end
end)

---------------------------------------------------------------------------
-- Tooltips: "AH: ..." und "Verkaufen: ..."
---------------------------------------------------------------------------
local gesehen = setmetatable({}, { __mode = "k" })   -- Tooltip -> itemID, für die schon Zeilen stehen

-- Wie viele Stück liegen auf dem Platz, über dem der Tooltip steht? anzahl, gebunden
local function stapelVomTooltip(tt, id)
  local owner = tt.GetOwner and tt:GetOwner()
  if not owner or not owner.GetID or not owner.GetParent then return 1, false end
  local eltern = owner:GetParent()
  local bag = owner.GetBagID and owner:GetBagID() or (eltern and eltern.GetID and eltern:GetID())
  local slot = owner:GetID()
  if not bag or not slot or slot < 1 then return 1, false end
  local sid, anz, gebunden = slotInfo(bag, slot)
  if sid == id then return anz or 1, gebunden end
  return 1, false
end

local function tooltipZeilen(tt, data)
  local db = einstellungen()
  if not db or not db.tooltip then return end
  if tt ~= GameTooltip and tt ~= ItemRefTooltip then return end
  local id = data and tonumber(data.id)
  if not id then
    local _, link = tt:GetItem()
    id = WW.ItemID(link)
  end
  if not id or gesehen[tt] == id then return end
  gesehen[tt] = id
  local lo, med, menge, alter = AH.Preis(id)
  if not lo then return end
  local okStapel, anz, gebunden = pcall(stapelVomTooltip, tt, id)
  if not okStapel then anz, gebunden = 1, false end
  if gebunden then return end
  local zeile = type(db.tt) == "table" and db.tt or {}
  local function an(k) return zeile[k] ~= false end
  local farbe, kurz, erloes, haendler, info = AH.Bewertung(id, anz, false)
  local einheit = (med and med > 0) and med or lo
  local vorher = tt.NumLines and tt:NumLines()
  if an("preis") then
    local text = "AH: " .. WW.Geld(einheit)
    if med and med > 0 and lo ~= med then text = text .. " (min " .. WW.Geld(lo) .. ")" end
    if info then
      text = text .. (" – nach Gebühren %s (%s %d %%)"):format(WW.Geld(math.floor(einheit * (1 - info.abzug))),
        FRAKTION_NAME[info.fraktion] or info.fraktion, runden(info.abzug * 100))
    end
    tt:AddLine(text, 1, 0.82, 0.4)
  end
  if an("menge") then tt:AddLine((menge or 0) .. " Stück im AH, Stand " .. vor(alter), 0.7, 0.7, 0.7) end
  -- Geschützt (Quest, Beruf, gemerkt): kein "Verkaufen: Händler" – die Wegweiser-Zeile sagt "Behalten"
  local U = WW.Urteil
  local okU, u = pcall(function() return U and U.Pruefen(id, anz, gebunden) end)
  local geschuetzt = okU and u and u.schutz
  if farbe ~= "grau" and an("urteil") and not geschuetzt then
    tt:AddLine(WW.f(farbe, "Verkaufen: " .. kurz), 1, 1, 1)
    if anz and anz > 1 then
      tt:AddLine(("%dx: AH %s nach Gebühren, Händler %s"):format(anz, WW.Geld(erloes), WW.Geld(haendler)), 0.7, 0.7, 0.7)
    end
  end
  if info and info.kaution and an("kaution") then
    tt:AddLine(("Einstellgebühr (%d Std.): %s (weg, wenn es nicht verkauft wird)"):format(info.dauer, WW.Geld(info.kaution)),
      0.7, 0.7, 0.7, true)
  end
  -- Normalpreis, "günstig" / "zu teuer", Uhrzeit-Tipps (aus dem Preisverlauf)
  local okV, a = pcall(AH.Analyse, id)
  if okV and a and a.normal then
    if an("normal") then
      tt:AddLine(("Normalpreis: %s (aus %d %s)"):format(WW.Geld(runden(a.normal)), a.scans, a.scans == 1 and "Scan" or "Scans"),
        0.7, 0.7, 0.7)
      if a.urteil == "guenstig" then
        tt:AddLine(WW.f("gruen", ("Gerade günstig (%+d %%)"):format(runden(a.abw * 100))), 1, 1, 1)
      elseif a.urteil == "teuer" then
        tt:AddLine(WW.f("rot", ("Gerade zu teuer (%+d %%)"):format(runden(a.abw * 100))), 1, 1, 1)
      end
    end
    if an("zeit") then
      local okT, tipp, echt = pcall(AH.ZeitTipp, id)
      if okT and echt then tt:AddLine(tipp, 0.7, 0.7, 0.7, true) end
    end
  end
  if vorher == nil or (tt.NumLines and tt:NumLines() ~= vorher) then tt:Show() end
end

AH.TooltipZeilen = tooltipZeilen   -- für die Tests (der Spiel-Haken ruft sie selbst auf)

local function tooltipsAnschliessen()
  local gehakt = false
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType
     and Enum.TooltipDataType.Item then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data)
      pcall(tooltipZeilen, tt, data)
    end)
    gehakt = true
  end
  for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
    if tt and tt.HookScript then
      if not gehakt then
        pcall(tt.HookScript, tt, "OnTooltipSetItem", function(self) pcall(tooltipZeilen, self) end)
      end
      pcall(tt.HookScript, tt, "OnTooltipCleared", function(self) gesehen[self] = nil end)
    end
  end
  if not gehakt and GameTooltip then
    for _, name in ipairs({ "SetBagItem", "SetHyperlink", "SetInventoryItem", "SetLootItem", "SetMerchantItem",
      "SetAuctionItem", "SetItemByID" }) do
      if type(GameTooltip[name]) == "function" then
        hooksecurefunc(GameTooltip, name, function(self) pcall(tooltipZeilen, self) end)
      end
    end
  end
end
WW:BeimStart(tooltipsAnschliessen)

---------------------------------------------------------------------------
-- Farben auf den Taschenplätzen (Blizzards Taschen: ContainerFrame1..13)
---------------------------------------------------------------------------
local ueberlagerungen = setmetatable({}, { __mode = "k" })   -- Button -> { 4 Rand-Texturen }
local gehakteRahmen = setmetatable({}, { __mode = "k" })
local taschenGeplant = false

local function randTexturen(button)
  local o = ueberlagerungen[button]
  if o then return o end
  o = {}
  for i = 1, 4 do
    local t = button:CreateTexture(nil, "OVERLAY")
    t:SetColorTexture(1, 1, 1, 1)
    t:Hide()
    o[i] = t
  end
  o[1]:SetPoint("TOPLEFT"); o[1]:SetPoint("TOPRIGHT"); o[1]:SetHeight(2)
  o[2]:SetPoint("BOTTOMLEFT"); o[2]:SetPoint("BOTTOMRIGHT"); o[2]:SetHeight(2)
  o[3]:SetPoint("TOPLEFT"); o[3]:SetPoint("BOTTOMLEFT"); o[3]:SetWidth(2)
  o[4]:SetPoint("TOPRIGHT"); o[4]:SetPoint("BOTTOMRIGHT"); o[4]:SetWidth(2)
  ueberlagerungen[button] = o
  return o
end

local function randSetzen(button, farbe)
  local o = ueberlagerungen[button]
  if not farbe then
    if o then for i = 1, 4 do o[i]:Hide() end end
    return
  end
  o = randTexturen(button)
  local c = RGB[farbe] or RGB.grau
  for i = 1, 4 do
    o[i]:SetColorTexture(c[1], c[2], c[3], 0.95)
    o[i]:Show()
  end
end

-- Alle Item-Buttons einer Taschen-Rahmens
local function taschenButtons(rahmen)
  local liste = {}
  if rahmen.EnumerateValidItems then
    pcall(function()
      for _, b in rahmen:EnumerateValidItems() do liste[#liste + 1] = b end
    end)
    if #liste > 0 then return liste end
  end
  if type(rahmen.Items) == "table" then
    for _, b in ipairs(rahmen.Items) do liste[#liste + 1] = b end
    if #liste > 0 then return liste end
  end
  local name = rahmen.GetName and rahmen:GetName()
  if name then
    for j = 1, 40 do
      local b = _G[name .. "Item" .. j]
      if b then liste[#liste + 1] = b end
    end
  end
  return liste
end

local function buttonFarbe(button, rahmen, an, sichtbar)
  -- Versteckte Taschen: nur das Zeichen ausblenden, sonst nichts lesen (spart Arbeit bei jedem Questlog-Update)
  if not sichtbar then
    if WW.Urteil then pcall(WW.Urteil.Knopf, button, nil) end
    return nil
  end
  local bag = button.GetBagID and button:GetBagID() or (rahmen.GetID and rahmen:GetID())
  local slot = button.GetID and button:GetID()
  local id, anz, gebunden
  if bag and slot and slot >= 1 then id, anz, gebunden = slotInfo(bag, slot) end
  -- Urteil (Module\Urteil.lua): Zeichen in der Ecke, Alt+Rechtsklick; geschützt = kein AH-Rand, Müll = rot
  local U = WW.Urteil
  local u
  if U then
    pcall(U.Knopf, button, sichtbar and id or nil, anz, gebunden)
    if an and id then
      local ok, e = pcall(U.Pruefen, id, anz, gebunden)
      u = ok and e or nil
    end
  end
  if not an or not id then return nil end
  if u then return u.rand end
  if gebunden then return nil end
  local farbe = AH.Bewertung(id, anz, false)
  if farbe == "grau" then return nil end
  return farbe
end

local function taschenAktualisieren()
  local db = einstellungen()
  local an = db and db.taschenFarben and true or false
  local rahmenListe = {}
  for i = 1, 13 do
    local f = _G["ContainerFrame" .. i]
    if f then rahmenListe[#rahmenListe + 1] = f end
  end
  if _G.ContainerFrameCombinedBags then rahmenListe[#rahmenListe + 1] = _G.ContainerFrameCombinedBags end
  for _, rahmen in ipairs(rahmenListe) do
    if not gehakteRahmen[rahmen] and rahmen.HookScript then
      gehakteRahmen[rahmen] = true
      pcall(rahmen.HookScript, rahmen, "OnShow", function() AH.TaschenPlanen() end)
    end
    local sichtbar = rahmen:IsShown() and true or false
    local zeigen = an and sichtbar
    for _, b in ipairs(taschenButtons(rahmen)) do
      local ok, farbe = pcall(buttonFarbe, b, rahmen, zeigen, sichtbar)
      randSetzen(b, ok and farbe or nil)
    end
  end
end

-- Sofort aktualisieren
function AH.TaschenAktualisieren()
  pcall(taschenAktualisieren)
end

-- Gleich aktualisieren (mehrere Anstöße werden zusammengefasst)
function AH.TaschenPlanen()
  if taschenGeplant then return end
  taschenGeplant = true
  if C_Timer and C_Timer.After then
    C_Timer.After(0.05, function()
      taschenGeplant = false
      AH.TaschenAktualisieren()
    end)
  else
    taschenGeplant = false
    AH.TaschenAktualisieren()
  end
end

WW:Event("BAG_UPDATE_DELAYED", function() AH.TaschenPlanen() end)
WW:BeimStart(function()
  for _, name in ipairs({ "ContainerFrame_Update", "ContainerFrame_GenerateFrame", "OpenAllBags", "ToggleAllBags",
    "OpenBag", "ToggleBag", "OpenBackpack", "ToggleBackpack" }) do
    if type(_G[name]) == "function" then hooksecurefunc(name, function() AH.TaschenPlanen() end) end
  end
  AH.TaschenPlanen()
end)

---------------------------------------------------------------------------
-- Reiter "Auktionshaus"
---------------------------------------------------------------------------
-- Inhalt der Taschen als Liste mit Urteil, sortiert nach AH-Gewinn
local function taschenListe()
  local nachSchluessel, liste = {}, {}
  for _, bag in ipairs(WW.TaschenIDs()) do
    for slot = 1, slotAnzahl(bag) do
      local id, anz, gebunden = slotInfo(bag, slot)
      if id then
        local k = id .. (gebunden and "g" or "f")
        local e = nachSchluessel[k]
        if not e then
          e = { id = id, anzahl = 0, gebunden = gebunden }
          nachSchluessel[k] = e
          liste[#liste + 1] = e
        end
        e.anzahl = e.anzahl + (tonumber(anz) or 1)
      end
    end
  end
  -- die zuletzt gesehene Bank (aus Inventar.lua), als eigene Zeilen
  local db = einstellungen()
  if db and db.taschenBank and WW.Inventar and WW.Inventar.BankListe then
    local ok, bank = pcall(WW.Inventar.BankListe)
    if ok and type(bank) == "table" then
      for _, b in ipairs(bank) do
        liste[#liste + 1] = { id = b.id, anzahl = b.anzahl, gebunden = b.gebunden, bank = true }
      end
    end
  end
  for _, e in ipairs(liste) do
    e.farbe, e.text, e.erloes, e.haendler = AH.Bewertung(e.id, e.anzahl, e.gebunden)
    e.gewinn = (e.erloes or 0) - (e.haendler or 0)
    e.rang = (e.farbe == "grau") and 1 or 0
    e.sortName = (WW.ItemName(e.id) or ""):lower()
  end
  table.sort(liste, function(a, b)
    if a.rang ~= b.rang then return a.rang < b.rang end
    if a.rang == 0 then
      if a.gewinn ~= b.gewinn then return a.gewinn > b.gewinn end
    else
      if (a.haendler or 0) ~= (b.haendler or 0) then return (a.haendler or 0) > (b.haendler or 0) end
    end
    if a.sortName ~= b.sortName then return a.sortName < b.sortName end
    return a.id < b.id
  end)
  return liste
end

-- Prüf-Befehl: zeigt Schritt für Schritt, ob die Taschen-Liste im Reiter Auktionshaus Daten bekommt.
WW:Befehl("diag", "Prüfung der Taschen-Liste (für Fehlersuche)", function()
  local teile = {}
  local ok, ids = pcall(WW.TaschenIDs)
  if not ok then WW:Print("TaschenIDs Fehler: " .. tostring(ids)) return end
  for _, bag in ipairs(ids) do
    local ok2, n = pcall(slotAnzahl, bag)
    local belegt = 0
    for slot = 1, (ok2 and n or 0) do
      local ok3, id = pcall(slotInfo, bag, slot)
      if ok3 and id then belegt = belegt + 1 end
    end
    teile[#teile + 1] = bag .. ":" .. tostring(ok2 and n or "Fehler") .. "/" .. belegt
  end
  WW:Print("Taschen (Nr:Plätze/belegt): " .. table.concat(teile, "  "))
  local ok4, l = pcall(taschenListe)
  WW:Print("Liste: " .. (ok4 and (#l .. " Einträge") or ("Fehler: " .. tostring(l))))
  local liste = AH._liste
  if liste then
    local sichtbar = 0
    for _, z in ipairs(liste.zeilen or {}) do if z:IsShown() and z.eintrag then sichtbar = sichtbar + 1 end end
    WW:Print(("Anzeige: Liste %s, %d Einträge geladen, %d Zeilen sichtbar, Größe %dx%d"):format(
      liste:IsShown() and "sichtbar" or "versteckt", #(liste.eintraege or {}), sichtbar,
      math.floor(liste:GetWidth() or 0), math.floor(liste:GetHeight() or 0)))
    if liste.Aktualisiere then
      local ok5, err = pcall(liste.Aktualisiere, liste)
      if not ok5 then WW:Print("Fehler beim Zeichnen: " .. tostring(err)) end
    end
  else
    WW:Print("Reiter Auktionshaus wurde noch nicht geöffnet.")
  end
end)

local SPALTEN = { name = 24, anzahl = 280, ah = 328, haendler = 500, urteil = 656 }
local SPALTEN2 = { name = 24, preis = 270, normal = 370, abw = 470, menge = 560, knopf = 676 }

-- 24-Stunden-Streifen: wie oft wurde zu welcher Uhrzeit gescannt?
local function streifenText()
  local st = AH.ScanStunden()
  local teile = {}
  for h = 0, 23 do
    local n = tonumber(st[h]) or 0
    local farbe = (n == 0 and "grau") or (n < 3 and "gelb") or "gruen"
    teile[#teile + 1] = WW.f(farbe, ("%02d"):format(h)) .. ":" .. n
  end
  return "Scans nach Uhrzeit (Stunde:Anzahl; grau = noch nie, gelb = wenig, grün = genug). "
    .. "Scanne zu verschiedenen Tageszeiten, dann zeigen Items Uhrzeit-Tipps.\n" .. table.concat(teile, "  ")
end

WW:Reiter("ah", "Auktionshaus", 20, function(p)
  local ansicht = "taschen"   -- "taschen" | "schnaeppchen" | "teuer" | "verkaufen"

  local titel = UI.Text(p, "gross")
  titel:SetPoint("TOPLEFT", 4, -4)
  titel:SetText("Auktionshaus")

  local scanKnopf = UI.Knopf(p, "Jetzt scannen", 110, function() AH.Scannen() end)
  scanKnopf:SetPoint("TOPRIGHT", -4, -4)
  local neuKnopf = UI.Knopf(p, "Taschen neu laden", 124)
  neuKnopf:SetPoint("RIGHT", scanKnopf, "LEFT", -8, 0)

  -- Laufzeit für die Einstellgebühr: 2 / 8 / 24 Std.
  local dauerKnopf = UI.Knopf(p, "", 84, function(self)
    local d = tonumber(WW.db.ah.dauer) or 8
    WW.db.ah.dauer = (d == 2 and 8) or (d == 8 and 24) or 2
    AH.KautionCacheLeeren()
    self:SetText(("Dauer: %d Std."):format(WW.db.ah.dauer))
    if p.OnZeigen then p.OnZeigen() end
  end)
  -- links neben "Taschen neu laden", mit Abstand (kein Überlappen mit "Zu teuer")
  dauerKnopf:SetPoint("RIGHT", neuKnopf, "LEFT", -8, 0)
  dauerKnopf:SetText(("Dauer: %d Std."):format(tonumber(WW.db.ah.dauer) or 8))

  local ansichtKnopf = {}
  local setzeAnsicht
  local function ansichtKnopfBauen(schluessel, text, x)
    local k = UI.Knopf(p, text, 96, function() setzeAnsicht(schluessel) end)
    k:SetPoint("TOPLEFT", x, -4)
    ansichtKnopf[schluessel] = k
  end
  ansichtKnopfBauen("taschen", "Taschen", 120)
  ansichtKnopfBauen("schnaeppchen", "Schnäppchen", 220)
  ansichtKnopfBauen("teuer", "Zu teuer", 320)
  ansichtKnopfBauen("verkaufen", "Verkaufen", 420)

  local status = UI.Text(p)
  status:SetPoint("TOPLEFT", titel, "BOTTOMLEFT", 0, -6)
  -- 2 einzeilige Textfelder (Scan-Stand, Zustand), sonst rutscht der Text in die Filter-Zeile darunter.
  -- Nicht ein Feld mit "\n": ohne Umbruch zeigt WoW davon nur die erste Zeile.
  status:SetWidth(WW.INHALT_BREITE - 8)
  status:SetWordWrap(false)
  local status2 = UI.Text(p)
  status2:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -3)
  status2:SetWidth(WW.INHALT_BREITE - 8)
  status2:SetWordWrap(false)

  local haken1 = UI.Haken(p, "Farben in Taschen",
    function() return WW.db.ah.taschenFarben end,
    function(an) WW.db.ah.taschenFarben = an; AH.TaschenAktualisieren() end)
  haken1:SetPoint("TOPLEFT", 0, -72)
  local haken2 = UI.Haken(p, "Preise im Tooltip",
    function() return WW.db.ah.tooltip end,
    function(an) WW.db.ah.tooltip = an end)
  haken2:SetPoint("TOPLEFT", 150, -72)
  local haken3 = UI.Haken(p, "Beim Öffnen scannen",
    function() return WW.db.ah.autoScan end,
    function(an) WW.db.ah.autoScan = an end)
  haken3:SetPoint("TOPLEFT", 295, -72)
  local haken4 = UI.Haken(p, "Marken im Blizzard-AH",
    function() return WW.db.ah.ahMarken end,
    function(an) WW.db.ah.ahMarken = an end)
  haken4:SetPoint("TOPLEFT", 475, -72)
  local haken5 = UI.Haken(p, "Bank einbeziehen",
    function() return WW.db.ah.taschenBank end,
    function(an)
      WW.db.ah.taschenBank = an
      if p.OnZeigen then p.OnZeigen() end   -- Liste neu aufbauen
    end)
  haken5:SetPoint("TOPLEFT", 665, -72)
  local taschenHaken = { haken1, haken2, haken3, haken4, haken5 }

  -- Filter für "Schnäppchen" und "Zu teuer" (gleiche Zeile wie die Haken der Taschen-Ansicht)
  local filterText = ""
  local mf = WW.db.ah.markt
  local sucheLabel = UI.Text(p)
  sucheLabel:SetPoint("TOPLEFT", 4, -76)
  sucheLabel:SetText("Suche:")
  local suche = UI.Eingabe(p, 170, function(t)
    filterText = t or ""
    if p.LadeListe then p.LadeListe() end
  end)
  suche:SetPoint("LEFT", sucheLabel, "RIGHT", 8, 0)
  local bezahlbar = UI.Haken(p, "Nur bezahlbar",
    function() return mf.bezahlbar end,
    function(an) mf.bezahlbar = an; if p.LadeListe then p.LadeListe() end end)
  bezahlbar:SetPoint("TOPLEFT", 250, -72)
  local ERSPARNIS = { 0, 30, 40, 50, 70 }
  local function ersparnisText()
    local e = tonumber(mf.ersparnis) or 0
    return e > 0 and ("Ersparnis ab %d %%"):format(e) or "Ersparnis: alle"
  end
  local ersparnisKnopf = UI.Knopf(p, ersparnisText(), 130, function(self)
    local e, naechste = tonumber(mf.ersparnis) or 0, ERSPARNIS[1]
    for i, w in ipairs(ERSPARNIS) do if w == e then naechste = ERSPARNIS[i + 1] or ERSPARNIS[1] end end
    mf.ersparnis = naechste
    self:SetText(ersparnisText())
    if p.LadeListe then p.LadeListe() end
  end)
  ersparnisKnopf:SetPoint("TOPLEFT", 400, -73)
  -- Klapp-Fenster (Filter, Kategorie): immer nur eins offen; ein Klick daneben oder Verlassen des Reiters schließt es
  p.fenster = {}
  function p.nurDiesesFenster(f)
    for _, x in ipairs(p.fenster) do if x ~= f then x:Hide() end end
    if f then f:Show() end
  end
  local schliesser = CreateFrame("Frame", nil, p)
  pcall(schliesser.RegisterEvent, schliesser, "GLOBAL_MOUSE_DOWN")
  schliesser:SetScript("OnEvent", function()
    for _, x in ipairs(p.fenster) do
      if x:IsShown() and not x:IsMouseOver() and not (x.knopf and x.knopf:IsMouseOver()) then x:Hide() end
    end
  end)
  p:HookScript("OnHide", function() p.nurDiesesFenster(nil) end)

  -- Knopf "Filter (n)" öffnet ein kleines Filter-Fenster (Seltenheit, Stufe, nur nutzbare)
  AH.FilterEinst(mf)
  local filterFenster
  local function filterAufschrift()
    local n = AH.FilterAnzahl(mf)
    return n > 0 and ("Filter (%d)"):format(n) or "Filter"
  end
  local qualitaetKnopf = UI.Knopf(p, filterAufschrift(), 130)
  qualitaetKnopf:SetPoint("TOPLEFT", 536, -73)
  local function filterGeaendert()
    qualitaetKnopf:SetText(filterAufschrift())
    if p.LadeListe then p.LadeListe() end
  end
  local function baueFilterFenster()
    local f = CreateFrame("Frame", "WegweiserAHFilter", p, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetFrameStrata("DIALOG")
    f:SetSize(240, 330)
    f:SetPoint("TOPLEFT", qualitaetKnopf, "BOTTOMLEFT", 0, -2)
    if f.SetBackdrop then
      f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
      f:SetBackdropColor(0.05, 0.05, 0.05, 0.97)
    end
    f:EnableMouse(true)
    tinsert(UISpecialFrames, "WegweiserAHFilter")   -- Esc schließt
    local t = UI.Text(f)
    t:SetPoint("TOPLEFT", 12, -12)
    t:SetText(WW.f("titel", "Stufenreichweite"))
    local function stufeFeld(feld, x)
      local e = UI.Eingabe(f, 40, function(text)
        mf[feld] = tonumber(text)
        filterGeaendert()
      end)
      e:SetPoint("TOPLEFT", x, -32)
      if e.SetNumeric then e:SetNumeric(true) end
      if e.SetMaxLetters then e:SetMaxLetters(2) end
      return e
    end
    f.von = stufeFeld("stufeVon", 18)
    local strich = UI.Text(f)
    strich:SetPoint("LEFT", f.von, "RIGHT", 6, 0)
    strich:SetText("-")
    f.bis = stufeFeld("stufeBis", 82)
    local vorher
    f.haken = {}
    local function haken(text, get, set, abstand)
      local h = UI.Haken(f, text, get, function(an) set(an) filterGeaendert() end)
      if vorher then h:SetPoint("TOPLEFT", vorher, "BOTTOMLEFT", 0, abstand or 2)
      else h:SetPoint("TOPLEFT", 8, -60) end
      h.get = get
      vorher = h
      f.haken[#f.haken + 1] = h
      return h
    end
    haken("Nur nutzbare", function() return mf.nutzbar end, function(an) mf.nutzbar = an end)
    haken("Keine weißen Waffen/Rüstungen", function() return mf.weissAus end, function(an) mf.weissAus = an end)
    local t2 = UI.Text(f)
    t2:SetPoint("TOPLEFT", vorher, "BOTTOMLEFT", 4, -10)
    t2:SetText(WW.f("titel", "Seltenheit"))
    for i = 0, 5 do
      haken(qualitaetsCode(i) .. AH.SELTENHEIT[i] .. "|r", function() return AH.FilterEinst(mf).q[i] end,
        function(an) AH.FilterEinst(mf).q[i] = an end, (i == 0) and -26 or 2)
    end
    local zurueck = UI.Knopf(f, "Zurücksetzen", 120, function()
      mf.q, mf.qualitaet, mf.stufeVon, mf.stufeBis, mf.nutzbar, mf.weissAus = nil, nil, nil, nil, false, nil
      AH.FilterEinst(mf)
      f.von:SetText("")
      f.bis:SetText("")
      for _, h in ipairs(f.haken) do h:SetChecked(h.get() and true or false) end
      filterGeaendert()
    end)
    zurueck:SetPoint("BOTTOM", 0, 10)
    f:SetScript("OnShow", function(self)
      self.von:SetText(mf.stufeVon and tostring(mf.stufeVon) or "")
      self.bis:SetText(mf.stufeBis and tostring(mf.stufeBis) or "")
    end)
    f:Hide()
    return f
  end
  qualitaetKnopf:SetScript("OnClick", function()
    if not filterFenster then
      filterFenster = baueFilterFenster()
      filterFenster.knopf = qualitaetKnopf
      p.fenster[#p.fenster + 1] = filterFenster
    end
    if filterFenster:IsShown() then filterFenster:Hide() return end
    p.nurDiesesFenster(filterFenster)
  end)
  qualitaetKnopf:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Filter für Schnäppchen")
    GameTooltip:AddLine("Seltenheit, Stufe und nur nutzbare Items. Graue Items und weiße Waffen/Rüstungen sind am Anfang aus: ihr üblicher Preis kommt von Angeboten, die keiner kauft.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  qualitaetKnopf:SetScript("OnLeave", function() GameTooltip:Hide() end)
  local nurMeine = UI.Haken(p, "Nur Items, die ich habe",
    function() return mf.nurMeine end,
    function(an) mf.nurMeine = an; if p.LadeListe then p.LadeListe() end end)
  nurMeine:SetPoint("TOPLEFT", 250, -72)
  local nurLohnt = UI.Haken(p, "Nur wo AH lohnt",
    function() return mf.nurLohnt ~= false end,
    function(an) mf.nurLohnt = an; if p.LadeListe then p.LadeListe() end end)
  nurLohnt:SetPoint("TOPLEFT", 250, -72)
  local auchGeschuetzt = UI.Haken(p, "Auch behalten-Items",
    function() return mf.geschuetzt end,
    function(an) mf.geschuetzt = an; if p.LadeListe then p.LadeListe() end end)
  auchGeschuetzt:SetPoint("TOPLEFT", 420, -72)
  local handelText = UI.Text(p, "klein", 0.85, 0.85, 0.85)
  handelText:SetPoint("TOPLEFT", 676, -78)
  handelText:SetWidth(WW.INHALT_BREITE - 680)
  handelText:SetWordWrap(false)

  local legende = UI.Text(p, "klein", 0.8, 0.8, 0.8)
  legende:SetPoint("TOPLEFT", 4, -98)
  legende:SetWidth(WW.INHALT_BREITE - 8)
  legende:SetWordWrap(false)

  local LEGENDE = {
    taschen = ("%s = AH lohnt (nach Gebühren: 5 %% Abzug, neutral 15 %%; mind. %s mal Händlerpreis, %s mehr).  %s = knapp / Kaution hoch.  %s = Händler.  %s = nicht handelbar / kein Preis."),
  }
  local function legendeText()
    local db = WW.db.ah
    if ansicht == "taschen" then
      return LEGENDE.taschen:format(WW.f("gruen", "Grün"), tostring(db.faktor), WW.Geld(db.mindestGewinn),
        WW.f("gelb", "Gelb"), WW.f("rot", "Rot"), WW.f("grau", "Grau"))
    elseif ansicht == "schnaeppchen" then
      return ("Mindestpreis aus dem letzten Scan höchstens %d %% vom üblichen Mindestpreis (Durchschnitt der Scans). Ab %d Scans pro Item, sortiert nach Ersparnis je Stück."):format(
        runden((tonumber(db.schnaeppchen) or 0.7) * 100), MIN_SCANS)
    end
    if ansicht == "verkaufen" then
      return ("Ungebundene Items in deinen Taschen. Vorschlag: 1 Silber unter dem günstigsten Angebot, nie unter %d %% vom üblichen Preis und nie weniger als beim Händler. Erlös nach Gebühren und Kaution."):format(
        runden(BODEN_ANTEIL * 100))
    end
    return ("Mindestpreis aus dem letzten Scan mindestens %d %% vom üblichen Mindestpreis. Ab %d Scans pro Item, sortiert nach Aufschlag je Stück."):format(
      runden((tonumber(db.zuTeuer) or 1.3) * 100), MIN_SCANS)
  end

  -- Spaltenköpfe (zwei Sätze, je nach Ansicht)
  local kopfY = -118
  local koepfe = { taschen = {}, markt = {}, verkauf = {} }
  local function kopf(satz, text, x)
    local t = UI.Text(p, "klein", 0.9, 0.8, 0.3)
    t:SetPoint("TOPLEFT", 10 + x, kopfY)
    t:SetText(text)
    koepfe[satz][#koepfe[satz] + 1] = t
  end
  kopf("taschen", "Item", SPALTEN.name)
  kopf("taschen", "Anz.", SPALTEN.anzahl)
  kopf("taschen", "AH (nach Gebühren)", SPALTEN.ah)
  kopf("taschen", "Händler", SPALTEN.haendler)
  kopf("taschen", "Urteil", SPALTEN.urteil)
  kopf("markt", "Item", SPALTEN2.name)
  kopf("markt", "Jetzt (min)", SPALTEN2.preis)
  kopf("markt", "Üblich (min)", SPALTEN2.normal)
  kopf("markt", "Abweichung", SPALTEN2.abw)
  kopf("markt", "Menge", SPALTEN2.menge)
  kopf("verkauf", "Item", SPALTEN2.name)
  kopf("verkauf", "Vorschlag (je)", SPALTEN2.preis)
  kopf("verkauf", "Üblich (min)", SPALTEN2.normal)
  kopf("verkauf", "Erlös (alle)", SPALTEN2.abw)
  kopf("verkauf", "Du hast", SPALTEN2.menge)

  -- Kategorie (wie links in Blizzards Auktionshaus): Knopf über der Spalte mit den Prüfen-Knöpfen
  local katFenster
  local function katAufschrift()
    local k = AH.KategorieVon(mf.kategorie)
    return k and ("Kategorie: " .. k.name) or "Kategorie: alle"
  end
  local katKnopf = UI.Knopf(p, katAufschrift(), 150)
  katKnopf:SetHeight(18)
  katKnopf:SetPoint("TOPLEFT", 4 + 6 + SPALTEN2.knopf, -113)
  if katKnopf.GetFontString and katKnopf:GetFontString() and katKnopf:GetFontString().SetWordWrap then
    katKnopf:GetFontString():SetWordWrap(false)
  end
  local offenOben   -- aufgeklappte Oberkategorie (Name)
  local function katGewaehlt(pfad)
    mf.kategorie = pfad
    katKnopf:SetText(katAufschrift())
    if p.LadeListe then p.LadeListe() end
  end
  local function baueKatFenster()
    local f = CreateFrame("Frame", "WegweiserAHKategorie", p, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetFrameStrata("DIALOG")
    f:SetWidth(188)
    f:SetPoint("TOPRIGHT", katKnopf, "BOTTOMRIGHT", 0, -2)
    if f.SetBackdrop then
      f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
      f:SetBackdropColor(0.05, 0.05, 0.05, 0.97)
    end
    f:EnableMouse(true)
    tinsert(UISpecialFrames, "WegweiserAHKategorie")   -- Esc schließt
    f.zeilen = {}
    -- Zwei Spalten: links die Hauptkategorien, rechts die Unterkategorien der gewählten (sonst zu lang)
    local ZH, LB, RB = 16, 170, 190
    function f:Fuellen()
      local links = { { text = "Alle Kategorien", pfad = nil } }
      local rechts = {}
      for _, k in ipairs((AH.Kategorien())) do
        links[#links + 1] = { text = k.name, pfad = k.name, kinder = k.kinder ~= nil }
        if offenOben == k.name and k.kinder then
          for _, kind in ipairs(k.kinder) do rechts[#rechts + 1] = { text = kind.name, pfad = k.name .. "/" .. kind.name, unter = true } end
        end
      end
      for _, z in ipairs(self.zeilen) do z:Hide() end
      local n = 0
      local function zeile(e, spalte, i)
        n = n + 1
        local z = self.zeilen[n]
        if not z then
          z = CreateFrame("Button", nil, self)
          z:SetHeight(ZH)
          local hl = z:CreateTexture(nil, "HIGHLIGHT")
          hl:SetAllPoints()
          hl:SetColorTexture(1, 1, 1, 0.12)
          z.sel = z:CreateTexture(nil, "BACKGROUND")
          z.sel:SetAllPoints()
          z.sel:SetColorTexture(0.9, 0.75, 0.2, 0.25)
          z.text = UI.Text(z)
          z.text:SetPoint("LEFT", 4, 0)
          z.text:SetPoint("RIGHT", z, "RIGHT", -4, 0)
          if z.text.SetWordWrap then z.text:SetWordWrap(false) end
          self.zeilen[n] = z
        end
        z:ClearAllPoints()
        z:SetPoint("TOPLEFT", spalte == 1 and 6 or (6 + LB + 6), -6 - (i - 1) * ZH)
        z:SetWidth(spalte == 1 and LB or RB)
        local gewaehlt = mf.kategorie == e.pfad
          or (spalte == 1 and e.pfad and type(mf.kategorie) == "string" and mf.kategorie:match("^([^/]+)") == e.pfad)
        z.text:SetText(spalte == 1 and WW.f("titel", e.text) .. (e.kinder and WW.f("grau", "  >") or "") or e.text)
        z.sel:SetShown(gewaehlt and true or false)
        z.eintrag = e
        z:SetScript("OnClick", function(self)
          local x = self.eintrag
          katGewaehlt(x.pfad)
          if x.unter or not x.kinder then
            f:Hide()          -- Unterkategorie, "Alle" oder Kategorie ohne Unterteile: fertig
          else
            offenOben = x.pfad   -- Hauptkategorie: gewählt, rechts ihre Unterkategorien
            f:Fuellen()
          end
        end)
        z:Show()
      end
      for i, e in ipairs(links) do zeile(e, 1, i) end
      for i, e in ipairs(rechts) do zeile(e, 2, i) end
      self:SetWidth(12 + LB + (#rechts > 0 and (6 + RB) or 0))
      self:SetHeight(12 + math.max(#links, #rechts) * ZH)
    end
    f:Hide()
    return f
  end
  katKnopf:SetScript("OnClick", function()
    if not katFenster then
      katFenster = baueKatFenster()
      katFenster.knopf = katKnopf
      p.fenster[#p.fenster + 1] = katFenster
    end
    if katFenster:IsShown() then katFenster:Hide() return end
    offenOben = type(mf.kategorie) == "string" and mf.kategorie:match("^([^/]+)") or nil
    katFenster:Fuellen()
    p.nurDiesesFenster(katFenster)
  end)
  katKnopf:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Kategorie")
    GameTooltip:AddLine("Nur Items einer Art zeigen, wie links in Blizzards Auktionshaus (z. B. Handwerkswaren > Stoff).", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  katKnopf:SetScript("OnLeave", function() GameTooltip:Hide() end)


  local LISTEN_H = WW.INHALT_HOEHE - 138 - 30

  -- Liste 1: Inhalt der Taschen
  local liste, liste2
  local function baueZeile(z)
    z.icon = z:CreateTexture(nil, "ARTWORK")
    z.icon:SetSize(20, 20)
    z.icon:SetPoint("LEFT", 0, 0)
    z.name = UI.Text(z)
    z.name:SetPoint("LEFT", SPALTEN.name, 0)
    z.name:SetWidth(SPALTEN.anzahl - SPALTEN.name - 6)
    z.name:SetWordWrap(false)
    z.anzahl = UI.Text(z)
    z.anzahl:SetPoint("LEFT", SPALTEN.anzahl, 0)
    z.anzahl:SetWidth(36)
    z.anzahl:SetJustifyH("RIGHT")
    z.ah = UI.Text(z)
    z.ah:SetPoint("LEFT", SPALTEN.ah, 0)
    z.ah:SetWidth(SPALTEN.haendler - SPALTEN.ah - 6)
    z.ah:SetWordWrap(false)
    z.haendler = UI.Text(z)
    z.haendler:SetPoint("LEFT", SPALTEN.haendler, 0)
    z.haendler:SetWidth(SPALTEN.urteil - SPALTEN.haendler - 6)
    z.haendler:SetWordWrap(false)
    z.urteil = UI.Text(z)
    z.urteil:SetPoint("LEFT", SPALTEN.urteil, 0)
    z.urteil:SetWidth(140)
    z.urteil:SetWordWrap(false)
    z:SetScript("OnEnter", function(self)
      if self.eintrag then UI.ItemTooltip(self, self.eintrag.id) end
    end)
    z:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  local function fuelleZeile(z, e)
    z.icon:SetTexture(itemSymbol(e.id))
    local name = WW.ItemName(e.id) or ("Item " .. e.id)
    local q = select(3, WW.GetItemInfo(e.id))
    z.name:SetText(qualitaetsCode(q) .. name .. "|r" .. (e.bank and WW.f("grau", " (Bank)") or ""))
    z.anzahl:SetText(e.anzahl)
    z.ah:SetText((e.erloes or 0) > 0 and WW.Geld(e.erloes) or "-")
    z.haendler:SetText((e.haendler or 0) > 0 and WW.Geld(e.haendler) or "-")
    z.urteil:SetText(WW.f(e.farbe, e.text))
  end
  liste = UI.Liste(p, WW.INHALT_BREITE - 8, LISTEN_H, 22, baueZeile, fuelleZeile)
  AH._liste = liste   -- für /ww diag
  liste:SetPoint("TOPLEFT", 4, -134)
  liste.itemKlick = true   -- Klick auf eine Zeile: Item-Details im Reiter "Items"

  -- Liste 2: Schnäppchen / zu teuer
  local function baueZeile2(z)
    z.icon = z:CreateTexture(nil, "ARTWORK")
    z.icon:SetSize(20, 20)
    z.icon:SetPoint("LEFT", 0, 0)
    z.name = UI.Text(z)
    z.name:SetPoint("LEFT", SPALTEN2.name, 0)
    z.name:SetWidth(SPALTEN2.preis - SPALTEN2.name - 6)
    z.name:SetWordWrap(false)
    z.preis = UI.Text(z)
    z.preis:SetPoint("LEFT", SPALTEN2.preis, 0)
    z.preis:SetWidth(SPALTEN2.normal - SPALTEN2.preis - 6)
    z.preis:SetWordWrap(false)
    z.normal = UI.Text(z)
    z.normal:SetPoint("LEFT", SPALTEN2.normal, 0)
    z.normal:SetWidth(SPALTEN2.abw - SPALTEN2.normal - 6)
    z.normal:SetWordWrap(false)
    z.abw = UI.Text(z)
    z.abw:SetPoint("LEFT", SPALTEN2.abw, 0)
    z.abw:SetWidth(90)
    z.abw:SetWordWrap(false)
    z.menge = UI.Text(z)
    z.menge:SetPoint("LEFT", SPALTEN2.menge, 0)
    z.menge:SetWidth(76)
    z.menge:SetWordWrap(false)
    -- Kaufen / Einstellen (zwei Klicks, Module\AuktionHandel.lua)
    z.knopf = UI.Knopf(z, "", 130, function(self)
      local e = self:GetParent().eintrag
      if e and WW.AHHandel then WW.AHHandel.Klick(e, ansicht) end
    end)
    z.knopf:SetHeight(18)
    z.knopf:SetPoint("LEFT", SPALTEN2.knopf, 0)
    z.knopf:SetScript("OnEnter", function(self)
      local e = self:GetParent().eintrag
      if not (e and WW.AHHandel) then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine((ansicht == "teuer" or ansicht == "verkaufen") and "Einstellen" or "Sofort kaufen")
      GameTooltip:AddLine(WW.ItemName(e.id) or ("Item " .. e.id), 0.8, 0.8, 0.8)
      GameTooltip:AddLine(WW.AHHandel.KnopfHilfe(e, ansicht), 1, 1, 1, true)
      if not AH.Offen() then GameTooltip:AddLine("Das Auktionshaus ist zu.", 1, 0.3, 0.3) end
      GameTooltip:Show()
    end)
    z.knopf:SetScript("OnLeave", function() GameTooltip:Hide() end)
    z:SetScript("OnEnter", function(self)
      if self.eintrag then UI.ItemTooltip(self, self.eintrag.id) end
    end)
    z:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  local function fuelleZeile2(z, e)
    z.icon:SetTexture(itemSymbol(e.id))
    local name = WW.ItemName(e.id) or ("Item " .. e.id)
    local q = select(3, WW.GetItemInfo(e.id))
    z.name:SetText(qualitaetsCode(q) .. name .. "|r")
    -- kurz, sonst schneidet die Spalte hohe Preise ab ("178g 56s ..."); genauer Preis im Tooltip und beim Prüfen
    z.preis:SetText(WW.GeldKurz(e.preis))
    z.normal:SetText(WW.GeldKurz(runden(e.normal)))
    if ansicht == "verkaufen" then
      -- Vorschlag gelb, wenn er die Untergrenze ist (das günstigste Angebot ist billiger)
      z.preis:SetText(e.zurGrenze and WW.f("gelb", WW.GeldKurz(e.preis)) or WW.GeldKurz(e.preis))
      z.abw:SetText(WW.f(e.farbe or "weiss", WW.GeldKurz(e.erloes)))
      z.menge:SetText(e.menge .. (e.geschuetzt and WW.f("gelb", " (B)") or ""))   -- B = Urteil will behalten
      z.knopf:SetShown(true)
    elseif ansicht == "teuer" then
      z.abw:SetText(WW.f(e.abw < 0 and "gruen" or "rot", ("%+d %%"):format(runden(e.abw * 100))))
      local hab = WW.AHHandel and WW.AHHandel.Besitz(e.id) or 0
      z.menge:SetText(e.menge .. (hab > 0 and WW.f("gruen", " (du " .. hab .. ")") or ""))
      z.knopf:SetShown(hab > 0)
    else
      z.abw:SetText(WW.f(e.abw < 0 and "gruen" or "rot", ("%+d %%"):format(runden(e.abw * 100))))
      z.menge:SetText(e.menge)
      z.knopf:SetShown(true)
    end
    if z.knopf:IsShown() then
      z.knopf:SetText(WW.AHHandel and WW.AHHandel.KnopfText(e, ansicht) or "")
      setzeAktiv(z.knopf, AH.Offen())
    end
  end
  liste2 = UI.Liste(p, WW.INHALT_BREITE - 8, LISTEN_H, 22, baueZeile2, fuelleZeile2)
  liste2:SetPoint("TOPLEFT", 4, -134)
  liste2.itemKlick = true   -- Klick auf eine Zeile: Item-Details im Reiter "Items"
  liste2:Hide()

  -- Hinweis in der leeren Liste (liegt auf der Liste, sonst verdeckt ihr Hintergrund den Text)
  local leer = UI.Text(liste2, "klein", 0.75, 0.75, 0.75)
  leer:SetPoint("TOPLEFT", 16, -16)
  leer:SetWidth(WW.INHALT_BREITE - 60)
  leer:SetSpacing(3)
  leer:SetJustifyV("TOP")

  -- Streifen mit den gescannten Uhrzeiten, unten im Reiter
  local streifen = UI.Text(p, "klein", 0.8, 0.8, 0.8)
  streifen:SetPoint("BOTTOMLEFT", 4, 2)
  streifen:SetWidth(WW.INHALT_BREITE - 8)
  streifen:SetSpacing(2)
  streifen:SetJustifyV("BOTTOM")

  local function ladeListe()
    if ansicht == "taschen" then
      liste:Setze(taschenListe())
      return
    end
    local eintraege, bereit = {}, 0
    if ansicht == "verkaufen" then
      local alleV = AH.VerkaufListe(mf)
      -- Läuft gerade ein Einstellen (bereit oder Warnung des Servers), bleibt seine Zeile stehen: nach der Warnung
      -- sperrt das Spiel die Items vielleicht schon, dann fehlen sie in der Taschen-Liste und "Trotzdem?" wäre weg.
      local laufend = WW.AHHandel and WW.AHHandel.Zustand and WW.AHHandel.Zustand()
      if type(laufend) == "table" and laufend.ansicht == "verkaufen"
        and (laufend.phase == "bereit" or laufend.phase == "warnung") then
        local da = false
        for _, e in ipairs(alleV) do if e.id == laufend.id then da = true end end
        if not da then
          for _, e in ipairs(liste2.eintraege or {}) do
            if e.id == laufend.id and e.boden then table.insert(alleV, 1, e) break end
          end
        end
      end
      eintraege = AH.MarktFiltern(alleV, ansicht, filterText)
      liste2:Setze(eintraege)
      if #eintraege > 0 then
        leer:SetText("")
      elseif #alleV > 0 then
        leer:SetText(("Kein Treffer für die Suche (%d Items ohne Suche)."):format(#alleV))
      elseif not scanListe()[1] then
        leer:SetText("Noch kein Scan auf diesem Realm. Scanne das Auktionshaus, dann siehst du hier Preise für deine Items.")
      else
        leer:SetText("Nichts zu verkaufen. Ohne Haken \"Nur wo AH lohnt\" siehst du auch Items, die der Händler besser bezahlt.")
      end
      return
    end
    if ansicht == "schnaeppchen" then eintraege, bereit = AH.Schnaeppchen() else eintraege, bereit = AH.ZuTeuer() end
    local alle = #eintraege
    eintraege = AH.MarktFiltern(eintraege, ansicht, filterText)
    liste2:Setze(eintraege)
    if #eintraege == 0 and alle > 0 then
      leer:SetText(("Kein Treffer für die Filter (%d Items ohne Filter). Nimm einen Filter weg."):format(alle))
    elseif #eintraege > 0 then
      leer:SetText("")
    elseif not scanListe()[1] then
      leer:SetText("Noch kein Scan auf diesem Realm. Scanne das Auktionshaus mindestens " .. MIN_SCANS
        .. " Mal (zu verschiedenen Zeiten), dann siehst du hier Schnäppchen und überteuerte Items.")
    elseif bereit == 0 then
      leer:SetText("Noch keine Items mit genug Verlauf. Ein Item braucht mindestens " .. MIN_SCANS
        .. " Scans, bevor es mit seinem Normalpreis verglichen wird. Scanne öfter, am besten zu verschiedenen Tageszeiten.")
    elseif ansicht == "schnaeppchen" then
      leer:SetText(("Zurzeit keine Schnäppchen unter %d %% vom üblichen Mindestpreis (%d Items verglichen)."):format(
        runden((tonumber(WW.db.ah.schnaeppchen) or 0.7) * 100), bereit))
    else
      leer:SetText(("Zurzeit nichts über %d %% vom üblichen Mindestpreis (%d Items verglichen)."):format(
        runden((tonumber(WW.db.ah.zuTeuer) or 1.3) * 100), bereit))
    end
  end

  setzeAnsicht = function(neu)
    ansicht = neu
    for k, knopf in pairs(ansichtKnopf) do
      if k == neu then knopf:LockHighlight() else knopf:UnlockHighlight() end
    end
    local taschen = neu == "taschen"
    liste:SetShown(taschen)
    liste2:SetShown(not taschen)
    for _, t in ipairs(koepfe.taschen) do t:SetShown(taschen) end
    for _, t in ipairs(koepfe.markt) do t:SetShown(neu == "schnaeppchen" or neu == "teuer") end
    for _, t in ipairs(koepfe.verkauf) do t:SetShown(neu == "verkaufen") end
    neuKnopf:SetText(taschen and "Taschen neu laden" or "Liste neu laden")
    for _, h in ipairs(taschenHaken) do h:SetShown(taschen) end
    sucheLabel:SetShown(not taschen)
    suche:SetShown(not taschen)
    handelText:SetShown(not taschen)
    bezahlbar:SetShown(neu == "schnaeppchen")
    ersparnisKnopf:SetShown(neu == "schnaeppchen")
    qualitaetKnopf:SetShown(neu == "schnaeppchen")
    if filterFenster and neu ~= "schnaeppchen" then filterFenster:Hide() end
    nurMeine:SetShown(neu == "teuer")
    nurLohnt:SetShown(neu == "verkaufen")
    katKnopf:SetShown(not taschen)
    katKnopf:SetText(katAufschrift())   -- Blizzards Liste kann inzwischen geladen sein
    if katFenster and taschen then katFenster:Hide() end
    auchGeschuetzt:SetShown(neu == "verkaufen")
    legende:SetText(legendeText())
    ladeListe()
  end

  p.LadeListe = function() if ansicht ~= "taschen" then ladeListe() end end
  -- Kauf/Verkauf: Knöpfe und Meldung neu zeichnen
  if WW.AHHandel then
    WW.AHHandel.BeiAenderung(function()
      if not p:IsShown() then return end
      local _, m = WW.AHHandel.Zustand()
      handelText:SetText(m or "")
      liste2:Aktualisiere()
    end)
  end

  neuKnopf:SetScript("OnClick", function()
    ladeListe()
    if ansicht == "taschen" then AH.TaschenAktualisieren() end
  end)

  local function zeigeStatus()
    local zeilen = {}
    local zustand = {}   -- zweite Zeile: Scan-Meldung, Pause, Auktionshaus offen/zu
    local st = scanListe()[1]
    if st then
      local z = tonumber(st.z)
      if not z then
        z = 0
        for _ in pairs(st.i) do z = z + 1 end
      end
      zeilen[#zeilen + 1] = ("Letzter Scan: %s - %s (%s), %d Items aus %d Angeboten."):format(
        vor(time() - (tonumber(st.t) or 0)), tostring(st.r or realmName() or "?"), FRAKTION_DE[st.f] or tostring(st.f or "?"),
        z, tonumber(st.n) or 0)
    else
      zeilen[#zeilen + 1] = "Auf diesem Realm gibt es noch keinen Scan. Öffne das Auktionshaus und klicke auf \"Jetzt scannen\"."
    end
    if S.phase == "warten" then
      zustand[#zustand + 1] = WW.f("gelb", "Scan: warte auf das Auktionshaus ...")
    elseif S.phase == "lesen" then
      zustand[#zustand + 1] = WW.f("gelb", ("Scan: %d von %d Angeboten gelesen."):format(S.fertig, S.gesamt))
    elseif S.phase == "rechnen" then
      zustand[#zustand + 1] = WW.f("gelb", ("Scan: rechne Preise aus (%d von %d Items)."):format(S.fertig, S.gesamt2 or 0))
    elseif S.phase == "fehler" and S.meldung then
      zustand[#zustand + 1] = WW.f("rot", S.meldung)
    elseif S.phase == "fertig" and S.meldung then
      zustand[#zustand + 1] = WW.f("gruen", S.meldung)
    elseif S.meldung then
      zustand[#zustand + 1] = WW.f("orange", S.meldung)
    end
    if S.pause then zustand[#zustand + 1] = WW.f("orange", "Pausiert: du bist im Kampf.") end
    if not api() then
      zustand[#zustand + 1] = WW.f("rot", "Dieser Client lässt Addons das Auktionshaus nicht lesen.")
    elseif S.offen then
      local warte = AH.Wartezeit()
      if warte > 0 then
        zustand[#zustand + 1] = ("Auktionshaus offen. Nächster Voll-Scan in %d:%02d Min."):format(
          math.floor(warte / 60), math.floor(warte % 60))
      else
        zustand[#zustand + 1] = "Auktionshaus offen. Du kannst jetzt scannen."
      end
    else
      zustand[#zustand + 1] = WW.f("grau", "Auktionshaus geschlossen. Gehe zu einem Auktionator, um zu scannen.")
    end
    status:SetText(zeilen[1] or "")
    status2:SetText(table.concat(zustand, "  ·  "))
    streifen:SetText(streifenText())
    setzeAktiv(scanKnopf, (AH.KannScannen()))
  end

  local letztePhase = S.phase
  zuhoerer[#zuhoerer + 1] = function()
    if not p:IsShown() then return end
    zeigeStatus()
    if S.phase ~= letztePhase then
      letztePhase = S.phase
      if S.phase == "fertig" then ladeListe() end   -- neue Preise: Listen neu aufbauen
    end
  end
  WW:Event("BAG_UPDATE_DELAYED", function()
    if p:IsShown() and (ansicht == "taschen" or ansicht == "verkaufen") then ladeListe() end   -- Taschen geändert
  end)

  local zeit = 0
  p:SetScript("OnUpdate", function(_, dt)
    zeit = zeit + dt
    if zeit >= 1 then
      zeit = 0
      zeigeStatus()
    end
  end)
  p.OnZeigen = function()
    zeigeStatus()
    setzeAnsicht(ansicht)
  end
end)
