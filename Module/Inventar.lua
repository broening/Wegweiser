-- Wegweiser: Reiter "Inventar". Taschen, Bank und angelegte Gegenstände aller Charaktere merken,
-- zusammenzählen und bewerten (Auktionshaus oder Händler?).
--
-- Gespeichert in WW.db.inventar[Realm][Charaktername] (in WTF\Account\<KONTO>\SavedVariables\Wegweiser.lua, lesbar):
--   klasse = "WARRIOR", stufe, fraktion = "Alliance", geld (Kupfer), t = Zeit der letzten Aufnahme,
--   tasche  = "itemID:anzahl:gebunden,..."   (Taschen inklusive der Taschen selbst; gebunden 1 = ja, 0 = nein),
--   bank    = "itemID:anzahl:gebunden,..."   (nur lesbar, solange die Bank offen ist; sonst bleibt der letzte Stand),
--   bankT   = Zeit des letzten Bank-Standes (fehlt = Bank noch nie geöffnet),
--   angelegt = "platz:itemID,..."            (angelegte Gegenstände, Plätze 1-19)
-- Öffentlich: WW.Inventar.Aktualisieren(), .Charaktere(), .Bestand(itemID), .BankListe()
local ADDON, WW = ...
local UI = WW.UI

WW.standardDB.inventar = {}
WW.standardDB.inventarEinst = {
  tooltip = true,           -- "Bestand im Tooltip"
  nurDieser = false,        -- Liste: nur der gewählte Charakter
  nurVerkaufbar = false,    -- Liste: nur Ungebundenes
  sortierung = "gewinn",    -- "gewinn" | "name" | "anzahl"
  spalten = "preise",       -- "preise" (AH, Händler) | "behalten" (Urteil: behalten oder weg, mit Grund)
}

local Inv = {}
WW.Inventar = Inv

local PLAETZE = 19
local SPEICHER_VERZOEGERUNG = 1.0

---------------------------------------------------------------------------
-- Hilfen
---------------------------------------------------------------------------
local function pass(ok, ...) if ok then return ... end end
local function try(f, ...)
  if type(f) ~= "function" then return nil end
  return pass(pcall(f, ...))
end

local function einst() return WW.db and WW.db.inventarEinst end

local function vor(sekunden)
  sekunden = tonumber(sekunden) or 0
  if sekunden < 90 then return "gerade eben" end
  if sekunden < 3600 then return ("vor %d Min."):format(math.floor(sekunden / 60 + 0.5)) end
  if sekunden < 2 * 86400 then return ("vor %d Std."):format(math.floor(sekunden / 3600 + 0.5)) end
  return ("vor %d Tagen"):format(math.floor(sekunden / 86400 + 0.5))
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

local function slotAnzahl(bag)
  local f = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
  return tonumber(try(f, bag)) or 0
end

-- itemID, anzahl, gebunden eines Platzes (nil bei leerem Platz)
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

local function meinRealm()
  local r = GetRealmName and GetRealmName()
  if type(r) ~= "string" or r == "" then return nil end
  return r
end
local function meinName()
  local n = UnitName and UnitName("player")
  if type(n) ~= "string" or n == "" then return nil end
  return n
end

---------------------------------------------------------------------------
-- Aufnahme
---------------------------------------------------------------------------
local bankOffen = false
local bankWarLeer = false
local bankLeerVersuche = 0   -- Bank offen, aber noch keine Plätze lesbar: so oft schon neu versucht
local letzterFehler          -- Fehler der letzten Aufnahme (Text) oder nil
local fehlerGemeldet = false

-- Ist die Bank offen? Ereignis oder sichtbares Bankfenster.
local function bankIstOffen()
  if bankOffen then return true end
  local bf = rawget(_G, "BankFrame")
  if type(bf) == "table" and type(bf.IsShown) == "function" then
    local ok, an = pcall(bf.IsShown, bf)
    if ok and an == true then return true end
  end
  return false
end

-- Arten von Interaktion, die eine Bank öffnen (Banker, CharacterBanker, AccountBanker ...)
local function istBankArt(art)
  if art == nil then return false end
  local e = Enum and Enum.PlayerInteractionType
  if type(e) == "table" then
    for k, v in pairs(e) do
      if v == art and type(k) == "string" and k:find("Bank") and not k:find("Guild") then return true end
    end
    return false
  end
  return art == 8
end
local version = 0            -- zählt hoch, wenn sich Bestände ändern (für den Tooltip-Index)

-- Zählt id*2 + gebunden -> Anzahl
local function platzLesen(bag, summe)
  local n = slotAnzahl(bag)
  for slot = 1, n do
    local id, anz, geb = slotInfo(bag, slot)
    id = tonumber(id)
    if id then
      local k = id * 2 + (geb and 1 or 0)
      summe[k] = (summe[k] or 0) + (tonumber(anz) or 1)
    end
  end
  return n
end

