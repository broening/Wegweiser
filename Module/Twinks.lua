-- Wegweiser: an Twinks denken. Twinks = deine anderen Charaktere auf demselben Realm und in derselben Fraktion.
-- Jeder Charakter speichert beim Einloggen seine Berufe und gelernten Rezepte in WW.db.inventar[Realm][Name]:
--   berufe = { [Beruf englisch] = Fertigkeit }, rezepte = { [Beruf] = { [Zauber] = true } }, twinkAus = true (ausgeschlossen)
-- Ein Item ist "für Twinks", wenn es eine Zutat für ein Rezept ist, das einem Twink noch Punkte gibt
-- (Rezept bekannt, oder: Haken "fremde" und Fertigkeit reicht schon). Gebundene Items gehen nicht per Post.
-- Am Briefkasten: Knopf "An Twinks" hängt die Items für einen Twink an und trägt den Namen ein. Senden klickst du selbst.
-- Öffentlich: WW.Twinks.Liste(), WW.Twinks.Brauchen(id) -> { {name, berufe = {englisch, ...}} } oder nil
local ADDON, WW = ...

local T = {}
WW.Twinks = T

local LEER = {}
local function pass(ok, ...) if ok then return ... end end
local function try(f, ...)
  if type(f) ~= "function" then return nil end
  return pass(pcall(f, ...))
end
local function tab(t) return type(t) == "table" and t or LEER end
local function einst() return WW.db and WW.db.urteil end

local function meinRealm() local r = GetRealmName and try(GetRealmName) return (type(r) == "string" and r ~= "") and r or nil end
local function meinName() local n = UnitName and try(UnitName, "player") return (type(n) == "string" and n ~= "") and n or nil end
local function meineFraktion() return UnitFactionGroup and try(UnitFactionGroup, "player") end

local function eigenerEintrag()
  local inv = WW.db and WW.db.inventar
  local realm, name = meinRealm(), meinName()
  if type(inv) ~= "table" or not realm or not name then return nil end
  inv[realm] = type(inv[realm]) == "table" and inv[realm] or {}
  inv[realm][name] = type(inv[realm][name]) == "table" and inv[realm][name] or {}
  return inv[realm][name]
end

-- Berufe und Rezepte dieses Charakters für die Twinks der anderen speichern
function T.Speichern()
  local e = eigenerEintrag()
  if not e then return end
  local f = WW.Handwerk and WW.Handwerk.EigeneBerufe
  local berufe = f and try(f)
  if type(berufe) == "table" and next(berufe) then e.berufe = berufe end
  local r = WW.charDb and WW.charDb.rezepte
  if type(r) == "table" then
    local kopie = {}
    for beruf, t in pairs(r) do
      if type(t) == "table" and type(t.s) == "table" then
        kopie[beruf] = {}
        for z in pairs(t.s) do kopie[beruf][z] = true end
      end
    end
    e.rezepte = kopie
  end
  local fr = meineFraktion()
  if type(fr) == "string" then e.fraktion = fr end
end

WW:BeimStart(function() if C_Timer and C_Timer.After then C_Timer.After(3, T.Speichern) else T.Speichern() end end)
WW:Event("SKILL_LINES_CHANGED", function() T.Speichern() end)
WW:Event("PLAYER_LOGOUT", function() T.Speichern() end)

