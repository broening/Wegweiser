-- Wegweiser: Kaufen und Einstellen aus dem Reiter "Auktionshaus" (Ansichten "Schnäppchen" und "Zu teuer").
-- Jeder Schritt ist ein eigener Klick, und jeder Klick zeigt vorher, was der nächste tut:
--   Einzel-Item kaufen:   1. suchen  -> 2. kaufen (PlaceBid)
--   Handelsware kaufen:   1. suchen  -> 2. Preis vom Server holen (StartCommoditiesPurchase) -> 3. kaufen (Confirm)
--   Einstellen:           1. suchen  -> 2. einstellen (PostCommodity/PostItem) [-> 3. Warnung des Servers bestätigen]
-- Sicherungen: Kauf nur bis zur Schnäppchen-Grenze (üblicher Mindestpreis x Einstellung "schnaeppchen") je Stück und
-- nie über die bei der Suche gezeigte Summe; höchstens MAX_ANTEIL deines Golds pro Kauf; jede neue Preisansage wird
-- geprüft; ein Schritt gilt erst nach PAUSE Sekunden (kein Doppelklick-Kauf); vor dem Einstellen wird der Taschenplatz
-- neu geprüft. Einstellpreis: 1 Silber unter dem günstigsten fremden Angebot, auf ganze Silber, nie unter dem üblichen
-- Mindestpreis (Kupferbeträge lehnt das Auktionshaus ab, solange C_AuctionHouse.SupportsCopperValues() nicht true ist).
-- Ansicht "Verkaufen" (art = "verkaufen"): wie "Zu teuer", aber mit eigener Untergrenze e.boden je Stück
-- (80 % vom üblichen Preis, nie weniger als beim Händler). Ist das günstigste Angebot billiger, wird zur
-- Untergrenze eingestellt statt abgebrochen.
-- Öffentlich: WW.AHHandel.Klick(eintrag, art), .KnopfText, .KnopfHilfe, .Besitz(id), .BesitzAlle(), .Zustand(),
-- .EinstellPreis(guenstigste)
local ADDON, WW = ...

local H = {}
WW.AHHandel = H

local SUCH_ZEIT = 10       -- Sekunden Wartezeit auf eine Antwort des Auktionshauses
local BEREIT_ZEIT = 15     -- so lange gilt ein Schritt für den nächsten Klick
local PAUSE = 0.7          -- ein Schritt nimmt Klicks erst nach so vielen Sekunden an
local MAX_ANTEIL = 0.25    -- höchstens ein Viertel deines Golds pro Kauf
local DAUER_NR = { [2] = 1, [8] = 2, [24] = 3 }

local function pass(ok, ...) if ok then return ... end end
local function try(f, ...)
  if type(f) ~= "function" then return nil end
  return pass(pcall(f, ...))
end
local function C(name)
  local t = rawget(_G, "C_AuctionHouse")
  return type(t) == "table" and type(t[name]) == "function" and t[name] or nil
end
local function jetzt() return (GetTime and GetTime()) or 0 end
local function geld() return tonumber(try(rawget(_G, "GetMoney"))) or 0 end
local function name(id) return WW.ItemName(id) or ("Item " .. tostring(id)) end

-- Der laufende Vorgang (höchstens einer)
--   art = "kauf" | "verkauf", id, schritt (Text für den Knopf), phase:
--   "suche"    warte auf Suchergebnis
--   "gefunden" Handelsware: Menge und Summe bekannt, nächster Klick holt den Preis vom Server
--   "warte"    Handelsware: warte auf COMMODITY_PRICE_UPDATED
--   "bereit"   nächster Klick kauft / stellt ein
--   "warnung"  Server will eine Bestätigung fürs Einstellen
local op = nil
local meldung = nil
local eigenBis = 0      -- bis dahin gehören Kauf-/Einstell-Meldungen des Servers zu uns
local gestartet = false -- StartCommoditiesPurchase von uns läuft (nur dann abbrechen)
local beiAenderung
function H.BeiAenderung(fn) beiAenderung = fn end
local function geaendert() if beiAenderung then pcall(beiAenderung) end end
local function melde(text)
  meldung = text
  if text then WW:Print(text) end
  geaendert()
end
function H.Zustand() return op, meldung end

local function kaufAbbrechen()
  if gestartet then
    gestartet = false
    local f = C("CancelCommoditiesPurchase")
    if f then pcall(f) end
  end
