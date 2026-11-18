-- Wegweiser: Reiter "Items". Suche nach Items (deutsche und englische Namen) und "Wofür ist das?".
-- Daten: WW.quelle.fdb.items[itemID] = "Fakten|Fakten|..." (Aufbau siehe Kopf von Daten\FDB_Items.lua),
--        WW.quelle.fdb.recipes[Beruf] = { {Zauber, Name, Stufe, gelb, grün, grau, Produkt, Anzahl, "Zutat:n,...", ...} },
--        WW.quelle.fdb.searchItemNames[itemID] = englischer Name.
-- Deutsche Namen sammelt ein Hintergrund-Sammler in WW.db.namen (langsam, mit Pausen im Kampf).
local ADDON, WW = ...
local UI = WW.UI

WW.standardDB.items = {
  tooltip = true,    -- "Wofür im Tooltip"
  namenFehl = {},    -- [itemID] = wie oft das Spiel den Namen nicht liefern konnte
}

local MAX_TREFFER = 500
local MAX_KANDIDATEN = 6000
local SUCH_VERZOEGERUNG = 0.3
local NAMEN_PRO_SCHRITT = 40
local NAMEN_ABSTAND = 0.2

---------------------------------------------------------------------------
-- Hilfen
---------------------------------------------------------------------------
local function fdb() return WW.quelle and WW.quelle.fdb end
local function imKampf() return InCombatLockdown and InCombatLockdown() and true or false end

local function split(s)
  local out = {}
  for x in (s .. "~"):gmatch("(.-)~") do out[#out + 1] = x end
  return out
end

local function berufEn(index)
  local f = fdb()
  local liste = f and f.professions
  return liste and liste[(tonumber(index) or -1) + 1] or nil
end
local function berufDe(en)
  if not en then return "?" end
  return WW.beruf[en] or en
end

local RANG = { "Hasserfüllt", "Feindselig", "Unfreundlich", "Neutral", "Freundlich", "Wohlwollend", "Respektvoll", "Ehrfürchtig" }
local function rangName(i)
  local n = (tonumber(i) or 0) + 1
  local s = _G["FACTION_STANDING_LABEL" .. n]
  if type(s) == "string" and s ~= "" then return s end
  return RANG[n] or tostring(i)
end

-- Name für die Anzeige: Spiel, Zwischenspeicher, Daten (englisch), sonst "Item 123"
local function itemName(id)
  local n = WW.ItemName(id)
  if n then return n end
  local f = fdb()
  local en = f and f.names and f.names[id]
  return en or ("Item " .. tostring(id))
end

local function itemSymbol(id)
  local t = WW.GetItemIcon(id)
  return t or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function qualitaet(id)
  if C_Item and C_Item.GetItemQualityByID then
    local q = C_Item.GetItemQualityByID(id)
    if q then return q end
  end
  local q = select(3, WW.GetItemInfo(id))
  return q
end

local function qualitaetsCode(q)
  local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q or 1]
  if c and c.r then
    return ("|cff%02x%02x%02x"):format(math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5), math.floor(c.b * 255 + 0.5))
  end
  return "|cffffffff"
end

local RGB = {
  gruen = { 0.25, 1, 0.25 },
  gelb  = { 1, 0.82, 0 },
  rot   = { 1, 0.25, 0.25 },
}

-- Suchtext vergleichbar machen: Umlaute und ß vereinfachen, klein schreiben (Ä/Ö/Ü sind 2 Bytes, lower() fasst sie nicht an)
local faltCache = {}
local function falten(s)
  local c = faltCache[s]
  if c then return c end
  local r = s
  if r:find("\195", 1, true) then
    r = r:gsub("\195[\132\164]", "a"):gsub("\195[\150\182]", "o"):gsub("\195[\156\188]", "u"):gsub("\195\159", "ss")
  end
  r = r:lower()
  faltCache[s] = r
  return r
end

