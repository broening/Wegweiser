-- Wegweiser: Müll-Knopf an der Tasche und Taschenwert.
-- Ein Klick löscht das billigste Müll-Item (grau, oder "Müll" aus Module\Urteil.lua bis Qualität grün).
-- Nie: geschützte Items (Quest, Beruf, Twink, Entzaubern, gemerkt), Qualität blau oder besser, gesperrte Plätze.
-- Maus darüber: was als Nächstes gelöscht wird, und was Müll und AH-Items in der Tasche wert sind.
-- Öffentlich: WW.Muell.Kandidat() -> {bag, slot, id, anzahl, wert} oder nil, WW.Muell.Loeschen(),
--             WW.Muell.Taschenwert() -> { muellN, muell, ahN, ah, ahListe }, WW.Muell.WertText(w)
local ADDON, WW = ...

local M = {}
WW.Muell = M

local LEER = {}
local function pass(ok, ...) if ok then return ... end end
local function try(f, ...)
  if type(f) ~= "function" then return nil end
  return pass(pcall(f, ...))
end
local function einst() return WW.db and WW.db.urteil end

local function slots(bag)
  local f = (C_Container and C_Container.GetContainerNumSlots) or WW.Alt("GetContainerNumSlots")
  return tonumber(try(f, bag)) or 0
end
local function platz(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo then
    local i = try(C_Container.GetContainerItemInfo, bag, slot)
    if type(i) == "table" and i.itemID then
      return { id = tonumber(i.itemID), anzahl = i.stackCount or 1, gebunden = i.isBound and true or false,
        gesperrt = i.isLocked and true or false, q = tonumber(i.quality) }
    end
    return nil
  end
  local alt = WW.Alt("GetContainerItemInfo")
  if alt then
    local _, anz, gesperrt, q, _, _, link, _, _, id, geb = try(alt, bag, slot)
    id = tonumber(id) or WW.ItemID(link)
    if id then return { id = id, anzahl = anz or 1, gebunden = geb and true or false, gesperrt = gesperrt and true or false, q = tonumber(q) } end
  end
  return nil
end

local function taschen() return (WW.TaschenIDs and try(WW.TaschenIDs)) or { 0, 1, 2, 3, 4 } end

-- Ist das Müll, den der Knopf löschen darf? Gibt Verkaufswert (Kupfer, ganzer Stapel) zurück oder nil
local function muellWert(p)
  if not p or p.gesperrt then return nil end
  local _, _, qInfo, _, _, _, _, _, _, _, verkauf = WW.GetItemInfo(p.id)
  local q = math.max(tonumber(p.q) or 0, tonumber(qInfo) or 0)
  if not qInfo and not p.q then return nil end   -- Daten noch nicht da: nichts tun
  if q >= 3 then return nil end
  if verkauf == nil then return nil end   -- Wert unbekannt (Item noch nicht geladen): nie als "billigster" löschen
  local U = WW.Urteil
  local ok, e = pcall(function() return U and U.Pruefen(p.id, p.anzahl, p.gebunden) end)
  if not ok then return nil end
  if e and e.schutz then return nil end
  local istMuell = q == 0 or (e and e.gruppe == "muell")
  if not istMuell then return nil end
  return (tonumber(verkauf) or 0) * (p.anzahl or 1)
end

function M.Kandidat()
  local best
  for _, bag in ipairs(taschen()) do
    for slot = 1, slots(bag) do
      local p = platz(bag, slot)
      local w = muellWert(p)
      if w and (not best or w < best.wert or (w == best.wert and p.anzahl < best.anzahl)) then
        best = { bag = bag, slot = slot, id = p.id, anzahl = p.anzahl, wert = w }
      end
    end
  end
  return best
end

function M.Taschenwert()
  local w = { muellN = 0, muell = 0, ahN = 0, ah = 0, ahListe = {} }
  local AH = WW.AH
  for _, bag in ipairs(taschen()) do
    for slot = 1, slots(bag) do
      local p = platz(bag, slot)
      local mw = muellWert(p)
      if mw then
        w.muellN, w.muell = w.muellN + 1, w.muell + mw
      elseif p and not p.gebunden and AH and AH.Bewertung then
        local U = WW.Urteil
        local ok, e = pcall(function() return U and U.Pruefen(p.id, p.anzahl, p.gebunden) end)
        if ok and not e then
          local farbe, _, erloes = AH.Bewertung(p.id, p.anzahl, false)
          if farbe == "gruen" then
            w.ahN, w.ah = w.ahN + 1, w.ah + (tonumber(erloes) or 0)
            table.insert(w.ahListe, { id = p.id, anzahl = p.anzahl, erloes = tonumber(erloes) or 0 })
          end
        end
      end
    end
  end
  table.sort(w.ahListe, function(a, b) return a.erloes > b.erloes end)
  return w
end

local function anzahl(n) return n == 1 and "1 Item" or (n .. " Items") end
function M.WertText(w)
  local muell = (w.muellN > 0) and ("Müll: %s, %s beim Händler"):format(anzahl(w.muellN), WW.Geld(w.muell))
    or "Müll: keiner"
  local ah = (w.ahN > 0) and ("AH lohnt: %s, %s nach Gebühren"):format(anzahl(w.ahN), WW.Geld(w.ah))
    or "AH lohnt: nichts"
  return muell .. "\n" .. ah
end

-- Billigsten Müll löschen. Gibt true zurück, wenn gelöscht wurde.
function M.Loeschen()
  local k = M.Kandidat()
  if not k then WW:Print("Kein Müll in den Taschen.") return false end
  local hat, info, frei = WW.Alt("CursorHasItem"), WW.Alt("GetCursorInfo"), WW.Alt("ClearCursor")
  local loesch = WW.Alt("DeleteCursorItem")
  local pickup = (C_Container and C_Container.PickupContainerItem) or WW.Alt("PickupContainerItem")
  if not (info and loesch and pickup) then WW:Print("Dieser Client kann keine Items löschen.") return false end
  if (hat and try(hat)) or try(info) then WW:Print("Du hast etwas an der Maus. Leg es zuerst ab.") return false end
  -- Wartet ein Zauber auf ein Ziel, würde das Aufnehmen ihn auf das Item wirken
  if try(WW.Alt("SpellIsTargeting")) then WW:Print("Ein Zauber wartet auf ein Ziel. Brich ihn zuerst ab.") return false end
  -- Zur Sicherheit: liegt noch dasselbe auf dem Platz?
  local p = platz(k.bag, k.slot)
  if not p or p.id ~= k.id then return false end
  try(pickup, k.bag, k.slot)
  local typ, cid = try(info)
  if typ == "item" and tonumber(cid) == k.id then
    try(loesch)
    WW:Print(("Gelöscht: %s x%d (Wert %s)"):format(WW.ItemName(k.id) or ("Item " .. k.id), k.anzahl, WW.Geld(k.wert)))
    return true
  end
  if frei then try(frei) end
  return false
end

---------------------------------------------------------------------------
-- Knopf an der Tasche
---------------------------------------------------------------------------
local knopf
local function rahmen()
  for _, n in ipairs({ "ContainerFrameCombinedBags", "ContainerFrame1" }) do
    local f = rawget(_G, n)
    if f and f.IsShown and f:IsShown() then return f end
  end
  return nil
end

local function knopfBauen()
  if knopf then return knopf end
  knopf = CreateFrame("Button", "WegweiserMuellKnopf", UIParent)
  knopf:SetSize(24, 24)
  knopf:SetFrameStrata("HIGH")
  local icon = knopf:CreateTexture(nil, "ARTWORK")
  icon:SetAllPoints()
  icon:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
  local hl = knopf:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 1, 1, 0.15)
  knopf:SetScript("OnClick", function(self, maus)
    if maus and maus ~= "LeftButton" then return end
    M.Loeschen()
    if self:IsMouseOver() and self:GetScript("OnEnter") then self:GetScript("OnEnter")(self) end
  end)
  knopf:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Wegweiser")
    local k = M.Kandidat()
    if k then
      GameTooltip:AddLine(("Klick löscht: %s x%d (Wert %s)"):format(WW.ItemName(k.id) or ("Item " .. k.id), k.anzahl,
        WW.Geld(k.wert)), 1, 1, 1, true)
      GameTooltip:AddLine("Billigster Müll in deinen Taschen. Nie blau oder besser, nie geschützt.", 0.7, 0.7, 0.7, true)
    else
      GameTooltip:AddLine("Kein Müll in den Taschen.", 1, 1, 1)
    end
    local ok, w = pcall(M.Taschenwert)
    if ok and w then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine(M.WertText(w), 1, 0.82, 0.4, true)
      for i = 1, math.min(3, #w.ahListe) do
        local x = w.ahListe[i]
        GameTooltip:AddLine(("  %s x%d: %s"):format(WW.ItemName(x.id) or ("Item " .. x.id), x.anzahl, WW.Geld(x.erloes)), 0.8, 0.8, 0.8)
      end
    end
    GameTooltip:Show()
  end)
  knopf:SetScript("OnLeave", function() GameTooltip:Hide() end)
  knopf:Hide()
  return knopf
