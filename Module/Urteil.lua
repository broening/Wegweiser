-- Wegweiser: Urteil "Behalten oder Müll?" für jedes Item, immer mit Grund.
-- Reihenfolge (das erste, was passt, gewinnt):
--   1. Gemerkt     – du hast es mit Alt+Rechtsklick geschützt
--   2. Quest       – Quest im Questlog, Item startet eine Quest, oder (Haken) Quest in deiner Stufe (± Spanne)
--   3. Beruf       – Rezept für deinen Beruf, das du noch nicht kennst; Zutat für ein Rezept, das noch Punkte gibt
--   4. Müll        – seelengebunden und deine Klasse kann es nie tragen; Rezept schon bekannt und AH lohnt nicht
--   sonst nil      – dann entscheidet das Auktionshaus-Modul (AH lohnt / knapp / Händler)
-- Im Zweifel bleibt ein Item: ohne Daten gibt es kein "Müll".
-- Gelernte Rezepte: beim Öffnen eines Berufsfensters in WW.charDb.rezepte[Beruf (englisch)] = { s = {[Zauber] = Name}, t }.
-- Öffentlich: WW.Urteil.Pruefen(id, anzahl, gebunden) -> { gruppe, schutz, text, kurz, farbe, rand } oder nil
--             WW.Urteil.Merken(id) (umschalten), WW.Urteil.Knopf(button, bag, slot, id) (Zeichen am Taschenplatz)
local ADDON, WW = ...
local UI = WW.UI

WW.standardDB.urteil = {
  tooltip = true,    -- Zeile im Tooltip
  zeichen = true,    -- Buchstabe in der Ecke des Taschenplatzes
  quest = true,      -- Quest-Items behalten
  kommende = true,   -- auch für Quests, die du noch nicht hast (Stufe ± spanne)
  spanne = 5,
  beruf = true,      -- Zutaten für Rezepte, die noch Punkte geben
  fremde = true,     -- auch Rezepte, die du noch nicht gelernt hast (aber schon lernen kannst)
  rezepte = true,    -- Rezept-Items für deinen Beruf behalten, solange du sie nicht kennst
  muell = true,      -- "Müll": gebunden und deine Klasse kann es nie tragen; bekanntes Rezept
  alt = true,        -- Alt+Rechtsklick merkt ein Item
  twinks = true,     -- an Twinks denken (Module\Twinks.lua)
  entzaubern = true, -- mit Verzauberkunst: Entzaubern vorschlagen, wenn die Materialien mehr bringen
  loeschen = true,   -- Knopf an der Tasche: billigsten Müll löschen (Module\Muell.lua)
  merken = {},       -- [itemID] = true
}
WW.standardCharDB.rezepte = {}

local U = {}
WW.Urteil = U

local LEER = {}
local GRUPPE = {
  merken = { farbe = "gruen",  zeichen = "+", rgb = { 0.25, 1, 0.25 } },
  quest  = { farbe = "gelb",   zeichen = "Q", rgb = { 1, 0.82, 0 } },
  beruf  = { farbe = "ff66b3ff", zeichen = "B", rgb = { 0.4, 0.7, 1 } },
  twink  = { farbe = "orange", zeichen = "T", rgb = { 1, 0.6, 0.2 } },
  entzaubern = { farbe = "ffb380ff", zeichen = "E", rgb = { 0.7, 0.5, 1 } },
  muell  = { farbe = "grau",   zeichen = nil, rgb = { 0.6, 0.6, 0.6 } },
}
U.GRUPPE = GRUPPE

local function pass(ok, ...) if ok then return ... end end
local function try(f, ...)
  if type(f) ~= "function" then return nil end
  return pass(pcall(f, ...))
end
local function einst() return WW.db and WW.db.urteil end
local function fdb() return WW.quelle and WW.quelle.fdb or LEER end
local function tab(t) return type(t) == "table" and t or LEER end

---------------------------------------------------------------------------
-- Stand: jede Änderung (Questlog, Fertigkeit, Rezepte, Merkliste) macht den Zwischenspeicher ungültig
---------------------------------------------------------------------------
local stand = 1
local cache = {}        -- [itemID] = { stand, ergebnis (ohne "Müll"), oder false }
function U.Stand() return stand end
local function neuerStand()
  stand = stand + 1
  cache = {}
  if WW.AH and WW.AH.TaschenPlanen then WW.AH.TaschenPlanen() end
end
U.NeuerStand = neuerStand

-- Eigene Berufe (englisch) -> Fertigkeit. Kurz zwischengespeichert, Fertigkeiten lesen kostet.
local berufeCache, berufeStand
local function eigeneBerufe()
  if berufeCache and berufeStand == stand then return berufeCache end
  local f = WW.Handwerk and WW.Handwerk.EigeneBerufe
  berufeCache = f and try(f) or {}
  berufeStand = stand
  return berufeCache
end

