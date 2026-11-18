-- Szenen fuer AuktionHandel.lua und die Filter der Ansichten "Schnaeppchen" / "Zu teuer".
-- SZENE: Handel - Vorbereiten (Scan, Verlauf, nachgebautes Auktionshaus)
function __HG(ist, soll, was)
  if ist ~= soll then error((was or "?") .. ": erwartet " .. tostring(soll) .. ", war " .. tostring(ist), 2) end
end
__HA = { alt = {}, log = {} }
for _, k in ipairs({ "SendSearchQuery", "GetNumCommoditySearchResults", "GetCommoditySearchResultInfo", "StartCommoditiesPurchase",
  "ConfirmCommoditiesPurchase", "CancelCommoditiesPurchase", "GetNumItemSearchResults", "GetItemSearchResultInfo", "PlaceBid",
  "PostCommodity", "PostItem", "MakeItemKey", "ConfirmPostCommodity", "ConfirmPostItem", "GetQuoteDurationRemaining",
  "SupportsCopperValues" }) do __HA.alt[k] = C_AuctionHouse[k] end
__HA.altGetTime, __HA.altMoney, __HA.altItemLoc = GetTime, rawget(_G, "GetMoney"), rawget(_G, "ItemLocation")
__HA.altNum, __HA.altInfo = C_Container.GetContainerNumSlots, C_Container.GetContainerItemInfo
__HA.t = 5000
GetTime = function() return __HA.t end
__HA.gold = 1000000
GetMoney = function() return __HA.gold end
ItemLocation = { CreateFromBagAndSlot = function(self, b, s) return { bag = b, slot = s } end }
-- Angebote im nachgebauten AH
__HA.com = {}     -- [itemID] = { {preis, menge}, ... }
__HA.items = {}   -- [itemID] = { {auktion, buyout, menge}, ... }
local function log(t) __HA.log[#__HA.log + 1] = t end
C_AuctionHouse.MakeItemKey = function(id) return { itemID = id } end
C_AuctionHouse.SendSearchQuery = function(key) log("suche " .. key.itemID) end
C_AuctionHouse.GetNumCommoditySearchResults = function(id) return #(__HA.com[id] or {}) end
C_AuctionHouse.GetCommoditySearchResultInfo = function(id, i)
  local a = (__HA.com[id] or {})[i]
  if a then return { unitPrice = a[1], quantity = a[2], numOwnerItems = 0 } end
end
C_AuctionHouse.StartCommoditiesPurchase = function(id, n) log("start " .. id .. " " .. n) end
C_AuctionHouse.ConfirmCommoditiesPurchase = function(id, n) log("kaufe " .. id .. " " .. n) end
C_AuctionHouse.CancelCommoditiesPurchase = function() log("abbruch") end
C_AuctionHouse.GetNumItemSearchResults = function(key) return #(__HA.items[key.itemID] or {}) end
C_AuctionHouse.GetItemSearchResultInfo = function(key, i)
  local a = (__HA.items[key.itemID] or {})[i]
  if a then return { auctionID = a[1], buyoutAmount = a[2], quantity = a[3] or 1 } end
end
C_AuctionHouse.PlaceBid = function(aid, betrag) log("bid " .. aid .. " " .. betrag) end
C_AuctionHouse.PostCommodity = function(ort, dauer, n, preis) log(("post %d/%d %d %d %d"):format(ort.bag, ort.slot, dauer, n, preis)) return __HA.warnung end
C_AuctionHouse.PostItem = function(ort, dauer, n, bid, buyout) log(("postitem %d/%d %d %d %d"):format(ort.bag, ort.slot, dauer, n, buyout)) return __HA.warnung end
C_AuctionHouse.ConfirmPostCommodity = function(ort, dauer, n, preis) log(("confirmpost %d/%d %d %d %d"):format(ort.bag, ort.slot, dauer, n, preis)) end
C_AuctionHouse.ConfirmPostItem = function(ort, dauer, n, bid, buyout) log(("confirmpostitem %d/%d %d %d %d"):format(ort.bag, ort.slot, dauer, n, buyout)) end
__HA.quote = 30
C_AuctionHouse.GetQuoteDurationRemaining = function() return __HA.quote end
C_AuctionHouse.SupportsCopperValues = function() return false end
function __HA.warte(sek) __HA.t = __HA.t + sek __UPDATE(1) end
-- Taschen: 8003 (5 Stueck, ungebunden) in Rucksack Platz 1
__HA.bags = { [0] = { { 8003, 5, false } } }
C_Container.GetContainerNumSlots = function(b) return __HA.bags[b] and #__HA.bags[b] or 0 end
C_Container.GetContainerItemInfo = function(b, s)
  local x = __HA.bags[b] and __HA.bags[b][s]
  if x then return { itemID = x[1], stackCount = x[2], isBound = x[3], isLocked = false } end
end
-- Scan und Verlauf: 8001 / 8002 guenstig (ueblich 1000), 8003 zu teuer (ueblich 1000, jetzt 5000)
local db = __WW.db
db.ah["Forever|Alliance"] = { r = "Forever", f = "Alliance", t = time(), n = 30, z = 3, m = "test", i = {
  [8001] = "100,100,20", [8002] = "200,200,1", [8003] = "5000,5000,4", [8004] = "6000,6000,2" } }
db.ahVerlauf["Forever|Alliance"] = { [8001] = "1000,5,498598,1000;6:1000:1", [8002] = "1000,5,498598,1000;6:1000:1",
  [8003] = "1000,5,498598,1000;6:1000:1", [8004] = "1000,5,498598,1000;6:1000:1" }
db.ah.schnaeppchen, db.ah.zuTeuer, db.ah.dauer = 0.7, 1.3, 8
db.ah.markt = { bezahlbar = false, ersparnis = 0, nurMeine = false }
__FEUER("AUCTION_HOUSE_SHOW")
function __HA.zeile(liste, id) for _, e in ipairs(liste) do if e.id == id then return e end end end
function __HA.hat(teil) for _, t in ipairs(__HA.log) do if t:find(teil, 1, true) then return true end end return false end

-- SZENE: Handel - Filter: Suche, bezahlbar, Mindest-Ersparnis, nur meine Items
local AH = __WW.AH
local s = AH.Schnaeppchen()
if not (__HA.zeile(s, 8001) and __HA.zeile(s, 8002)) then error("Schnaeppchen fehlen") end
__HG(#AH.MarktFiltern(s, "schnaeppchen", "gibtsnicht"), 0, "Suche ohne Treffer")
__HG(#AH.MarktFiltern(s, "schnaeppchen", "8001"), 1, "Suche nach Nummer")
__WW.db.ah.markt.ersparnis = 85
local f = AH.MarktFiltern(s, "schnaeppchen", "")
__HG(#f, 1, "Ersparnis ab 85 %") __HG(f[1].id, 8001, "nur 8001 (90 % billiger)")
__WW.db.ah.markt.ersparnis = 0
__HA.gold = 150
__WW.db.ah.markt.bezahlbar = true
f = AH.MarktFiltern(s, "schnaeppchen", "")
__HG(#f, 1, "nur bezahlbar") __HG(f[1].id, 8001, "8001 kostet 100")
__WW.db.ah.markt.bezahlbar = false
__HA.gold = 1000000
local t = AH.ZuTeuer()
__WW.db.ah.markt.nurMeine = true
__HG(#AH.MarktFiltern(t, "teuer", ""), 1, "nur meine Items")
__HA.bags[0] = {}
__HG(#AH.MarktFiltern(t, "teuer", ""), 0, "ohne Besitz leer")
__HA.bags[0] = { { 8003, 5, false } }
__WW.db.ah.markt.nurMeine = false

-- SZENE: Handel - Handelsware kaufen: suchen, Preis holen, kaufen - jeder Schritt erst nach der Pause
local H = __WW.AHHandel
local e = __HA.zeile(__WW.AH.Schnaeppchen(), 8001)
__HA.log = {}
__HA.com[8001] = { { 100, 5 }, { 150, 10 }, { 800, 3 } }   -- Grenze: 1000 x 0.7 = 700
H.Klick(e, "schnaeppchen")
if not __HA.hat("suche 8001") then error("erster Klick hat nicht gesucht") end
__FEUER("COMMODITY_SEARCH_RESULTS_UPDATED", 8001)
__HG(H.KnopfText(e, "schnaeppchen"), "Preis holen", "Knopf nach der Suche")
H.Klick(e, "schnaeppchen")   -- Doppelklick: zu schnell
if __HA.hat("start") then error("Doppelklick hat sofort den Kauf gestartet") end
__HA.warte(1)
H.Klick(e, "schnaeppchen")
if not __HA.hat("start 8001 15") then error("falsche Menge (nur bis 700 je Stueck): " .. table.concat(__HA.log, "; ")) end
if __HA.hat("kaufe") then error("Preis holen hat schon gekauft") end
__FEUER("COMMODITY_PRICE_UPDATED", 130, 1950)
if not H.KnopfText(e, "schnaeppchen"):find("Kaufen:", 1, true) then error("Knopf zeigt keinen Kauf: " .. H.KnopfText(e, "schnaeppchen")) end
H.Klick(e, "schnaeppchen")   -- zu schnell nach der Preisansage
if __HA.hat("kaufe") then error("ohne Pause gekauft") end
__HA.warte(1)
H.Klick(e, "schnaeppchen")
if not __HA.hat("kaufe 8001 15") then error("dritter Klick hat nicht gekauft") end

-- SZENE: Handel - jede Preisansage zaehlt: spaetere Aenderung, zu teurer Durchschnitt, fremde Ansage
local H = __WW.AHHandel
local e = __HA.zeile(__WW.AH.Schnaeppchen(), 8001)
local function bisPreis()
  __HA.log = {}
  H.Klick(e, "schnaeppchen")
  __FEUER("COMMODITY_SEARCH_RESULTS_UPDATED", 8001)
  __HA.warte(1)
  H.Klick(e, "schnaeppchen")
end
-- fremde Ansage vor unserem Start wird nicht beachtet
__HA.log = {}
H.Klick(e, "schnaeppchen")
__FEUER("COMMODITY_PRICE_UPDATED", 6, 6)
__FEUER("COMMODITY_SEARCH_RESULTS_UPDATED", 8001)
__HG(H.KnopfText(e, "schnaeppchen"), "Preis holen", "fremde Ansage vor dem Start veraendert nichts")
H.Klick(__HA.zeile(__WW.AH.Schnaeppchen(), 8002), "schnaeppchen")   -- anderer Vorgang: alter faellt weg
-- spaetere Ansage mit anderem Preis
bisPreis()
__FEUER("COMMODITY_PRICE_UPDATED", 130, 1950)
__FEUER("COMMODITY_PRICE_UPDATED", 140, 2100)
__HA.warte(1)
H.Klick(e, "schnaeppchen")
if __HA.hat("kaufe") then error("trotz geaenderter Preisansage gekauft") end
if not __HA.hat("abbruch") then error("Kauf beim Server nicht abgebrochen") end
-- Summe hoeher als bei der Suche (guenstige Angebote inzwischen weg)
bisPreis()
__FEUER("COMMODITY_PRICE_UPDATED", 366, 5500)
__HA.warte(1)
H.Klick(e, "schnaeppchen")
if __HA.hat("kaufe") then error("ueber der gezeigten Summe gekauft") end
-- Stueckpreis ueber der Grenze
bisPreis()
__FEUER("COMMODITY_PRICE_UPDATED", 800, 12000)
__HA.warte(1)
H.Klick(e, "schnaeppchen")
if __HA.hat("kaufe") then error("ueber der Schnaeppchen-Grenze gekauft") end
-- Preis vom Server abgelaufen
bisPreis()
__FEUER("COMMODITY_PRICE_UPDATED", 130, 1950)
__HA.quote = 0
__HA.warte(1)
H.Klick(e, "schnaeppchen")
__HA.quote = 30
if __HA.hat("kaufe") then error("mit abgelaufenem Server-Preis gekauft") end

-- SZENE: Handel - fremde Ansage nach unserem Start und "Preis nicht verfuegbar"
local H = __WW.AHHandel
local e = __HA.zeile(__WW.AH.Schnaeppchen(), 8001)
__HA.warte(20)
__HA.log = {}
H.Klick(e, "schnaeppchen")
__FEUER("COMMODITY_SEARCH_RESULTS_UPDATED", 8001)
__HA.warte(1)
H.Klick(e, "schnaeppchen")
__FEUER("COMMODITY_PRICE_UPDATED", 2, 6)   -- passt nicht zu 15 Stueck: fremd
if H.KnopfText(e, "schnaeppchen"):find("Kaufen:", 1, true) then error("fremde Preisansage angenommen") end
__HA.warte(1)
H.Klick(e, "schnaeppchen")
if __HA.hat("kaufe") then error("mit fremder Preisansage gekauft") end
__HA.warte(20)
__HA.log = {}
H.Klick(e, "schnaeppchen")
__FEUER("COMMODITY_SEARCH_RESULTS_UPDATED", 8001)
__HA.warte(1)
H.Klick(e, "schnaeppchen")
__FEUER("COMMODITY_PRICE_UNAVAILABLE")
local o = H.Zustand()
if o then error("nach COMMODITY_PRICE_UNAVAILABLE laeuft der Vorgang weiter") end

-- SZENE: Handel - hoechstens ein Viertel des Golds pro Kauf
local H = __WW.AHHandel
local e = __HA.zeile(__WW.AH.Schnaeppchen(), 8001)
__HA.log = {}
__HA.gold = 4000   -- ein Viertel: 1000
H.Klick(e, "schnaeppchen")
__FEUER("COMMODITY_SEARCH_RESULTS_UPDATED", 8001)
__HA.warte(1)
H.Klick(e, "schnaeppchen")
__HA.gold = 1000000
if not __HA.hat("start 8001 8") then error("Obergrenze falsch (5 x 100 + 3 x 150 = 950): " .. table.concat(__HA.log, "; ")) end
H.Klick(__HA.zeile(__WW.AH.Schnaeppchen(), 8002), "schnaeppchen")   -- Vorgang wechseln (bricht den Kauf ab)

-- SZENE: Handel - Einzel-Item kaufen, zu teures Angebot und Obergrenze
local H = __WW.AHHandel
local e = __HA.zeile(__WW.AH.Schnaeppchen(), 8002)
local function versuch(auktion, preis)
  __HA.log = {}
  __HA.items[8002] = { { auktion, preis, 1 } }
  __HA.warte(20)   -- alter Vorgang laeuft ab
  H.Klick(e, "schnaeppchen")
  __FEUER("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 8002 })
  H.Klick(e, "schnaeppchen")   -- zu schnell
  if __HA.hat("bid") then error("Doppelklick hat gekauft") end
  __HA.warte(1)
  H.Klick(e, "schnaeppchen")
end
versuch(55, 300)
if not __HA.hat("bid 55 300") then error("Einzel-Item nicht gekauft: " .. table.concat(__HA.log, "; ")) end
versuch(56, 900)
if __HA.hat("bid") then error("Angebot ueber der Schnaeppchen-Grenze gekauft") end
__HA.gold = 1000   -- ein Viertel: 250
versuch(57, 300)
__HA.gold = 1000000
if __HA.hat("bid") then error("ueber ein Viertel des Golds gekauft") end

-- SZENE: Handel - einstellen: 1 Silber darunter auf ganze Silber, Platz neu pruefen, Warnung, PostItem je Stueck
local H = __WW.AHHandel
local e = __HA.zeile(__WW.AH.ZuTeuer(), 8003)
if not e then error("8003 fehlt in Zu teuer") end
local function bisBereit(id, angebote, item)
  __HA.log = {}
  __HA.warte(20)
  local z = __HA.zeile(__WW.AH.ZuTeuer(), id)
  if item then __HA.items[id] = angebote else __HA.com[id] = angebote end
  H.Klick(z, "teuer")
  if item then __FEUER("ITEM_SEARCH_RESULTS_UPDATED", { itemID = id }) else __FEUER("COMMODITY_SEARCH_RESULTS_UPDATED", id) end
  __HA.warte(1)
  return z
end
bisBereit(8003, { { 4000, 2 } })
if __HA.hat("post") then error("erster Klick hat eingestellt") end
H.Klick(e, "teuer")
if not __HA.hat("post 0/1 2 5 3900") then error("falsch eingestellt (erwartet 3900 = 1 Silber darunter): " .. table.concat(__HA.log, "; ")) end
-- zu nah am ueblichen Preis (1050 - 100 = 900 < 1000)
bisBereit(8003, { { 1050, 2 } })
H.Klick(e, "teuer")
if __HA.hat("post") then error("unter dem ueblichen Preis eingestellt") end
-- Platz zwischen den Klicks getauscht
bisBereit(8003, { { 4000, 2 } })
__HA.bags[0][1] = { 9999, 5, false }
H.Klick(e, "teuer")
__HA.bags[0][1] = { 8003, 5, false }
if __HA.hat("post") then error("anderes Item eingestellt: " .. table.concat(__HA.log, "; ")) end
-- Server verlangt Bestaetigung
__HA.warnung = true
bisBereit(8003, { { 4000, 2 } })
H.Klick(e, "teuer")
__HA.warnung = false
if not __HA.hat("post 0/1") then error("PostCommodity nicht aufgerufen") end
if __HA.hat("confirmpost") then error("Warnung ohne Klick bestaetigt") end
__HG(H.KnopfText(e, "teuer"), "Trotzdem?", "Knopf bei Warnung")
__HA.warte(1)
H.Klick(e, "teuer")
if not __HA.hat("confirmpost 0/1 2 5 3900") then error("Warnung nicht bestaetigt: " .. table.concat(__HA.log, "; ")) end
-- Einzel-Item (kein Handelsgut): Sofortkauf je Stueck
__HA.bags[0][2] = { 8004, 3, false }
local z4 = bisBereit(8004, { { 70, 6000, 1 } }, true)
H.Klick(z4, "teuer")
if not __HA.hat("postitem 0/2 2 3 5900") then error("PostItem falsch (5900 je Stueck): " .. table.concat(__HA.log, "; ")) end
__HA.bags[0][2] = nil

-- SZENE: Handel - Verkaufen: Liste mit Vorschlag und Untergrenze, einstellen, zur Untergrenze, geschuetzte Items
do
  local AH, H = __WW.AH, __WW.AHHandel
  local mf = __WW.db.ah.markt
  -- 8003: 5 Stueck in der Tasche, jetzt 5000, ueblich 1000, Haendler 150 je Stueck
  local v = __HA.zeile(AH.VerkaufListe(mf), 8003)
  if not v then error("8003 fehlt in Verkaufen") end
  __HG(v.menge, 5, "Menge aus der Tasche")
  __HG(v.preis, 4900, "Vorschlag 1 Silber unter dem Scan-Preis")
  __HG(v.boden, 800, "Untergrenze 80 % vom ueblichen Preis")
  __HG(v.zurGrenze, false, "Vorschlag ueber der Grenze")
  __HG(v.erloes, math.floor(4900 * 5 * 0.95) - 150, "Erloes nach Abzug und Kaution")
  -- Untergrenze nie unter dem Haendlerpreis: Haendler zahlt viel mehr als 80 % vom ueblichen Preis
  local altGII = C_Item.GetItemInfo
  C_Item.GetItemInfo = function(id)
    if tonumber(id) == 8003 then return "Item8003", "", 2, 10, 5, "", "", 20, "", 134400, 2000, 7, 0, 0 end
    return altGII(id)
  end
  local v2 = __HA.zeile(AH.VerkaufListe({ nurLohnt = false }), 8003)
  if not v2 then error("8003 fehlt ohne 'nur wo AH lohnt'") end
  if v2.boden < math.ceil(2000 / 0.95) then error("Untergrenze unter dem Haendlerpreis: " .. v2.boden) end
  C_Item.GetItemInfo = altGII
  -- einstellen wie bei "Zu teuer": 1 Silber unter dem guenstigsten fremden Angebot
  local function bisBereit(angebote)
    __HA.log = {}
    __HA.warte(20)
    __HA.com[8003] = angebote
    H.Klick(v, "verkaufen")
    __FEUER("COMMODITY_SEARCH_RESULTS_UPDATED", 8003)
    __HA.warte(1)
  end
  bisBereit({ { 4000, 2 } })
  if __HA.hat("post") then error("erster Klick hat eingestellt") end
  H.Klick(v, "verkaufen")
  if not __HA.hat("post 0/1 2 5 3900") then error("Verkaufen: erwartet 3900: " .. table.concat(__HA.log, "; ")) end
  -- guenstigstes Angebot unter der Untergrenze: zur Untergrenze einstellen, nicht billiger
  bisBereit({ { 500, 2 } })
  local hilfe = H.KnopfHilfe(v, "verkaufen")
  if not hilfe:find("Untergrenze", 1, true) then error("Hilfe nennt die Untergrenze nicht: " .. hilfe) end
  H.Klick(v, "verkaufen")
  if not __HA.hat("post 0/1 2 5 800") then error("nicht zur Untergrenze eingestellt: " .. table.concat(__HA.log, "; ")) end
  -- kein fremdes Angebot mehr: nur 1 Silber unter dem Scan-Preis (4900), nicht zweimal abziehen
  bisBereit({})
  H.Klick(v, "verkaufen")
  if not __HA.hat("post 0/1 2 5 4900") then error("ohne Angebot: erwartet 4900: " .. table.concat(__HA.log, "; ")) end
  -- in "Verkaufen" geprueft, dann gleich in "Zu teuer" geklickt: dort gilt wieder die strenge Grenze
  bisBereit({ { 500, 2 } })
  local t0 = __HA.zeile(AH.ZuTeuer(), 8003)
  __HG(H.KnopfText(t0, "teuer"), "Prüfen", "Zu teuer zeigt keinen fremden Vorgang")
  __HA.log = {}
  H.Klick(t0, "teuer")
  if __HA.hat("post") then error("Zu teuer hat den Vorgang aus Verkaufen eingestellt: " .. table.concat(__HA.log, "; ")) end
  -- "Zu teuer" bleibt streng: gleiche Lage bricht ab
  __HA.log = {}
  __HA.warte(20)
  local t = __HA.zeile(AH.ZuTeuer(), 8003)
  H.Klick(t, "teuer")
  __FEUER("COMMODITY_SEARCH_RESULTS_UPDATED", 8003)
  __HA.warte(1)
  H.Klick(t, "teuer")
  if __HA.hat("post") then error("Zu teuer hat unter dem ueblichen Preis eingestellt") end
  -- Items, die das Urteil behalten will, nur mit Haken "Auch behalten-Items"
  local U = __WW.Urteil
  local altG = U.Geschuetzt
  U.Geschuetzt = function(id) return tonumber(id) == 8003 end
  if __HA.zeile(AH.VerkaufListe(mf), 8003) then error("geschuetztes Item in Verkaufen") end
  local g = __HA.zeile(AH.VerkaufListe({ geschuetzt = true }), 8003)
  if not (g and g.geschuetzt) then error("geschuetztes Item fehlt mit Haken") end
  U.Geschuetzt = altG
  -- Reiter: Ansicht "Verkaufen" hat einen Knopf fuer 8003
  __WW:Oeffnen("ah")
  local vk
  for _, f in ipairs(__FRAMES) do if f.__typ == "Button" and f.__text == "Verkaufen" then vk = f end end
  if not vk then error("Knopf Verkaufen fehlt") end
  vk.__scripts.OnClick(vk, "LeftButton")
  local ein
  for _, f in ipairs(__FRAMES) do
    if f.__typ == "Button" and f.__shown and f:GetParent() and f:GetParent().eintrag
      and f:GetParent().eintrag.id == 8003 and f:GetParent().eintrag.boden then ein = f end
  end
  if not ein then error("kein Einstellen-Knopf in der Ansicht Verkaufen") end
  ein.__scripts.OnEnter(ein)
  -- Warnung des Servers, danach sperrt das Spiel die Items: die Zeile mit "Trotzdem?" bleibt stehen
  local liste2 = ein:GetParent():GetParent()
  local e8003 = ein:GetParent().eintrag
  __HA.warnung = true
  __HA.log = {}
  __HA.warte(20)
  __HA.com[8003] = { { 4000, 2 } }
  H.Klick(e8003, "verkaufen")
  __FEUER("COMMODITY_SEARCH_RESULTS_UPDATED", 8003)
  __HA.warte(1)
  H.Klick(e8003, "verkaufen")
  __HA.warnung = false
  __HG(H.KnopfText(e8003, "verkaufen"), "Trotzdem?", "Knopf nach der Warnung")
  local altInfo = C_Container.GetContainerItemInfo
  C_Container.GetContainerItemInfo = function(b, s)
    local x = altInfo(b, s)
    if x and x.itemID == 8003 then x.isLocked = true end
    return x
  end
  __FEUER("BAG_UPDATE_DELAYED")
  __UPDATE(1)
  local noch = false
  for _, x in ipairs(liste2.eintraege or {}) do if x.id == 8003 then noch = true end end
  C_Container.GetContainerItemInfo = altInfo
  if not noch then error("Zeile mit 'Trotzdem?' verschwindet, wenn das Spiel die Items sperrt") end
  __HA.warte(20)
  for _, f in ipairs(__FRAMES) do if f.__typ == "Button" and f.__text == "Taschen" then f.__scripts.OnClick(f, "LeftButton") end end
end

-- SZENE: Handel - Auktionshaus zu, abgelaufene Schritte, Kleinschreibung mit Umlauten
local H = __WW.AHHandel
local e = __HA.zeile(__WW.AH.Schnaeppchen(), 8002)
__HA.log = {}
__HA.items[8002] = { { 58, 300, 1 } }
__HA.warte(20)
H.Klick(e, "schnaeppchen")
__FEUER("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 8002 })
__HA.warte(20)
H.Klick(e, "schnaeppchen")   -- Schritt abgelaufen: neuer erster Klick, kein Kauf
if __HA.hat("bid") then error("abgelaufener Schritt hat gekauft") end
__FEUER("AUCTION_HOUSE_CLOSED")
__HA.log = {}
H.Klick(e, "schnaeppchen")
if __HA.hat("suche") then error("bei geschlossenem AH gesucht") end
__HG(__WW.Klein("ÖLIGE Äste ÜBER"), "ölige äste über", "Kleinschreibung mit Umlauten")

-- SZENE: Handel - Reiter: Filter und Knoepfe in den Ansichten
__FEUER("AUCTION_HOUSE_SHOW")
__WW:Oeffnen("ah")
local function knopf(text)
  for _, f in ipairs(__FRAMES) do if f.__typ == "Button" and f.__text == text and f.__shown ~= false then return f end end
end
knopf("Schnäppchen").__scripts.OnClick(knopf("Schnäppchen"), "LeftButton")
local kauf
for _, f in ipairs(__FRAMES) do if f.__typ == "Button" and f.__text == "Prüfen" and f.__shown and f:GetParent().eintrag then kauf = f end end
if not kauf then error("kein Kaufen-Knopf in der Schnaeppchen-Liste") end
kauf.__scripts.OnEnter(kauf)
knopf("Zu teuer").__scripts.OnClick(knopf("Zu teuer"), "LeftButton")
local ein
for _, f in ipairs(__FRAMES) do if f.__typ == "Button" and f.__text == "Prüfen" and f.__shown and f:GetParent().eintrag and f:GetParent().eintrag.id == 8003 then ein = f end end
if not ein then error("kein Einstellen-Knopf fuer eigenes Item") end
knopf("Taschen").__scripts.OnClick(knopf("Taschen"), "LeftButton")
__FEUER("AUCTION_HOUSE_CLOSED")

-- SZENE: Handel - Aufraeumen
for k, f in pairs(__HA.alt) do C_AuctionHouse[k] = f end
GetTime, GetMoney, ItemLocation = __HA.altGetTime, __HA.altMoney, __HA.altItemLoc
C_Container.GetContainerNumSlots, C_Container.GetContainerItemInfo = __HA.altNum, __HA.altInfo
__WW.db.ah["Forever|Alliance"] = nil
__WW.db.ahVerlauf["Forever|Alliance"] = nil
