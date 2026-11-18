-- Szenen fuer Haendler.lua: was verkauft wird, Bestaetigung mit zwei Klicks, langsamer Verkauf, Stopp beim Schliessen.
-- Nachbildung: GetItemInfo liefert Qualitaet 2 und Verkaufspreis 150 fuer jedes Item.
-- SZENE: Haendler - Vorbereiten
__HD_ALT = { num = C_Container.GetContainerNumSlots, info = C_Container.GetContainerItemInfo,
  use = C_Container.UseContainerItem, mf = rawget(_G, "MerchantFrame"), getTime = GetTime }
-- __HD_BAGS[bag][slot] = { id, anzahl, gebunden, qualitaet, gesperrt }
__HD_BAGS = {
  [0] = { { 6001, 3, false, 0 }, { 6002, 1, false, 2 }, { 6003, 5, false, 2 }, { 6004, 1, true, 0, false }, { 6005, 1, false, 0, true } },
  [1] = { { 6006, 2, false, 2 } },
}
C_Container.GetContainerNumSlots = function(b) return __HD_BAGS[b] and #__HD_BAGS[b] or 0 end
C_Container.GetContainerItemInfo = function(b, s)
  local x = __HD_BAGS[b] and __HD_BAGS[b][s]
  if x then return { itemID = x[1], stackCount = x[2], isBound = x[3], quality = x[4], isLocked = x[5] or false } end
