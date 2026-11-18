-- Wegweiser: Kern. Namensraum, Ereignisse, gespeicherte Daten, Hilfsfunktionen.
-- Jede Datei beginnt mit "local ADDON, WW = ...". WW ist der gemeinsame Namensraum.
-- Daten aus anderen Addons liegen unter WW.quelle.fdb / .helper / .fdm / .gc (siehe Daten\*.lua).
local ADDON, WW = ...
_G.Wegweiser = WW

local GetMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
WW.version = GetMeta(ADDON, "Version") or "?"
WW.quelle = WW.quelle or {}

---------------------------------------------------------------------------
-- Farben und Ausgabe
---------------------------------------------------------------------------
WW.farbe = {
  titel = "ff4fc3f7",
  gruen = "ff40ff40",
  gelb  = "ffffd200",
  orange = "ffff9933",
  rot   = "ffff4040",
  grau  = "ff9d9d9d",
  weiss = "ffffffff",
}

-- Text einfärben: WW.f("gruen", "Hallo")
function WW.f(farbe, text)
  return "|c" .. (WW.farbe[farbe] or farbe) .. tostring(text) .. "|r"
end

function WW:Print(...)
  print(WW.f("titel", "Wegweiser:"), ...)
end

-- Kupfer als Text mit Münz-Symbolen. 0 oder nil: "-"
function WW.Geld(kupfer)
  kupfer = tonumber(kupfer)
  if not kupfer or kupfer <= 0 then return "-" end
  kupfer = math.floor(kupfer + 0.5)
  -- Forever hat nur C_CurrencyInfo.GetCoinTextureString, ältere Clients die globale Funktion
  local f = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or rawget(_G, "GetCoinTextureString")
  if type(f) == "function" then
    local ok, text = pcall(f, kupfer)
    if ok and type(text) == "string" and text ~= "" then return text end
  end
  local g, s, c = math.floor(kupfer / 10000), math.floor(kupfer / 100) % 100, kupfer % 100
  local t = {}
  if g > 0 then t[#t + 1] = g .. "g" end
  if s > 0 then t[#t + 1] = s .. "s" end
  if c > 0 or #t == 0 then t[#t + 1] = c .. "k" end
  return table.concat(t, " ")
end

-- Kurzer Preis für schmale Spalten: ab 1 Gold ohne Kupfer, ab 1000 Gold nur Gold (gerundet).
function WW.GeldKurz(kupfer)
  kupfer = tonumber(kupfer)
  if not kupfer or kupfer <= 0 then return "-" end
  if kupfer >= 10000000 then return WW.Geld(math.floor(kupfer / 10000 + 0.5) * 10000) end
  if kupfer >= 10000 then return WW.Geld(math.floor(kupfer / 100 + 0.5) * 100) end
  return WW.Geld(kupfer)
end

---------------------------------------------------------------------------
-- Ereignisse: WW:Event("NAME", function(...) end). Mehrere Funktionen pro Ereignis.
---------------------------------------------------------------------------
local ereignisRahmen = CreateFrame("Frame")
local handler = {}

-- Gibt false zurück, wenn der Client das Ereignis nicht kennt (dann wirft RegisterEvent einen Fehler:
-- abfangen, sonst bricht die ganze Datei beim Laden ab).
function WW:Event(name, fn)
  if not handler[name] then
    local ok = pcall(ereignisRahmen.RegisterEvent, ereignisRahmen, name)
    if not ok then return false end
    handler[name] = {}
  end
  table.insert(handler[name], fn)
  return true
end

ereignisRahmen:SetScript("OnEvent", function(_, name, ...)
  local liste = handler[name]
  if not liste then return end
  for i = 1, #liste do
    local ok, err = pcall(liste[i], ...)
    if not ok then geterrorhandler()(err) end
  end
end)

---------------------------------------------------------------------------
-- Gespeicherte Daten
--   WegweiserDB      (alle Charaktere)    -> WW.db
--   WegweiserCharDB  (nur dieser Charakter) -> WW.charDb
-- Module tragen ihre Standardwerte VOR dem Laden ein:
--   WW.standardDB.meinModul = { ... }   /   WW.standardCharDB.meinModul = { ... }
---------------------------------------------------------------------------
WW.standardDB = {
  minimap = { winkel = 200, aus = false },
  fenster = {},
  namen = {},          -- [itemID] = deutscher Name (Zwischenspeicher)
}
WW.standardCharDB = {}

local function fuelleStandard(ziel, vorlage)
  for k, v in pairs(vorlage) do
    if type(v) == "table" then
      if type(ziel[k]) ~= "table" then ziel[k] = {} end
      fuelleStandard(ziel[k], v)
    elseif ziel[k] == nil then
      ziel[k] = v
    end
  end
end

-- Funktionen, die nach dem Einloggen laufen (dann sind WW.db und alle Daten da).
local startListe = {}
function WW:BeimStart(fn)
  table.insert(startListe, fn)
end

WW:Event("ADDON_LOADED", function(name)
  if name ~= ADDON then return end
  WegweiserDB = WegweiserDB or {}
  WegweiserCharDB = WegweiserCharDB or {}
  fuelleStandard(WegweiserDB, WW.standardDB)
  fuelleStandard(WegweiserCharDB, WW.standardCharDB)
  WW.db, WW.charDb = WegweiserDB, WegweiserCharDB
end)

WW:Event("PLAYER_LOGIN", function()
  for i = 1, #startListe do
    local ok, err = pcall(startListe[i])
    if not ok then geterrorhandler()(err) end
  end
end)

---------------------------------------------------------------------------
-- Hilfen für Items
---------------------------------------------------------------------------
-- Der Forever-Client hat die alten Funktionen GetItemInfo/GetItemIcon nicht mehr, nur C_Item.*.
-- Immer diese beiden benutzen, nie die alten Namen direkt.
function WW.GetItemInfo(item)
  local f = (C_Item and C_Item.GetItemInfo) or rawget(_G, "GetItemInfo")
  if not f or item == nil then return nil end
  return f(item)
end

function WW.GetItemIcon(id)
  local f = (C_Item and C_Item.GetItemIconByID) or rawget(_G, "GetItemIcon")
  if not f or id == nil then return nil end
  return f(id)
end

---------------------------------------------------------------------------
-- Neue und alte Spiel-API (Forever hat viele alte globale Funktionen nicht mehr)
-- Erst die neue Funktion (C_*), dann die alte globale als Ersatz für Classic-Clients.
-- Alte Namen nur über WW.Alt("Name") holen, nie direkt: dann stürzt nichts ab, wenn es sie nicht gibt.
---------------------------------------------------------------------------
function WW.Alt(name)
  local f = rawget(_G, name)
  return type(f) == "function" and f or nil
end

local function neu(tabelle, name)
  local t = rawget(_G, tabelle)
  local f = type(t) == "table" and t[name]
  return type(f) == "function" and f or nil
end
WW.Neu = neu

-- Zaubername oder nil
function WW.SpellName(id)
  if id == nil then return nil end
  local f = neu("C_Spell", "GetSpellName")
  if f then
    local ok, n = pcall(f, id)
    if ok and type(n) == "string" and n ~= "" then return n end
  end
  f = neu("C_Spell", "GetSpellInfo")
  if f then
    local ok, info = pcall(f, id)
    if ok and type(info) == "table" and type(info.name) == "string" and info.name ~= "" then return info.name end
  end
  f = WW.Alt("GetSpellInfo")
  if f then
    local ok, n = pcall(f, id)
    if ok and type(n) == "string" and n ~= "" then return n end
  end
  return nil
end

-- Questlog: Anzahl der Zeilen (Überschriften mitgezählt)
function WW.QuestLogAnzahl()
  local f = neu("C_QuestLog", "GetNumQuestLogEntries") or WW.Alt("GetNumQuestLogEntries")
  if not f then return 0 end
  local ok, n = pcall(f)
  return ok and tonumber(n) or 0
end

-- Eine Zeile im Questlog, einheitlich:
-- { index, titel, stufe, kopf, questID, fertig, versteckt, eingeklappt } oder nil
function WW.QuestLogEintrag(i)
  local f = neu("C_QuestLog", "GetInfo")
  if f then
    local ok, info = pcall(f, i)
    if ok and type(info) == "table" then
      local qid = tonumber(info.questID)
      local fertig = info.isComplete == 1 or info.isComplete == true
      -- Ersatz wie ForeverDB: C_QuestLog.IsComplete, falls GetInfo kein isComplete liefert
      if info.isComplete == nil and qid and qid > 0 then
        local ic = neu("C_QuestLog", "IsComplete")
        if ic then
          local ok2, r = pcall(ic, qid)
          fertig = ok2 and (r == true or r == 1) or false
        end
      end
      return { index = i, titel = info.title, stufe = tonumber(info.level), kopf = info.isHeader and true or false,
        questID = (qid and qid > 0) and qid or nil, fertig = fertig,
        versteckt = info.isHidden and true or false, eingeklappt = info.isCollapsed and true or false }
    end
    return nil
  end
  f = WW.Alt("GetQuestLogTitle")
  if not f then return nil end
  local ok, titel, stufe, _, kopf, eingeklappt, fertig, _, qid = pcall(f, i)
  if not ok or not titel then return nil end
  qid = tonumber(qid)
  return { index = i, titel = titel, stufe = tonumber(stufe), kopf = kopf and true or false,
    questID = (qid and qid > 0) and qid or nil, fertig = fertig == 1 or fertig == true,
    versteckt = false, eingeklappt = eingeklappt and true or false }
end

-- Alle Zeilen im Questlog (nur die sichtbaren, ohne eingeklappte Überschriften aufzuklappen)
function WW.QuestLogEintraege()
  local liste = {}
  for i = 1, WW.QuestLogAnzahl() do
    local e = WW.QuestLogEintrag(i)
    if e then liste[#liste + 1] = e end
  end
  return liste
end

-- Quest abgeschlossen? true/false, nil wenn das Spiel es nicht sagen kann
function WW.QuestErledigt(id)
  if not id then return nil end
  for _, f in ipairs({ neu("C_QuestLog", "IsQuestFlaggedCompleted") or false, WW.Alt("IsQuestFlaggedCompleted") or false }) do
    if f then
      local ok, r = pcall(f, id)
      if ok then return r and true or false end
    end
  end
  return nil
end

-- Kann Wegweiser eine Quest im Log auswählen? "modern" (über questID), "alt" (über Index) oder nil.
-- Die alten Funktionen für Belohnungen (GetQuestLogItemLink, GetNumQuestLogRewards ...) lesen die gewählte Quest.
function WW.QuestWahlArt()
  if neu("C_QuestLog", "SetSelectedQuest") and neu("C_QuestLog", "GetSelectedQuest") then return "modern" end
  if WW.Alt("SelectQuestLogEntry") and WW.Alt("GetQuestLogSelection") then return "alt" end
  return nil
end

-- Quest im Log wählen und prüfen, ob es geklappt hat.
-- Gibt ok und eine Funktion zurück, die die vorherige Auswahl wieder herstellt.
function WW.QuestWaehlen(questID, index)
  local art = WW.QuestWahlArt()
  if art == "modern" then
    local get, set = C_QuestLog.GetSelectedQuest, C_QuestLog.SetSelectedQuest
    local ok, a = pcall(get)
    local vorher = ok and a or nil
    if vorher ~= questID then pcall(set, questID) end
    local okN, jetzt = pcall(get)
    return (okN and jetzt == questID) and true or false, function()
      if vorher ~= questID then pcall(set, vorher or 0) end
    end
  elseif art == "alt" and index then
    local sel, get = WW.Alt("SelectQuestLogEntry"), WW.Alt("GetQuestLogSelection")
    local ok, a = pcall(get)
    local vorher = ok and tonumber(a) or nil
    if vorher ~= index then pcall(sel, index) end
    local okN, jetzt = pcall(get)
    return (okN and tonumber(jetzt) == index) and true or false, function()
      if vorher and vorher ~= index then pcall(sel, vorher) end
    end
  end
  return false, function() end
end

-- Fertigkeiten des Charakters: { [Name] = { rang, max } }.
-- Forever listet jeden Beruf zweimal (Eltern- und Kindzeile): der höchste Wert zählt (wie ForeverDB Armory.lua).
function WW.Fertigkeiten()
  local raus = {}
  local function dazu(name, rang, max)
    rang, max = tonumber(rang), tonumber(max) or 0
    if type(name) ~= "string" or name == "" or not rang then return end
    local e = raus[name]
    if e then
      if rang > e.rang then e.rang = rang end
      if max > e.max then e.max = max end
    else
      raus[name] = { rang = rang, max = max }
    end
  end
  local anzahlF, infoF = neu("C_SkillInfo", "GetNumSkillLines"), neu("C_SkillInfo", "GetSkillLineInfo")
  if anzahlF and infoF then
    local ok, n = pcall(anzahlF)
    for i = 1, (ok and tonumber(n) or 0) do
      local ok2, k = pcall(infoF, i)
      if ok2 and type(k) == "table" and not k.isHeader then dazu(k.name, k.rank, k.maxRank) end
    end
  end
  if next(raus) == nil then
    local profs, pinfo = WW.Alt("GetProfessions"), WW.Alt("GetProfessionInfo")
    if profs and pinfo then
      local r = { pcall(profs) }
      if r[1] then
        for j = 2, table.maxn(r) do
          if r[j] then
            local ok, name, _, rang, max = pcall(pinfo, r[j])
            if ok then dazu(name, rang, max) end
          end
        end
      end
    end
  end
  if next(raus) == nil then
    anzahlF, infoF = WW.Alt("GetNumSkillLines"), WW.Alt("GetSkillLineInfo")
    if anzahlF and infoF then
      local ok, n = pcall(anzahlF)
      for i = 1, (ok and tonumber(n) or 0) do
        local ok2, name, kopf, _, rang, _, _, max = pcall(infoF, i)
        if ok2 and not kopf then dazu(name, rang, max) end
      end
    end
  end
  return raus
end

-- Name eines Items: deutsch aus dem Spiel, sonst aus dem Zwischenspeicher, sonst englisch aus den Daten.
-- Gibt name, istDeutsch zurück.
function WW.ItemName(id)
  id = tonumber(id)
  if not id then return nil end
  local name = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or WW.GetItemInfo(id)
  if name then
    if WW.db then WW.db.namen[id] = name end
    return name, true
  end
  if WW.db and WW.db.namen[id] then return WW.db.namen[id], true end
  local fdb = WW.quelle.fdb
  local en = fdb and fdb.searchItemNames and fdb.searchItemNames[id]
  if en then return en, false end
  return nil
end

-- Item-ID aus einem Link oder einer Zahl.
function WW.ItemID(linkOderID)
  if type(linkOderID) == "number" then return linkOderID end
  if type(linkOderID) ~= "string" then return nil end
  return tonumber(linkOderID:match("item:(%d+)")) or tonumber(linkOderID)
end

-- Händler-Verkaufspreis (Kupfer) oder nil, wenn das Spiel das Item noch nicht kennt.
function WW.HaendlerPreis(id)
  local preis = select(11, WW.GetItemInfo(id))
  return preis
end

---------------------------------------------------------------------------
-- Befehle: /ww und /wegweiser
-- Module melden Unterbefehle an: WW:Befehl("scan", "Auktionshaus scannen", function(rest) end)
---------------------------------------------------------------------------
WW.befehle = {}
function WW:Befehl(wort, hilfe, fn)
  WW.befehle[wort] = { hilfe = hilfe, fn = fn }
end

SLASH_WEGWEISER1 = "/ww"
SLASH_WEGWEISER2 = "/wegweiser"
SlashCmdList.WEGWEISER = function(text)
  text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local wort, rest = text:match("^(%S+)%s*(.*)$")
  wort = wort and wort:lower()
  if not wort then
    WW:Umschalten()
    return
  end
  local b = WW.befehle[wort]
  if b then
    b.fn(rest)
  else
    WW:Print("Befehle:")
    print("  /ww - Fenster auf/zu")
    local w = {}
    for k in pairs(WW.befehle) do w[#w + 1] = k end
    table.sort(w)
    for _, k in ipairs(w) do print("  /ww " .. k .. " - " .. WW.befehle[k].hilfe) end
  end
end

-- Tastenbelegung (Bindings.xml)
BINDING_HEADER_WEGWEISER = "Wegweiser"
BINDING_NAME_WEGWEISER_FENSTER = "Fenster öffnen/schließen"
BINDING_NAME_WEGWEISER_DUNGEONKARTE = "Dungeon-Karte öffnen/schließen"
BINDING_NAME_WEGWEISER_ITEMINFO = "Mehr Information zum Item unter der Maus"