-- Twinks: { {name, e, an} } (an = nicht ausgeschlossen), sortiert nach Name
function T.Liste()
  local out = {}
  local inv = WW.db and WW.db.inventar
  local realm, name, fr = meinRealm(), meinName(), meineFraktion()
  if type(inv) ~= "table" or not realm then return out end
  for n, e in pairs(tab(inv[realm])) do
    if n ~= name and type(e) == "table" and (not fr or not e.fraktion or e.fraktion == fr) then
      out[#out + 1] = { name = n, e = e, an = not e.twinkAus }
    end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

-- Twinks, deren Berufe Wegweiser noch nicht kennt (nie mit dieser Version eingeloggt)
function T.OhneDaten()
  local out = {}
  for _, tw in ipairs(T.Liste()) do
    if tw.an and type(tw.e.berufe) ~= "table" then out[#out + 1] = tw.name end
  end
  return out
end

-- Wer braucht das Item? Liste oder nil. Zwischengespeichert bis zur nächsten Änderung (WW.Urteil.Stand()).
local cache, cacheStand = {}, nil
function T.Brauchen(id)
  id = tonumber(id)
  local db, U = einst(), WW.Urteil
  if not id or not db or not db.twinks or not U or not U.RezepteMit then return nil end
  local st = U.Stand and U.Stand()
  if cacheStand ~= st then cache, cacheStand = {}, st end
  local c = cache[id]
  if c ~= nil then return c or nil end
  local raus = {}
  local rezepte = U.RezepteMit(id)
  if #rezepte > 0 then
    for _, tw in ipairs(T.Liste()) do
      if tw.an then
        local berufe, gesehen, kenntEins = {}, {}, false
        for _, r in ipairs(rezepte) do
          local rang = tonumber(tab(tw.e.berufe)[r.beruf])
          local grau = tonumber(r.row[6]) or 0
          local zauber = tonumber(r.row[1])
          if rang and rang < grau and not gesehen[r.beruf] then
            local kennt = tab(tab(tw.e.rezepte)[r.beruf])[zauber] == true
            if kennt or (db.fremde and (tonumber(r.row[3]) or 0) <= rang) then
              if kennt then kenntEins = true end
              gesehen[r.beruf] = true
              berufe[#berufe + 1] = r.beruf
            end
          end
        end
        if #berufe > 0 then raus[#raus + 1] = { name = tw.name, berufe = berufe, kennt = kenntEins } end
      end
    end
  end
  -- Wer das Rezept schon kennt, kommt zuerst (er bekommt die Post)
  table.sort(raus, function(a, b)
    if a.kennt ~= b.kennt then return a.kennt end
    return a.name < b.name
  end)
  cache[id] = #raus > 0 and raus or false
  return cache[id] or nil
end

-- Twink ein- oder ausschließen: /ww twink Name
WW:Befehl("twink", "Twink ein- oder ausschließen: /ww twink Name", function(arg)
  arg = (arg or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local liste = T.Liste()
  if arg == "" then
    local t = {}
    for _, tw in ipairs(liste) do t[#t + 1] = tw.name .. (tw.an and "" or " (aus)") end
    WW:Print("Twinks: " .. (#t > 0 and table.concat(t, ", ") or "keine (jeder Twink muss sich einmal mit Wegweiser einloggen)"))
    return
  end
  for _, tw in ipairs(liste) do
    if tw.name:lower() == arg:lower() then
      tw.e.twinkAus = tw.an and true or nil
      WW:Print(tw.name .. (tw.an and " ist jetzt ausgeschlossen." or " ist wieder dabei."))
      if WW.Urteil and WW.Urteil.NeuerStand then WW.Urteil.NeuerStand() end
      return
    end
  end
  WW:Print("Kein Twink mit dem Namen " .. arg .. ".")
end)

---------------------------------------------------------------------------
-- Briefkasten: Items für einen Twink anhängen
---------------------------------------------------------------------------
local function slots(bag)
  local f = (C_Container and C_Container.GetContainerNumSlots) or WW.Alt("GetContainerNumSlots")
  return tonumber(try(f, bag)) or 0
end
local function itemAmPlatz(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo then
    local i = try(C_Container.GetContainerItemInfo, bag, slot)
    if type(i) == "table" then return tonumber(i.itemID), i.stackCount, i.isBound, i.isLocked end
    return nil
  end
  local alt = WW.Alt("GetContainerItemInfo")
  if alt then
    local _, anz, gesperrt, _, _, _, link, _, _, id, geb = try(alt, bag, slot)
    return tonumber(id) or WW.ItemID(link), anz, geb, gesperrt
  end
end

-- Was liegt für wen in den Taschen? { [name] = { {bag, slot, id} } }, Reihenfolge der Namen nach Menge
function T.Postliste()
  local nachName, reihe = {}, {}
  local U = WW.Urteil
  if not U then return nachName, reihe end
  for _, bag in ipairs((WW.TaschenIDs and try(WW.TaschenIDs)) or { 0, 1, 2, 3, 4 }) do
    for slot = 1, slots(bag) do
      local id, anz, geb, gesperrt = itemAmPlatz(bag, slot)
      if id and not geb and not gesperrt then
        local e = U.Pruefen(id, anz, geb)
        if e and e.gruppe == "twink" and type(e.twinks) == "table" and e.twinks[1] then
          local n = e.twinks[1].name
          if not nachName[n] then nachName[n] = {}; reihe[#reihe + 1] = n end
          table.insert(nachName[n], { bag = bag, slot = slot, id = id })
        end
      end
    end
  end
  table.sort(reihe, function(a, b)
    if #nachName[a] ~= #nachName[b] then return #nachName[a] > #nachName[b] end
    return a < b
  end)
  return nachName, reihe
end

local knopf
local function knopfText()
  if not knopf then return end
  local nachName, reihe = T.Postliste()
  local n = 0
  for _, l in pairs(nachName) do n = n + #l end
  knopf:SetText(n > 0 and ("An Twinks: " .. n) or "An Twinks: nichts")
  knopf.reihe, knopf.nachName = reihe, nachName
  if knopf.SetEnabled then knopf:SetEnabled(n > 0) end
end

-- Ein Klick: der Twink mit den meisten Items; Name eintragen, bis zu 12 Items anhängen
function T.Anhaengen()
  local nachName, reihe = T.Postliste()
  local name = reihe[1]
  if not name then WW:Print("Nichts für deine Twinks in den Taschen.") return end
  local senden = rawget(_G, "SendMailFrame")
  if senden and senden.IsShown and not senden:IsShown() then
    local tabKlick = WW.Alt("MailFrameTab_OnClick")
    if tabKlick then try(tabKlick, nil, 2) end
  end
  if not (senden and senden.IsShown and senden:IsShown()) then
    WW:Print("Öffne im Briefkasten den Reiter \"Senden\" und klicke noch einmal.")
    return
  end
  local hatItem, frei = WW.Alt("CursorHasItem"), WW.Alt("ClearCursor")
  if hatItem and try(hatItem) then WW:Print("Du hast etwas an der Maus. Leg es zuerst ab.") return end
  if try(WW.Alt("SpellIsTargeting")) then WW:Print("Ein Zauber wartet auf ein Ziel. Brich ihn zuerst ab.") return end
  local pickup = (C_Container and C_Container.PickupContainerItem) or WW.Alt("PickupContainerItem")
  local anhaengen, belegt = WW.Alt("ClickSendMailItemButton"), WW.Alt("GetSendMailItem")
  -- Angefangenen Brief nie umadressieren: steht schon ein Name drin, nur für diesen Twink weiter anhängen
  local feld = rawget(_G, "SendMailNameEditBox")
  local jetzt = feld and feld.GetText and feld:GetText()
  jetzt = type(jetzt) == "string" and jetzt:gsub("^%s+", ""):gsub("%s+$", "") or ""
  local max0 = tonumber(rawget(_G, "ATTACHMENTS_MAX_SEND")) or 12
  local hatAnhang = false
  for j = 1, max0 do if belegt and try(belegt, j) then hatAnhang = true break end end
  if jetzt ~= "" then
    local passend
    for n in pairs(nachName) do if n:lower() == jetzt:lower() then passend = n end end
    if not passend then
      WW:Print("Im Brief steht schon \"" .. jetzt .. "\". Schick ihn ab oder leere das Feld, dann klicke noch einmal.")
      return
    end
    name = passend
  elseif hatAnhang then
    WW:Print("Der Brief hat schon Anhänge. Schick ihn ab oder nimm sie heraus, dann klicke noch einmal.")
    return
  end
  if feld and feld.SetText then feld:SetText(name) end
  if not (pickup and anhaengen) then WW:Print("Dieser Client kann keine Items anhängen.") return end
  local max = tonumber(rawget(_G, "ATTACHMENTS_MAX_SEND")) or 12
  local n, i = 0, 1
  for _, p in ipairs(nachName[name]) do
    while i <= max and belegt and try(belegt, i) do i = i + 1 end
    if i > max then break end
    local id = itemAmPlatz(p.bag, p.slot)
    if id == p.id then
      try(pickup, p.bag, p.slot)
      if not hatItem or try(hatItem) then
        try(anhaengen, i)
        if hatItem and try(hatItem) then   -- hat nicht geklappt: zurücklegen und aufhören
          if frei then try(frei) end
          break
        end
        n, i = n + 1, i + 1
      end
    end
  end
  WW:Print(("Für %s: %d Items angehängt. Prüfe den Brief und klicke selbst auf \"Senden\"."):format(name, n))
end

local function knopfBauen()
  if knopf then return knopf end
  local mf = rawget(_G, "MailFrame")
  if not mf then return nil end
  knopf = CreateFrame("Button", "WegweiserTwinkPost", mf, "UIPanelButtonTemplate")
  knopf:SetSize(150, 22)
  knopf:SetPoint("TOPLEFT", mf, "TOPRIGHT", 4, -40)
  knopf:SetScript("OnClick", function() T.Anhaengen() knopfText() end)
  knopf:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Wegweiser: an Twinks schicken")
    for _, n in ipairs(self.reihe or LEER) do
      GameTooltip:AddLine(("%s: %d Items"):format(n, #((self.nachName or LEER)[n] or LEER)), 1, 1, 1)
    end
    GameTooltip:AddLine("Ein Klick hängt die Items für den ersten Twink an. Senden klickst du selbst.", 0.8, 0.8, 0.8, true)
    local ohne = T.OhneDaten()
    if #ohne > 0 then
      GameTooltip:AddLine("Noch ohne Berufe: " .. table.concat(ohne, ", ")
        .. ". Logge jeden davon einmal ein und öffne seine Berufsfenster.", 1, 0.6, 0.2, true)
    end
    GameTooltip:Show()
  end)
  knopf:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return knopf
end

WW:Event("MAIL_SHOW", function()
  local db = einst()
  if not (db and db.twinks) then if knopf then knopf:Hide() end return end
  if knopfBauen() then knopf:Show() knopfText() end
end)
WW:Event("BAG_UPDATE_DELAYED", function() if knopf and knopf:IsShown() then knopfText() end end)
