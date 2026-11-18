-- Szenen fuer Quests.lua: Bewertung von Belohnungen fuer die eigene Klasse (Krieger, Stufe 30 in mockwow),
-- Reiter "Quests", Tooltip-Zeilen, Haken im Questlog, Dungeon-Karte mit Bewertung.
-- SZENE: Quests - Vorbereiten (Gegenstaende und Questlog nachgebaut)
function __QGLEICH(ist, soll, was)
  if ist ~= soll then error((was or "?") .. ": erwartet " .. tostring(soll) .. ", war " .. tostring(ist), 2) end
end
function __QENTHAELT(text, teil, was)
  if type(text) ~= "string" or not text:find(teil, 1, true) then
    error((was or "?") .. ": '" .. tostring(teil) .. "' fehlt in '" .. tostring(text) .. "'", 2)
  end
end
__QALT = {
  GetItemInfo = rawget(_G, "GetItemInfo"), C_ItemGetItemInfo = C_Item.GetItemInfo, GetItemInfoInstant = rawget(_G, "GetItemInfoInstant"), GetItemStats = rawget(_G, "GetItemStats"),
  GetInventoryItemLink = rawget(_G, "GetInventoryItemLink"),
}
-- Forever: Questlog nur ueber C_QuestLog (die alten globalen Funktionen fehlen, siehe mockwow __FEHLT)
__QALT_QL = {}
for _, k in ipairs({ "GetNumQuestLogEntries", "GetInfo", "GetSelectedQuest", "SetSelectedQuest", "GetLogIndexForQuestID", "GetTitleForQuestID" }) do
  __QALT_QL[k] = C_QuestLog[k]
end
-- id = { name, qualitaet, minStufe, loc, klasse, unter, werte }
__QITEMS = {
  [9000] = { "Altes Schwert", 1, 20, "INVTYPE_WEAPON", 2, 7, { ITEM_MOD_STRENGTH_SHORT = 1, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 5 } },
  [9001] = { "Blaues Schwert", 3, 28, "INVTYPE_WEAPON", 2, 7, { ITEM_MOD_STRENGTH_SHORT = 5, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 8 } },
  [9002] = { "Stoffrobe", 2, 25, "INVTYPE_ROBE", 4, 1, { ITEM_MOD_INTELLECT_SHORT = 8, ITEM_MOD_SPIRIT_SHORT = 6 } },
  [9003] = { "Plattenbrust", 4, 40, "INVTYPE_CHEST", 4, 4, { ITEM_MOD_STRENGTH_SHORT = 10, RESISTANCE0_NAME = 400 } },
  [9004] = { "Zauberstab", 2, 25, "INVTYPE_RANGEDRIGHT", 2, 19, { ITEM_MOD_INTELLECT_SHORT = 3, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 20 } },
  [9005] = { "Heiltrank", 1, 20, "", 0, 0, {} },
}
local function idVon(x) return tonumber(tostring(x):match("item:(%d+)") or x) end
GetItemInfo = function(x)
  local id = idVon(x)
  local d = id and __QITEMS[id]
  if not d then return nil end   -- unbekannt: wie ein Gegenstand, den das Spiel noch nicht kennt
  return d[1], "|Hitem:" .. id .. "|h[" .. d[1] .. "]|h", d[2], 30, d[3], "Waffe", "Schwert", 1, d[4], 135000 + id, 100, d[5], d[6]
end
GetItemInfoInstant = function(x)
  local id = idVon(x)
  local d = id and __QITEMS[id]
  if not d then return nil end
  return id, "Waffe", "Schwert", d[4], 135000 + id, d[5], d[6]
end
-- Forever-Client: Wegweiser liest Items über C_Item.GetItemInfo
C_Item.GetItemInfo = GetItemInfo
GetItemStats = function(link)
  local d = __QITEMS[idVon(link) or 0]
  return d and d[7] or nil
