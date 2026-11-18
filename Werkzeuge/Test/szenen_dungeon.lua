-- Szenen fuer Dungeon.lua: Bosse und Beute im Kartenfenster, Questgeber und Folgequests auf der Weltkarte.
-- SZENE: Dungeon - Beute-Daten
function __DGLEICH(ist, soll, was)
  if ist ~= soll then error((was or "?") .. ": erwartet " .. tostring(soll) .. ", war " .. tostring(ist), 2) end
end
function __DENTHAELT(text, teil, was)
  if type(text) ~= "string" or not text:find(teil, 1, true) then
    error((was or "?") .. ": '" .. tostring(teil) .. "' fehlt in '" .. tostring(text) .. "'", 2)
  end
end
function __DFINDE(l, id)
  for _, e in ipairs(l or {}) do if e.id == id then return e end end
end
local D = __WW.Dungeon
local b = D.Beute(D.Dungeon(33))
local e = __DFINDE(b.boss["Razorclaw the Butcher"], 1292)
__DGLEICH(e and e.quelle, "s", "Razorclaw: 1292 in Forever gesehen")
-- Die Forever-Chance aendert sich mit jedem ForeverDB-Update. Darum nur pruefen, dass sie stimmen kann.
if type(e.pct) ~= "number" or e.pct <= 0 or e.pct > 100 then
  error("Razorclaw: 1292 Dropchance ist keine Zahl von 0 bis 100: " .. tostring(e.pct))
end
__DGLEICH(e.kpct, 10, "Razorclaw: 1292 Classic-Chance")
-- Hinweis (unbestaetigt) aus dem Client: irgendwo in einem Dungeon muss es einen geben, mit Grund.
-- Welcher Dungeon, wechselt mit jedem ForeverDB-Update. Darum alle durchsuchen.
local hinweis
for _, d in ipairs(D.Alle()) do
  local bt = D.Beute(d)
  for _, x in ipairs(bt.trash or {}) do if x.quelle == "c" then hinweis = hinweis or x end end
  for _, l in pairs(bt.boss or {}) do
    for _, x in ipairs(l) do if x.quelle == "c" then hinweis = hinweis or x end end
  end