end

function M.KnopfAktualisieren()
  local db = einst()
  local r = rahmen()
  if not (db and db.loeschen and r) then
    if knopf then knopf:Hide() end
    return
  end
  knopfBauen()
  knopf:ClearAllPoints()
  knopf:SetPoint("BOTTOMLEFT", r, "TOPLEFT", 6, 2)
  knopf:Show()
end

local function planen()
  if C_Timer and C_Timer.After then C_Timer.After(0.05, M.KnopfAktualisieren) else M.KnopfAktualisieren() end
end
local gehakt = {}
WW:BeimStart(function()
  for _, name in ipairs({ "OpenAllBags", "ToggleAllBags", "OpenBag", "ToggleBag", "OpenBackpack", "ToggleBackpack",
    "CloseAllBags", "CloseBag", "CloseBackpack" }) do
    if type(rawget(_G, name)) == "function" then hooksecurefunc(name, planen) end
  end
  for _, n in ipairs({ "ContainerFrameCombinedBags", "ContainerFrame1" }) do
    local f = rawget(_G, n)
    if f and f.HookScript and not gehakt[f] then
      gehakt[f] = true
      pcall(f.HookScript, f, "OnShow", planen)
      pcall(f.HookScript, f, "OnHide", planen)
    end
  end
  planen()
end)
WW:Event("BAG_UPDATE_DELAYED", planen)