end
__HD_VERKAUFT = {}
C_Container.UseContainerItem = function(b, s)
  local x = __HD_BAGS[b] and __HD_BAGS[b][s]
  if x then __HD_VERKAUFT[#__HD_VERKAUFT + 1] = x[1]; __HD_BAGS[b][s] = false end
end
MerchantFrame = CreateFrame("Frame", "MerchantFrame", UIParent)
__HD_T = 100
GetTime = function() return __HD_T end
-- AH: 6003 bringt im AH weniger als beim Haendler (rot), 6006 lohnt im AH (gruen)
__WW.db.ah["Forever|Alliance"] = { r = "Forever", f = "Alliance", t = time(), n = 4, z = 2, m = "test", i = {
  [6003] = "100,100,10", [6006] = "90000,90000,3" } }
__WW.db.ahVerlauf["Forever|Alliance"] = { [6003] = "100,5,498598,100;6:100:1", [6021] = "100,5,498598,100;6:100:1",
  [6022] = "100,1,498598,100;6:100:1", [6023] = "90000,5,498598,90000;6:90000:1" }
if __WW.db.haendler.rote ~= false then error("rote muessen am Anfang aus sein") end
if __WW.db.haendler.graue ~= true then error("graue muessen am Anfang an sein") end
__WW.db.haendler.knopf, __WW.db.haendler.graue, __WW.db.haendler.rote = true, true, true

-- SZENE: Haendler - Liste: grau und rot, nicht gesperrt, nicht gruen
local liste, summe = __WW.Haendler.Liste()
local ids = {}
for _, e in ipairs(liste) do ids[#ids + 1] = e.id .. ":" .. e.grund end
local text = table.concat(ids, ",")
if text ~= "6001:grau,6003:AH lohnt nicht,6004:grau" then error("Liste falsch: " .. text) end
if summe ~= 3 * 150 + 5 * 150 + 150 then error("Summe falsch: " .. tostring(summe)) end
__WW.db.haendler.rote = false
liste = __WW.Haendler.Liste()
if #liste ~= 2 then error("ohne rote: erwartet 2, war " .. #liste) end
__WW.db.haendler.rote = true

-- SZENE: Haendler - Knopf: erster Klick verkauft nichts, zweiter Klick verkauft langsam
__FEUER("MERCHANT_SHOW")
local k = WegweiserHaendlerKnopf
if not k then error("Haendler-Knopf fehlt") end
if not k.__text:find("3 Items", 1, true) then error("Knopftext: " .. tostring(k.__text)) end
k.__scripts.OnEnter(k)
k.__scripts.OnClick(k, "LeftButton")
__UPDATE(3)
if #__HD_VERKAUFT ~= 0 then error("erster Klick hat verkauft") end
if not k.__text:find("Wirklich?", 1, true) then error("Bestaetigung fehlt: " .. tostring(k.__text)) end
k.__scripts.OnClick(k, "LeftButton")
__UPDATE(1, 0.25)
if #__HD_VERKAUFT ~= 1 then error("nach einem Schritt erwartet 1 verkauft, war " .. #__HD_VERKAUFT) end
__UPDATE(10, 0.25)
if table.concat(__HD_VERKAUFT, ",") ~= "6001,6003,6004" then error("verkauft: " .. table.concat(__HD_VERKAUFT, ",")) end
__FEUER("BAG_UPDATE_DELAYED")
if not k.__text:find("Nichts", 1, true) then error("nach dem Verkauf: " .. tostring(k.__text)) end

-- SZENE: Haendler - Bestaetigung laeuft nach 5 Sekunden ab
__HD_BAGS[0][1] = { 6001, 3, false, 0 }
__FEUER("BAG_UPDATE_DELAYED")
local k = WegweiserHaendlerKnopf
k.__scripts.OnClick(k, "LeftButton")
__HD_T = __HD_T + 6
__UPDATE(2, 0.5)
if k.__text:find("Wirklich?", 1, true) then error("Bestaetigung nicht abgelaufen") end
k.__scripts.OnClick(k, "LeftButton")
__UPDATE(3)
if #__HD_VERKAUFT ~= 3 then error("abgelaufener Klick hat verkauft") end

-- SZENE: Haendler - Schliessen stoppt den Verkauf, anderes Item auf dem Platz wird nicht verkauft
local k = WegweiserHaendlerKnopf
__HD_BAGS[0][3] = { 6003, 5, false, 2 }
k.__scripts.OnClick(k, "LeftButton")
k.__scripts.OnClick(k, "LeftButton")
-- vor dem ersten Schritt liegt auf Platz 1 plötzlich etwas anderes
__HD_BAGS[0][1] = { 6099, 1, false, 4 }
__UPDATE(1, 0.25)
for _, id in ipairs(__HD_VERKAUFT) do if id == 6099 then error("falsches Item verkauft") end end
__FEUER("MERCHANT_CLOSED")
local vorher = #__HD_VERKAUFT
__UPDATE(10, 0.25)
if #__HD_VERKAUFT ~= vorher then error("nach dem Schliessen weiter verkauft") end

-- SZENE: Haendler - Luecke 1: neues Item zwischen erstem und zweitem Klick wird nicht mitverkauft
__FEUER("MERCHANT_SHOW")
__HD_VERKAUFT = {}
__HD_BAGS = { [0] = { { 6001, 3, false, 0 } }, [1] = {} }
__FEUER("BAG_UPDATE_DELAYED")
local k = WegweiserHaendlerKnopf
k.__scripts.OnClick(k, "LeftButton")
__HD_BAGS[1][1] = { 6010, 1, false, 0 }   -- neue graue Beute
k.__scripts.OnClick(k, "LeftButton")
__UPDATE(10, 0.25)
for _, id in ipairs(__HD_VERKAUFT) do if id == 6010 then error("Luecke 1: nicht gezeigtes Item verkauft") end end
-- erster Klick bei leerer Liste schaltet nicht scharf
__HD_BAGS = { [0] = {}, [1] = {} }
__FEUER("BAG_UPDATE_DELAYED")
k.__scripts.OnClick(k, "LeftButton")
__HD_BAGS[0][1] = { 6011, 1, false, 0 }
k.__scripts.OnClick(k, "LeftButton")
__UPDATE(5, 0.25)
for _, id in ipairs(__HD_VERKAUFT) do if id == 6011 then error("Luecke 1: Klick auf leere Liste hat scharf geschaltet") end end

-- SZENE: Haendler - Luecke 2: gleiche ID, aber jetzt gebunden, wird nicht verkauft
__HD_VERKAUFT = {}
__HD_BAGS = { [0] = { { 6003, 5, false, 2 } }, [1] = {} }
__FEUER("BAG_UPDATE_DELAYED")
local k = WegweiserHaendlerKnopf
k.__scripts.OnClick(k, "LeftButton")
k.__scripts.OnClick(k, "LeftButton")
__HD_BAGS[0][1] = { 6003, 5, true, 2 }    -- getauscht gegen ein gebundenes Exemplar
__UPDATE(5, 0.25)
if #__HD_VERKAUFT ~= 0 then error("Luecke 2: gebundenes Exemplar verkauft") end

-- SZENE: Haendler - Luecke 3: rot nur mit frischen Preisen, mind. 3 Angeboten, nie gruene Ausruestung
local ah = __WW.db.ah["Forever|Alliance"]
ah.i[6020] = "100,100,1"      -- ohne Verlauf
ah.i[6021] = "100,100,10"     -- seit 5 Scans billig, aber Ausruestung (unten)
ah.i[6022] = "100,100,20"     -- ein einziger 20er-Stapel, erst 1 Scan: kein sicheres Urteil
ah.i[6023] = "100,100,20"     -- jetzt billig, aber normal teuer (90000): kein sicheres Urteil
__HD_BAGS = { [0] = { { 6020, 1, false, 2 }, { 6021, 1, false, 2 }, { 6022, 20, false, 1 }, { 6023, 1, false, 1 } }, [1] = {} }
local altInfo = C_Item.GetItemInfo
C_Item.GetItemInfo = function(id)
  local r = { altInfo(id) }
  if id == 6021 then r[9] = "INVTYPE_CHEST" end   -- Ausruestung, Qualitaet 2 (gruen)
  return unpack(r, 1, 14)
end
local liste = __WW.Haendler.Liste()
C_Item.GetItemInfo = altInfo
if #liste ~= 0 then error("Luecke 3: unsicheres rotes Urteil verkauft: " .. liste[1].id) end
ah.i[6021] = "100,100,10"
__HD_BAGS = { [0] = { { 6021, 1, false, 2 } }, [1] = {} }
if #__WW.Haendler.Liste() ~= 1 then error("Luecke 3: sicheres rotes Item fehlt") end
local altT = ah.t
ah.t = time() - 8 * 86400
if #__WW.Haendler.Liste() ~= 0 then error("Luecke 3: Preis aelter als 7 Tage zaehlt noch") end
ah.t = altT

-- SZENE: Haendler - Luecke 4: nur echte Verkaeufe zaehlen, Handelsfenster stoppt
__HD_T = __HD_T + 6   -- alte Bestaetigung ablaufen lassen
__HD_VERKAUFT = {}
__HD_BAGS = { [0] = { { 6001, 3, false, 0 }, { 6004, 1, false, 0 } }, [1] = {} }
local echtesUse = C_Container.UseContainerItem
C_Container.UseContainerItem = function() end     -- Haendler nimmt nichts an
__FEUER("BAG_UPDATE_DELAYED")
local k = WegweiserHaendlerKnopf
k.__scripts.OnClick(k, "LeftButton")
k.__scripts.OnClick(k, "LeftButton")
__HD_MELDUNG = nil
local altPrint = __WW.Print
__WW.Print = function(self, ...) __HD_MELDUNG = table.concat({ ... }, " ") end
__UPDATE(10, 0.25)
__WW.Print = altPrint
C_Container.UseContainerItem = echtesUse
if __HD_MELDUNG and __HD_MELDUNG:find("Verkauft: 2", 1, true) then error("Luecke 4: Meldung zaehlt nicht verkaufte Items: " .. __HD_MELDUNG) end
-- Handelsfenster offen: kein Verkauf
TradeFrame = CreateFrame("Frame", "TradeFrame", UIParent)
TradeFrame:Show()
__HD_VERKAUFT = {}
k.__scripts.OnClick(k, "LeftButton")
k.__scripts.OnClick(k, "LeftButton")
__UPDATE(10, 0.25)
TradeFrame:Hide()
if #__HD_VERKAUFT ~= 0 then error("Luecke 4: bei offenem Handelsfenster verkauft") end

-- SZENE: Haendler - Luecke 5: nach "Liste geaendert" verkauft auch ein schneller dritter Klick nicht
__HD_T = __HD_T + 6   -- alte Bestaetigung ablaufen lassen
__HD_VERKAUFT = {}
__HD_BAGS = { [0] = { { 6001, 3, false, 0 } }, [1] = {} }
__FEUER("BAG_UPDATE_DELAYED")
local k = WegweiserHaendlerKnopf
k.__scripts.OnClick(k, "LeftButton")
__HD_BAGS[1][1] = { 6010, 1, false, 0 }
k.__scripts.OnClick(k, "LeftButton")   -- Liste geaendert
k.__scripts.OnClick(k, "LeftButton")   -- schneller dritter Klick
__UPDATE(10, 0.25)
if #__HD_VERKAUFT ~= 0 then error("Luecke 5: dritter Klick hat ohne Pruefung verkauft: " .. table.concat(__HD_VERKAUFT, ",")) end

-- SZENE: Haendler - Luecke 6: Server antwortet langsam (Platz noch gesperrt), Verkauf zaehlt trotzdem
__HD_T = __HD_T + 6   -- alte Bestaetigung ablaufen lassen
__HD_VERKAUFT = {}
__HD_BAGS = { [0] = { { 6001, 3, false, 0 } }, [1] = {} }
local echtesUse = C_Container.UseContainerItem
C_Container.UseContainerItem = function(b, s)
  local x = __HD_BAGS[b][s]
  __HD_BAGS[b][s] = { x[1], x[2], x[3], x[4], true }   -- erst gesperrt
  __HD_SPAETER = function() __HD_VERKAUFT[#__HD_VERKAUFT + 1] = x[1]; __HD_BAGS[b][s] = false end
end
__FEUER("BAG_UPDATE_DELAYED")
local k = WegweiserHaendlerKnopf
k.__scripts.OnClick(k, "LeftButton")
k.__scripts.OnClick(k, "LeftButton")
__HD_MELDUNG = nil
local altPrint = __WW.Print
__WW.Print = function(self, ...) __HD_MELDUNG = table.concat({ ... }, " ") end
__UPDATE(3, 0.25)
if __HD_SPAETER then __HD_SPAETER() __HD_SPAETER = nil end
__UPDATE(10, 0.25)
__WW.Print = altPrint
C_Container.UseContainerItem = echtesUse
if not (__HD_MELDUNG and __HD_MELDUNG:find("Verkauft: 1", 1, true)) then error("Luecke 6: langsamer Verkauf nicht gezaehlt: " .. tostring(__HD_MELDUNG)) end

-- SZENE: Haendler - Aufraeumen
C_Container.GetContainerNumSlots, C_Container.GetContainerItemInfo = __HD_ALT.num, __HD_ALT.info
C_Container.UseContainerItem, GetTime = __HD_ALT.use, __HD_ALT.getTime
__WW.db.ah["Forever|Alliance"] = nil
__WW.db.ahVerlauf["Forever|Alliance"] = nil