end
__QANGELEGT = { [16] = "|Hitem:9000|h[Altes Schwert]|h", [17] = "|Hitem:9000|h[Altes Schwert]|h" }
GetInventoryItemLink = function(unit, slot) return __QANGELEGT[slot] end
-- Questlog: Ueberschrift, Quest 5001 (Belohnungen vom Spiel), Quest 1144 (aus den Daten), Quest 5002 (nichts)
__QLOG = {
  { "Brachland", true },
  { "Ein blaues Schwert", false, 5001, 28 },
  { "Willix der Importeur", false, 1144, 30 },
  { "Nur Gold", false, 5002, 29 },
}
-- Auswahl wie im Forever-Client ueber die questID (__QAUSWAHL = gewaehlte Quest); 1144 = Zeile 3
__QAUSWAHL = 1144
__QWAHLEN = {}
C_QuestLog.GetNumQuestLogEntries = function() return #__QLOG, 3 end
C_QuestLog.GetInfo = function(i)
  local e = __QLOG[i]
  if not e then return nil end
  return { title = e[1], level = e[4], isHeader = e[2], isComplete = false, questID = e[3] or 0, isHidden = false, isCollapsed = false }
end
C_QuestLog.GetLogIndexForQuestID = function(id) for i, e in ipairs(__QLOG) do if e[3] == id then return i end end end
C_QuestLog.GetTitleForQuestID = function(id) for _, e in ipairs(__QLOG) do if e[3] == id then return e[1] end end end
C_QuestLog.GetSelectedQuest = function() return __QAUSWAHL end
C_QuestLog.SetSelectedQuest = function(id) __QAUSWAHL = id __QWAHLEN[#__QWAHLEN + 1] = id end
-- die alten Belohnungs-Funktionen lesen die gewaehlte Quest (wie im Client)
local belohnung = { [5001] = { reward = { 9001 }, choice = { 9002, 9003, 9004 } } }
GetNumQuestLogRewards = function() local b = belohnung[__QAUSWAHL] return b and #b.reward or 0 end
GetNumQuestLogChoices = function() local b = belohnung[__QAUSWAHL] return b and #b.choice or 0 end
GetQuestLogItemLink = function(art, i)
  local b = belohnung[__QAUSWAHL]
  local id = b and b[art][i]
  return id and ("|Hitem:" .. id .. "|h[x]|h") or nil
end
-- "Klick auf alle Knoepfe" hat die Spezialisierung schon umgeschaltet: zurueck auf automatisch,
-- und die Ausruestung hat sich "geaendert" (Spezialisierung neu bestimmen)
__WW.charDb.quests.spez = "auto"
__WW.QW.Vergessen()   -- fruehere Szenen haben Gegenstaende mit dem Standard-GetItemInfo der Nachbildung gelesen
__FEUER("PLAYER_EQUIPMENT_CHANGED", 16)
__UPDATE(2)

-- SZENE: Quests - Bewertung einzelner Gegenstaende
local QW = __WW.QW
local sp, _, wie = QW.Spez()
__QGLEICH(sp and sp.name, "Arms", "Spezialisierung aus der Ausruestung (Staerke)")
__QGLEICH(wie, "Ausrüstung", "wie die Spezialisierung gefunden wurde")
local r = QW.Bewerte(9001)
__QGLEICH(r.art, "upgrade", "blaues Schwert ist ein Upgrade")
__QGLEICH(r.selten, true, "blaues Schwert ist selten")
__QENTHAELT(QW.UrteilText(r), "Upgrade +67 %", "Prozent fuer das Schwert")
r = QW.Bewerte(9002)
__QGLEICH(r.art, "werte", "Stoffrobe mit Int/Wille bringt einem Krieger nichts")
__QENTHAELT(table.concat(r.gutFuer, ","), "MAGE", "Stoffrobe ist gut fuer Magier")
__QGLEICH(table.concat(r.gutFuer, ","):find("WARRIOR"), nil, "Stoffrobe nicht fuer Krieger")
r = QW.Bewerte(9003)
__QGLEICH(r.art, "leer", "Plattenbrust fuellt den leeren Brust-Platz")
__QGLEICH(r.ab, 40, "Platte erst ab Stufe 40")
__QENTHAELT(QW.UrteilText(r), "ab Stufe 40", "Text ab Stufe 40")
r = QW.Bewerte(9004)
__QGLEICH(r.art, "nicht", "Zauberstab kann ein Krieger nicht benutzen")
__QENTHAELT(r.warum, "Krieger kann diese Waffe nicht benutzen", "Grund Zauberstab")
__QGLEICH(QW.Bewerte(9005).art, "kein", "Trank ist keine Ausruestung")
-- Monkey Ring: das Spiel kennt ihn (noch) nicht -> ForeverDB-Daten (Beweglichkeit, Willenskraft)
r = QW.Bewerte(6748)
__QGLEICH(r.info.loc, "INVTYPE_FINGER", "Ring aus den Daten")
__QGLEICH(r.info.da, nil, "Ring noch nicht vom Spiel geladen")
local fuer = table.concat(r.gutFuer or {}, ",")
if not (fuer:find("ROGUE") or fuer:find("HUNTER")) then error("Monkey Ring sollte gut fuer Schurke/Jaeger sein: " .. fuer) end
__QENTHAELT(QW.Kurz(6748), "für", "Kurztext fuer die Dungeon-Karte")
__QGLEICH(QW.Bewerte(nil), nil, "nil ohne Gegenstand")
__QGLEICH(QW.Bewerte(424242).art, "kein", "voellig unbekannter Gegenstand")
__LOG[#__LOG + 1] = "Quests: Ring gut fuer " .. fuer .. ", Kurz: " .. tostring(QW.Kurz(6748))

-- SZENE: Quests - Spezialisierung waehlen
local QW = __WW.QW
__WW.charDb.quests.spez = "Protection"
__QGLEICH(QW.Spez().name, "Protection", "gewaehlte Spezialisierung")
__QENTHAELT(QW.SpezText(), "Schutz (gewählt)", "Text gewaehlt")
__WW.charDb.quests.spez = "gibtsnicht"
__QGLEICH(QW.Spez().name, "Arms", "unbekannte Wahl -> automatisch")
__WW.charDb.quests.spez = "auto"

-- SZENE: Quests - Questlog lesen und Reiter
local QW = __WW.QW
__QAUSWAHL = 1144
__QWAHLEN = {}
local liste = QW.Scannen()
__QGLEICH(#liste, 4, "vier Eintraege im Log")
__QGLEICH(liste[1].kopf, true, "Ueberschrift zuerst")
local q1, q2, q3 = liste[2], liste[3], liste[4]
__QGLEICH(q1.bel.quelle, "log", "5001 vom Spiel gelesen")
__QGLEICH(#q1.bel.rewards, 1, "5001 eine Belohnung")
__QGLEICH(#q1.bel.choices, 3, "5001 drei zur Wahl")
__QGLEICH(q1.urteil.art, "upgrade", "5001 hat ein Upgrade")
__QGLEICH(q1.urteil.beste and __WW.ItemID(q1.urteil.beste.x), 9003, "beste Wahl ist die Plattenbrust (leerer Platz)")
__QGLEICH(QW.HatUpgrade(5001), true, "5001 als Upgrade gemerkt")
__QGLEICH(__QAUSWAHL, 1144, "Auswahl im Questlog wieder hergestellt")
__QGLEICH(q2.bel.quelle, "daten", "1144 aus den Daten (Spiel liefert nichts)")
__QGLEICH(#q2.bel.choices, 3, "1144 drei Ringe zur Wahl")
__QGLEICH(q3.urteil.art, "leer", "5002 ohne Gegenstaende")
__WW:Oeffnen("quests")
__WW.QW.ZeigeQuestItems(false)   -- "Klick auf alle Knoepfe" hat vorher auf die Quest-Item-Ansicht umgeschaltet
__UPDATE(2)
-- Klick auf die Quest-Zeile 5001 -> Details
local zeile
for _, f in ipairs(__FRAMES) do
  if f.__typ == "Button" and type(f.eintrag) == "table" and f.eintrag.questID == 5001 and f.__shown then zeile = f end
end
if not zeile then error("keine Zeile fuer Quest 5001") end
zeile.__scripts.OnClick(zeile, "LeftButton")
local text
for _, f in ipairs(__FRAMES) do
  if f.__typ == "FontString" and type(f.__text) == "string" and f.__text:find("Bewertet für:", 1, true) and f.__text:find("Belohnung", 1, true) then text = f.__text end
end
__QENTHAELT(text, "Beste Wahl:", "Detail markiert die beste Wahl")
__QENTHAELT(text, "Gut für:", "Detail nennt Klassen")
zeile.__scripts.OnEnter(zeile)
-- Ereignisse: Questlog aendert sich, Item-Daten kommen
__FEUER("QUEST_LOG_UPDATE")
__FEUER("GET_ITEM_INFO_RECEIVED", 6748, true)
__FEUER("PLAYER_EQUIPMENT_CHANGED", 16)
__UPDATE(3)
__QGLEICH(__QAUSWAHL, 1144, "Auswahl nach erneutem Lesen wieder hergestellt")

-- SZENE: Quests - Tooltip
local QW = __WW.QW
local zeilen = {}
local altAdd = GameTooltip.AddLine
GameTooltip.AddLine = function(self, text) zeilen[#zeilen + 1] = text end
local function tip(id)
  zeilen = {}
  local f = GameTooltip.__scripts.OnTooltipCleared
  if f then f(GameTooltip) end
  QW.TooltipZeilen(GameTooltip, { id = id, type = 0 })
  return table.concat(zeilen, " | ")
end
__QENTHAELT(tip(9001), "Für dich (Krieger, Waffen): ", "Tooltip fuer dich")
__QENTHAELT(tip(9001), "Upgrade +67 %", "Tooltip Prozent")
__QENTHAELT(tip(9004), "Krieger kann diese Waffe nicht benutzen", "Tooltip Zauberstab")
__QENTHAELT(tip(9002), "Gut für:", "Tooltip Gut fuer")
__QGLEICH(tip(9005), "", "Trank ohne Zeile")
-- nur einmal pro Anzeige
zeilen = {}
GameTooltip.__scripts.OnTooltipCleared(GameTooltip)
QW.TooltipZeilen(GameTooltip, { id = 9001 })
QW.TooltipZeilen(GameTooltip, { id = 9001 })
__QGLEICH(#zeilen, 2, "Zeilen nur einmal")
__WW.db.quests.tooltip = false
__QGLEICH(tip(9001), "", "Tooltip abgeschaltet")
__WW.db.quests.tooltip = true
GameTooltip.AddLine = altAdd

-- SZENE: Quests - Haken in Blizzards Questlog
local QW = __WW.QW
QUESTS_DISPLAYED = 3
for i = 1, 3 do
  local b = CreateFrame("Button", "QuestLogTitle" .. i, UIParent)
  b:SetID(i + 1)   -- Zeile i zeigt Log-Eintrag i+1
end
QuestLog_Update = function() end
__FEUER("ADDON_LOADED", "Blizzard_QuestLog")
QW.Scannen()
QuestLog_Update()
local function hatHaken(b)
  for _, f in ipairs(__FRAMES) do
    if f.__parent == b and f.__typ == "Texture" and f.__tex == "Interface\\RaidFrame\\ReadyCheck-Ready" then return f.__shown end
  end
  return false
end
__QGLEICH(hatHaken(QuestLogTitle1), true, "Haken bei Quest 5001 (Upgrade)")
__QGLEICH(hatHaken(QuestLogTitle3), false, "kein Haken bei Quest 5002")
__WW.db.quests.marken = false
QuestLog_Update()
__QGLEICH(hatHaken(QuestLogTitle1), false, "Haken aus, wenn abgeschaltet")
__WW.db.quests.marken = true

-- SZENE: Quests - Dungeon-Karte zeigt Bewertung
__WW:DungeonKarteZeigen(47)
__UPDATE(2)
for _, f in ipairs(__FRAMES) do
  if f.__typ == "Button" and type(f.eintrag) == "table" and type(f.eintrag.q) == "table" and f.eintrag.q.id == 1144 then
    f.__scripts.OnClick(f, "LeftButton")
  end
end
local gefunden
for _, f in ipairs(__FRAMES) do
  if f.__typ == "FontString" and type(f.__text) == "string" and f.__text:find("Zur Wahl (eine davon):", 1, true) then gefunden = f.__text end
end
if gefunden then __QENTHAELT(gefunden, "(", "Bewertung hinter dem Ring") end
__LOG[#__LOG + 1] = "Quests: Dungeon-Detail mit Wahl " .. tostring(gefunden ~= nil)
__WW:DungeonKarteUmschalten()

-- SZENE: Quests - Review 1: Zweihaender angelegt, Schildhand leer (kein "leerer Platz")
local QW = __WW.QW
__QITEMS[9100] = { "Zweihaender", 2, 20, "INVTYPE_2HWEAPON", 2, 8, { ITEM_MOD_STRENGTH_SHORT = 20, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 30 } }
__QITEMS[9101] = { "Holzschild", 1, 10, "INVTYPE_SHIELD", 4, 6, { ITEM_MOD_STAMINA_SHORT = 1, RESISTANCE0_NAME = 50 } }
__QITEMS[9102] = { "Dolch", 1, 10, "INVTYPE_WEAPON", 2, 15, { ITEM_MOD_AGILITY_SHORT = 1, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 3 } }
local altAngelegt = __QANGELEGT
__QANGELEGT = { [16] = "|Hitem:9100|h[Zweihaender]|h" }
QW.Vergessen()
for _, id in ipairs({ 9101, 9102 }) do
  local r = QW.Bewerte(id)
  if r.art == "leer" or r.art == "upgrade" then
    error(id .. " neben einem Zweihaender darf kein Upgrade sein, war " .. tostring(r.art) .. " " .. tostring(r.pct))
  end
end
-- Zweihaender pruefen, wenn Waffenhand leer und Schildhand belegt: Vergleich mit der Schildhand, nicht "leer"
__QANGELEGT = { [17] = "|Hitem:9101|h[Holzschild]|h" }
local r = QW.Bewerte(9100)
__QGLEICH(r.art, "upgrade", "Zweihaender gegen Schild: Upgrade, nicht leerer Platz")
-- Review 6: riesige Prozent werden gedeckelt
__QENTHAELT(QW.UrteilText(r), "300 % und mehr", "Prozent gedeckelt")
-- Zweihaender gegen Einhand + Schildhand zusammen
__QANGELEGT = { [16] = "|Hitem:9000|h[Altes Schwert]|h", [17] = "|Hitem:9000|h[Altes Schwert]|h" }
r = QW.Bewerte(9100)
__QGLEICH(r.slot, 16, "Zweihaender zaehlt fuer die Waffenhand")
__QANGELEGT = altAngelegt
QW.Vergessen()

-- SZENE: Quests - Review 3: Spezialisierung aus dem Talentbaum (Traits) nach TRAIT_CONFIG_UPDATED
local QW = __WW.QW
local altBaum = __WW.quelle.fdb.talentTrees
local altCT, altTraits = rawget(_G, "C_ClassTalents"), rawget(_G, "C_Traits")
__WW.quelle.fdb.talentTrees = { WARRIOR = {
  { name = "Arms", talents = { { "a", 0, 0, 5, 1001 } } },
  { name = "Fury", talents = { { "b", 0, 0, 5, 1002 } } },
  { name = "Protection", talents = { { "c", 0, 0, 5, 1003 }, { "d", 1, 0, 3, 1004 } } },
} }
C_ClassTalents = { GetActiveConfigID = function() return 7 end }
C_Traits = { GetNodeInfo = function(cfg, node) return { ranksPurchased = (node == 1003 or node == 1004) and 3 or (node == 1001 and 1 or 0) } end }
__WW.charDb.quests.spez = "auto"
QW.Spez()   -- Zwischenspeicher fuellen
__FEUER("TRAIT_CONFIG_UPDATED", 7)
local sp, _, wie = QW.Spez()
__QGLEICH(sp and sp.name, "Protection", "Spezialisierung aus den Traits")
__QGLEICH(wie, "Talente", "Spezialisierung aus den Talenten")
__WW.quelle.fdb.talentTrees = altBaum
C_ClassTalents, C_Traits = altCT, altTraits
__FEUER("PLAYER_TALENT_UPDATE")
__QGLEICH(QW.Spez().name, "Arms", "ohne Traits wieder aus der Ausruestung")

-- SZENE: Quests - Review 4: Quests unter eingeklappten Ueberschriften
local QW = __WW.QW
local alt = { GetQuestsOnMap = C_QuestLog.GetQuestsOnMap, IsOnQuest = C_QuestLog.IsOnQuest, GetTitleForQuestID = C_QuestLog.GetTitleForQuestID }
C_QuestLog.GetQuestsOnMap = function(m) return { { questID = 5003, x = 0.5, y = 0.5 }, { questID = 5001 } } end
C_QuestLog.IsOnQuest = function(id) return id == 5003 or id == 5001 or id == 1144 or id == 5002 end
C_QuestLog.GetTitleForQuestID = function(id) if id == 5003 then return "Versteckte Quest" end end
local liste = QW.Scannen()
local gefunden, doppelt = false, 0
for _, e in ipairs(liste) do
  if e.questID == 5003 then gefunden = e end
  if e.questID == 5001 then doppelt = doppelt + 1 end
end
if not gefunden then error("Quest 5003 unter eingeklappter Ueberschrift fehlt") end
__QGLEICH(gefunden.titel, "Versteckte Quest", "Titel der versteckten Quest")
__QGLEICH(doppelt, 1, "5001 nur einmal")
for k, v in pairs(alt) do C_QuestLog[k] = v end

-- SZENE: Quests - Review 5: Auswahl im Questlog klappt nicht -> keine falschen Belohnungen
local QW = __WW.QW
local altSel = C_QuestLog.SetSelectedQuest
C_QuestLog.SetSelectedQuest = function() end   -- Auswahl bleibt haengen
__QAUSWAHL = 5001                               -- ... auf Quest 5001 (die mit den Belohnungen)
QW.Vergessen()
local liste = QW.Scannen()
for _, e in ipairs(liste) do
  if e.questID == 5002 then
    if e.bel and e.bel.quelle == "log" and #e.bel.rewards > 0 then error("5002 hat die Belohnungen von 5001 bekommen") end
  end
end
C_QuestLog.SetSelectedQuest = altSel
__QAUSWAHL = 1144
QW.Vergessen()
liste = QW.Scannen()
for _, e in ipairs(liste) do
  if e.questID == 5001 then __QGLEICH(e.bel.quelle, "log", "nach funktionierender Auswahl wieder vom Spiel gelesen") end
end

-- SZENE: Quests - Quest-Items: Index und Status
-- 5792 = Ziel von 1101 (erledigt laut mockwow) -> kann weg; 5791 startet 1100 (Allianz, nicht erledigt);
-- 16305 gehoert zu Quest 2 (Horde) -> fuer Allianz nichts; 9200 = Forever-Quest im Log, nur ueber den Namen erkennbar
local QW = __WW.QW
__QITEMS[9200] = { "Steuerkonsolen-Bedienungsanleitung", 1, 1, "", 15, 0, {} }
local altObj = C_QuestLog.GetQuestObjectives
C_QuestLog.GetQuestObjectives = function(id)
  if id == 5001 then return { { text = "Steuerkonsolen-Bedienungsanleitung: 0/1", type = "item", finished = false } } end
  return {}
end
QW.QuestItemsNeu()
local function status(id)
  local liste, gesamt = QW.ItemQuests(id)
  return gesamt, liste
end
local g, l = status(5792)
__QGLEICH(g, "weg", "5792: Quest 1101 erledigt -> kann weg")
__QENTHAELT(l[1].text, "kann weg", "Text kann weg")
g, l = status(5791)
__QGLEICH(g, "start", "5791 startet eine Quest")
__QENTHAELT(l[1].text, "Startet Quest:", "Text startet")
g = status(16305)
__QGLEICH(g, nil, "Horde-Quest-Item fuer Allianz ohne Status")
g, l = status(9200)
__QGLEICH(g, "log", "Forever-Quest im Log ueber den Namen")
__QENTHAELT(l[1].text, "im Questlog 0/1", "Fortschritt im Text")
__QGLEICH(status(2448), nil, "normales Item ohne Quest")
-- Tooltip
local zeilen = {}
local altAdd = GameTooltip.AddLine
GameTooltip.AddLine = function(self, text) zeilen[#zeilen + 1] = text end
local f = GameTooltip.__scripts.OnTooltipCleared
if f then f(GameTooltip) end
QW.TooltipZeilen(GameTooltip, { id = 5792 })
__QENTHAELT(table.concat(zeilen, " | "), "kann weg", "Tooltip kann weg")
zeilen = {}
if f then f(GameTooltip) end
QW.TooltipZeilen(GameTooltip, { id = 9200 })
__QENTHAELT(table.concat(zeilen, " | "), "Quest: Ein blaues Schwert", "Tooltip Questname aus dem Log")
GameTooltip.AddLine = altAdd
__QALTOBJ = altObj

-- SZENE: Quests - Quest-Items im Reiter
local QW = __WW.QW
local altInfo = C_Container.GetContainerItemInfo
local altSlots = C_Container.GetContainerNumSlots
local tasche = { 5792, 9200, 5791, 2448 }
C_Container.GetContainerNumSlots = function(b) return b == 0 and #tasche or 0 end
C_Container.GetContainerItemInfo = function(b, s)
  if b == 0 and tasche[s] then return { itemID = tasche[s], stackCount = 1, hyperlink = "|Hitem:" .. tasche[s] .. "|h" } end
end
__WW:Oeffnen("quests")
local zeilen = QW.QuestItemZeilen()
__QGLEICH(#zeilen, 3, "drei Quest-Items in der Tasche")
__QGLEICH(zeilen[1].id, 5792, "kann weg zuerst")
__QGLEICH(zeilen[2].id, 9200, "dann im Questlog")
__QGLEICH(zeilen[3].id, 5791, "dann startet Quest")
-- Ansicht umschalten und neu laden (Knoepfe)
for _, b in ipairs(__FRAMES) do
  if b.__typ == "Button" and (b.__text == "Quest-Items in Taschen" or b.__text == "Taschen neu laden") then
    b.__scripts.OnClick(b, "LeftButton")
  end
end
__UPDATE(2)
local gezeigt = false
for _, b in ipairs(__FRAMES) do
  if b.__typ == "Button" and type(b.eintrag) == "table" and b.eintrag.id == 5792 and b.__shown then gezeigt = true end
end
__QGLEICH(gezeigt, true, "Zeile fuer 5792 in der Liste")
C_Container.GetContainerItemInfo, C_Container.GetContainerNumSlots = altInfo, altSlots
C_QuestLog.GetQuestObjectives = __QALTOBJ

-- SZENE: Quests - Aufraeumen
for _, k in ipairs({ "GetItemInfo", "GetItemInfoInstant", "GetItemStats", "GetInventoryItemLink" }) do _G[k] = __QALT[k] end
for k, f in pairs(__QALT_QL) do C_QuestLog[k] = f end
__QALT_QL = nil
C_Item.GetItemInfo = __QALT.C_ItemGetItemInfo
for _, k in ipairs({ "GetNumQuestLogRewards", "GetNumQuestLogChoices", "GetQuestLogItemLink", "QuestLog_Update", "QUESTS_DISPLAYED" }) do _G[k] = nil end