---------------------------------------------------------------------------
-- Fakten zu einem Item (aus fdb.items) lesen
---------------------------------------------------------------------------
local faktenCache = {}
local function fakten(id)
  local c = faktenCache[id]
  if c ~= nil then return c or nil end
  local f = fdb()
  local roh = f and f.items and f.items[id]
  if type(roh) ~= "string" then
    faktenCache[id] = false
    return nil
  end
  local r = {}
  for teil in roh:gmatch("[^|]+") do
    local code, a = teil:sub(1, 1), split(teil:sub(2))
    if code == "n" then
      r.neu = true
    elseif code == "c" then
      r.geaendert = true
    elseif code == "r" then
      r.ruf = { fraktion = a[1], rang = tonumber(a[2]) }
    elseif code == "m" then
      r.hergestellt = { beruf = berufEn(a[1]), stufe = tonumber(a[2]) or 0 }
    elseif code == "u" then
      local berufe = {}
      for i in (a[2] or ""):gmatch("%d+") do
        local en = berufEn(i)
        if en then berufe[#berufe + 1] = en end
      end
      r.gebraucht = { n = tonumber(a[1]) or 0, berufe = berufe }
    elseif code == "v" then
      r.haendler = { n = tonumber(a[1]) or 1, npc = a[2], zone = a[3] }
    elseif code == "d" then
      local prozent
      if a[5] ~= nil then prozent = (tonumber(a[5]) or 0) / 100 else prozent = (tonumber(a[2]) or 0) / 10 end
      r.beute = { quelle = a[1], prozent = prozent, mehr = (tonumber(a[4]) or 1) - 1 }
    elseif code == "q" then
      r.quest = { name = a[1] }
    elseif code == "s" then
      r.gesehen = { n = tonumber(a[1]) or 0, spieler = tonumber(a[2]) or 1 }
    end
  end
  faktenCache[id] = r
  return r
end

---------------------------------------------------------------------------
-- Rezept-Verzeichnis: welche Rezepte brauchen / machen ein Item (einmal gebaut, beim ersten Gebrauch)
---------------------------------------------------------------------------
local rezeptIndex
local function indexBauen()
  if rezeptIndex then return rezeptIndex end
  local idx = { zutat = {}, gemacht = {} }
  rezeptIndex = idx
  local f = fdb()
  local alle = f and f.recipes
  if type(alle) ~= "table" then return idx end
  for beruf, liste in pairs(alle) do
    if type(liste) == "table" then
      for _, row in ipairs(liste) do
        if type(row) == "table" then
          local eintrag = { beruf = beruf, row = row }
          local macht = tonumber(row[7])
          if macht and macht > 0 then
            local t = idx.gemacht[macht]
            if not t then t = {}; idx.gemacht[macht] = t end
            t[#t + 1] = eintrag
          end
          if type(row[9]) == "string" then
            for zid in row[9]:gmatch("(%d+):%d+") do
              zid = tonumber(zid)
              local t = idx.zutat[zid]
              if not t then t = {}; idx.zutat[zid] = t end
              t[#t + 1] = eintrag
            end
          end
        end
      end
    end
  end
  return idx
end

local function nachStufe(a, b)
  local sa, sb = tonumber(a.row[3]) or 0, tonumber(b.row[3]) or 0
  if sa ~= sb then return sa < sb end
  return (tonumber(a.row[1]) or 0) < (tonumber(b.row[1]) or 0)
end

local function reagenzText(str)
  if type(str) ~= "string" then return "" end
  local teile = {}
  for zid, n in str:gmatch("(%d+):(%d+)") do
    teile[#teile + 1] = n .. "x " .. itemName(tonumber(zid))
  end
  return table.concat(teile, ", ")
end

-- Name des Ergebnisses eines Rezepts (Item, sonst Rezeptname)
local function produktName(row)
  local macht = tonumber(row[7])
  if macht and macht > 0 then return itemName(macht), macht end
  return tostring(row[2] or "?"), nil
end

---------------------------------------------------------------------------
-- Texte: kurz (Liste), Tooltip, Details
---------------------------------------------------------------------------
local kurzCache = {}
local function kurz(id)
  local c = kurzCache[id]
  if c then return c end
  local fk = fakten(id)
  local teile = {}
  if fk then
    if fk.gebraucht and fk.gebraucht.n > 0 then teile[#teile + 1] = "Zutat (" .. fk.gebraucht.n .. ")" end
    if fk.hergestellt and fk.hergestellt.beruf then teile[#teile + 1] = "hergestellt" end
    if fk.haendler then teile[#teile + 1] = "Händler" end
    if fk.beute then teile[#teile + 1] = "Beute" end
    if fk.quest then teile[#teile + 1] = "Quest" end
    if fk.ruf then teile[#teile + 1] = "Ruf" end
  end
  c = #teile > 0 and table.concat(teile, ", ") or "-"
  kurzCache[id] = c
  return c
end

-- Eine kurze Zeile für den Tooltip oder nil
local function tooltipText(id)
  local fk = fakten(id)
  if not fk then return nil end
  local teile = {}
  if fk.hergestellt and fk.hergestellt.beruf then
    local t = "Hergestellt: " .. berufDe(fk.hergestellt.beruf)
    if fk.hergestellt.stufe > 1 then t = t .. " " .. fk.hergestellt.stufe end
    teile[#teile + 1] = t
  end
  if fk.gebraucht and fk.gebraucht.n > 0 then
    local t = fk.gebraucht.n == 1 and "Zutat für 1 Rezept" or ("Zutat für " .. fk.gebraucht.n .. " Rezepte")
    local namen = {}
    for i = 1, math.min(4, #fk.gebraucht.berufe) do namen[i] = berufDe(fk.gebraucht.berufe[i]) end
    if #namen > 0 then
      t = t .. " (" .. table.concat(namen, ", ") .. (#fk.gebraucht.berufe > 4 and ", ..." or "") .. ")"
    end
    teile[#teile + 1] = t
  end
  if #teile == 0 then return nil end
  return "Wegweiser: " .. table.concat(teile, "; ")
end

local function ahAbschnitt(z, id)
  if not WW.AH then return end
  local lo, med, menge, alter = WW.AH.Preis(id)
  local verkauf = select(11, WW.GetItemInfo(id))
  z[#z + 1] = WW.f("titel", "Wert")
  if lo then
    local zeit = ""
    if alter then
      if alter < 3600 then zeit = ", Stand vor " .. math.floor(alter / 60 + 0.5) .. " Min."
      elseif alter < 2 * 86400 then zeit = ", Stand vor " .. math.floor(alter / 3600 + 0.5) .. " Std."
      else zeit = ", Stand vor " .. math.floor(alter / 86400 + 0.5) .. " Tagen" end
    end
    z[#z + 1] = "Auktionshaus: " .. WW.Geld((med and med > 0) and med or lo)
      .. ((med and med > 0 and med ~= lo) and (" (min " .. WW.Geld(lo) .. ")") or "")
      .. ", " .. (menge or 0) .. " Stück" .. zeit
  else
    z[#z + 1] = "Auktionshaus: " .. WW.f("grau", "kein Preis bekannt (Auktionshaus scannen)")
  end
  if verkauf == nil then
    z[#z + 1] = "Händler: " .. WW.f("grau", "unbekannt (Item noch nicht geladen)")
  elseif verkauf == 0 then
    z[#z + 1] = "Händler: " .. WW.f("grau", "nicht verkäuflich")
  else
    z[#z + 1] = "Händler: " .. WW.Geld(verkauf)
  end
  local farbe, text = WW.AH.Bewertung(id)
  z[#z + 1] = "Verkaufen: " .. WW.f(farbe, text)
  -- Preisverlauf (nur wenn Auktion.lua ihn kennt)
  if WW.AH.Analyse then
    local ok, an = pcall(WW.AH.Analyse, id)
    if ok and an and an.normal then
      z[#z + 1] = ("Normalpreis: %s (aus %d %s)"):format(WW.Geld(math.floor(an.normal + 0.5)), an.scans,
        an.scans == 1 and "Scan" or "Scans")
      if an.urteil == "guenstig" then
        z[#z + 1] = WW.f("gruen", ("Gerade günstig (%+d %%)"):format(math.floor(an.abw * 100 + 0.5)))
      elseif an.urteil == "teuer" then
        z[#z + 1] = WW.f("rot", ("Gerade zu teuer (%+d %%)"):format(math.floor(an.abw * 100 + 0.5)))
      end
    end
    if ok and an and WW.AH.ZeitTipp then
      local ok2, tipp, echt = pcall(WW.AH.ZeitTipp, id)
      if ok2 and tipp then z[#z + 1] = echt and tipp or WW.f("grau", tipp) end
    end
  end
  z[#z + 1] = ""
end

local function detailText(id)
  local z = {}
  ahAbschnitt(z, id)
  local fk = fakten(id)
  local idx = indexBauen()
  local gefunden = false

  -- Hergestellt
  local gem = idx.gemacht[id]
  if (fk and fk.hergestellt and fk.hergestellt.beruf) or gem then
    gefunden = true
    z[#z + 1] = WW.f("titel", "Hergestellt mit")
    if fk and fk.hergestellt and fk.hergestellt.beruf then
      local t = berufDe(fk.hergestellt.beruf)
      if fk.hergestellt.stufe > 0 then t = t .. " (Stufe " .. fk.hergestellt.stufe .. ")" end
      z[#z + 1] = t
    end
    if gem then
      local liste = {}
      for i = 1, #gem do liste[i] = gem[i] end
      table.sort(liste, nachStufe)
      for i = 1, math.min(3, #liste) do
        local row = liste[i].row
        local t = "- " .. berufDe(liste[i].beruf) .. ", Stufe " .. tostring(row[3] or "?")
        local zut = reagenzText(row[9])
        if zut ~= "" then t = t .. ": " .. zut end
        z[#z + 1] = t
      end
      if #liste > 3 then z[#z + 1] = "- und " .. (#liste - 3) .. " weitere Rezepte" end
    end
    z[#z + 1] = ""
  end

  -- Gebraucht für
  local zut = idx.zutat[id]
  local nRezepte = (zut and #zut > 0 and #zut) or (fk and fk.gebraucht and fk.gebraucht.n) or 0
  if nRezepte > 0 then
    gefunden = true
    local berufe = {}
    if zut and #zut > 0 then
      local gesehenB = {}
      for i = 1, #zut do
        local b = zut[i].beruf
        if not gesehenB[b] then gesehenB[b] = true; berufe[#berufe + 1] = berufDe(b) end
      end
      table.sort(berufe)
    elseif fk and fk.gebraucht then
      for i = 1, #fk.gebraucht.berufe do berufe[i] = berufDe(fk.gebraucht.berufe[i]) end
    end
    z[#z + 1] = WW.f("titel", "Gebraucht für")
    z[#z + 1] = nRezepte .. (nRezepte == 1 and " Rezept" or " Rezepte")
      .. (#berufe > 0 and (" (" .. table.concat(berufe, ", ") .. ")") or "")
    if zut and #zut > 0 then
      local liste = {}
      for i = 1, #zut do liste[i] = zut[i] end
      table.sort(liste, nachStufe)
      local gezeigt, schon = 0, {}
      for i = 1, #liste do
        if gezeigt >= 8 then break end
        local row = liste[i].row
        local name, macht = produktName(row)
        local k = macht or name
        if not schon[k] then
          schon[k] = true
          gezeigt = gezeigt + 1
          z[#z + 1] = "- " .. name .. " (" .. berufDe(liste[i].beruf) .. " " .. tostring(row[3] or "?") .. ")"
        end
      end
      if nRezepte > gezeigt then z[#z + 1] = "- und weitere" end
    end
    z[#z + 1] = ""
  end

  if fk then
    -- Händler
    if fk.haendler and fk.haendler.npc and fk.haendler.npc ~= "" then
      gefunden = true
      z[#z + 1] = WW.f("titel", "Verkauft von")
      local t = fk.haendler.npc
      if fk.haendler.zone and fk.haendler.zone ~= "" then t = t .. " (" .. fk.haendler.zone .. ")" end
      if fk.haendler.n > 1 then t = t .. " und " .. (fk.haendler.n - 1) .. " weitere" end
      z[#z + 1] = t
      z[#z + 1] = ""
    end
    -- Beute
    if fk.beute and fk.beute.quelle and fk.beute.quelle ~= "" then
      gefunden = true
      z[#z + 1] = WW.f("titel", "Beute von")
      local t = fk.beute.quelle
      if fk.beute.prozent > 0 then t = t .. (" (%.1f %%)"):format(fk.beute.prozent) end
      if fk.beute.mehr > 0 then t = t .. " und " .. fk.beute.mehr .. " weitere" end
      z[#z + 1] = t
      z[#z + 1] = ""
    end
    -- Quest
    if fk.quest and fk.quest.name and fk.quest.name ~= "" then
      gefunden = true
      z[#z + 1] = WW.f("titel", "Questbelohnung")
      z[#z + 1] = fk.quest.name
      z[#z + 1] = ""
    end
    -- Ruf
    if fk.ruf then
      gefunden = true
      z[#z + 1] = WW.f("titel", "Ruf")
      z[#z + 1] = "Benötigt " .. rangName(fk.ruf.rang) .. " bei " .. tostring(fk.ruf.fraktion or "?")
      z[#z + 1] = ""
    end
    -- Forever
    if fk.neu or fk.geaendert or (fk.gesehen and fk.gesehen.n > 0) then
      gefunden = true
      z[#z + 1] = WW.f("titel", "WoW Forever")
      if fk.neu then z[#z + 1] = WW.f("gruen", "Neu in WoW Forever") end
      if fk.geaendert then z[#z + 1] = WW.f("orange", "In WoW Forever geändert") end
      if fk.gesehen and fk.gesehen.n > 0 then
        z[#z + 1] = ("%d-mal als Beute gesehen (%d %s)"):format(fk.gesehen.n, fk.gesehen.spieler,
          fk.gesehen.spieler == 1 and "Spieler" or "Spieler")
      end
      z[#z + 1] = ""
    end
  end

  if not gefunden then
    z[#z + 1] = WW.f("grau", "Zu diesem Item gibt es keine Angaben in den Daten.")
  end
  return table.concat(z, "\n")
end

---------------------------------------------------------------------------
-- Tooltip: eine Zeile "Wegweiser: ..." (nur einmal pro Anzeige)
---------------------------------------------------------------------------
local gesehen = setmetatable({}, { __mode = "k" })

local function tooltipZeile(tt, data)
  if not WW.db or not WW.db.items.tooltip then return end
  if tt ~= GameTooltip and tt ~= ItemRefTooltip then return end
  local id = data and tonumber(data.id)
  if not id then
    local _, link = tt:GetItem()
    id = WW.ItemID(link)
  end
  if not id or gesehen[tt] == id then return end
  gesehen[tt] = id
  local text = tooltipText(id)
  if not text then return end
  tt:AddLine(text, 0.31, 0.76, 0.97, true)
  tt:Show()
end

local function tooltipsAnschliessen()
  local gehakt = false
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType
     and Enum.TooltipDataType.Item then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data)
      pcall(tooltipZeile, tt, data)
    end)
    gehakt = true
  end
  for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
    if tt and tt.HookScript then
      if not gehakt then
        pcall(tt.HookScript, tt, "OnTooltipSetItem", function(self) pcall(tooltipZeile, self) end)
      end
      pcall(tt.HookScript, tt, "OnTooltipCleared", function(self) gesehen[self] = nil end)
    end
  end
  if not gehakt and GameTooltip then
    for _, name in ipairs({ "SetBagItem", "SetHyperlink", "SetInventoryItem", "SetLootItem", "SetMerchantItem",
      "SetAuctionItem", "SetItemByID" }) do
      if type(GameTooltip[name]) == "function" then
        hooksecurefunc(GameTooltip, name, function(self) pcall(tooltipZeile, self) end)
      end
    end
  end
end
WW:BeimStart(tooltipsAnschliessen)

---------------------------------------------------------------------------
-- Alle bekannten Item-IDs
---------------------------------------------------------------------------
local idListe
local function alleIDs()
  if idListe then return idListe end
  local menge, liste = {}, {}
  local function dazu(id)
    if type(id) == "number" and not menge[id] then
      menge[id] = true
      liste[#liste + 1] = id
    end
  end
  local f = fdb()
  if f then
    if type(f.items) == "table" then for id in pairs(f.items) do dazu(id) end end
    if type(f.searchItemNames) == "table" then for id in pairs(f.searchItemNames) do dazu(id) end end
  end
  if WW.db and WW.db.namen then for id in pairs(WW.db.namen) do dazu(id) end end
  table.sort(liste)
  idListe = liste
  return liste
end

---------------------------------------------------------------------------
-- Namen-Sammler: holt die deutschen Namen im Hintergrund (40 alle 0,2 Sekunden, Pause im Kampf)
---------------------------------------------------------------------------
local sammler = { todo = nil, pos = 1, angefragt = {}, fertig = false, gestartet = false }
local sammlerRahmen = CreateFrame("Frame")

local function nameSpeichern(id)
  local name = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or WW.GetItemInfo(id)
  if name and WW.db then
    WW.db.namen[id] = name
    return true
  end
  return false
end

WW:Event("GET_ITEM_INFO_RECEIVED", function(id, erfolg)
  if not WW.db or not sammler.angefragt[id] then return end
  sammler.angefragt[id] = nil
  if erfolg == false then
    local fehl = WW.db.items.namenFehl
    fehl[id] = (fehl[id] or 0) + 1
  else
    nameSpeichern(id)
  end
end)

local function sammlerSchritt()
  local todo = sammler.todo
  if not todo then return end
  for _ = 1, NAMEN_PRO_SCHRITT do
    local id = todo[sammler.pos]
    if not id then
      sammler.fertig = true
      sammlerRahmen:SetScript("OnUpdate", nil)
      return
    end
    sammler.pos = sammler.pos + 1
    if not WW.db.namen[id] then
      local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
      if name then
        WW.db.namen[id] = name
      elseif C_Item and C_Item.RequestLoadItemDataByID then
        sammler.angefragt[id] = true
        C_Item.RequestLoadItemDataByID(id)
      else
        local n = WW.GetItemInfo(id)
        if n then WW.db.namen[id] = n else sammler.angefragt[id] = true end
      end
    end
  end
end

local function sammlerStarten()
  if sammler.gestartet or not WW.db or not fdb() then return end
  sammler.gestartet = true
  local namen, fehl = WW.db.namen, WW.db.items.namenFehl
  local todo = {}
  local ids = alleIDs()
  for i = 1, #ids do
    local id = ids[i]
    if not namen[id] and (fehl[id] or 0) < 2 then todo[#todo + 1] = id end
  end
  sammler.todo, sammler.pos = todo, 1
  if #todo == 0 then
    sammler.fertig = true
    return
  end
  local zeit = 0
  sammlerRahmen:SetScript("OnUpdate", function(_, dt)
    zeit = zeit + dt
    if zeit < NAMEN_ABSTAND then return end
    zeit = 0
    if imKampf() then return end
    local ok, err = pcall(sammlerSchritt)
    if not ok then
      sammlerRahmen:SetScript("OnUpdate", nil)
      sammler.fertig = true
      geterrorhandler()(err)
    end
  end)
end

WW:BeimStart(function()
  if C_Timer and C_Timer.After then
    C_Timer.After(8, function()
      local ok, err = pcall(sammlerStarten)
      if not ok then geterrorhandler()(err) end
    end)
  else
    sammlerStarten()
  end
end)

local function zaehleNamen()
  local ids, namen = alleIDs(), WW.db.namen
  local n = 0
  for i = 1, #ids do if namen[ids[i]] then n = n + 1 end end
  return n, #ids
end

---------------------------------------------------------------------------
-- Suche
---------------------------------------------------------------------------
-- Gibt Liste { {id, q, s}, ... } (höchstens MAX_TREFFER), Gesamtzahl der gefundenen Items zurück.
local function sucheItems(text)
  text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local treffer, n = {}, 0
  local f = fdb()
  local namen = WW.db.namen
  local en = f and f.searchItemNames or {}
  local kandidaten = {}
  local exakt = false

  local linkID = text:match("item:(%d+)")
  local nurZahl = text:match("^%d+$")
  if linkID or nurZahl then
    local id = tonumber(linkID or nurZahl)
    if id and (namen[id] or en[id] or (f and f.items and f.items[id])) then kandidaten[1] = id; exakt = true end
  end
  if #text >= 2 and not linkID then
    local q = falten(text)
    local ids = alleIDs()
    for i = 1, #ids do
      local id = ids[i]
      local de, e = namen[id], en[id]
      if (de and falten(de):find(q, 1, true)) or (e and falten(e):find(q, 1, true)) then
        if id ~= kandidaten[1] then kandidaten[#kandidaten + 1] = id end
        if #kandidaten >= MAX_KANDIDATEN then break end
      end
    end
  end
  for i = 1, #kandidaten do
    local id = kandidaten[i]
    n = n + 1
    treffer[n] = { id = id, q = qualitaet(id) or -1, s = falten(namen[id] or en[id] or ""), x = (i == 1 and exakt) or false }
  end
  table.sort(treffer, function(a, b)
    if a.x ~= b.x then return a.x end   -- die genau eingegebene Item-Nummer steht oben
    if a.q ~= b.q then return a.q > b.q end
    if a.s ~= b.s then return a.s < b.s end
    return a.id < b.id
  end)
  local gesamt = n
  for i = n, MAX_TREFFER + 1, -1 do treffer[i] = nil end
  return treffer, gesamt
end

---------------------------------------------------------------------------
-- Reiter "Items"
---------------------------------------------------------------------------
local ui = {}   -- vom Reiter gefüllt: ui.edit, ui.suche(text), ui.zeige(id, von)

-- Eigene Items dieses Charakters (Taschen, Bank, angelegt) aus dem Inventar-Modul, nach Name sortiert
local function eigeneItems()
  local Inv = WW.Inventar
  if not (Inv and Inv.Charaktere and Inv.BestandBauen) then return {} end
  local ok, alle = pcall(Inv.Charaktere)
  if not ok or type(alle) ~= "table" then return {} end
  for _, c in ipairs(alle) do
    if c.ich then
      local ok2, liste = pcall(Inv.BestandBauen, { c }, false, "", "name")
      return (ok2 and type(liste) == "table") and liste or {}
    end
  end
  return {}
end

WW:Reiter("items", "Items", 10, function(p)
  local LISTE_B, LISTE_H = 500, WW.INHALT_HOEHE - 52
  local gewaehlt
  local aktuelleSuche = ""

  local label = UI.Text(p)
  label:SetPoint("TOPLEFT", 4, -9)
  label:SetText("Suche:")

  local waehle

  local liste, hinweis   -- hinweis liegt auf der Liste (sonst verdeckt ihr Hintergrund den Text)
  local anzahlText = UI.Text(p, "klein", 0.8, 0.8, 0.8)

  local function zeigeErgebnis(text)
    aktuelleSuche = text or ""
    -- Ohne Suchtext: die eigenen Items (Taschen, Bank, angelegt) dieses Charakters
    if #(aktuelleSuche:gsub("%s", "")) < 2 then
      local eigene = eigeneItems()
      if #eigene > 0 then
        liste:Setze(eigene)
        hinweis:Hide()
        anzahlText:SetText(("Deine Items: %d (Taschen, Bank, angelegt). Tippe, um alle Items zu suchen."):format(#eigene))
        return
      end
    end
    local treffer, gesamt = sucheItems(aktuelleSuche)
    liste:Setze(treffer)
    if #(aktuelleSuche:gsub("%s", "")) < 2 and #treffer == 0 then
      anzahlText:SetText("")
      hinweis:SetText("Tippe mindestens 2 Buchstaben. Gesucht wird in deutschen und englischen Namen.\n"
        .. "Du kannst auch eine Item-Nummer eingeben oder einen Item-Link einfügen.")
      hinweis:Show()
    elseif #treffer == 0 then
      anzahlText:SetText("Keine Treffer")
      hinweis:SetText("Nichts gefunden. Die deutschen Namen werden im Hintergrund geladen; "
        .. "versuche es auch mit dem englischen Namen.")
      hinweis:Show()
    else
      hinweis:Hide()
      if gesamt > #treffer then
        anzahlText:SetText(("%d Treffer, die ersten %d werden gezeigt"):format(gesamt, #treffer))
      else
        anzahlText:SetText(gesamt == 1 and "1 Treffer" or (gesamt .. " Treffer"))
      end
    end
  end

  local verzoegert = 0
  local edit = UI.Eingabe(p, 260, function(text)
    verzoegert = verzoegert + 1
    local mein = verzoegert
    local function los()
      if mein == verzoegert then zeigeErgebnis(text) end
    end
    if C_Timer and C_Timer.After then C_Timer.After(SUCH_VERZOEGERUNG, los) else los() end
  end)
  edit:SetPoint("LEFT", label, "RIGHT", 12, 0)
  ui.edit = edit

  anzahlText:SetPoint("LEFT", edit, "RIGHT", 10, 0)
  anzahlText:SetWidth(WW.INHALT_BREITE - 340 - 180)
  anzahlText:SetWordWrap(false)

  -- "Zurück" zum Reiter, aus dem ein Klick hierher geführt hat (Inventar, Auktionshaus)
  local herkunft
  local zurueck = UI.Knopf(p, "Zurück", 170, function()
    local ziel = herkunft
    herkunft = nil
    if ziel then WW:Oeffnen(ziel) end
  end)
  zurueck:SetPoint("TOPRIGHT", -4, -4)
  zurueck:Hide()

  -- Liste links
  local function baueZeile(z)
    z.sel = z:CreateTexture(nil, "BACKGROUND")
    z.sel:SetAllPoints()
    z.sel:SetColorTexture(0.3, 0.5, 0.9, 0.25)
    z.sel:Hide()
    z.icon = z:CreateTexture(nil, "ARTWORK")
    z.icon:SetSize(18, 18)
    z.icon:SetPoint("LEFT", 0, 0)
    z.name = UI.Text(z)
    z.name:SetPoint("LEFT", 24, 0)
    z.name:SetWidth(205)
    z.name:SetWordWrap(false)
    z.was = UI.Text(z, "klein", 0.75, 0.75, 0.75)
    z.was:SetPoint("LEFT", 234, 0)
    z.was:SetWidth(205)
    z.was:SetWordWrap(false)
    z.punkt = z:CreateTexture(nil, "ARTWORK")
    z.punkt:SetSize(10, 10)
    z.punkt:SetPoint("RIGHT", -2, 0)
    z:SetScript("OnEnter", function(self)
      if self.eintrag then UI.ItemTooltip(self, self.eintrag.id) end
    end)
    z:SetScript("OnLeave", function() GameTooltip:Hide() end)
    z:SetScript("OnClick", function(self)
      if self.eintrag then waehle(self.eintrag.id) end
    end)
  end
  local function fuelleZeile(z, e)
    z.icon:SetTexture(itemSymbol(e.id))
    local q = qualitaet(e.id)
    z.name:SetText(qualitaetsCode(q) .. itemName(e.id) .. "|r")
    z.was:SetText(kurz(e.id))
    z.sel:SetShown(e.id == gewaehlt)
    local farbe = WW.AH and WW.AH.Bewertung(e.id)
    local c = farbe and RGB[farbe]
    if c then
      z.punkt:SetColorTexture(c[1], c[2], c[3], 1)
      z.punkt:Show()
    else
      z.punkt:Hide()
    end
  end
  liste = UI.Liste(p, LISTE_B, LISTE_H, 22, baueZeile, fuelleZeile)
  liste:SetPoint("TOPLEFT", 0, -34)

  hinweis = UI.Text(liste, "klein", 0.7, 0.7, 0.7)
  hinweis:SetPoint("TOPLEFT", 16, -16)
  hinweis:SetWidth(LISTE_B - 60)
  hinweis:SetSpacing(3)
  hinweis:SetJustifyV("TOP")

  -- Fortschritt der deutschen Namen unter der Liste
  local fortschritt = UI.Text(p, "klein", 0.7, 0.7, 0.7)
  fortschritt:SetPoint("TOPLEFT", liste, "BOTTOMLEFT", 4, -4)
  fortschritt:SetWidth(WW.INHALT_BREITE - 8)

  -- Details rechts
  local detail = UI.Kasten(p)
  detail:SetSize(WW.INHALT_BREITE - LISTE_B - 8, LISTE_H)
  detail:SetPoint("TOPLEFT", liste, "TOPRIGHT", 8, 0)

  local dIcon = detail:CreateTexture(nil, "ARTWORK")
  dIcon:SetSize(36, 36)
  dIcon:SetPoint("TOPLEFT", 10, -10)
  dIcon:Hide()
  local dName = UI.Text(detail, "gross")
  dName:SetPoint("TOPLEFT", dIcon, "TOPRIGHT", 8, -1)
  dName:SetWidth(detail:GetWidth() - 66)
  dName:SetWordWrap(false)
  local dKopf = UI.Text(detail, "klein", 0.7, 0.7, 0.7)
  dKopf:SetPoint("TOPLEFT", dName, "BOTTOMLEFT", 0, -3)
  dKopf:SetWidth(detail:GetWidth() - 66)
  dKopf:SetWordWrap(false)

  local scroll = CreateFrame("ScrollFrame", nil, detail, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 10, -56)
  scroll:SetPoint("BOTTOMRIGHT", -30, 8)
  local inhalt = CreateFrame("Frame", nil, scroll)
  inhalt:SetSize(detail:GetWidth() - 44, 10)
  scroll:SetScrollChild(inhalt)
  -- Preis-Grafik oben in den Details (nur wenn es einen Preisverlauf gibt)
  local grafik = UI.PreisGrafik and UI.PreisGrafik(inhalt, detail:GetWidth() - 48)
  if grafik then
    grafik:SetPoint("TOPLEFT", 0, 0)
    grafik:Hide()
  end
  local dText = UI.Text(inhalt)
  dText:SetPoint("TOPLEFT", 0, 0)
  dText:SetWidth(detail:GetWidth() - 48)
  dText:SetSpacing(2)
  dText:SetJustifyV("TOP")
  dText:SetText(WW.f("grau", "Klicke links auf ein Item, um zu sehen, wofür es gut ist."))

  local function zeigeDetails(id)
    if not id then return end
    dIcon:SetTexture(itemSymbol(id))
    dIcon:Show()
    dName:SetText(qualitaetsCode(qualitaet(id)) .. itemName(id) .. "|r")
    local _, istDeutsch = WW.ItemName(id)
    dKopf:SetText("Item-Nummer " .. id .. (istDeutsch == false and "  (Name noch englisch)" or ""))
    local ok, text = pcall(detailText, id)
    if not ok then
      geterrorhandler()(text)
      text = "Fehler beim Zusammenstellen der Angaben."
    end
    dText:SetText(text)
    local oben = 0
    if grafik then
      local okG, daten = pcall(function() return WW.AH and WW.AH.Grafikdaten and WW.AH.Grafikdaten(id) end)
      local gezeigt = okG and grafik:Setze(daten)
      if gezeigt then oben = UI.GRAFIK_HOEHE + 10 else grafik:Hide() end
    end
    dText:ClearAllPoints()
    dText:SetPoint("TOPLEFT", 0, -oben)
    inhalt:SetHeight(math.max(10, oben + dText:GetStringHeight() + 12))
    scroll:SetVerticalScroll(0)
  end

  waehle = function(id)
    gewaehlt = id
    zeigeDetails(id)
    liste:Aktualisiere()
  end

  -- Von außen ein Item zeigen (Klick in Inventar oder Auktionshaus). von = Reiter, zu dem "Zurück" führt.
  ui.zeige = function(id, von)
    herkunft = (von and von ~= "items") and von or nil
    zurueck:SetShown(herkunft ~= nil)
    if herkunft then
      local titel = { inventar = "Inventar", ah = "AH", handwerk = "Handwerk" }
      zurueck:SetText("Zurück" .. (titel[herkunft] and (" zum " .. titel[herkunft]) or ""))
    end
    -- Name in die Suche eintragen: die Liste zeigt dann ähnliche Items (z. B. alle Stufen eines Tranks)
    local name = WW.ItemName(id) or itemName(id)
    edit:SetText(name)
    verzoegert = verzoegert + 1   -- die verzögerte Suche vom SetText nicht doppelt laufen lassen
    zeigeErgebnis(name)
    waehle(id)
  end

  -- Suche von außen starten (/ww suche <Text>)
  ui.suche = function(text)
    text = text or ""
    edit:SetText(text)
    verzoegert = verzoegert + 1
    zeigeErgebnis(text)
    if text ~= "" and liste.eintraege[1] then waehle(liste.eintraege[1].id) end
  end

  local function zeigeFortschritt()
    if not fdb() then
      fortschritt:SetText(WW.f("rot", "Keine Item-Daten geladen."))
      return
    end
    local n, gesamt = zaehleNamen()
    local t = ("Deutsche Namen: %d / %d"):format(n, gesamt)
    if not sammler.gestartet then
      t = t .. " (startet kurz nach dem Einloggen)"
    elseif not sammler.fertig then
      t = t .. " (werden im Hintergrund geladen)"
    else
      t = t .. " (fertig; was fehlt, kennt der Server nicht)"
      if not sammler.neuGesucht then
        sammler.neuGesucht = true
        if #aktuelleSuche >= 2 then zeigeErgebnis(aktuelleSuche) end
      end
    end
    fortschritt:SetText(t)
  end

  local zeit = 0
  p:SetScript("OnUpdate", function(_, dt)
    zeit = zeit + dt
    if zeit >= 1 then
      zeit = 0
      zeigeFortschritt()
    end
  end)
  p.OnZeigen = function()
    zeigeFortschritt()
    if #(aktuelleSuche:gsub("%s", "")) < 2 then zeigeErgebnis(aktuelleSuche) end   -- eigene Items frisch
    if gewaehlt then zeigeDetails(gewaehlt) end
  end
end)

-- Item-Details zeigen, z. B. nach Klick auf eine Zeile in Inventar oder Auktionshaus
function WW:ItemZeigen(id)
  id = tonumber(id)
  if not id then return end
  local von = WW.AktiverReiter and WW:AktiverReiter() or nil
  WW:Oeffnen("items")
  if ui.zeige then ui.zeige(id, von) end
end

-- Taste (Tastenbelegung "Mehr Information zum Item unter der Maus"): Item aus dem gerade sichtbaren
-- Tooltip nehmen. Geht überall, wo das Spiel einen Item-Tooltip zeigt (Tasche, Bank, Auktionshaus, Chat-Link).
function WW:ItemUnterMaus()
  for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
    if tt and tt.IsShown and tt:IsShown() and tt.GetItem then
      local ok, _, link = pcall(tt.GetItem, tt)
      local id = ok and WW.ItemID and WW.ItemID(link)
      if id then WW:ItemZeigen(id) return true end
    end
  end
  WW:Print("Kein Item unter der Maus. Zeige mit der Maus auf ein Item und drücke die Taste dann.")
  return false
end

-- /ww suche <Text>
WW:Befehl("suche", "Item suchen", function(text)
  WW:Oeffnen("items")
  if ui.suche then ui.suche(text or "") end
end)
