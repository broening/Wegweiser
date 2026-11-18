-- Wegweiser: Händler-Hilfe. Beim Händler ein Knopf, der Items verkauft, die nur beim Händler Geld bringen:
--   graue Items (schlechte Qualität) und Items, die im AH weniger bringen als beim Händler (Urteil "Händler", rot).
-- Sicherheit: erster Klick zeigt Anzahl und Summe, erst der zweite Klick (innerhalb von 5 Sekunden) verkauft.
-- Verkauft wird langsam (ein Platz pro Schritt) und nur, solange das Händlerfenster offen ist.
-- Öffentlich: WW.Haendler.Liste() -> { {bag, slot, id, anzahl, preis, grund}, ... }, summe
local ADDON, WW = ...
local UI = WW.UI

WW.standardDB.haendler = {
  knopf = true,     -- Knopf beim Händler zeigen
  graue = true,     -- graue Items verkaufen
  rote = false,     -- Items, die im AH weniger bringen als beim Händler (selbst einschalten)
  muell = true,     -- "Müll" aus Module\Urteil.lua: gebunden und deine Klasse kann es nie tragen, bekanntes Rezept
  stand = 2,        -- Stand der Standardwerte (2: "rote" aus)
}

-- Wer die erste Fassung schon geladen hat, hatte "rote" an: einmal auf aus setzen (Dans Wahl, 18.11.).
WW:BeimStart(function()
  local db = WW.db and WW.db.haendler
  if db and (tonumber(db.stand) or 0) < 2 then db.rote, db.stand = false, 2 end
end)

local HD = {}
WW.Haendler = HD

local BESTAETIGEN_SEK = 5     -- so lange gilt der erste Klick
local ROT_MAX_ALTER = 7 * 86400   -- "AH lohnt nicht" nur mit Preisen aus den letzten 7 Tagen,
local ROT_MIN_SCANS = 3           -- aus mindestens 3 Scans, und auch der Normalpreis liegt unter dem Händlerpreis
local AH_ABZUG_MIN = 0.05         -- kleinster Abzug des Auktionshauses (Fraktions-AH)
local MAX_WARTEN = 10             -- Schritte, die auf die Antwort des Servers gewartet wird
-- Diese Fenster lassen UseContainerItem etwas anderes tun als verkaufen (Handel, Post, Bank): dann stoppen.
local SPERR_FENSTER = { "TradeFrame", "SendMailFrame", "BankFrame", "GuildBankFrame", "MailFrame" }
local SCHRITT_SEK = 0.2       -- Pause zwischen zwei Verkäufen

local function pass(ok, ...) if ok then return ... end end
local function try(f, ...)
  if type(f) ~= "function" then return nil end
  return pass(pcall(f, ...))
end

local function einst() return WW.db and WW.db.haendler end