---------------------------------------------------------------------------
-- Rezept-Verzeichnis (einmal gebaut): Zutat -> Rezepte, Rezept-Item -> Rezept, Zauber/Produkt -> Rezept
---------------------------------------------------------------------------
local zutatIdx, rezeptItemIdx, zauberIdx, produktIdx
local function verzeichnis()
  if zutatIdx then return end
  zutatIdx, rezeptItemIdx, zauberIdx, produktIdx = {}, {}, {}, {}
  for beruf, liste in pairs(tab(fdb().recipes)) do
    if type(liste) == "table" then
      for _, row in ipairs(liste) do
        if type(row) == "table" then
          local e = { beruf = beruf, row = row }
          local zauber, produkt = tonumber(row[1]), tonumber(row[7])
          if zauber then zauberIdx[zauber] = e end
          if produkt then
            produktIdx[produkt] = produktIdx[produkt] or {}
            table.insert(produktIdx[produkt], e)
          end
          if type(row[9]) == "string" then
            for it in row[9]:gmatch("(%d+):%d+") do
              it = tonumber(it)
              zutatIdx[it] = zutatIdx[it] or {}
              table.insert(zutatIdx[it], e)
            end
          end
          local lern = type(row[10]) == "string" and tonumber(row[10]:match("^i(%d+)"))
          if lern then rezeptItemIdx[lern] = e end
        end
      end
    end
  end
end
-- Rezepte, die das Item als Zutat brauchen: { {beruf, row} } (für Module\Twinks.lua)
function U.RezepteMit(id)
  verzeichnis()
  return zutatIdx[tonumber(id)] or LEER
end

-- Nach neuen Rezept-Daten (Tests) neu bauen
function U.VerzeichnisNeu()
  zutatIdx = nil
  neuerStand()
end

-- Kennt der Charakter das Rezept? true / false / nil (Berufsfenster noch nie geöffnet)
local function bekannt(beruf, zauber)
  local r = WW.charDb and WW.charDb.rezepte and WW.charDb.rezepte[beruf]
  if type(r) ~= "table" or type(r.s) ~= "table" then return nil end
  return r.s[zauber] ~= nil
end

local function rezeptName(e)
  local zauber = tonumber(e.row[1])
  local r = WW.charDb and WW.charDb.rezepte and WW.charDb.rezepte[e.beruf]
  local n = r and type(r.s) == "table" and r.s[zauber]
  if type(n) == "string" and n ~= "" then return n end
  return (zauber and WW.SpellName(zauber)) or tostring(e.row[2] or "?")
end

local function berufDe(en) return (WW.beruf and WW.beruf[en]) or en end

---------------------------------------------------------------------------
-- Berufsfenster lesen: welche Rezepte kennt der Charakter?
---------------------------------------------------------------------------
local function zauberAusLink(link)
  if type(link) ~= "string" then return nil end
  return tonumber(link:match("enchant:(%d+)") or link:match("spell:(%d+)"))
end

