-- Szenen fuer Inventar.lua: Aufnahme von Taschen, Bank, Ausruestung, mehrere Charaktere, Tooltip, Reiter.
-- SZENE: Inventar - Vorbereiten (Taschen, Bank und Charaktere nachgebaut)
function __GLEICH(ist, soll, was)
  if ist ~= soll then error((was or "?") .. ": erwartet " .. tostring(soll) .. ", war " .. tostring(ist), 2) end
end
function __ENTHAELT(text, teil, was)
  if type(text) ~= "string" or not text:find(teil, 1, true) then
    error((was or "?") .. ": '" .. tostring(teil) .. "' fehlt in '" .. tostring(text) .. "'", 2)
  end
end
__INV_ALT = __INV_ALT or {
  num = C_Container.GetContainerNumSlots, info = C_Container.GetContainerItemInfo,
  name = UnitName, geld = rawget(_G, "GetMoney"), link = rawget(_G, "GetInventoryItemLink"),
}
__NAME = "Dan"
__GELD = 123456
-- __BAGS[behaelter] = { { itemID, anzahl, gebunden }, ... }  (Platz = Reihenfolge)
__BAGS = {
  [0] = { { 3001, 5, false }, { 3002, 2, true }, { 3001, 3, false } },
  [-1] = {},
}
C_Container.GetContainerNumSlots = function(b) return __BAGS[b] and #__BAGS[b] or 0 end
C_Container.GetContainerItemInfo = function(b, s)
  local x = __BAGS[b] and __BAGS[b][s]
  if x then return { itemID = x[1], stackCount = x[2], isBound = x[3], hyperlink = "|Hitem:" .. x[1] .. "|h" } end
end
UnitName = function() return __NAME end
GetMoney = function() return __GELD end
GetInventoryItemLink = function(u, slot)
  if slot == 1 then return "|Hitem:5000|h[Helm]|h" end
  if slot == 16 then return "|Hitem:5001|h[Schwert]|h" end
end
local db = __WW.db
db.inventar = {}
db.inventarEinst.tooltip = true
db.inventarEinst.nurDieser = false
db.inventarEinst.nurVerkaufbar = false
db.inventarEinst.sortierung = "gewinn"