end
if not hinweis then error("kein unbestaetigter Hinweis in irgendeinem Dungeon") end
if type(hinweis.why) ~= "string" or hinweis.why == "" then error("Hinweis ohne Grund (why)") end
-- Classic: Verlies, Trash 2941 mit 33 %
local t = __DFINDE(D.Beute(D.Dungeon(34)).trash, 2941)
__DGLEICH(t and t.kpct, 33, "Verlies Trash 2941 Classic 33 %")
-- seltene Bosse
local selten
for _, bo in ipairs(D.BossListe(D.Dungeon(129))) do if bo.name == "Ragglesnout" then selten = bo end end
__DGLEICH(selten and selten.rare, true, "Ragglesnout ist selten")
-- keine Daten: kein Absturz
__DGLEICH(#D.BossListe({ id = 1, bosse = {}, bossNachNpc = {} }), 0, "leerer Dungeon")

-- SZENE: Dungeon - Bosse im Kartenfenster
local D = __WW.Dungeon
__WW:DungeonKarteZeigen(33)
D.Ansicht("bosse")
local zeile
for _, f in ipairs(__FRAMES) do
  if f.__typ == "Button" and type(f.eintrag) == "table" and f.eintrag.name == "Razorclaw the Butcher" and f.eintrag.beute then zeile = f end
end
if not zeile then error("keine Bosszeile fuer Razorclaw") end
zeile.__scripts.OnClick(zeile, "LeftButton")
local beuteZeile
for _, f in ipairs(__FRAMES) do
  if f.__typ == "Button" and type(f.eintrag) == "table" and f.eintrag.id == 1292 and f.eintrag.quelle and f.__shown then beuteZeile = f end
end
if not beuteZeile then error("keine Beutezeile fuer 1292") end
__DENTHAELT(beuteZeile.unter:GetText(), "in Forever gesehen", "Quelle in der Beutezeile")
__DENTHAELT(beuteZeile.name:GetText(), math.floor(beuteZeile.eintrag.pct + 0.5) .. " %", "Chance in der Beutezeile")
beuteZeile.__scripts.OnEnter(beuteZeile)
-- Boss-Nadel: Tooltip mit den besten Drops (Hoehlen des Wehklagens haben Boss-Positionen)
__WW:DungeonKarteZeigen(43)
local nadel
for _, f in ipairs(__FRAMES) do
  if f.__typ == "Frame" and f.boss and f.npcID and f.__shown and D.Beute(D.Dungeon(43)).boss[f.boss.name] then nadel = f end
end
if not nadel then error("keine Boss-Nadel mit Beute in 43") end
__TTZEILEN = {} local __altAdd = GameTooltip.AddLine GameTooltip.AddLine = function(self, t) __TTZEILEN[#__TTZEILEN + 1] = tostring(t) end
nadel.__scripts.OnEnter(nadel)
__DENTHAELT(table.concat(__TTZEILEN, " | "), "Beute:", "Nadel-Tooltip mit Beute")
GameTooltip.AddLine = __altAdd
D.Ansicht("quests")
__WW:DungeonKarteUmschalten()

-- SZENE: Dungeon - Questgeber und Folgequests auf der Weltkarte
local D = __WW.Dungeon
local altStufe = UnitLevel
local altFertig = C_QuestLog.IsQuestFlaggedCompleted
local altN, altInfo = C_QuestLog.GetNumQuestLogEntries, C_QuestLog.GetInfo
local altAdd = GameTooltip.AddLine
local ok, err = pcall(function()
  UnitLevel = function() return 18 end
  __WW.db.dungeonKarte.weltPins, __WW.db.dungeonKarte.nurPassend, __WW.db.dungeonKarte.graue = true, true, false
  local function finde(gruppen, qid, art)
    for _, g in ipairs(gruppen) do
      for _, q in ipairs(g.quests) do if q.id == qid and (not art or g.art == art) then return g end end
    end
  end
  local gr = D.WeltPinsNeu()
  if not finde(gr, 65, "geber") then error("Quest 65 (Gryan, Westfall) fehlt als Questgeber") end
  if finde(gr, 132) then error("Folgequest 132 darf erst nach 65 erscheinen") end
  for _, g in ipairs(gr) do
    for _, q in ipairs(g.quests) do if q.inside then error("Quest " .. q.id .. " hat den Geber im Dungeon") end end
    if g.x < 0 or g.x > 1 or g.y < 0 or g.y > 1 then error("Nadel ausserhalb 0..1") end
  end
  -- 65 erledigt -> Folgequest 132 (Wiley) erscheint
  C_QuestLog.IsQuestFlaggedCompleted = function(id) return id == 65 or id == 1101 end
  gr = D.WeltPinsNeu()
  local g132 = finde(gr, 132, "geber")
  if not g132 then error("Folgequest 132 fehlt nach Abschluss von 65") end
  if finde(gr, 65) then error("65 ist erledigt und darf nicht mehr erscheinen") end
  local zeilen = {}
  GameTooltip.AddLine = function(self, t) zeilen[#zeilen + 1] = tostring(t) end
  g132.pin.__scripts.OnEnter(g132.pin)
  local tip = table.concat(zeilen, " | ")
  __DENTHAELT(tip, "Folgequest von:", "Tooltip Folgequest")
  __DENTHAELT(tip, "Teil 2 von", "Tooltip Kettenschritt")
  -- Stufe passt nicht (Spieler 40): nichts aus Westfall
  UnitLevel = function() return 40 end
  if finde(D.WeltPinsNeu(), 132) then error("132 (Stufe 18) bei Stufe 40 mit 'nur passende Stufe'") end
  -- Quest fertig im Log -> "?" beim Abgabe-NPC
  UnitLevel = function() return 18 end
  C_QuestLog.GetNumQuestLogEntries = function() return 1 end
  C_QuestLog.GetInfo = function(i) if i == 1 then return { title = "Die Defias", level = 18, isHeader = false, isComplete = 1, questID = 132 } end end
  gr = D.WeltPinsNeu()
  local abg = finde(gr, 132, "abgabe")
  if not abg then error("fertige Quest 132 ohne Abgabe-Nadel") end
  __DGLEICH(abg.map, 1436, "Abgabe bei Gryan in Westfall")
  C_QuestLog.GetNumQuestLogEntries, C_QuestLog.GetInfo = altN, altInfo
  -- abgeschaltet: keine Nadeln
  __WW.db.dungeonKarte.weltPins = false
  __DGLEICH(#D.WeltPinsNeu(), 0, "Weltkarten-Nadeln aus")
end)
-- immer zuruecksetzen, auch nach einem Fehler (spaetere Szenen erwarten Stufe 30)
__WW.db.dungeonKarte.weltPins = true
UnitLevel, C_QuestLog.IsQuestFlaggedCompleted = altStufe, altFertig
C_QuestLog.GetNumQuestLogEntries, C_QuestLog.GetInfo = altN, altInfo
GameTooltip.AddLine = altAdd
if not ok then error(err, 0) end
__FEUER("QUEST_LOG_UPDATE")
__UPDATE(10)
D.WeltPinsNeu()

-- SZENE: Dungeon - Review 1+5: Raid-Beute und Bossnamen aus zwei Quellen
local D = __WW.Dungeon
local function boss(d, name)
  for _, bo in ipairs(D.BossListe(d)) do if bo.name == name then return bo end end
end
local mc = D.Dungeon(409)
local luc, rag = boss(mc, "Lucifron"), boss(mc, "Ragnaros")
if not (luc and #luc.beute > 0) then error("Lucifron (Geschmolzener Kern) ohne Beute") end
if not (rag and #rag.beute > 0) then error("Ragnaros ohne Beute") end
-- gleiche Bosse, andere Schreibweise oder umbenannt: keine doppelten Zeilen
for _, fall in ipairs({ { 48, "Geilhast", "Gelihast" }, { 3065, "Infurnus", "Magmatus" }, { 2999, "The Butcher", "The Baron" } }) do
  local d = D.Dungeon(fall[1])
  if boss(d, fall[2]) then error(fall[1] .. ": doppelte Zeile '" .. fall[2] .. "' neben '" .. fall[3] .. "'") end
  local b = boss(d, fall[3])
  if not (b and #b.beute > 0) then error(fall[1] .. ": '" .. fall[3] .. "' ohne die Beute aus dem Helper") end
end

-- SZENE: Dungeon - Review 2+3+4: exklusive Gruppen, "braucht eine von", "nur waehrend", graue Quests
local D = __WW.Dungeon
local altStufe, altFertig = UnitLevel, C_QuestLog.IsQuestFlaggedCompleted
local altN, altInfo = C_QuestLog.GetNumQuestLogEntries, C_QuestLog.GetInfo
local e = __WW.db.dungeonKarte
local ok, err = pcall(function()
  local function ids(von, bis)
    local t = {}
    for _, g in ipairs(D.WeltPinsNeu()) do
      for _, q in ipairs(g.quests) do if q.id >= von and q.id <= bis and g.art == "geber" then t[#t + 1] = q.id end end
    end
    table.sort(t)
    return table.concat(t, ",")
  end
  UnitLevel = function() return 60 end
  e.nurPassend, e.graue = true, false
  -- exklusive Gruppe 8962..8965: nach 8962 keine der anderen
  C_QuestLog.IsQuestFlaggedCompleted = function(id) return id == 8961 or id == 8962 end
  __DGLEICH(ids(8962, 8965), "", "exklusive Gruppe nach 8962")
  -- "braucht eine von": mit 8962 und 8970 erledigt nur 8987
  C_QuestLog.IsQuestFlaggedCompleted = function(id) return id == 8961 or id == 8962 or id == 8970 end
  __DGLEICH(ids(8985, 8988), "8987", "braucht eine von (8987 braucht 8962)")
  -- 4022 erledigt -> 4023 gesperrt
  C_QuestLog.IsQuestFlaggedCompleted = function(id) return id == 4022 end
  D.WeltPinsNeu()
  if D.Status(D.Quest(4023) or { id = 4023 }) == "verfuegbar" then error("4023 trotz erledigter 4022 verfuegbar") end
  -- 2842 nur waehrend 2841 im Log
  UnitLevel = function() return 30 end
  C_QuestLog.IsQuestFlaggedCompleted = function() return false end
  D.WeltPinsNeu()
  if D.Status(D.Quest(2842)) == "verfuegbar" then error("2842 ohne 2841 im Log verfuegbar") end
  C_QuestLog.GetNumQuestLogEntries = function() return 1 end
  C_QuestLog.GetInfo = function(i) if i == 1 then return { title = "Rig Wars", level = 35, isHeader = false, questID = 2841 } end end
  D.WeltPinsNeu()
  __DGLEICH(D.Status(D.Quest(2842)), "verfuegbar", "2842 mit 2841 im Log")
  C_QuestLog.GetNumQuestLogEntries, C_QuestLog.GetInfo = altN, altInfo
  -- graue Quests erweitern die untere Grenze, auch bei "nur passende Stufe"
  UnitLevel = function() return 40 end
  local function zahl() local n = 0 for _, g in ipairs(D.WeltPinsNeu()) do n = n + #g.quests end return n end
  e.nurPassend, e.graue = true, false
  local a = zahl()
  e.graue = true
  local b = zahl()
  if b <= a then error("auch graue Quests aendert nichts bei 'nur passende Stufe' (" .. a .. " / " .. b .. ")") end
end)
UnitLevel, C_QuestLog.IsQuestFlaggedCompleted = altStufe, altFertig
C_QuestLog.GetNumQuestLogEntries, C_QuestLog.GetInfo = altN, altInfo
e.nurPassend, e.graue = true, false
D.WeltPinsNeu()
if not ok then error(err, 0) end

-- SZENE: Dungeon - Forever-Quests: Abgabe "?" und Geber aus den ForeverDB-Forever-Daten
-- 92401 (Ruinen von Lordaeron, Horde) hat keinen qcQuests-Eintrag und keine Karte in den FDM-Daten
local D = __WW.Dungeon
local altStufe, altFertig, altFrak = UnitLevel, C_QuestLog.IsQuestFlaggedCompleted, UnitFactionGroup
local altN, altInfo = C_QuestLog.GetNumQuestLogEntries, C_QuestLog.GetInfo
local altAdd = GameTooltip.AddLine
local ok, err = pcall(function()
  local function finde(gruppen, qid, art)
    for _, g in ipairs(gruppen) do
      for _, q in ipairs(g.quests) do if q.id == qid and g.art == art then return g end end
    end
  end
  UnitLevel = function() return 22 end
  UnitFactionGroup = function() return "Horde", "Horde" end
  C_QuestLog.IsQuestFlaggedCompleted = function() return false end
  -- Geber: aus dem Questpunkt des Forever-Clients
  local g = finde(D.WeltPinsNeu(), 92401, "geber")
  if not g then error("Forever-Quest 92401 ohne Geber-Nadel") end
  __DGLEICH(g.map, 1421, "Geber in Silberwald")
  -- fertig im Log -> "?" beim Abgabe-NPC mit Namen
  C_QuestLog.GetNumQuestLogEntries = function() return 1 end
  C_QuestLog.GetInfo = function(i) if i == 1 then return { title = "Eine verängstigte Bitte", level = 22, isHeader = false, isComplete = 1, questID = 92401 } end end
  local a = finde(D.WeltPinsNeu(), 92401, "abgabe")
  if not a then error("fertige Forever-Quest 92401 ohne Abgabe-Nadel") end
  __DGLEICH(a.map, 1421, "Abgabe in Silberwald")
  local zeilen = {}
  GameTooltip.AddLine = function(self, t) zeilen[#zeilen + 1] = tostring(t) end
  a.pin.__scripts.OnEnter(a.pin)
  __DENTHAELT(table.concat(zeilen, " | "), "Tabitha Heartweaver", "Abgabe-NPC im Tooltip")
end)
UnitLevel, C_QuestLog.IsQuestFlaggedCompleted, UnitFactionGroup = altStufe, altFertig, altFrak
C_QuestLog.GetNumQuestLogEntries, C_QuestLog.GetInfo = altN, altInfo
GameTooltip.AddLine = altAdd
D.WeltPinsNeu()
if not ok then error(err, 0) end

-- SZENE: Dungeon - Geber ohne Ort in den DungeonMaster-Daten: Questpunkt aus den Forever-Daten
local D = __WW.Dungeon
local q = D.Quest(92421)
if not q then error("Quest 92421 fehlt in den Daten") end
local altM, altX, altY = q.map, q.x, q.y
local altStufe, altFertig, altFrak = UnitLevel, C_QuestLog.IsQuestFlaggedCompleted, UnitFactionGroup
local ok, err = pcall(function()
  q.map, q.x, q.y = nil, nil, nil
  UnitLevel = function() return 22 end
  UnitFactionGroup = function() return "Horde", "Horde" end
  C_QuestLog.IsQuestFlaggedCompleted = function() return false end
  local gefunden
  for _, g in ipairs(D.WeltPinsNeu()) do
    for _, x in ipairs(g.quests) do if x.id == 92421 and g.art == "geber" then gefunden = g end end
  end
  if not gefunden then error("92421 ohne Geber-Nadel aus den Forever-Daten") end
  __DGLEICH(gefunden.map, 1458, "Geber in Unterstadt (Questpunkt)")
end)
q.map, q.x, q.y = altM, altX, altY
UnitLevel, C_QuestLog.IsQuestFlaggedCompleted, UnitFactionGroup = altStufe, altFertig, altFrak
D.WeltPinsNeu()
if not ok then error(err, 0) end