-- Speichert gefundene Rezepte. eintraege = { {zauber, produkt, name} }, berufName = deutscher Name aus dem Spiel
local function rezepteSpeichern(berufName, eintraege)
  verzeichnis()
  local en = WW.berufEn and WW.berufEn[berufName] or ((WW.beruf and WW.beruf[berufName]) and berufName)
  local gefunden, stimmen = {}, {}
  for _, x in ipairs(eintraege) do
    local e = x.zauber and zauberIdx[x.zauber]
    -- Ersatz über das Produkt, nur wenn genau ein Rezept (des Berufs) es herstellt
    if not e and x.produkt then
      local treffer = 0
      for _, k in ipairs(produktIdx[x.produkt] or LEER) do
        if not en or k.beruf == en then e, treffer = k, treffer + 1 end
      end
      if treffer ~= 1 then e = nil end
    end
    if e then
      gefunden[#gefunden + 1] = { e = e, name = x.name }
      stimmen[e.beruf] = (stimmen[e.beruf] or 0) + 1
    end
  end
  if not en then   -- Name unbekannt: der Beruf, zu dem die meisten Rezepte gehören
    local best = 0
    for b, n in pairs(stimmen) do if n > best then en, best = b, n end end
  end
  if not en or #gefunden == 0 or not WW.charDb then return 0 end
  WW.charDb.rezepte = type(WW.charDb.rezepte) == "table" and WW.charDb.rezepte or {}
  local r = WW.charDb.rezepte[en]
  if type(r) ~= "table" or type(r.s) ~= "table" then r = { s = {} }; WW.charDb.rezepte[en] = r end
  local neu = 0
  for _, g in ipairs(gefunden) do
    if g.e.beruf == en then
      local z = tonumber(g.e.row[1])
      if z and r.s[z] == nil then neu = neu + 1 end
      if z then r.s[z] = type(g.name) == "string" and g.name or true end
    end
  end
  r.t = time and time() or 0
  if neu > 0 then
    neuerStand()
    if WW.Twinks and WW.Twinks.Speichern then pcall(WW.Twinks.Speichern) end
  end
  return neu
end

local function scanAlt()
  local eintraege = {}
  local zeile, anzahl, info = WW.Alt("GetTradeSkillLine"), WW.Alt("GetNumTradeSkills"), WW.Alt("GetTradeSkillInfo")
  if zeile and anzahl and info then
    local name = try(zeile)
    for i = 1, tonumber(try(anzahl)) or 0 do
      local n, typ = try(info, i)
      if n and typ ~= "header" and typ ~= "subheader" then
        local z = zauberAusLink(try(WW.Alt("GetTradeSkillRecipeLink"), i))
        local p = WW.ItemID(try(WW.Alt("GetTradeSkillItemLink"), i))
        eintraege[#eintraege + 1] = { zauber = z, produkt = p, name = n }
      end
    end
    if name and #eintraege > 0 then rezepteSpeichern(name, eintraege) end
  end
  eintraege = {}
  zeile, anzahl, info = WW.Alt("GetCraftDisplaySkillLine"), WW.Alt("GetNumCrafts"), WW.Alt("GetCraftInfo")
  if zeile and anzahl and info then
    local name = try(zeile)
    for i = 1, tonumber(try(anzahl)) or 0 do
      local n, _, typ = try(info, i)
      if n and typ ~= "header" and typ ~= "subheader" then
        local z = zauberAusLink(try(WW.Alt("GetCraftRecipeLink"), i)) or zauberAusLink(try(WW.Alt("GetCraftItemLink"), i))
        eintraege[#eintraege + 1] = { zauber = z, name = n }
      end
    end
    if name and #eintraege > 0 then rezepteSpeichern(name, eintraege) end
  end
end

-- Neuere Clients: C_TradeSkillUI
local function scanNeu()
  local T = C_TradeSkillUI
  if type(T) ~= "table" or type(T.GetAllRecipeIDs) ~= "function" or type(T.GetRecipeInfo) ~= "function" then return end
  local name
  local b = try(T.GetBaseProfessionInfo)
  if type(b) == "table" then name = b.professionName end
  if not name then
    local c = try(T.GetChildProfessionInfo)
    if type(c) == "table" then name = c.parentProfessionName or c.professionName end
  end
  local eintraege = {}
  for _, id in ipairs(tab(try(T.GetAllRecipeIDs))) do
    local info = try(T.GetRecipeInfo, id)
    if type(info) == "table" and info.learned then
      eintraege[#eintraege + 1] = { zauber = tonumber(id), name = info.name }
    end
  end
  if #eintraege > 0 then rezepteSpeichern(name or "", eintraege) end
end

function U.BerufsfensterLesen()
  pcall(scanAlt)
  pcall(scanNeu)
end

for _, ev in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE", "CRAFT_SHOW", "CRAFT_UPDATE",
  "TRADE_SKILL_LIST_UPDATE", "NEW_RECIPE_LEARNED" }) do
  WW:Event(ev, function()
    if C_Timer and C_Timer.After then C_Timer.After(0.2, U.BerufsfensterLesen) else U.BerufsfensterLesen() end
  end)
end
for _, ev in ipairs({ "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "SKILL_LINES_CHANGED", "PLAYER_LEVEL_UP" }) do
  WW:Event(ev, function() neuerStand() end)
end

---------------------------------------------------------------------------
-- Die einzelnen Prüfungen
---------------------------------------------------------------------------
local function questStufe(q)
  local s = tab(fdb().qcQuests)[q]
  if type(s) ~= "string" then return nil end
  local stufe, min = s:match("^[^|]*|(%-?%d*)|(%d*)")
  return tonumber(stufe), tonumber(min)
end

local function questPruefen(id, db)
  local QW = WW.QW
  if not (db.quest and QW and QW.ItemQuests) then return nil end
  local ok, liste = pcall(QW.ItemQuests, id)
  if not ok or type(liste) ~= "table" then return nil end
  local kurzName = not (WW.db.quests and WW.db.quests.itemTipp)   -- ohne Quest-Zeilen: Namen hier zeigen
  -- Questname aus dem Text von QW.ItemQuests ("Quest: X – im Questlog", "Startet Quest: X", "Für Quest: X (...)")
  local function name(q)
    for _, e in ipairs(liste) do
      if e.q == q and type(e.text) == "string" then
        return e.text:match("^Quest: (.-) –") or e.text:match("^Startet Quest: (.+)$") or e.text:match("^Für Quest: (.-) %(")
      end
    end
    return nil
  end
  for _, e in ipairs(liste) do
    if e.status == "log" then
      local n = kurzName and name(e.q)
      return { gruppe = "quest", kurz = "Quest im Questlog", text = "Quest im Questlog" .. (n and (": " .. n) or "") }
    end
  end
  for _, e in ipairs(liste) do
    if e.status == "start" then
      local n = kurzName and name(e.q)
      return { gruppe = "quest", kurz = "startet eine Quest", text = "startet eine Quest" .. (n and (": " .. n) or "") }
    end
  end
  if db.kommende then
    local mein = tonumber(UnitLevel and UnitLevel("player")) or 1
    local spanne = tonumber(db.spanne) or 5
    local gone = tab(fdb().qcGone)
    for _, e in ipairs(liste) do
      if e.status == "offen" and not gone[e.q] then
        local st, min = questStufe(e.q)
        if st and st > 0 and math.abs(st - mein) <= spanne and (min or 0) <= mein + spanne then
          local n = name(e.q)
          return { gruppe = "quest", kurz = "für eine Quest in deiner Stufe",
            text = "gebraucht für " .. (n and ("\"" .. n .. "\" ") or "eine Quest ") .. "(Stufe " .. st .. ")" }
        end
      end
    end
  end
  return nil
end

-- Steht "Bereits bekannt" im Tooltip? Dann merken (gilt für Rezept-Items).
local function tooltipSagtBekannt(tt)
  local muster = rawget(_G, "ITEM_SPELL_KNOWN")
  if type(muster) ~= "string" or not tt or not tt.GetName or not tt.NumLines then return false end
  local name = tt:GetName()
  if not name then return false end
  for i = 1, tonumber(tt:NumLines()) or 0 do
    local fs = rawget(_G, name .. "TextLeft" .. i)
    local t = fs and fs.GetText and fs:GetText()
    if t == muster then return true end
  end
  return false
end

local function berufPruefen(id, db)
  if not (db.beruf or db.rezepte) then return nil end
  verzeichnis()
  local eigene = eigeneBerufe()
  -- Rezept-Item für deinen Beruf
  local r = rezeptItemIdx[id]
  if r and db.rezepte and eigene[r.beruf] then
    local kennt = bekannt(r.beruf, tonumber(r.row[1]))
    if kennt == true then return nil end   -- bekannt: entscheidet die Müll-Prüfung / das AH
    local rang, braucht = eigene[r.beruf], tonumber(r.row[3]) or 0
    local ab = (braucht > rang) and (" (ab Fertigkeit " .. braucht .. ")") or ""
    if kennt == false then
      return { gruppe = "beruf", kurz = "Rezept, noch nicht gelernt", text = "Rezept für " .. berufDe(r.beruf) .. ", noch nicht gelernt" .. ab }
    end
    return { gruppe = "beruf", kurz = "Rezept für deinen Beruf",
      text = "Rezept für " .. berufDe(r.beruf) .. ab .. " – Berufsfenster einmal öffnen, dann weiß Wegweiser, ob du es kennst" }
  end
  if not db.beruf then return nil end
  -- Zutat: ein Rezept deines Berufs, das noch Punkte gibt (Fertigkeit unter "grau")
  local bestBekannt, bestFremd
  for _, e in ipairs(zutatIdx[id] or LEER) do
    local rang = eigene[e.beruf]
    local grau = tonumber(e.row[6]) or 0
    if rang and rang < grau then
      local kennt = bekannt(e.beruf, tonumber(e.row[1]))
      if kennt == true then
        if not bestBekannt or grau < (tonumber(bestBekannt.row[6]) or 0) then bestBekannt = e end
      elseif db.fremde and (tonumber(e.row[3]) or 0) <= rang then
        if not bestFremd or grau < (tonumber(bestFremd.row[6]) or 0) then bestFremd = e end
      end
    end
  end
  if bestBekannt then
    return { gruppe = "beruf", kurz = "Zutat, ein bekanntes Rezept gibt noch Punkte",
      text = "Zutat: \"" .. rezeptName(bestBekannt) .. "\" (" .. berufDe(bestBekannt.beruf) .. ") gibt noch Punkte" }
  end
  if bestFremd then
    local kennt = bekannt(bestFremd.beruf, tonumber(bestFremd.row[1]))
    return { gruppe = "beruf", kurz = "Zutat für ein Rezept, das noch Punkte gibt",
      text = "Zutat: \"" .. rezeptName(bestFremd) .. "\" (" .. berufDe(bestFremd.beruf) .. ") gibt noch Punkte"
        .. (kennt == false and ", noch nicht gelernt" or "") }
  end
  return nil
end

-- Müll: hängt vom Platz ab (gebunden), darum nicht im Zwischenspeicher.
local kannCache = {}
local function muellPruefen(id, anzahl, gebunden, db)
  if not db.muell then return nil end
  local QW = WW.QW
  if gebunden and QW and QW.KannTragen then
    local c = kannCache[id]
    if c == nil then
      local ok, kann, warum = pcall(QW.KannTragen, id)
      c = (ok and kann == false) and (warum or "deine Klasse kann es nicht tragen") or false
      -- Daten noch nicht geladen (nil): nicht merken, später noch einmal fragen
      if ok and kann ~= nil then kannCache[id] = c end
    end
    if c then return { gruppe = "muell", kurz = "Klasse kann es nicht tragen", text = c .. ", seelengebunden" } end
  end
  verzeichnis()
  local r = rezeptItemIdx[id]
  -- Bekanntes Rezept ist nur gebunden Müll. Ungebunden entscheidet das AH (Händler-Knopf: Haken "rote" mit Verlauf).
  if gebunden and r and bekannt(r.beruf, tonumber(r.row[1])) == true then
    return { gruppe = "muell", kurz = "Rezept schon bekannt", text = "Rezept schon bekannt, seelengebunden" }
  end
  return nil
end

-- Für Twinks (nur ungebunden, sonst geht es nicht per Post)
local function twinkPruefen(id, gebunden, db)
  if gebunden or not db.twinks or not (WW.Twinks and WW.Twinks.Brauchen) then return nil end
  local ok, liste = pcall(WW.Twinks.Brauchen, id)
  if not ok or not liste then return nil end
  local t = {}
  for i, x in ipairs(liste) do
    if i > 3 then t[#t + 1] = "..." break end
    local b = {}
    for _, en in ipairs(x.berufe) do b[#b + 1] = berufDe(en) end
    t[#t + 1] = x.name .. " (" .. table.concat(b, ", ") .. ")"
  end
  return { gruppe = "twink", kurz = "für " .. liste[1].name, twinks = liste,
    text = "für Twinks: " .. table.concat(t, ", ") .. " – per Post schicken" }
end

-- Entzaubern lohnt mehr als Verkaufen (nur mit Verzauberkunst und genug Fertigkeit)
local function entzauberPruefen(id, anzahl, gebunden, db)
  local E = WW.Entzaubern
  if not db.entzaubern or not E then return nil end
  local okK, kann = pcall(E.Kann, id, eigeneBerufe())
  if not okK or not kann then return nil end
  local okW, wert = pcall(E.Wert, id)
  if not okW or not wert or wert <= 0 then return nil end
  local _, _, _, _, _, _, _, _, _, _, verkauf = WW.GetItemInfo(id)
  local haendler = (tonumber(verkauf) or 0) * (anzahl or 1)
  local ah = 0
  if not gebunden and WW.AH and WW.AH.Bewertung then
    local farbe, _, erloes = WW.AH.Bewertung(id, anzahl, false)
    if farbe ~= "grau" then ah = tonumber(erloes) or 0 end
  end
  if wert * (anzahl or 1) <= math.max(haendler, ah) then return nil end
  local vergleich = (ah > 0) and ("AH %s, Händler %s"):format(WW.Geld(ah), WW.Geld(haendler)) or ("Händler " .. WW.Geld(haendler))
  return { gruppe = "entzaubern", kurz = "Entzaubern bringt mehr", wert = wert,
    text = "entzaubern, ~" .. WW.Geld(wert) .. " (" .. vergleich .. ")" }
end

local function fertig(e, schutz)
  if not e then return nil end
  local g = GRUPPE[e.gruppe]
  e.schutz = schutz
  e.farbe = g and g.farbe or "weiss"
  e.rand = (e.gruppe == "muell") and "rot" or nil
  return e
end

-- Das Urteil für ein Item. anzahl und gebunden kommen vom Taschenplatz (sonst 1 / false).
function U.Pruefen(id, anzahl, gebunden)
  id = tonumber(id)
  local db = einst()
  if not id or not db then return nil end
  if type(db.merken) == "table" and db.merken[id] then
    return fertig({ gruppe = "merken", kurz = "von dir gemerkt", text = "von dir gemerkt (Alt+Rechtsklick gibt es frei)" }, true)
  end
  local c = cache[id]
  local e
  if c and c[1] == stand then
    e = c[2] or nil
  else
    e = questPruefen(id, db) or berufPruefen(id, db)
    cache[id] = { stand, e or false }
  end
  if e then return fertig(e, true) end
  gebunden = gebunden and true or false
  e = twinkPruefen(id, gebunden, db) or entzauberPruefen(id, anzahl or 1, gebunden, db)
  if e then return fertig(e, true) end
  return fertig(muellPruefen(id, anzahl or 1, gebunden, db), false)
end

-- Ist das Item geschützt (Händler-Knopf, AH-Farben)?
function U.Geschuetzt(id)
  local e = U.Pruefen(id)
  return e and e.schutz or false
end

---------------------------------------------------------------------------
-- Merkliste
---------------------------------------------------------------------------
function U.Merken(id, an)
  id = tonumber(id)
  local db = einst()
  if not id or not db then return end
  db.merken = type(db.merken) == "table" and db.merken or {}
  if an == nil then an = not db.merken[id] end
  db.merken[id] = an and true or nil
  local name = WW.ItemName(id) or ("Item " .. id)
  WW:Print(an and (WW.f("gruen", "Gemerkt: ") .. name .. " – wird nie verkauft.")
    or (WW.f("gelb", "Freigegeben: ") .. name))
  neuerStand()
end

function U.MerkAnzahl()
  local n = 0
  for _ in pairs(tab(einst() and einst().merken)) do n = n + 1 end
  return n
end

function U.MerkenLeeren()
  local db = einst()
  if db then db.merken = {} end
  neuerStand()
end

WW:Befehl("merken", "Merkliste: /ww merken leeren", function(arg)
  if arg == "leeren" then
    U.MerkenLeeren()
    WW:Print("Merkliste geleert.")
  else
    WW:Print(("%d Items gemerkt. Alt+Rechtsklick auf ein Item in der Tasche merkt es oder gibt es frei."):format(U.MerkAnzahl()))
  end
end)

-- Fehlersuche im Spiel: /ww urteil [Item-Link oder ID] (ohne Angabe: Item unter der Maus)
WW:Befehl("urteil", "Fehlersuche: Urteil für ein Item (Link, ID oder Item unter der Maus)", function(arg)
  local id = WW.ItemID(arg) or tonumber(arg)
  if not id and GameTooltip and GameTooltip.GetItem then
    local _, link = GameTooltip:GetItem()
    id = WW.ItemID(link)
  end
  if not id then WW:Print("Kein Item. Beispiel: /ww urteil 3575") return end
  local db = einst()
  local an = {}
  for _, k in ipairs({ "tooltip", "quest", "kommende", "beruf", "fremde", "rezepte", "muell" }) do
    an[#an + 1] = k .. "=" .. tostring(db and db[k])
  end
  WW:Print("Urteil für " .. tostring(WW.ItemName(id)) .. " (" .. id .. "), Stand " .. stand)
  print("  " .. table.concat(an, " "))
  local QW = WW.QW
  local ok, liste, gesamt = pcall(function() return QW.ItemQuests(id) end)
  if ok then
    print("  Quests: " .. tostring(gesamt) .. ", " .. (type(liste) == "table" and #liste or 0) .. " Einträge")
    for i, e in ipairs(type(liste) == "table" and liste or LEER) do
      if i <= 3 then print("    " .. tostring(e.status) .. " " .. tostring(e.q) .. " " .. tostring(e.text)) end
    end
  else
    print("  Quests: FEHLER " .. tostring(liste))
  end
  local okB, berufe = pcall(eigeneBerufe)
  local b = {}
  for k, v in pairs(okB and type(berufe) == "table" and berufe or LEER) do b[#b + 1] = k .. " " .. tostring(v) end
  print("  Berufe: " .. (okB and table.concat(b, ", ") or ("FEHLER " .. tostring(berufe))))
  local n = 0
  for _, r in pairs(tab(WW.charDb and WW.charDb.rezepte)) do for _ in pairs(tab(r.s)) do n = n + 1 end end
  print("  Gelernte Rezepte gespeichert: " .. n)
  local tb = debugstack and function(e) return tostring(e) .. "\n" .. debugstack(2) end or tostring
  local okP, e = xpcall(function() return U.Pruefen(id) end, tb)
  if not okP then
    print("  Pruefen: FEHLER " .. tostring(e))
  elseif e then
    print("  Pruefen: " .. tostring(e.gruppe) .. " – " .. tostring(e.text))
  else
    print("  Pruefen: nichts (das AH entscheidet)")
  end
end)

---------------------------------------------------------------------------
-- Taschenplätze: Zeichen in der Ecke und Alt+Rechtsklick (ruft Auktion.lua beim Aktualisieren der Taschen)
---------------------------------------------------------------------------
local zeichen = setmetatable({}, { __mode = "k" })
local gehakt = setmetatable({}, { __mode = "k" })

local function platzVon(button)
  local bag = button.GetBagID and try(button.GetBagID, button)
  if not bag then
    local eltern = button.GetParent and button:GetParent()
    bag = eltern and eltern.GetID and eltern:GetID()
  end
  local slot = button.GetID and button:GetID()
  return bag, slot
end

local function itemAmPlatz(bag, slot)
  if not bag or not slot or slot < 1 then return nil end
  if C_Container and C_Container.GetContainerItemInfo then
    local info = try(C_Container.GetContainerItemInfo, bag, slot)
    if type(info) == "table" then return tonumber(info.itemID), info.stackCount, info.isBound end
    return nil
  end
  local alt = WW.Alt("GetContainerItemInfo")
  if alt then
    local _, anz, _, _, _, _, link, _, _, id, geb = try(alt, bag, slot)
    return tonumber(id) or WW.ItemID(link), anz, geb
  end
end

function U.Knopf(button, id, anzahl, gebunden)
  if not button then return end
  local db = einst() or LEER
  if not gehakt[button] and button.HookScript then
    gehakt[button] = true
    pcall(button.HookScript, button, "OnClick", function(self, maus)
      local d = einst()
      if maus ~= "RightButton" or not (d and d.alt) or not (IsAltKeyDown and IsAltKeyDown()) then return end
      local b, s = platzVon(self)
      local iid = itemAmPlatz(b, s)
      if iid then U.Merken(iid) end
    end)
  end
  local fs = zeichen[button]
  local e = (db.zeichen and id) and U.Pruefen(id, anzahl, gebunden) or nil
  local g = e and GRUPPE[e.gruppe]
  if not (g and g.zeichen) then
    if fs then fs:Hide() end
    return
  end
  if not fs then
    fs = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", 2, -2)
    zeichen[button] = fs
  end
  fs:SetText(g.zeichen)
  fs:SetTextColor(g.rgb[1], g.rgb[2], g.rgb[3])
  fs:Show()
end

---------------------------------------------------------------------------
-- Tooltip: "Behalten: Quest im Questlog" / "Müll: ..."
---------------------------------------------------------------------------
local gesehen = setmetatable({}, { __mode = "k" })

-- Platz unter der Maus (Taschen): anzahl, gebunden
local function platzVomTooltip(tt, id)
  local owner = tt.GetOwner and tt:GetOwner()
  if not owner or not owner.GetID then return 1, false end
  local bag, slot = platzVon(owner)
  local iid, anz, geb = itemAmPlatz(bag, slot)
  if iid == id then return anz or 1, geb and true or false end
  return 1, false
end

function U.TooltipZeilen(tt, data)
  local db = einst()
  if not db or not db.tooltip then return end
  if tt ~= GameTooltip and tt ~= ItemRefTooltip then return end
  local id = data and tonumber(data.id)
  if not id and tt.GetItem then
    local _, link = tt:GetItem()
    id = WW.ItemID(link)
  end
  if not id or gesehen[tt] == id then return end
  gesehen[tt] = id
  -- "Bereits bekannt" im Tooltip eines Rezepts: als gelernt speichern
  verzeichnis()
  local r = rezeptItemIdx[id]
  if r and bekannt(r.beruf, tonumber(r.row[1])) ~= true and tooltipSagtBekannt(tt) and WW.charDb then
    WW.charDb.rezepte = type(WW.charDb.rezepte) == "table" and WW.charDb.rezepte or {}
    local t = WW.charDb.rezepte[r.beruf]
    if type(t) ~= "table" or type(t.s) ~= "table" then t = { s = {} }; WW.charDb.rezepte[r.beruf] = t end
    t.s[tonumber(r.row[1])] = true
    neuerStand()
  end
  local okP, anz, geb = pcall(platzVomTooltip, tt, id)
  if not okP then anz, geb = 1, false end
  local e = U.Pruefen(id, anz, geb)
  if not e then return end
  local wort = e.schutz and "Behalten" or "Müll"
  tt:AddLine(WW.f("titel", "Wegweiser: ") .. WW.f(e.farbe, wort .. " – " .. e.text), 1, 1, 1, true)
  if e.gruppe == "entzaubern" and WW.Entzaubern then
    for _, z in ipairs(WW.Entzaubern.Zeilen(id)) do tt:AddLine("    " .. z, 0.75, 0.75, 0.75) end
    tt:AddLine("    (Classic-Tabelle, ungefähr; Preise aus deinem AH-Scan)", 0.5, 0.5, 0.5)
  end
  if tt.Show then tt:Show() end
end

local function tooltipsAnschliessen()
  local ueberDaten = false
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType
     and Enum.TooltipDataType.Item then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data)
      pcall(U.TooltipZeilen, tt, data)
    end)
    ueberDaten = true
  end
  for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
    if tt and tt.HookScript then
      if not ueberDaten then
        pcall(tt.HookScript, tt, "OnTooltipSetItem", function(self) pcall(U.TooltipZeilen, self) end)
      end
      pcall(tt.HookScript, tt, "OnTooltipCleared", function(self) gesehen[self] = nil end)
    end
  end
end
WW:BeimStart(tooltipsAnschliessen)

---------------------------------------------------------------------------
-- Reiter "Taschen": alles in deinen Taschen nach Gruppe, mit Grund; daneben die Schalter
---------------------------------------------------------------------------
local REIHE = { merken = 1, quest = 2, beruf = 3, twink = 4, entzaubern = 5, ah = 6, knapp = 7, haendler = 8, muell = 9 }
local REIHE_TITEL = { merken = "Gemerkt", quest = "Quest", beruf = "Beruf", twink = "Für Twinks", entzaubern = "Entzaubern",
  ah = "Auktionshaus", knapp = "Auktionshaus knapp", haendler = "Händler", muell = "Müll" }
local REIHE_FARBE = { merken = "gruen", quest = "gelb", beruf = "ff66b3ff", twink = "orange", entzaubern = "ffb380ff",
  ah = "gruen", knapp = "gelb", haendler = "rot", muell = "grau" }

U.REIHE, U.REIHE_TITEL, U.REIHE_FARBE = REIHE, REIHE_TITEL, REIHE_FARBE

-- Gruppe und Grund für ein Item: erst das Urteil (Quest, Beruf, Müll ...), sonst die AH-Bewertung.
-- Gibt gruppe (Schlüssel in REIHE) und grund zurück, oder nil.
function U.Einordnen(id, anzahl, gebunden)
  local e = U.Pruefen(id, anzahl, gebunden)
  if e then return e.gruppe, e.text end
  local farbe, kurz = "grau", nil
  if WW.AH and WW.AH.Bewertung then farbe, kurz = WW.AH.Bewertung(id, anzahl, gebunden) end
  local gruppe = (farbe == "gruen" and "ah") or (farbe == "gelb" and "knapp") or (farbe == "rot" and "haendler") or nil
  return gruppe, kurz
end

function U.TaschenListe()
  local raus = {}
  local taschen = (WW.TaschenIDs and try(WW.TaschenIDs)) or { 0, 1, 2, 3, 4 }
  local slots = (C_Container and C_Container.GetContainerNumSlots) or WW.Alt("GetContainerNumSlots")
  local summe = {}
  for _, bag in ipairs(taschen) do
    for slot = 1, tonumber(try(slots, bag)) or 0 do
      local id, anz, geb = itemAmPlatz(bag, slot)
      if id then
        local e = U.Pruefen(id, anz, geb)
        local gruppe, grund
        if e then
          gruppe, grund = e.gruppe, e.text
        else
          local farbe, kurz = "grau", nil
          if WW.AH and WW.AH.Bewertung then farbe, kurz = WW.AH.Bewertung(id, anz, geb) end
          gruppe = (farbe == "gruen" and "ah") or (farbe == "gelb" and "knapp") or (farbe == "rot" and "haendler") or nil
          grund = kurz
        end
        if gruppe then
          local schluessel = gruppe .. ":" .. id
          local x = summe[schluessel]
          if x then
            x.anzahl = x.anzahl + (anz or 1)
          else
            x = { id = id, anzahl = anz or 1, gruppe = gruppe, grund = grund or "" }
            summe[schluessel] = x
            raus[#raus + 1] = x
          end
        end
      end
    end
  end
  table.sort(raus, function(a, b)
    if REIHE[a.gruppe] ~= REIHE[b.gruppe] then return REIHE[a.gruppe] < REIHE[b.gruppe] end
    return a.id < b.id
  end)
  -- Überschriften einfügen
  local mitKopf, letzte = {}, nil
  for _, x in ipairs(raus) do
    if x.gruppe ~= letzte then
      mitKopf[#mitKopf + 1] = { kopf = true, gruppe = x.gruppe }
      letzte = x.gruppe
    end
    mitKopf[#mitKopf + 1] = x
  end
  return mitKopf
end

-- Unterreiter "Behalten" in den Einstellungen. Die Liste "Behalten oder weg?" steht im Reiter Inventar
-- (Knopf "Spalten: Behalten?"), dort mit Klick auf die Item-Details.
WW:Reiter("behalten", "Behalten", 3, function(p)
  local db = einst()
  local LINKS = 440
  local titel = UI.Text(p, "gross")
  titel:SetPoint("TOPLEFT", 4, -4)
  titel:SetText("Behalten oder weg?")

  local function neu() neuerStand() if WW.Inventar and WW.Inventar.beiAenderung then pcall(WW.Inventar.beiAenderung) end end
  local vorher, abstand, einzug = titel, -8, 0
  local function haken(text, feld, ein)
    ein = ein or 0
    local h = UI.Haken(p, text, function() return db[feld] end, function(an) db[feld] = an neu() end)
    h:SetPoint("TOPLEFT", vorher, "BOTTOMLEFT", ein - einzug, abstand)
    vorher, abstand, einzug = h, 2, ein
    return h
  end
  haken("Quest-Items behalten", "quest")
  haken(("auch für Quests in deiner Stufe (± %d)"):format(tonumber(db.spanne) or 5), "kommende", 16)
  haken("Berufs-Zutaten behalten (Rezept gibt noch Punkte)", "beruf")
  haken("auch für Rezepte, die du noch nicht gelernt hast", "fremde", 16)
  haken("Rezepte für deinen Beruf behalten", "rezepte")
  haken("Müll erkennen (Klasse kann es nie tragen)", "muell")
  haken("Alt+Rechtsklick merkt ein Item", "alt")
  haken("Zeichen in der Tasche", "zeichen")
  haken("An Twinks denken (gleicher Realm, gleiche Fraktion)", "twinks")
  haken("Entzaubern vorschlagen (mit Verzauberkunst)", "entzaubern")
  haken("Knopf an der Tasche: billigsten Müll löschen", "loeschen")
  haken("Zeile im Tooltip", "tooltip")
  local hm = UI.Haken(p, "Händler-Knopf verkauft Müll",
    function() return WW.db.haendler and WW.db.haendler.muell end,
    function(an) if WW.db.haendler then WW.db.haendler.muell = an end end)
  hm:SetPoint("TOPLEFT", vorher, "BOTTOMLEFT", -einzug, 2)

  -- rechte Spalte: Erklärung, Merkliste, Twinks, Taschenwert
  local hilfe = UI.Text(p, "klein", 0.8, 0.8, 0.8)
  hilfe:SetPoint("TOPLEFT", LINKS, -8)
  hilfe:SetWidth(WW.INHALT_BREITE - LINKS - 10)
  hilfe:SetSpacing(2)
  hilfe:SetText("Geschützte Items verkauft der Händler-Knopf nie. Zeichen in der Tasche: "
    .. WW.f("gelb", "Q") .. " Quest, " .. WW.f("ff66b3ff", "B") .. " Beruf, " .. WW.f("orange", "T") .. " Twink, "
    .. WW.f("ffb380ff", "E") .. " Entzaubern, " .. WW.f("gruen", "+") .. " gemerkt. Müll: roter Rand.\n"
    .. "Öffne jedes Berufsfenster einmal, dann kennt Wegweiser deine Rezepte.\n"
    .. "Die Liste deiner Items mit Grund steht im Reiter Inventar: Knopf \"Spalten: Behalten?\".")
  local merkText = UI.Text(p)
  merkText:SetPoint("TOPLEFT", hilfe, "BOTTOMLEFT", 0, -14)
  local leeren = UI.Knopf(p, "Merkliste leeren", 130, function()
    U.MerkenLeeren()
    p:OnZeigen()
  end)
  leeren:SetPoint("LEFT", merkText, "LEFT", 150, 0)
  local twinkText = UI.Text(p, "klein", 0.8, 0.8, 0.8)
  twinkText:SetPoint("TOPLEFT", merkText, "BOTTOMLEFT", 0, -14)
  twinkText:SetWidth(WW.INHALT_BREITE - LINKS - 10)
  local wertText = UI.Text(p, "klein")
  wertText:SetPoint("TOPLEFT", twinkText, "BOTTOMLEFT", 0, -8)
  wertText:SetWidth(WW.INHALT_BREITE - LINKS - 10)

  function p:OnZeigen()
    merkText:SetText(("Gemerkt: %d Items"):format(U.MerkAnzahl()))
    local t = {}
    for _, tw in ipairs(WW.Twinks and WW.Twinks.Liste() or LEER) do t[#t + 1] = tw.name .. (tw.an and "" or " (aus)") end
    twinkText:SetText("Twinks: " .. (#t > 0 and table.concat(t, ", ") or "noch keine – jeder Twink loggt sich einmal ein")
      .. "\n/ww twink Name schließt einen Twink aus oder ein.")
    local okW, w = pcall(function() return WW.Muell and WW.Muell.Taschenwert() end)
    wertText:SetText((okW and type(w) == "table") and WW.Muell.WertText(w) or "")
  end
  WW:Event("BAG_UPDATE_DELAYED", function() if p:IsShown() then p:OnZeigen() end end)
end, "einstellungen")