-- Inhalt eines Platzes als Tabelle: { id, anzahl, gebunden, gesperrt, qualitaet } oder nil
local function platz(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo then
    local info = try(C_Container.GetContainerItemInfo, bag, slot)
    if type(info) == "table" and info.itemID then
      return { id = info.itemID, anzahl = info.stackCount or 1, gebunden = info.isBound and true or false,
        gesperrt = info.isLocked and true or false, qualitaet = info.quality }
    end
    return nil
  end
  local alt = WW.Alt("GetContainerItemInfo")
  if alt then
    local _, anz, gesperrt, q, _, _, link, _, _, id, gebunden = try(alt, bag, slot)
    if not id and type(link) == "string" then id = tonumber(link:match("item:(%d+)")) end
    if id then return { id = id, anzahl = anz or 1, gebunden = gebunden and true or false, gesperrt = gesperrt and true or false, qualitaet = q } end
  end
  return nil
end

local function slotAnzahl(bag)
  local f = (C_Container and C_Container.GetContainerNumSlots) or WW.Alt("GetContainerNumSlots")
  return tonumber(try(f, bag)) or 0
end

-- Prüft einen Platz: Eintrag { bag, slot, id, anzahl, preis, grund } oder nil, wenn er nicht verkauft wird.
function HD.PlatzPruefen(bag, slot)
  local db = einst() or {}
  local p = platz(bag, slot)
  if not p or p.gesperrt then return nil end
  local _, _, q, _, _, _, _, _, ort, _, verkauf = WW.GetItemInfo(p.id)
  local qInfo = tonumber(q) or 0
  q = p.qualitaet or q
  verkauf = tonumber(verkauf) or 0
  if verkauf <= 0 then return nil end
  -- Geschützt (Quest, Beruf, gemerkt, Module\Urteil.lua): nie verkaufen, auch nicht grau
  local U = WW.Urteil
  local okU, u = pcall(function() return U and U.Pruefen(p.id, p.anzahl, p.gebunden) end)
  if not okU then return nil end   -- im Zweifel bleibt es
  if u and u.schutz then return nil end
  local grund
  if db.graue and q == 0 then
    grund = "grau"
  elseif db.rote and WW.AH and WW.AH.Bewertung and WW.AH.Preis then
    -- Nie Ausrüstung ab Qualität grün: die will man vielleicht tragen.
    local ausruestung = type(ort) == "string" and ort ~= "" and ort ~= "INVTYPE_NON_EQUIP_IGNORE"
    if not (ausruestung and (tonumber(q) or 0) >= 2) then
      -- Ein einzelner billiger Stapel reicht nicht: das Item muss seit mehreren Scans billig sein.
      local farbe = WW.AH.Bewertung(p.id, p.anzahl, p.gebunden)
      local a = farbe == "rot" and WW.AH.Analyse and WW.AH.Analyse(p.id)
      if a and (tonumber(a.alter) or math.huge) <= ROT_MAX_ALTER and (tonumber(a.scans) or 0) >= ROT_MIN_SCANS
        and tonumber(a.normal) and a.normal * (1 - AH_ABZUG_MIN) <= verkauf then
        grund = "AH lohnt nicht"
      end
    end
  end
  -- Müll: nur bis Qualität grün; mit Verzauberkunst nicht ab grün (lieber entzaubern)
  if not grund and db.muell and u and u.gruppe == "muell" then
    -- höhere der beiden Qualitäten (manche Clients melden im Taschenplatz -1)
    local qz = math.max(tonumber(q) or 0, qInfo)
    local berufe = WW.Handwerk and try(WW.Handwerk.EigeneBerufe)
    local entzaubern = type(berufe) == "table" and berufe.Enchanting ~= nil
    if qz <= 2 and not (entzaubern and qz >= 2) then grund = "Müll: " .. (u.kurz or "") end
  end
  if not grund then return nil end
  return { bag = bag, slot = slot, id = p.id, anzahl = p.anzahl, preis = verkauf * p.anzahl, grund = grund }
end

-- Was würde verkauft? Liste und Summe (Kupfer).
function HD.Liste()
  local raus, summe = {}, 0
  for _, bag in ipairs(WW.TaschenIDs and WW.TaschenIDs() or { 0, 1, 2, 3, 4 }) do
    for slot = 1, slotAnzahl(bag) do
      local e = HD.PlatzPruefen(bag, slot)
      if e then
        raus[#raus + 1] = e
        summe = summe + e.preis
      end
    end
  end
  return raus, summe
end

---------------------------------------------------------------------------
-- Verkaufen
---------------------------------------------------------------------------
local haendlerOffen = false
local warteschlange, verkauft, erloes = nil, 0, 0
local offen = nil   -- letzter Verkauf, noch nicht bestätigt: { bag, slot, id, preis }
local motor = CreateFrame("Frame")
motor:Hide()

-- Ist der letzte Verkauf wirklich passiert (Platz leer oder anderes Item)? Erst dann zählt er.
-- Gibt true zurück, wenn noch auf den Server gewartet wird (Platz gesperrt).
local function offenPruefen(amEnde)
  if not offen then return false end
  local p = platz(offen.bag, offen.slot)
  if p and p.id == offen.id and p.gesperrt and not amEnde and offen.warten < MAX_WARTEN then
    offen.warten = offen.warten + 1
    return true
  end
  if not p or p.id ~= offen.id then
    verkauft = verkauft + 1
    erloes = erloes + offen.preis
  end
  offen = nil
  return false
end

-- Name eines offenen Fensters, das den Verkauf stört, sonst nil
local function stoerFenster()
  for _, name in ipairs(SPERR_FENSTER) do
    local f = rawget(_G, name)
    local sichtbar = type(f) == "table" and (type(f.IsVisible) == "function" and f.IsVisible or f.IsShown)
    if type(sichtbar) == "function" then
      local ok, an = pcall(sichtbar, f)
      if ok and an == true then return name end
    end
  end
  local mf = rawget(_G, "MerchantFrame")
  if type(mf) == "table" then
    if type(mf.IsShown) == "function" then
      local ok, an = pcall(mf.IsShown, mf)
      if ok and an == false then return "MerchantFrame zu" end
    end
    if mf.selectedTab == 2 then return "Rückkauf" end
  end
  return nil
end

local function fertig(grund)
  if not grund and offenPruefen() then return end   -- letzter Verkauf: noch auf den Server warten
  offenPruefen(true)
  motor:Hide()
  if warteschlange and verkauft > 0 then
    WW:Print(("Verkauft: %d Items für %s.%s"):format(verkauft, WW.Geld(erloes),
      grund and (" " .. grund) or ""))
  elseif grund then
    WW:Print(grund)
  end
  warteschlange, verkauft, erloes = nil, 0, 0
  if HD.KnopfAktualisieren then HD.KnopfAktualisieren() end
end

local zeit = 0
motor:SetScript("OnUpdate", function(_, dt)
  zeit = zeit + (dt or 0)
  if zeit < SCHRITT_SEK then return end
  zeit = 0
  if offenPruefen() then return end   -- Server hat den letzten Verkauf noch nicht bestätigt
  if not haendlerOffen then return fertig("Händler geschlossen, Verkauf gestoppt.") end
  if stoerFenster() then return fertig("Ein anderes Fenster ist offen (Handel, Post, Bank). Verkauf gestoppt.") end
  local e = warteschlange and table.remove(warteschlange, 1)
  if not e then return fertig() end
  -- Gilt für diesen Platz noch genau dasselbe? Sonst überspringen (nie etwas anderes verkaufen).
  local jetzt = HD.PlatzPruefen(e.bag, e.slot)
  if not jetzt or jetzt.id ~= e.id or jetzt.anzahl ~= e.anzahl or jetzt.grund ~= e.grund then return end
  local use = (C_Container and C_Container.UseContainerItem) or WW.Alt("UseContainerItem")
  if not use then return fertig("Dieser Client lässt Addons nichts verkaufen.") end
  if pcall(use, e.bag, e.slot) then offen = { bag = e.bag, slot = e.slot, id = e.id, preis = e.preis, warten = 0 } end
end)

-- Fingerabdruck einer Liste: gleiche Plätze, Items und Mengen
local function abdruck(liste)
  local t = {}
  for i, e in ipairs(liste) do t[i] = e.bag .. ":" .. e.slot .. ":" .. e.id .. ":" .. e.anzahl end
  return table.concat(t, ",")
end
HD.Abdruck = abdruck

-- Verkauft nur, wenn die Liste noch genau die gezeigte ist (gezeigt = Abdruck vom ersten Klick).
function HD.Verkaufen(gezeigt)
  if not haendlerOffen then return false, "Kein Händler offen." end
  if warteschlange then return false, "Verkauf läuft schon." end
  local liste = HD.Liste()
  if #liste == 0 then return false, "Nichts zu verkaufen." end
  if gezeigt ~= abdruck(liste) then return false, "Die Liste hat sich geändert. Prüfe sie und klicke noch zweimal." end
  if stoerFenster() then return false, "Schließe zuerst Handel, Post und Bank." end
  offen = nil
  warteschlange, verkauft, erloes, zeit = liste, 0, 0, SCHRITT_SEK
  motor:Show()
  return true
end

---------------------------------------------------------------------------
-- Knopf am Händlerfenster
---------------------------------------------------------------------------
local knopf
local bestaetigtBis = 0
local gezeigt = nil   -- Abdruck der Liste beim ersten Klick

local function jetzt() return (GetTime and GetTime()) or 0 end

function HD.KnopfAktualisieren()
  if not knopf then return end
  if warteschlange then
    knopf:SetText(("Verkaufe ... (%d übrig)"):format(#warteschlange))
    return
  end
  local liste, summe = HD.Liste()
  if #liste == 0 then
    knopf:SetText("Nichts zu verkaufen")
  elseif jetzt() < bestaetigtBis then
    knopf:SetText(("Wirklich? %d für %s"):format(#liste, WW.Geld(summe)))
  else
    knopf:SetText(("Händlerware: %d Items"):format(#liste))
  end
end

local function knopfTooltip(self)
  local liste, summe = HD.Liste()
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:AddLine("Wegweiser: Händlerware verkaufen")
  GameTooltip:AddLine("Graue Items und Items, die im Auktionshaus weniger bringen als beim Händler.", 1, 1, 1, true)
  GameTooltip:AddLine("Erster Klick: prüfen. Zweiter Klick: verkaufen.", 0.8, 0.8, 0.8, true)
  GameTooltip:AddLine(" ")
  -- Rote Items immer mit Namen; graue nur bis 15 Zeilen, der Rest als Summe.
  local zeilen, grauRest, grauSumme = 0, 0, 0
  for _, e in ipairs(liste) do
    if e.grund == "grau" and zeilen >= 15 then
      grauRest, grauSumme = grauRest + 1, grauSumme + e.preis
    else
      zeilen = zeilen + 1
      local name = WW.ItemName(e.id) or ("Item " .. e.id)
      GameTooltip:AddDoubleLine((e.anzahl > 1 and (e.anzahl .. "x ") or "") .. name .. WW.f("grau", " (" .. e.grund .. ")"),
        WW.Geld(e.preis), 1, 1, 1, 1, 1, 1)
    end
  end
  if grauRest > 0 then
    GameTooltip:AddDoubleLine(("... und %d weitere graue Items"):format(grauRest), WW.Geld(grauSumme), 0.7, 0.7, 0.7, 1, 1, 1)
  end
  if #liste > 0 then GameTooltip:AddDoubleLine("Summe", WW.Geld(summe), 1, 0.82, 0, 1, 1, 1) end
  GameTooltip:Show()
end

local function knopfBauen()
  if knopf then return knopf end
  local mf = rawget(_G, "MerchantFrame")
  if type(mf) ~= "table" then return nil end
  knopf = CreateFrame("Button", "WegweiserHaendlerKnopf", mf, "UIPanelButtonTemplate")
  knopf:SetSize(190, 22)
  knopf:SetPoint("TOPRIGHT", mf, "BOTTOMRIGHT", 0, -2)
  knopf:SetScript("OnClick", function(self)
    if warteschlange then return end
    if jetzt() < bestaetigtBis then
      bestaetigtBis = 0
      local ok, warum = HD.Verkaufen(gezeigt)
      gezeigt = nil   -- nach einer Änderung prüft der nächste Klick wieder nur
      if not ok and warum then WW:Print(warum) end
    else
      local liste = HD.Liste()
      if #liste > 0 then   -- leere Liste: nicht scharf schalten
        gezeigt, bestaetigtBis = abdruck(liste), jetzt() + BESTAETIGEN_SEK
      end
    end
    HD.KnopfAktualisieren()
    if GameTooltip:IsOwned(self) then knopfTooltip(self) end
  end)
  knopf:SetScript("OnEnter", knopfTooltip)
  knopf:SetScript("OnLeave", function() GameTooltip:Hide() end)
  -- Nach Ablauf der 5 Sekunden wieder den normalen Text zeigen
  local t = 0
  knopf:SetScript("OnUpdate", function(_, dt)
    t = t + (dt or 0)
    if t >= 0.5 then
      t = 0
      if bestaetigtBis > 0 and jetzt() >= bestaetigtBis then
        bestaetigtBis = 0
        HD.KnopfAktualisieren()
      end
    end
  end)
  return knopf
end

WW:Event("MERCHANT_SHOW", function()
  haendlerOffen = true
  bestaetigtBis, gezeigt = 0, nil
  local db = einst()
  if db and db.knopf and knopfBauen() then
    knopf:Show()
    HD.KnopfAktualisieren()
  elseif knopf then
    knopf:Hide()
  end
end)
WW:Event("MERCHANT_CLOSED", function()
  haendlerOffen = false
  bestaetigtBis, gezeigt = 0, nil
end)
WW:Event("BAG_UPDATE_DELAYED", function()
  if haendlerOffen and knopf and knopf:IsShown() then HD.KnopfAktualisieren() end
end)