-- Die Tasche selbst (liegt auf einem Ausrüstungsplatz): Gegenstand der Taschen 1.. und der Bankfächer
local function taschenSelbst(bag, summe)
  local inv
  if C_Container and C_Container.ContainerIDToInventoryID then
    inv = try(C_Container.ContainerIDToInventoryID, bag)
  elseif type(ContainerIDToInventoryID) == "function" then
    inv = try(ContainerIDToInventoryID, bag)
  end
  if not inv then return end
  local id = tonumber(try(GetInventoryItemID, "player", inv))
  if not id then
    local link = try(GetInventoryItemLink, "player", inv)
    id = type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
  end
  if id then
    local k = id * 2 + 1       -- gebunden: ob die Tasche selbst gebunden ist, sagt das Spiel hier nicht
    summe[k] = (summe[k] or 0) + 1
  end
end

local function serialisieren(summe)
  local keys = {}
  for k in pairs(summe) do keys[#keys + 1] = k end
  table.sort(keys)
  local t = {}
  for i, k in ipairs(keys) do
    t[i] = ("%d:%d:%d"):format(math.floor(k / 2), summe[k], k % 2)
  end
  return table.concat(t, ",")
end

local function eintragHolen(anlegen)
  if not WW.db or type(WW.db.inventar) ~= "table" then return nil end
  local realm, name = meinRealm(), meinName()
  if not realm or not name then return nil end
  local r = WW.db.inventar[realm]
  if type(r) ~= "table" then
    if not anlegen then return nil end
    r = {}
    WW.db.inventar[realm] = r
  end
  local e = r[name]
  if type(e) ~= "table" then
    if not anlegen then return nil end
    e = {}
    r[name] = e
  end
  return e, realm, name
end

-- Alles Lesbare des eigenen Charakters aufnehmen. bank = Bank mitlesen (nur wenn sie offen ist).
function Inv.Aktualisieren()
  local e = eintragHolen(true)
  if not e then return false end
  local jetzt = time()
  local token
  if UnitClass then local _, t = UnitClass("player"); token = t end
  if type(token) == "string" then e.klasse = token end
  e.stufe = tonumber(UnitLevel and UnitLevel("player")) or e.stufe
  local f = UnitFactionGroup and UnitFactionGroup("player")
  if type(f) == "string" then e.fraktion = f end
  local geld = tonumber(try(GetMoney))
  if geld then e.geld = geld end
  e.t = jetzt

  -- Taschen
  local summe = {}
  for _, bag in ipairs(WW.TaschenIDs()) do
    platzLesen(bag, summe)
    if bag ~= 0 then taschenSelbst(bag, summe) end
  end
  e.tasche = serialisieren(summe)

  -- Bank (nur solange offen)
  if bankIstOffen() then
    local ids, mitTasche = WW.BankIDs()
    local bs, plaetze = {}, 0
    for _, bag in ipairs(ids) do
      plaetze = plaetze + platzLesen(bag, bs)
      if mitTasche[bag] then taschenSelbst(bag, bs) end
    end
    if plaetze > 0 then   -- ohne Plätze ist die Bank nicht lesbar: alter Stand bleibt
      e.bank = serialisieren(bs)
      e.bankT = jetzt
      bankLeerVersuche = 0
      bankWarLeer = false
    else
      bankWarLeer = true
    end
  end

  -- angelegte Gegenstände
  local teile = {}
  for platz = 1, PLAETZE do
    local link = try(GetInventoryItemLink, "player", platz)
    local id = type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
    if id then teile[#teile + 1] = platz .. ":" .. id end
  end
  e.angelegt = table.concat(teile, ",")

  version = version + 1
  if Inv.beiAenderung then pcall(Inv.beiAenderung) end
  return true
end

-- Aufnahme mit Fehlermeldung: Fehler nicht still schlucken, sondern einmal im Chat zeigen und merken.
local function sicherAktualisieren()
  local ok, err = xpcall(Inv.Aktualisieren, function(m)
    return tostring(m) .. (debugstack and ("\n" .. debugstack(2, 6, 0)) or "")
  end)
  if ok then
    letzterFehler = nil
    return true
  end
  letzterFehler = tostring(err)
  if WW.db then WW.db.inventarFehler = { t = time(), text = letzterFehler } end
  if not fehlerGemeldet then
    fehlerGemeldet = true
    WW:Print(WW.f("rot", "Inventar konnte nicht gespeichert werden: ") .. (letzterFehler:match("^[^\n]+") or "?"))
  end
  return false
end

local geplant = false
local planen
planen = function()
  if geplant then return end
  geplant = true
  if C_Timer and C_Timer.After then
    C_Timer.After(SPEICHER_VERZOEGERUNG, function()
      geplant = false
      sicherAktualisieren()
      -- Bank offen, aber noch nicht lesbar (Daten kommen später): bis zu 5 Mal neu versuchen
      if bankWarLeer and bankIstOffen() and bankLeerVersuche < 5 then
        bankWarLeer = false
        bankLeerVersuche = bankLeerVersuche + 1
        planen()
      end
    end)
  else
    geplant = false
    sicherAktualisieren()
  end
end

local ereignisse = CreateFrame("Frame")
for _, ev in ipairs({ "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_MONEY", "PLAYER_LOGOUT",
  "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED", "PLAYERBANKBAGSLOTS_CHANGED",
  "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" }) do
  pcall(ereignisse.RegisterEvent, ereignisse, ev)
end
-- Für "/ww bank": die letzten Bank-Ereignisse (Name, Zeit, arg1)
local bankEreignisse = {}
local BANK_EREIGNIS = { BANKFRAME_OPENED = true, BANKFRAME_CLOSED = true, PLAYERBANKSLOTS_CHANGED = true,
  PLAYERBANKBAGSLOTS_CHANGED = true, PLAYER_INTERACTION_MANAGER_FRAME_SHOW = true, PLAYER_INTERACTION_MANAGER_FRAME_HIDE = true }

ereignisse:SetScript("OnEvent", function(_, ev, arg1)
  if BANK_EREIGNIS[ev] then
    table.insert(bankEreignisse, 1, ("%s (%s) %s"):format(ev, tostring(arg1), date and date("%H:%M:%S") or ""))
    bankEreignisse[9] = nil
  end
  if not WW.db then return end
  if ev == "PLAYER_LOGOUT" then
    sicherAktualisieren()
  elseif ev == "PLAYER_MONEY" then
    local e = eintragHolen(false)
    local geld = tonumber(try(GetMoney))
    if e and geld then e.geld = geld; e.t = time() end
  elseif ev == "BANKFRAME_OPENED" then
    bankOffen = true
    bankLeerVersuche = 0
    planen()
  elseif ev == "BANKFRAME_CLOSED" then
    bankOffen = false
  elseif ev == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" or ev == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
    if istBankArt(arg1) then
      bankOffen = (ev == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
      if bankOffen then bankLeerVersuche = 0; planen() end
    end
  else
    planen()
  end
end)

WW:BeimStart(function()
  if C_Timer and C_Timer.After then
    C_Timer.After(3, function() sicherAktualisieren() end)   -- Taschen sind kurz nach dem Einloggen noch leer
  else
    sicherAktualisieren()
  end
end)

---------------------------------------------------------------------------
-- Lesen der gespeicherten Bestände
---------------------------------------------------------------------------
-- Liste { schluessel, realm, name, e }, eigener Charakter zuerst, dann nach Realm und Name
function Inv.Charaktere()
  local out = {}
  local inv = WW.db and WW.db.inventar
  if type(inv) ~= "table" then return out end
  local mr, mn = meinRealm(), meinName()
  for realm, chars in pairs(inv) do
    if type(chars) == "table" then
      for name, e in pairs(chars) do
        if type(e) == "table" then
          out[#out + 1] = { schluessel = realm .. "|" .. name, realm = realm, name = name, e = e,
            ich = (realm == mr and name == mn) }
        end
      end
    end
  end
  table.sort(out, function(a, b)
    if a.ich ~= b.ich then return a.ich end
    if a.realm ~= b.realm then return a.realm < b.realm end
    return a.name < b.name
  end)
  return out
end

-- Pro Charakter: { [schluessel] = { name, realm, tasche, bank, angelegt } } und gesamt, für ein Item (aus dem Zwischenspeicher)
local index, indexVersion
local function indexBauen()
  if index and indexVersion == version then return index end
  index, indexVersion = {}, version
  local mehrereRealms
  local chars = Inv.Charaktere()
  local ersterRealm
  for _, c in ipairs(chars) do
    if not ersterRealm then ersterRealm = c.realm elseif c.realm ~= ersterRealm then mehrereRealms = true end
  end
  for _, c in ipairs(chars) do
    local anzeige = mehrereRealms and (c.name .. "-" .. c.realm) or c.name
    local function lesen(str, feld)
      if type(str) ~= "string" then return end
      for id, n in str:gmatch("(%d+):(%d+):%d") do
        id = tonumber(id)
        local x = index[id]
        if not x then x = {}; index[id] = x end
        local y = x[c.schluessel]
        if not y then y = { name = anzeige, ich = c.ich, tasche = 0, bank = 0, angelegt = 0 }; x[c.schluessel] = y end
        y[feld] = y[feld] + tonumber(n)
      end
    end
    lesen(c.e.tasche, "tasche")
    lesen(c.e.bank, "bank")
    if type(c.e.angelegt) == "string" then
      for _, id in c.e.angelegt:gmatch("(%d+):(%d+)") do
        id = tonumber(id)
        local x = index[id]
        if not x then x = {}; index[id] = x end
        local y = x[c.schluessel]
        if not y then y = { name = anzeige, ich = c.ich, tasche = 0, bank = 0, angelegt = 0 }; x[c.schluessel] = y end
        y.angelegt = y.angelegt + 1
      end
    end
  end
  return index
end

-- Wie viele hat wer? Gibt Liste { {name, anzahl, tasche, bank, angelegt, ich}, ... } (viele zuerst) und die Summe zurück.
function Inv.Bestand(itemID)
  itemID = tonumber(itemID)
  local x = itemID and indexBauen()[itemID]
  local liste, summe = {}, 0
  if not x then return liste, 0 end
  for _, y in pairs(x) do
    local n = y.tasche + y.bank + y.angelegt
    if n > 0 then
      liste[#liste + 1] = { name = y.name, anzahl = n, tasche = y.tasche, bank = y.bank, angelegt = y.angelegt, ich = y.ich }
      summe = summe + n
    end
  end
  table.sort(liste, function(a, b)
    if a.anzahl ~= b.anzahl then return a.anzahl > b.anzahl end
    return a.name < b.name
  end)
  return liste, summe
end

-- Gespeicherte Bank des eigenen Charakters als Liste { {id, anzahl, gebunden}, ... } (leer, wenn nie geöffnet)
function Inv.BankListe()
  local out = {}
  local e = eintragHolen(false)
  if not e or type(e.bank) ~= "string" then return out, nil end
  for id, n, b in e.bank:gmatch("(%d+):(%d+):(%d)") do
    out[#out + 1] = { id = tonumber(id), anzahl = tonumber(n), gebunden = (b == "1") }
  end
  return out, e.bankT
end

---------------------------------------------------------------------------
-- Tooltip: "Du hast: 25 (Dan 5, Enzrok 20)"
---------------------------------------------------------------------------
local gesehen = setmetatable({}, { __mode = "k" })

local function tooltipZeile(tt, data)
  local es = einst()
  if not es or not es.tooltip then return end
  if tt ~= GameTooltip and tt ~= ItemRefTooltip then return end
  local id = data and tonumber(data.id)
  if not id then
    local _, link = tt:GetItem()
    id = WW.ItemID(link)
  end
  if not id or gesehen[tt] == id then return end
  gesehen[tt] = id
  local liste, summe = Inv.Bestand(id)
  if summe == 0 then return end
  -- nur anzeigen, wenn es nicht allein in den Taschen dieses Charakters liegt
  local sonstwo = false
  for _, y in ipairs(liste) do
    if not y.ich or y.bank > 0 or y.angelegt > 0 then sonstwo = true end
  end
  if not sonstwo then return end
  local teile = {}
  for i = 1, math.min(#liste, 5) do teile[i] = liste[i].name .. " " .. liste[i].anzahl end
  local text = ("Du hast: %d (%s%s)"):format(summe, table.concat(teile, ", "), #liste > 5 and ", ..." or "")
  tt:AddLine(text, 0.6, 0.85, 1, true)
  tt:Show()
end

Inv.TooltipZeile = tooltipZeile   -- für die Tests (der Spiel-Haken ruft sie selbst auf)

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

-- Fehlersuche: Warum wird die Bank nicht gemerkt? Am besten bei offener Bank eingeben.
WW:Befehl("bank", "Prüfung der Bank-Erfassung (bei offener Bank eingeben)", function()
  WW:Print("Bank-Prüfung")
  local zeilen = {}
  local function print(text) zeilen[#zeilen + 1] = text; _G.print(text) end
  print("  Bank offen (laut Addon): " .. tostring(bankOffen) .. ", Bankfenster sichtbar: " .. tostring(bankIstOffen()))
  local arten = {}
  local pit = Enum and Enum.PlayerInteractionType
  if type(pit) == "table" then
    for k, v in pairs(pit) do if type(k) == "string" and k:find("Bank") then arten[#arten + 1] = k .. "=" .. tostring(v) end end
  end
  table.sort(arten)
  print("  Bank-Interaktionen: " .. (#arten > 0 and table.concat(arten, ", ") or "keine"))
  local e = Enum and Enum.BagIndex
  if type(e) == "table" then
    local t = {}
    for k, v in pairs(e) do
      if type(k) == "string" and k:find("Bank") then t[#t + 1] = k .. "=" .. tostring(v) end
    end
    table.sort(t)
    print("  Enum.BagIndex: " .. (#t > 0 and table.concat(t, ", ") or "keine Bank-Einträge"))
  else
    print("  Enum.BagIndex fehlt")
  end
  print("  NUM_BANKBAGSLOTS = " .. tostring(rawget(_G, "NUM_BANKBAGSLOTS")) .. ", NUM_TOTAL_EQUIPPED_BAG_SLOTS = "
    .. tostring(rawget(_G, "NUM_TOTAL_EQUIPPED_BAG_SLOTS")))
  local ok, ids = pcall(WW.BankIDs)
  if ok and type(ids) == "table" then
    local teile = {}
    for _, bag in ipairs(ids) do
      local n, voll = slotAnzahl(bag), 0
      for slot = 1, n do if slotInfo(bag, slot) then voll = voll + 1 end end
      teile[#teile + 1] = ("%s:%d/%d"):format(tostring(bag), voll, n)
    end
    print("  Behälter (Nummer:belegt/Plätze): " .. table.concat(teile, "  "))
  else
    print("  WW.BankIDs Fehler: " .. tostring(ids))
  end
  local alt = {}
  for _, bag in ipairs({ -1, -3, 5, 6, 7, 8, 9, 10, 11, 12 }) do
    local n = slotAnzahl(bag)
    if n > 0 then alt[#alt + 1] = bag .. ":" .. n end
  end
  print("  Alle Behälter mit Plätzen (-1, -3, 5-12): " .. (#alt > 0 and table.concat(alt, "  ") or "keine"))
  print("  Letzte Bank-Ereignisse: " .. (#bankEreignisse > 0 and table.concat(bankEreignisse, " | ") or "keine"))
  local jetztOk = sicherAktualisieren()
  print("  Jetzt speichern: " .. (jetztOk and "geklappt" or ("Fehler: " .. tostring(letzterFehler))))
  local eintrag = eintragHolen(false)
  print("  Gespeicherte Bank: " .. (eintrag and eintrag.bankT and vor(time() - eintrag.bankT) or "noch nie"))
  if WW.db then WW.db.bankPruefung = zeilen end   -- nach /reload in der SavedVariables-Datei lesbar
end)

WW:Befehl("inventar", "Inventar aller Charaktere", function()
  WW:Oeffnen("inventar")
end)

---------------------------------------------------------------------------
-- Reiter "Inventar"
---------------------------------------------------------------------------
local KLASSEN_DE = {}   -- wird bei Bedarf aus LOCALIZED_CLASS_NAMES_MALE gelesen

local function klassenName(token)
  local t = LOCALIZED_CLASS_NAMES_MALE
  if type(t) == "table" and type(rawget(t, token)) == "string" then return t[token] end
  return KLASSEN_DE[token] or (type(token) == "string" and token or "?")
end

local function klassenFarbe(token)
  local t = RAID_CLASS_COLORS
  local c = type(t) == "table" and type(token) == "string" and rawget(t, token)
  if type(c) == "table" and c.r then
    return ("|cff%02x%02x%02x"):format(math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5), math.floor(c.b * 255 + 0.5))
  end
  return "|cffffffff"
end

local SORTIERUNGEN = { "gewinn", "name", "anzahl" }
local SORT_TEXT = { gewinn = "AH-Gewinn", name = "Name", anzahl = "Anzahl" }

-- Aus den gewählten Charakteren eine Liste von Items bauen.
--   nurVerkaufbar: gebundene Stücke zählen nicht. suche: Teil des Namens (klein geschrieben) oder Item-Nummer.
-- Gibt liste, summen zurück: summen = { ah, haendler, ahLohnt, items }
local function bestandBauen(chars, nurVerkaufbar, suche, sortierung)
  local pro, reihenfolge = {}, {}
  local function eintrag(id)
    local x = pro[id]
    if not x then
      x = { id = id, gesamt = 0, frei = 0, wo = {}, woListe = {} }
      pro[id] = x
      reihenfolge[#reihenfolge + 1] = x
    end
    return x
  end
  for _, c in ipairs(chars) do
    local e = c.e
    local function dazu(id, n, gebunden, ort)
      if nurVerkaufbar and gebunden then return end
      local x = eintrag(id)
      x.gesamt = x.gesamt + n
      if not gebunden then x.frei = x.frei + n end
      local w = x.wo[c.schluessel]
      if not w then
        w = { name = c.name, tasche = 0, bank = 0, angelegt = 0 }
        x.wo[c.schluessel] = w
        x.woListe[#x.woListe + 1] = w
      end
      w[ort] = w[ort] + n
    end
    if type(e.tasche) == "string" then
      for id, n, b in e.tasche:gmatch("(%d+):(%d+):(%d)") do dazu(tonumber(id), tonumber(n), b == "1", "tasche") end
    end
    if type(e.bank) == "string" then
      for id, n, b in e.bank:gmatch("(%d+):(%d+):(%d)") do dazu(tonumber(id), tonumber(n), b == "1", "bank") end
    end
    if not nurVerkaufbar and type(e.angelegt) == "string" then
      for _, id in e.angelegt:gmatch("(%d+):(%d+)") do dazu(tonumber(id), 1, true, "angelegt") end
    end
  end

  local out = {}
  local summen = { ah = 0, haendler = 0, ahLohnt = 0, items = 0 }
  for _, x in ipairs(reihenfolge) do
    local name = WW.ItemName(x.id) or ("Item " .. x.id)
    x.sortName = name:lower()
    local passt = true
    if suche and suche ~= "" then
      passt = x.sortName:find(suche, 1, true) ~= nil or tostring(x.id) == suche
    end
    if passt then
      -- Wo liegt es?
      local teile = {}
      for _, w in ipairs(x.woListe) do
        local orte = {}
        if w.tasche > 0 then orte[#orte + 1] = "Tasche " .. w.tasche end
        if w.bank > 0 then orte[#orte + 1] = "Bank " .. w.bank end
        if w.angelegt > 0 then orte[#orte + 1] = "angelegt" end
        teile[#teile + 1] = w.name .. ": " .. table.concat(orte, ", ")
      end
      x.wotext = table.concat(teile, "; ")
      -- Bewertung des ungebundenen Teils
      if WW.AH and x.frei > 0 then
        x.farbe, x.text, x.erloes, x.haendler = WW.AH.Bewertung(x.id, x.frei, false)
      else
        x.farbe, x.text, x.erloes = "grau", x.frei > 0 and "kein AH-Preis" or "gebunden", 0
        local v = select(11, WW.GetItemInfo(x.id))
        x.haendler = (x.frei > 0 and v or 0) * x.frei
      end
      x.erloes, x.haendler = x.erloes or 0, x.haendler or 0
      x.gewinn = x.erloes - x.haendler
      x.rang = (x.farbe == "grau") and 1 or 0
      if x.frei > 0 then
        summen.items = summen.items + 1
        if x.erloes > 0 then summen.ah = summen.ah + x.erloes end
        summen.haendler = summen.haendler + x.haendler
        if x.farbe == "gruen" then summen.ahLohnt = summen.ahLohnt + x.erloes end
      end
      out[#out + 1] = x
    end
  end
  table.sort(out, function(a, b)
    if sortierung == "name" then
      if a.sortName ~= b.sortName then return a.sortName < b.sortName end
    elseif sortierung == "anzahl" then
      if a.gesamt ~= b.gesamt then return a.gesamt > b.gesamt end
      if a.sortName ~= b.sortName then return a.sortName < b.sortName end
    else
      if a.rang ~= b.rang then return a.rang < b.rang end
      if a.rang == 0 then
        if a.gewinn ~= b.gewinn then return a.gewinn > b.gewinn end
      elseif a.haendler ~= b.haendler then
        return a.haendler > b.haendler
      end
      if a.sortName ~= b.sortName then return a.sortName < b.sortName end
    end
    return a.id < b.id
  end)
  return out, summen
end
Inv.BestandBauen = bestandBauen   -- für Tests

local SP = { name = 22, anzahl = 164, wo = 204, ah = 330, haendler = 436 }

WW:Reiter("inventar", "Inventar", 25, function(p)
  local es = WW.db.inventarEinst
  local gewaehlt            -- Schlüssel des gewählten Charakters in der linken Liste
  local suchtext = ""

  -- Zeile 1: Suche, Filter, Sortierung
  local label = UI.Text(p)
  label:SetPoint("TOPLEFT", 4, -9)
  label:SetText("Suche:")
  local planeNeu
  local verzoegert = 0
  local edit = UI.Eingabe(p, 150, function(text)
    verzoegert = verzoegert + 1
    local mein = verzoegert
    local function los()
      if mein == verzoegert then suchtext = (text or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""); planeNeu() end
    end
    if C_Timer and C_Timer.After then C_Timer.After(0.3, los) else los() end
  end)
  edit:SetPoint("LEFT", label, "RIGHT", 10, 0)

  local alleKnopf = UI.Knopf(p, "Alle Charaktere", 120)
  alleKnopf:SetPoint("TOPLEFT", 270, -4)
  local einerKnopf = UI.Knopf(p, "Nur dieser", 100)
  einerKnopf:SetPoint("LEFT", alleKnopf, "RIGHT", 4, 0)
  local verkaufbarHaken = UI.Haken(p, "Nur verkaufbar",
    function() return es.nurVerkaufbar end,
    function(an) es.nurVerkaufbar = an; planeNeu() end)
  verkaufbarHaken:SetPoint("LEFT", einerKnopf, "RIGHT", 6, 0)
  local sortKnopf = UI.Knopf(p, "", 170)
  sortKnopf:SetPoint("TOPRIGHT", -4, -4)

  -- Linke Liste: Charaktere
  local CH_B, LISTE_H = 270, WW.INHALT_HOEHE - 34 - 48
  local charListe, itemListe

  local function baueCharZeile(z)
    z.sel = z:CreateTexture(nil, "BACKGROUND")
    z.sel:SetAllPoints()
    z.sel:SetColorTexture(0.3, 0.5, 0.9, 0.25)
    z.sel:Hide()
    z.l1 = UI.Text(z)
    z.l1:SetPoint("TOPLEFT", 2, -3)
    z.l1:SetWidth(CH_B - 40)
    z.l1:SetWordWrap(false)
    z.l2 = UI.Text(z, "klein", 0.75, 0.75, 0.75)
    z.l2:SetPoint("TOPLEFT", 2, -17)
    z.l2:SetWidth(CH_B - 40)
    z.l2:SetWordWrap(false)
    z.l3 = UI.Text(z, "klein", 0.75, 0.75, 0.75)
    z.l3:SetPoint("TOPLEFT", 2, -29)
    z.l3:SetWidth(CH_B - 40)
    z.l3:SetWordWrap(false)
    z:SetScript("OnClick", function(self)
      if self.eintrag then
        gewaehlt = self.eintrag.schluessel
        es.nurDieser = true
        planeNeu()
      end
    end)
  end
  local function fuelleCharZeile(z, c)
    local e = c.e
    z.sel:SetShown(c.schluessel == gewaehlt)
    local mehrere = c.mehrereRealms and (" (" .. c.realm .. ")") or ""
    z.l1:SetText(klassenFarbe(e.klasse) .. c.name .. "|r" .. mehrere .. (c.ich and WW.f("grau", " (du)") or ""))
    z.l2:SetText(("Stufe %s %s · %s"):format(tostring(e.stufe or "?"), klassenName(e.klasse), WW.Geld(e.geld)))
    local bank
    if e.bankT then bank = "Bank: " .. vor(time() - e.bankT) else bank = "Bank: noch nie geöffnet" end
    z.l3:SetText("Stand " .. vor(time() - (tonumber(e.t) or 0)) .. " · " .. bank)
  end
  charListe = UI.Liste(p, CH_B, LISTE_H, 40, baueCharZeile, fuelleCharZeile)
  charListe:SetPoint("TOPLEFT", 0, -34)

  -- Rechte Liste: Items
  local IT_B = WW.INHALT_BREITE - CH_B - 8
  local function kopf(text, x)
    local t = UI.Text(p, "klein", 0.9, 0.8, 0.3)
    t:SetPoint("TOPLEFT", CH_B + 8 + 10 + x, -26)
    t:SetText(text)
    return t
  end
  kopf("Item", SP.name)
  kopf("Anz.", SP.anzahl)
  kopf("Wo", SP.wo)
  local kopfAH = kopf("AH (nach Gebühren)", SP.ah)
  local kopfH = kopf("Händler", SP.haendler)
  local kopfB = kopf("Behalten oder weg? (für diesen Charakter)", SP.ah)

  local function baueItemZeile(z)
    z.icon = z:CreateTexture(nil, "ARTWORK")
    z.icon:SetSize(18, 18)
    z.icon:SetPoint("LEFT", 0, 0)
    z.name = UI.Text(z)
    z.name:SetPoint("LEFT", SP.name, 0)
    z.name:SetWidth(SP.anzahl - SP.name - 4)
    z.name:SetWordWrap(false)
    z.anzahl = UI.Text(z)
    z.anzahl:SetPoint("LEFT", SP.anzahl, 0)
    z.anzahl:SetWidth(36)
    z.anzahl:SetJustifyH("RIGHT")
    z.wo = UI.Text(z, "klein", 0.8, 0.8, 0.8)
    z.wo:SetPoint("LEFT", SP.wo, 0)
    z.wo:SetWidth(SP.ah - SP.wo - 4)
    z.wo:SetWordWrap(false)
    z.ah = UI.Text(z)
    z.ah:SetPoint("LEFT", SP.ah, 0)
    z.ah:SetWidth(SP.haendler - SP.ah - 4)
    z.ah:SetWordWrap(false)
    z.haendler = UI.Text(z)
    z.haendler:SetPoint("LEFT", SP.haendler, 0)
    z.haendler:SetWidth(100)
    z.haendler:SetWordWrap(false)
    z.grund = UI.Text(z, "klein")
    z.grund:SetPoint("LEFT", SP.ah, 0)
    z.grund:SetPoint("RIGHT", z, "RIGHT", -2, 0)
    z.grund:SetWordWrap(false)
    z:SetScript("OnEnter", function(self)
      if self.eintrag then
        UI.ItemTooltip(self, self.eintrag.id)
        if self.eintrag.wotext and self.eintrag.wotext ~= "" then
          GameTooltip:AddLine(self.eintrag.wotext, 0.6, 0.85, 1, true)
        end
        GameTooltip:AddLine("Klick: mehr über dieses Item", 0.6, 0.6, 0.6)
        GameTooltip:Show()
      end
    end)
    z:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  local function fuelleItemZeile(z, x)
    z.icon:SetTexture(itemSymbol(x.id))
    local name = WW.ItemName(x.id) or ("Item " .. x.id)
    local q = select(3, WW.GetItemInfo(x.id))
    z.name:SetText(qualitaetsCode(q) .. name .. "|r")
    z.anzahl:SetText(x.gesamt)
    z.wo:SetText(x.wotext)
    local behalten = es.spalten == "behalten"
    z.ah:SetShown(not behalten)
    z.haendler:SetShown(not behalten)
    z.grund:SetShown(behalten)
    if behalten then
      local U = WW.Urteil
      local farbe = U and x.gruppe and U.REIHE_FARBE[x.gruppe] or "grau"
      local titel = U and x.gruppe and U.REIHE_TITEL[x.gruppe] or "ohne Urteil"
      z.grund:SetText(WW.f(farbe, titel) .. ((x.grund and x.grund ~= "") and WW.f("grau", ": " .. x.grund) or ""))
      return
    end
    if x.frei > 0 and x.erloes > 0 then
      z.ah:SetText(WW.f(x.farbe, WW.Geld(x.erloes)))
    elseif x.frei > 0 then
      z.ah:SetText(WW.f(x.farbe, x.text))
    else
      z.ah:SetText(WW.f("grau", "gebunden"))
    end
    z.haendler:SetText(x.haendler > 0 and WW.Geld(x.haendler) or "-")
  end
  itemListe = UI.Liste(p, IT_B, LISTE_H, 22, baueItemZeile, fuelleItemZeile)
  itemListe:SetPoint("TOPLEFT", CH_B + 8, -40)
  itemListe.itemKlick = true   -- Klick: Item-Details im Reiter "Items"

  local leer = UI.Text(itemListe, "klein", 0.75, 0.75, 0.75)
  leer:SetPoint("TOPLEFT", 16, -16)
  leer:SetWidth(IT_B - 60)
  leer:SetSpacing(3)
  leer:SetJustifyV("TOP")

  -- Fuß: Summen und Einstellung
  local summe = UI.Text(p)
  summe:SetPoint("BOTTOMLEFT", 4, 28)
  summe:SetWidth(WW.INHALT_BREITE - 8)
  summe:SetWordWrap(false)
  local tipp = UI.Haken(p, "Bestand im Tooltip",
    function() return es.tooltip end,
    function(an) es.tooltip = an end)
  tipp:SetPoint("BOTTOMLEFT", 0, 0)
  local hinweis = UI.Text(p, "klein", 0.7, 0.7, 0.7)
  hinweis:SetPoint("LEFT", tipp, "RIGHT", 150, 0)
  hinweis:SetWidth(WW.INHALT_BREITE - 200 - 160)
  local spaltenKnopf = UI.Knopf(p, "", 150, function()
    es.spalten = (es.spalten == "behalten") and "preise" or "behalten"
    planeNeu()
  end)
  spaltenKnopf:SetPoint("BOTTOMRIGHT", -4, 2)
  hinweis:SetWordWrap(false)
  hinweis:SetText("Taschen, Bank und angelegte Gegenstände. Die Bank kennt das Addon nur vom letzten Besuch.")

  local function auswahl()
    local alle = Inv.Charaktere()
    local mehrere, erster = false, nil
    for _, c in ipairs(alle) do
      if not erster then erster = c.realm elseif c.realm ~= erster then mehrere = true end
    end
    for _, c in ipairs(alle) do c.mehrereRealms = mehrere end
    return alle
  end

  local function neuAufbauen()
    local alle = auswahl()
    if not gewaehlt or not (function() for _, c in ipairs(alle) do if c.schluessel == gewaehlt then return true end end end)() then
      gewaehlt = alle[1] and alle[1].schluessel or nil
    end
    local chars = alle
    if es.nurDieser then
      chars = {}
      for _, c in ipairs(alle) do if c.schluessel == gewaehlt then chars[1] = c end end
    end
    charListe:Setze(alle)
    local liste, s = bestandBauen(chars, es.nurVerkaufbar, suchtext, es.sortierung)
    local behalten = es.spalten == "behalten"
    if behalten and WW.Urteil and WW.Urteil.Einordnen then
      -- Urteil wie im früheren Reiter "Behalten": nach Gruppe, darin wie gewählt sortiert
      local reihe = WW.Urteil.REIHE
      for i, x in ipairs(liste) do
        local ok, g, grund = pcall(WW.Urteil.Einordnen, x.id, x.gesamt, x.frei == 0)
        x.gruppe, x.grund, x.platz = ok and g or nil, ok and grund or nil, i
      end
      table.sort(liste, function(a, b)
        local ra, rb = reihe[a.gruppe] or 99, reihe[b.gruppe] or 99
        if ra ~= rb then return ra < rb end
        return a.platz < b.platz
      end)
    end
    kopfAH:SetShown(not behalten)
    kopfH:SetShown(not behalten)
    kopfB:SetShown(behalten)
    spaltenKnopf:SetText(behalten and "Spalten: Behalten?" or "Spalten: Preise")
    itemListe:Setze(liste)
    if #liste == 0 then
      if #alle == 0 then
        leer:SetText("Noch keine Daten. Das Addon merkt sich Taschen und angelegte Gegenstände jedes Charakters, "
          .. "sobald er eingeloggt ist. Die Bank wird gemerkt, wenn du sie öffnest.")
      elseif suchtext ~= "" then
        leer:SetText("Nichts gefunden.")
      else
        leer:SetText("Keine Gegenstände.")
      end
    else
      leer:SetText("")
    end
    summe:SetText(("Verkaufswert AH: %s · beim Händler: %s · davon lohnt AH: %s   (%d verkaufbare Items)"):format(
      WW.Geld(s.ah), WW.Geld(s.haendler), WW.Geld(s.ahLohnt), s.items))
    sortKnopf:SetText("Sortierung: " .. (SORT_TEXT[es.sortierung] or "AH-Gewinn"))
    if es.nurDieser then einerKnopf:LockHighlight(); alleKnopf:UnlockHighlight()
    else alleKnopf:LockHighlight(); einerKnopf:UnlockHighlight() end
  end

  local neuGeplant = false
  planeNeu = function()
    if neuGeplant then return end
    neuGeplant = true
    local function los()
      neuGeplant = false
      if p:IsShown() then neuAufbauen() end
    end
    if C_Timer and C_Timer.After then C_Timer.After(0.05, los) else los() end
  end

  alleKnopf:SetScript("OnClick", function() es.nurDieser = false; neuAufbauen() end)
  einerKnopf:SetScript("OnClick", function() es.nurDieser = true; neuAufbauen() end)
  sortKnopf:SetScript("OnClick", function()
    local nach = 1
    for i, s in ipairs(SORTIERUNGEN) do if s == es.sortierung then nach = i % #SORTIERUNGEN + 1 end end
    es.sortierung = SORTIERUNGEN[nach]
    neuAufbauen()
  end)

  Inv.beiAenderung = function()
    if p:IsShown() then planeNeu() end
  end

  p.OnZeigen = function()
    gewaehlt = gewaehlt or nil
    neuAufbauen()
  end
end)