end
local function abbrechen(text)
  kaufAbbrechen()
  op = nil
  melde(text)
end
local function phase(p)
  op.phase, op.seit = p, jetzt()
  geaendert()
end

---------------------------------------------------------------------------
-- Eigene Items in den Taschen (nur ungebunden, nicht gesperrt)
---------------------------------------------------------------------------
local function taschenLesen(nurID)
  local plaetze, summe = {}, {}
  if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then return summe, plaetze end
  for _, bag in ipairs(WW.TaschenIDs and WW.TaschenIDs() or { 0, 1, 2, 3, 4 }) do
    local n = tonumber(try(C_Container.GetContainerNumSlots, bag)) or 0
    for slot = 1, n do
      local info = try(C_Container.GetContainerItemInfo, bag, slot)
      if type(info) == "table" and info.itemID and not info.isBound and not info.isLocked
        and (not nurID or info.itemID == nurID) then
        local a = tonumber(info.stackCount) or 1
        summe[info.itemID] = (summe[info.itemID] or 0) + a
        if nurID then plaetze[#plaetze + 1] = { bag = bag, slot = slot, anzahl = a } end
      end
    end
  end
  return summe, plaetze
end
-- anzahl, plaetze = { {bag, slot, anzahl}, ... }
function H.Besitz(id)
  id = tonumber(id)
  if not id then return 0, {} end
  local summe, plaetze = taschenLesen(id)
  return summe[id] or 0, plaetze
end
-- { [itemID] = anzahl } für alle ungebundenen Items in den Taschen (einmal lesen statt pro Zeile)
function H.BesitzAlle() return (taschenLesen(nil)) end

---------------------------------------------------------------------------
-- Abfrage beim Auktionshaus
---------------------------------------------------------------------------
local function itemKey(id)
  local k = try(C("MakeItemKey"), id)
  return k or { itemID = id, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }
end

local function suchen(id)
  local f = C("SendSearchQuery")
  if not f then return false end
  op.key = itemKey(id)
  local so = Enum and Enum.AuctionHouseSortOrder
  local ok = pcall(f, op.key, { { sortOrder = (so and so.Price) or 0, reverseSort = false } }, true)
  if ok then phase("suche") end
  return ok
end

-- Fremde Angebote einer Handelsware, günstigste zuerst: { {preis, menge}, ... }
local function commodityAngebote(id)
  local n = tonumber(try(C("GetNumCommoditySearchResults"), id)) or 0
  local raus = {}
  for i = 1, math.min(n, 100) do
    local r = try(C("GetCommoditySearchResultInfo"), id, i)
    if type(r) == "table" and tonumber(r.unitPrice) and tonumber(r.quantity) then
      local menge = r.quantity - (tonumber(r.numOwnerItems) or 0)
      if menge > 0 then raus[#raus + 1] = { preis = r.unitPrice, menge = menge } end
    end
  end
  table.sort(raus, function(a, b) return a.preis < b.preis end)
  return raus
end

-- Günstigstes fremdes Einzel-Angebot mit Sofortkauf: { auktion, preis (ganze Auktion), menge } oder nil
local function itemAngebot(key)
  local n = tonumber(try(C("GetNumItemSearchResults"), key)) or 0
  local bestes
  for i = 1, math.min(n, 100) do
    local r = try(C("GetItemSearchResultInfo"), key, i)
    if type(r) == "table" and tonumber(r.buyoutAmount) and r.buyoutAmount > 0 and tonumber(r.auctionID)
      and not (r.containsOwnerItem or r.containsAccountItem) then
      local menge = math.max(1, tonumber(r.quantity) or 1)
      if not bestes or r.buyoutAmount / menge < bestes.preis / bestes.menge then
        bestes = { auktion = r.auctionID, preis = r.buyoutAmount, menge = menge }
      end
    end
  end
  return bestes
end

-- Einstellpreis je Stück aus dem günstigsten fremden Angebot
local function einstellPreis(guenstigste)
  if not guenstigste then return nil end
  if try(C("SupportsCopperValues")) == true then return guenstigste - 1 end
  return math.floor((guenstigste - 100) / 100) * 100   -- 1 Silber darunter, ganze Silber
end
H.EinstellPreis = einstellPreis

-- Untergrenze als erlaubter Einstellpreis (ohne Kupfer aufgerundet, wenn der Client kein Kupfer annimmt)
local function grenzPreis(boden)
  boden = math.ceil(tonumber(boden) or 0)
  if boden <= 0 then return nil end
  if try(C("SupportsCopperValues")) == true then return boden end
  return math.ceil(boden / 100) * 100
end
H.GrenzPreis = grenzPreis

local function istVerkauf(art) return art == "teuer" or art == "verkaufen" end

---------------------------------------------------------------------------
-- Antworten des Auktionshauses
---------------------------------------------------------------------------
local function sucheFertig(istCommodity, key)
  if not op or op.phase ~= "suche" then return end
  op.commodity = istCommodity
  if key then op.key = key end
  if op.art == "kauf" then
    local budget = math.floor(geld() * MAX_ANTEIL)
    if istCommodity then
      local menge, summe = 0, 0
      for _, a in ipairs(commodityAngebote(op.id)) do
        if a.preis > op.maxPreis then break end
        local m = math.min(a.menge, math.floor((budget - summe) / a.preis))
        if m <= 0 then break end
        menge, summe = menge + m, summe + a.preis * m
      end
      if menge == 0 then
        return abbrechen("Kein Angebot unter " .. WW.Geld(op.maxPreis) .. " je Stück, das in ein Viertel deines Golds passt.")
      end
      op.menge, op.summe = menge, summe
      return phase("gefunden")
    end
    local a = itemAngebot(op.key)
    if not a then return abbrechen("Kein Sofortkauf-Angebot gefunden.") end
    if a.preis / a.menge > op.maxPreis then
      return abbrechen("Das günstigste Angebot kostet " .. WW.Geld(a.preis) .. " - kein Schnäppchen mehr.")
    end
    if a.preis > budget then return abbrechen(WW.Geld(a.preis) .. " ist mehr als ein Viertel deines Golds. Nicht gekauft.") end
    op.auktion, op.summe, op.menge = a.auktion, a.preis, a.menge
    return phase("bereit")
  end
  -- verkauf
  local guenstigste
  if istCommodity then
    local angebote = commodityAngebote(op.id)
    guenstigste = angebote[1] and angebote[1].preis
  else
    local a = itemAngebot(op.key)
    guenstigste = a and math.floor(a.preis / a.menge)
  end
  local preis = einstellPreis(guenstigste or op.scanPreis)
  op.zurGrenze = nil
  if op.zurGrenzeErlaubt and (not preis or preis < op.minPreis) then
    -- Ansicht "Verkaufen": nicht unter die Grenze gehen, sondern zur Grenze einstellen
    preis = grenzPreis(op.minPreis)
    op.zurGrenze = true
  end
  if not preis or preis < op.minPreis then
    return abbrechen("Das günstigste Angebot (" .. WW.Geld(guenstigste) .. ") ist zu nah am üblichen Preis "
      .. WW.Geld(op.minPreis) .. ". Einstellen lohnt gerade nicht.")
  end
  local anzahl, plaetze = H.Besitz(op.id)
  if anzahl == 0 then return abbrechen("Das Item liegt nicht mehr in deinen Taschen.") end
  op.stueckPreis, op.platz = preis, plaetze[1]
  op.menge = istCommodity and anzahl or plaetze[1].anzahl
  phase("bereit")
end

-- Ist Blizzards eigener Kauf-Dialog offen? (dann könnte die Preisansage ihm gehören)
local function blizzardKaufOffen()
  local f = rawget(_G, "AuctionHouseFrame")
  local d = type(f) == "table" and f.BuyDialog
  if type(d) == "table" and type(d.IsShown) == "function" then
    local ok, an = pcall(d.IsShown, d)
    return ok and an == true
  end
  return false
end

-- Preisansage des Servers (nach StartCommoditiesPurchase). Jede Ansage wird geprüft, auch spätere.
local function preisDa(stueck, gesamt)
  if not gestartet or not op or op.art ~= "kauf" or not op.commodity then return end
  if op.phase ~= "warte" and op.phase ~= "bereit" then return end
  stueck, gesamt = tonumber(stueck), tonumber(gesamt)
  if not stueck or not gesamt then return abbrechen("Das Auktionshaus hat keinen Preis genannt.") end
  -- Die Ansage nennt keine Item-Nummer. Passt Stückpreis x Menge nicht zur Summe, gehört sie zu einem anderen Kauf.
  if math.abs(stueck * op.menge - gesamt) > op.menge then
    return abbrechen("Eine fremde Preisansage kam dazwischen (anderer Kauf?). Nicht gekauft. Prüfe noch einmal.")
  end
  if blizzardKaufOffen() then
    return abbrechen("Blizzards Kauf-Fenster ist offen. Nicht gekauft.")
  end
  if op.phase == "bereit" and gesamt ~= op.preis then
    return abbrechen("Der Preis hat sich geändert (" .. WW.Geld(gesamt) .. "). Nicht gekauft. Prüfe noch einmal.")
  end
  if stueck > op.maxPreis or gesamt > op.summe or gesamt > geld() then
    return abbrechen("Der Preis ist gestiegen (" .. WW.Geld(gesamt) .. " für " .. op.menge .. " Stück). Nicht gekauft.")
  end
  op.preis = gesamt
  if op.phase == "warte" then phase("bereit") end
end

---------------------------------------------------------------------------
-- Klicks
---------------------------------------------------------------------------
local function quoteGilt()
  local f = C("GetQuoteDurationRemaining")
  if not f then return true end
  local r = tonumber(try(f))
  return r == nil or r > 0
end

local function ortVon(p)
  local mk = ItemLocation and ItemLocation.CreateFromBagAndSlot
  if not (mk and p) then return nil end
  local ok, ort = pcall(mk, ItemLocation, p.bag, p.slot)
  return ok and ort or nil
end

-- Nächster Schritt des laufenden Vorgangs (nur nach der PAUSE)
local function weiter()
  local o = op
  if jetzt() - (o.seit or 0) < PAUSE then return end
  if not (WW.AH and WW.AH.Offen and WW.AH.Offen()) then return abbrechen("Das Auktionshaus ist zu.") end
  if o.art == "kauf" and o.phase == "gefunden" then
    local f = C("StartCommoditiesPurchase")
    if not f or not pcall(f, o.id, o.menge) then return abbrechen("Dieser Client lässt Addons hier nicht kaufen.") end
    gestartet = true
    return phase("warte")
  end
  if o.phase ~= "bereit" and o.phase ~= "warnung" then return end
  if o.art == "kauf" then
    op = nil
    if o.summe > geld() then return melde("Zu wenig Gold.") end
    eigenBis = jetzt() + 30
    if o.commodity then
      if not quoteGilt() then
        gestartet = true   -- damit kaufAbbrechen den angefangenen Kauf beim Server beendet
        kaufAbbrechen()
        return melde("Der Preis vom Server ist abgelaufen. Prüfe noch einmal.")
      end
      local f = C("ConfirmCommoditiesPurchase")
      gestartet = false
      if not f or not pcall(f, o.id, o.menge) then return melde("Kauf ging nicht.") end
      return melde(("Kaufe %d x %s für %s ..."):format(o.menge, name(o.id), WW.Geld(o.preis)))
    end
    local f = C("PlaceBid")
    if not f or not pcall(f, o.auktion, o.summe) then return melde("Kauf ging nicht.") end
    return melde(("Kaufe %s für %s ..."):format(name(o.id), WW.Geld(o.summe)))
  end
  -- verkauf: Platz und Menge neu prüfen
  local p = o.platz
  local info = p and C_Container and C_Container.GetContainerItemInfo and try(C_Container.GetContainerItemInfo, p.bag, p.slot)
  local warnung = o.phase == "warnung"   -- nach der Warnung darf der Server die Items gesperrt haben
  if type(info) ~= "table" or info.itemID ~= o.id or info.isBound or (info.isLocked and not warnung)
    or (not o.commodity and (tonumber(info.stackCount) or 1) ~= o.menge)
    or (o.commodity and not warnung and H.Besitz(o.id) ~= o.menge) then
    return abbrechen("Deine Taschen haben sich geändert. Prüfe noch einmal.")
  end
  local ort = ortVon(p)
  if not ort then return abbrechen("Dieser Client lässt Addons hier nicht einstellen.") end
  local db = WW.db and WW.db.ah
  local dauer = DAUER_NR[tonumber(db and db.dauer) or 8] or 2
  local fname
  if o.phase == "warnung" then
    fname = o.commodity and "ConfirmPostCommodity" or "ConfirmPostItem"
  else
    fname = o.commodity and "PostCommodity" or "PostItem"
  end
  local f = C(fname)
  if not f then return abbrechen("Dieser Client lässt Addons hier nicht einstellen.") end
  -- PostItem: Sofortkauf je Stück (wie Blizzards Fenster), PostCommodity: Stückpreis
  local ok, warnung
  if o.commodity then ok, warnung = pcall(f, ort, dauer, o.menge, o.stueckPreis)
  else ok, warnung = pcall(f, ort, dauer, o.menge, nil, o.stueckPreis) end
  if not ok then return abbrechen("Einstellen ging nicht.") end
  if warnung == true and o.phase ~= "warnung" then
    phase("warnung")
    return melde("Das Auktionshaus verlangt eine Bestätigung (z. B. ungewöhnlicher Preis). Klick noch einmal, um trotzdem einzustellen.")
  end
  op = nil
  eigenBis = jetzt() + 30
  melde(("Stelle %d x %s für %s je Stück ein ..."):format(o.menge, name(o.id), WW.Geld(o.stueckPreis)))
end

-- Klick auf den Knopf einer Zeile. eintrag = Zeile der Liste (id, preis, normal), art = "schnaeppchen"|"teuer"
function H.Klick(e, art)
  if type(e) ~= "table" or not tonumber(e.id) then return end
  if not (WW.AH and WW.AH.Offen and WW.AH.Offen()) then return melde("Öffne das Auktionshaus, um zu kaufen oder einzustellen.") end
  local wolle = istVerkauf(art) and "verkauf" or "kauf"
  -- Vorgang gilt nur in der Ansicht, in der er begann ("Zu teuer" ist strenger als "Verkaufen")
  if op and op.id == e.id and op.art == wolle and op.ansicht == art then return weiter() end
  kaufAbbrechen()
  meldung = nil
  op = { art = wolle, id = e.id, ansicht = art }
  if wolle == "kauf" then
    local db = WW.db and WW.db.ah
    op.maxPreis = math.floor((tonumber(e.normal) or 0) * (tonumber(db and db.schnaeppchen) or 0.7))
    if op.maxPreis <= 0 then return abbrechen("Kein üblicher Preis bekannt.") end
  else
    if H.Besitz(e.id) == 0 then return abbrechen("Das Item liegt nicht (ungebunden) in deinen Taschen.") end
    if art == "verkaufen" then
      op.minPreis = math.floor(tonumber(e.boden) or 0)
      op.zurGrenzeErlaubt = true
    else
      op.minPreis = math.floor(tonumber(e.normal) or 0)
    end
    -- roher Scan-Preis (in "Verkaufen" ist e.preis schon der Vorschlag mit 1 Silber Abzug)
    op.scanPreis = tonumber(e.scanMin) or tonumber(e.preis)
    if op.minPreis <= 0 then return abbrechen("Kein üblicher Preis bekannt.") end
  end
  if not suchen(e.id) then return abbrechen("Dieser Client lässt Addons das Auktionshaus nicht durchsuchen.") end
end

local function meinOp(e, art)
  local wolle = istVerkauf(art) and "verkauf" or "kauf"
  return op and e and op.id == e.id and op.art == wolle and op.ansicht == art and op or nil, wolle
end

function H.KnopfText(e, art)
  local o, wolle = meinOp(e, art)
  if o then
    if o.phase == "suche" or o.phase == "warte" then return "Frage ..." end
    if o.phase == "gefunden" then return "Preis holen" end
    if o.phase == "warnung" then return "Trotzdem?" end
    if o.phase == "bereit" then
      if wolle == "kauf" then return "Kaufen: " .. WW.Geld(o.preis or o.summe) end
      return "Einstellen: " .. o.menge .. "x"
    end
  end
  return wolle == "kauf" and "Prüfen" or "Prüfen"
end

function H.KnopfHilfe(e, art)
  local o, wolle = meinOp(e, art)
  if o and o.phase == "gefunden" then
    return ("%d Stück für zusammen höchstens %s (je Stück bis %s). Nächster Klick holt den genauen Preis vom Server, kauft aber noch nicht."):format(
      o.menge, WW.Geld(o.summe), WW.Geld(o.maxPreis))
  end
  if o and o.phase == "bereit" and wolle == "kauf" then
    return ("%d Stück für zusammen %s. Nächster Klick kauft."):format(o.menge, WW.Geld(o.preis or o.summe))
  end
  if o and (o.phase == "bereit" or o.phase == "warnung") then
    if o.zurGrenze then
      return ("%d Stück für %s je Stück. Das günstigste Angebot ist billiger als deine Untergrenze, darum stellst du zur Untergrenze ein (verkauft sich vielleicht langsamer). Nächster Klick stellt ein."):format(
        o.menge, WW.Geld(o.stueckPreis))
    end
    return ("%d Stück für %s je Stück (1 Silber unter dem günstigsten Angebot). Nächster Klick stellt ein."):format(
      o.menge, WW.Geld(o.stueckPreis))
  end
  if wolle == "kauf" then
    return "Erster Klick: sucht das günstigste Angebot. Danach zeigt der Knopf Menge und Preis, gekauft wird erst mit einem weiteren Klick. "
      .. "Nur bis zur Schnäppchen-Grenze und höchstens ein Viertel deines Golds."
  end
  if art == "verkaufen" then
    return ("Erster Klick: sucht das günstigste Angebot. Danach zeigt der Knopf, was eingestellt wird: 1 Silber darunter, aber nie unter %s je Stück (80 %% vom üblichen Preis, nie weniger als beim Händler)."):format(
      WW.Geld(tonumber(e and e.boden) or 0))
  end
  return "Erster Klick: sucht das günstigste Angebot. Danach zeigt der Knopf, was eingestellt wird (1 Silber darunter, nie unter dem üblichen Preis)."
end

---------------------------------------------------------------------------
-- Ereignisse und Zeitlimits
---------------------------------------------------------------------------
local rahmen = CreateFrame("Frame")
for _, ev in ipairs({ "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED", "COMMODITY_PRICE_UPDATED",
  "COMMODITY_PURCHASE_SUCCEEDED", "COMMODITY_PURCHASE_FAILED", "AUCTION_HOUSE_CLOSED", "AUCTION_HOUSE_AUCTION_CREATED",
  "COMMODITY_PRICE_UNAVAILABLE" }) do
  pcall(rahmen.RegisterEvent, rahmen, ev)
end
rahmen:SetScript("OnEvent", function(_, ev, a1, a2)
  if ev == "COMMODITY_SEARCH_RESULTS_UPDATED" then
    if op and tonumber(a1) == op.id then sucheFertig(true) end
  elseif ev == "ITEM_SEARCH_RESULTS_UPDATED" then
    local id = type(a1) == "table" and tonumber(a1.itemID) or tonumber(a1)
    if op and id == op.id then sucheFertig(false, type(a1) == "table" and a1 or nil) end
  elseif ev == "COMMODITY_PRICE_UPDATED" then
    preisDa(a1, a2)
  elseif ev == "COMMODITY_PRICE_UNAVAILABLE" then
    if gestartet and op and op.commodity then abbrechen("Das Auktionshaus nennt gerade keinen Preis. Nicht gekauft.") end
  elseif ev == "COMMODITY_PURCHASE_SUCCEEDED" or ev == "COMMODITY_PURCHASE_FAILED" or ev == "AUCTION_HOUSE_AUCTION_CREATED" then
    if jetzt() <= eigenBis then
      eigenBis = 0
      melde((ev == "COMMODITY_PURCHASE_FAILED") and WW.f("rot", "Kauf fehlgeschlagen.")
        or (ev == "AUCTION_HOUSE_AUCTION_CREATED" and WW.f("gruen", "Auktion eingestellt.")) or WW.f("gruen", "Kauf erfolgreich."))
    end
  elseif ev == "AUCTION_HOUSE_CLOSED" then
    gestartet = false
    if op then op = nil; geaendert() end
  end
end)

local t = 0
rahmen:SetScript("OnUpdate", function(_, dt)
  t = t + (dt or 0)
  if t < 0.25 then return end
  t = 0
  if not op then return end
  local alter = jetzt() - (op.seit or jetzt())
  if (op.phase == "suche" or op.phase == "warte") and alter > SUCH_ZEIT then
    abbrechen("Das Auktionshaus hat nicht geantwortet.")
  elseif (op.phase == "gefunden" or op.phase == "bereit" or op.phase == "warnung") and alter > BEREIT_ZEIT then
    kaufAbbrechen()
    op = nil
    geaendert()
  elseif (op.phase == "bereit" or op.phase == "gefunden") and alter >= PAUSE and not op.freiGezeigt then
    op.freiGezeigt = true   -- Knopf nach der Pause neu zeichnen
    geaendert()
  end
end)