-- SZENE: Inventar - Taschen und Ausruestung werden aufgenommen
__FEUER("BAG_UPDATE_DELAYED")
__UPDATE(8)
local e = __WW.db.inventar["Forever"] and __WW.db.inventar["Forever"]["Dan"]
if not e then error("kein Eintrag fuer Dan") end
__GLEICH(e.tasche, "3001:8:0,3002:2:1", "Taschen zusammengefasst und sortiert")
__GLEICH(e.angelegt, "1:5000,16:5001", "angelegt")
__GLEICH(e.klasse, "WARRIOR", "Klasse")
__GLEICH(e.stufe, 30, "Stufe")
__GLEICH(e.fraktion, "Alliance", "Fraktion")
__GLEICH(e.geld, 123456, "Geld")
__GLEICH(e.bank, nil, "Bank noch nie geoeffnet")
__GLEICH(e.bankT, nil, "kein Bank-Zeitpunkt")
-- Geld wird nachgezogen
__GELD = 200000
__FEUER("PLAYER_MONEY")
__GLEICH(e.geld, 200000, "Geld nach PLAYER_MONEY")
__LOG[#__LOG + 1] = "Inventar Dan: " .. e.tasche .. " | " .. e.angelegt

-- SZENE: Inventar - Bank wird nur bei offener Bank gelesen und bleibt danach stehen
local e = __WW.db.inventar["Forever"]["Dan"]
__BAGS[-1] = { { 3001, 20, false } }
__BAGS[5] = { { 3003, 1, false } }
-- Bank zu: Aenderungen werden nicht uebernommen
__FEUER("BAG_UPDATE_DELAYED")
__UPDATE(8)
__GLEICH(e.bank, nil, "geschlossene Bank wird nicht gelesen")
__FEUER("BANKFRAME_OPENED")
__UPDATE(8)
__GLEICH(e.bank, "3001:20:0,3003:1:0", "Bank gelesen")
if not e.bankT then error("bankT fehlt") end
__FEUER("BANKFRAME_CLOSED")
__BAGS[-1], __BAGS[5] = {}, nil
__FEUER("BAG_UPDATE_DELAYED")
__UPDATE(8)
__GLEICH(e.bank, "3001:20:0,3003:1:0", "letzter Bank-Stand bleibt")

-- SZENE: Inventar - zweiter Charakter und Bestand
__NAME = "Enzrok"
__BAGS[0] = { { 3001, 40, false } }
__GELD = 5000
__FEUER("PLAYER_LOGOUT")
local en = __WW.db.inventar["Forever"]["Enzrok"]
if not en then error("kein Eintrag fuer Enzrok") end
__GLEICH(en.tasche, "3001:40:0", "Taschen Enzrok")
__GLEICH(en.bank, nil, "Enzrok ohne Bank")
__NAME = "Dan"
__BAGS[0] = { { 3001, 5, false }, { 3002, 2, true }, { 3001, 3, false } }
__FEUER("PLAYER_LOGOUT")
local liste, summe = __WW.Inventar.Bestand(3001)
__GLEICH(summe, 68, "Summe 3001")
__GLEICH(#liste, 2, "zwei Charaktere haben 3001")
__GLEICH(liste[1].name, "Enzrok", "Enzrok hat am meisten")
__GLEICH(liste[1].anzahl, 40, "Enzrok 40")
__GLEICH(liste[2].anzahl, 28, "Dan: Tasche 8 + Bank 20")
local chars = __WW.Inventar.Charaktere()
__GLEICH(#chars, 2, "zwei Charaktere")
__GLEICH(chars[1].name, "Dan", "eigener Charakter zuerst")

-- SZENE: Inventar - Tooltip "Du hast"
local zeilen = {}
GameTooltip.AddLine = function(self, text) zeilen[#zeilen + 1] = text end
local function tip(id)
  zeilen = {}
  local f = GameTooltip.__scripts.OnTooltipCleared
  if f then f(GameTooltip) end
  __WW.Inventar.TooltipZeile(GameTooltip, { id = id, type = 0 })
  return table.concat(zeilen, " | ")
end
__GLEICH(tip(3001), "Du hast: 68 (Enzrok 40, Dan 28)", "Tooltip 3001")
__GLEICH(tip(3002), "", "3002 liegt nur in den Taschen von Dan")
__ENTHAELT(tip(3003), "Du hast: 1 (Dan 1)", "3003 liegt in der Bank")
__GLEICH(tip(99999), "", "unbekanntes Item")
-- nur einmal pro Anzeige
zeilen = {}
GameTooltip.__scripts.OnTooltipCleared(GameTooltip)
__WW.Inventar.TooltipZeile(GameTooltip, { id = 3001 })
__WW.Inventar.TooltipZeile(GameTooltip, { id = 3001 })
__GLEICH(#zeilen, 1, "Zeile nur einmal")
__WW.db.inventarEinst.tooltip = false
__GLEICH(tip(3001), "", "Tooltip ausgeschaltet")
__WW.db.inventarEinst.tooltip = true

-- SZENE: Inventar - Bestand bauen: Suche, nur verkaufbar, Summen
-- AH-Preis fuer 3001 (Mindestpreis 1000, Median 1000)
__WW.db.ah["Forever|Alliance"] = { r = "Forever", f = "Alliance", t = time(), n = 1, z = 1, m = "replicate", i = { [3001] = "1000,1000,5" } }
local chars = __WW.Inventar.Charaktere()
local liste, s = __WW.Inventar.BestandBauen(chars, false, "", "gewinn")
local nach = {}
for _, x in ipairs(liste) do nach[x.id] = x end
__GLEICH(nach[3001].gesamt, 68, "3001 gesamt")
__GLEICH(nach[3001].frei, 68, "3001 ungebunden")
__ENTHAELT(nach[3001].wotext, "Dan: Tasche 8, Bank 20", "Wo Dan")
__ENTHAELT(nach[3001].wotext, "Enzrok: Tasche 40", "Wo Enzrok")
__GLEICH(nach[3002].gesamt, 2, "3002 gesamt")
__GLEICH(nach[3002].frei, 0, "3002 gebunden")
__GLEICH(nach[3002].farbe, "grau", "3002 grau")
__GLEICH(nach[5000].gesamt, 2, "angelegtes Item gezaehlt (Dan und Enzrok)")
__ENTHAELT(nach[5000].wotext, "angelegt", "angelegt im Wo-Text")
__GLEICH(liste[1].id, 3001, "groesster AH-Gewinn zuerst")
__GLEICH(nach[3001].farbe, "gruen", "AH lohnt fuer 3001")
__GLEICH(s.ah, math.floor(1000 * 68 * 0.95), "Verkaufswert AH")
__GLEICH(s.ahLohnt, math.floor(1000 * 68 * 0.95), "davon lohnt AH")
__GLEICH(s.haendler, 150 * 68 + 150, "beim Haendler (3001 und 3003)")
-- nur verkaufbar: 3002 und die Ausruestung fehlen
local l2 = __WW.Inventar.BestandBauen(chars, true, "", "name")
for _, x in ipairs(l2) do
  if x.id == 3002 or x.id == 5000 or x.id == 5001 then error("gebundenes Item in 'nur verkaufbar': " .. x.id) end
end
-- Suche
local l3 = __WW.Inventar.BestandBauen(chars, false, "deutsch3003", "name")
__GLEICH(#l3, 1, "Suche nach Namen")
__GLEICH(l3[1].id, 3003, "Suchtreffer")
local l4 = __WW.Inventar.BestandBauen(chars, false, "3002", "name")
__GLEICH(#l4, 1, "Suche nach Nummer")
-- Sortierung nach Anzahl
local l5 = __WW.Inventar.BestandBauen(chars, false, "", "anzahl")
__GLEICH(l5[1].id, 3001, "Anzahl: 3001 zuerst")
-- nur ein Charakter
local nurDan = {}
for _, c in ipairs(chars) do if c.name == "Dan" then nurDan[1] = c end end
local l6 = __WW.Inventar.BestandBauen(nurDan, false, "item3001", "name")
__GLEICH(l6[1].gesamt, 28, "nur Dan: 3001 gesamt")

-- SZENE: Inventar - Reiter, Knoepfe und Summenzeile
__WW:Oeffnen("inventar")
__UPDATE(8)
local function knopf(text)
  for _, f in ipairs(__FRAMES) do if f.__typ == "Button" and f.__text == text then return f end end
end
local function itemListe()
  for _, f in ipairs(__FRAMES) do
    if f.eintraege and f.eintraege[1] and f.eintraege[1].wotext then return f end
  end
end
local function charListe()
  for _, f in ipairs(__FRAMES) do
    if f.eintraege and f.eintraege[1] and f.eintraege[1].schluessel then return f end
  end
end
local function textMit(teil)
  for _, f in ipairs(__FRAMES) do
    if f.__typ == "FontString" and type(f.__text) == "string" and f.__text:find(teil, 1, true) then return f end
  end
end
local cl = charListe()
if not cl then error("Charakterliste fehlt") end
__GLEICH(#cl.eintraege, 2, "zwei Charaktere in der Liste")
local il = itemListe()
if not il then error("Item-Liste fehlt") end
local x3001
for _, x in ipairs(il.eintraege) do if x.id == 3001 then x3001 = x end end
__GLEICH(x3001 and x3001.gesamt, 68, "alle Charaktere: 3001 gesamt")
local sum = textMit("Verkaufswert AH:")
if not sum then error("Summenzeile fehlt") end
__ENTHAELT(sum.__text, "beim Händler:", "Summenzeile")
__ENTHAELT(sum.__text, "davon lohnt AH:", "Summenzeile")
__ENTHAELT(sum.__text, tostring(math.floor(1000 * 68 * 0.95)) .. "c", "AH-Wert in der Summenzeile")
-- nur dieser Charakter
local k = knopf("Nur dieser")
k.__scripts.OnClick(k, "LeftButton")
il = itemListe()
x3001 = nil
for _, x in ipairs(il.eintraege) do if x.id == 3001 then x3001 = x end end
__GLEICH(x3001 and x3001.gesamt, 28, "nur Dan: 3001 gesamt")
-- Charakter in der linken Liste anklicken (Enzrok)
local zeile
for _, f in ipairs(__FRAMES) do
  if f.eintraege == nil and f.eintrag and f.eintrag.name == "Enzrok" and f.__scripts.OnClick then zeile = f end
end
if not zeile then error("Zeile fuer Enzrok fehlt") end
zeile.__scripts.OnClick(zeile, "LeftButton")
__UPDATE(3)
il = itemListe()
x3001 = nil
for _, x in ipairs(il.eintraege) do if x.id == 3001 then x3001 = x end end
__GLEICH(x3001 and x3001.gesamt, 40, "nur Enzrok: 3001 gesamt")
local k2 = knopf("Alle Charaktere")
k2.__scripts.OnClick(k2, "LeftButton")
-- Sortierung durchschalten
local sk = knopf("Sortierung: AH-Gewinn")
if not sk then error("Sortierknopf fehlt") end
sk.__scripts.OnClick(sk, "LeftButton")
__ENTHAELT(sk.__text, "Name", "Sortierung Name")
sk.__scripts.OnClick(sk, "LeftButton")
__ENTHAELT(sk.__text, "Anzahl", "Sortierung Anzahl")
sk.__scripts.OnClick(sk, "LeftButton")
__ENTHAELT(sk.__text, "AH-Gewinn", "Sortierung AH-Gewinn")
-- Haken "Nur verkaufbar" und Slash
__WW.db.inventarEinst.nurVerkaufbar = true
k2.__scripts.OnClick(k2, "LeftButton")
il = itemListe()
for _, x in ipairs(il.eintraege) do
  if x.id == 3002 then error("gebundenes 3002 trotz 'nur verkaufbar'") end
end
__WW.db.inventarEinst.nurVerkaufbar = false
SlashCmdList.WEGWEISER("inventar")
__UPDATE(3)
-- Klick und Hover auf alles in diesem Reiter
for _, f in ipairs(__FRAMES) do
  if f.__shown and f.__scripts.OnEnter then f.__scripts.OnEnter(f) end
end

-- SZENE: Inventar - Ansicht Taschen im Auktionshaus mit Bank
__WW.db.ah.taschenBank = true
__WW:Oeffnen("ah")
__UPDATE(5)
local gefunden
for _, f in ipairs(__FRAMES) do
  if f.eintraege then
    for _, x in ipairs(f.eintraege) do if x.bank and x.id == 3003 then gefunden = x end end
  end
end
if not gefunden then error("Bank-Zeile in der Taschenansicht fehlt") end
__WW.db.ah.taschenBank = false

-- SZENE: Inventar - moderne Taschenordnung (Materialtasche 5, Bankfaecher 6-12)
__ENUM_ALT = rawget(_G, "Enum")
Enum = { BagIndex = { Backpack = 0, Bag_1 = 1, Bag_2 = 2, Bag_3 = 3, Bag_4 = 4, ReagentBag = 5, Bank = -1,
  BankBag_1 = 6, BankBag_2 = 7, BankBag_3 = 8, BankBag_4 = 9, BankBag_5 = 10, BankBag_6 = 11, BankBag_7 = 12 } }
__NAME = "Modern"
__BAGS = {
  [0] = { { 3001, 1, false } },
  [5] = { { 3010, 50, false } },
  [-1] = { { 3011, 2, false } },
  [6] = { { 3013, 4, false } },
  [12] = { { 3012, 1, false } },
}
__FEUER("BANKFRAME_OPENED")
__UPDATE(5)
__FEUER("BANKFRAME_CLOSED")
local e = __WW.db.inventar["Forever"]["Modern"]
if not e then error("kein Eintrag fuer Modern") end
__ENTHAELT(e.tasche, "3010:50:0", "Materialtasche gehoert zu den Taschen")
__ENTHAELT(e.bank, "3011:2:0", "Bank-Hauptfach")
__ENTHAELT(e.bank, "3013:4:0", "erstes Bankfach")
__ENTHAELT(e.bank, "3012:1:0", "letztes Bankfach")
if e.bank:find("3010", 1, true) then error("Materialtasche darf nicht zur Bank zaehlen: " .. e.bank) end
-- die Taschenansicht im Auktionshaus kennt die Materialtasche auch
__WW:Oeffnen("ah")
__UPDATE(5)
local gefunden
for _, f in ipairs(__FRAMES) do
  if f.eintraege then for _, x in ipairs(f.eintraege) do if x.id == 3010 and not x.bank then gefunden = x end end end
end
if not gefunden then error("Taschenansicht ohne Materialtasche") end
local ids = __WW.TaschenIDs()
__GLEICH(#ids, 6, "sechs Taschen (Rucksack, 4 Taschen, Materialtasche)")
local bank = __WW.BankIDs()
__GLEICH(#bank, 8, "acht Bankbehaelter")

-- SZENE: Inventar - Bank in Reitern (Hauptfach hat keine Plaetze)
Enum = { BagIndex = { Backpack = 0, Bag_1 = 1, Bag_2 = 2, Bag_3 = 3, Bag_4 = 4, ReagentBag = 5, Bank = -1,
  CharacterBankTab_1 = 6, CharacterBankTab_2 = 7, CharacterBankTab_3 = 8 } }
__NAME = "Reiter"
__BAGS = {
  [0] = { { 3001, 1, false } },
  [6] = { { 3020, 10, false } },
  [8] = { { 3021, 1, false } },
}
__FEUER("BANKFRAME_OPENED")
__UPDATE(5)
__FEUER("BANKFRAME_CLOSED")
local e = __WW.db.inventar["Forever"]["Reiter"]
if not e then error("kein Eintrag fuer Reiter") end
__ENTHAELT(e.bank or "", "3020:10:0", "Bank-Reiter 1")
__ENTHAELT(e.bank or "", "3021:1:0", "Bank-Reiter 3")
if not e.bankT then error("Bank wurde nicht gespeichert") end

-- SZENE: Inventar - klassische Taschenordnung (ohne Enum.BagIndex) funktioniert weiter
Enum = nil
__NAME = "Klassik"
__BAGS = {
  [0] = { { 3001, 1, false } },
  [1] = { { 3030, 7, false } },
  [-1] = { { 3031, 3, false } },
  [5] = { { 3032, 2, false } },
  [11] = { { 3033, 1, false } },
}
__FEUER("BANKFRAME_OPENED")
__UPDATE(5)
__FEUER("BANKFRAME_CLOSED")
local e = __WW.db.inventar["Forever"]["Klassik"]
if not e then error("kein Eintrag fuer Klassik") end
__ENTHAELT(e.tasche, "3030:7:0", "Tasche 1")
if e.tasche:find("3032", 1, true) then error("Bankfach 5 darf nicht zu den Taschen zaehlen: " .. e.tasche) end
__ENTHAELT(e.bank, "3031:3:0", "Hauptfach")
__ENTHAELT(e.bank, "3032:2:0", "erstes Bankfach (5)")
__ENTHAELT(e.bank, "3033:1:0", "letztes Bankfach (11)")
__GLEICH(#__WW.TaschenIDs(), 5, "klassisch: Rucksack und vier Taschen")
__GLEICH(#__WW.BankIDs(), 8, "klassisch: Hauptfach und sieben Fächer")
Enum = __ENUM_ALT

-- SZENE: Inventar - Aufraeumen (Mock zurueck)
Enum = __ENUM_ALT
C_Container.GetContainerNumSlots = __INV_ALT.num
C_Container.GetContainerItemInfo = __INV_ALT.info
UnitName = __INV_ALT.name
GetMoney = nil
GetInventoryItemLink = nil
__WW.db.inventar = {}
