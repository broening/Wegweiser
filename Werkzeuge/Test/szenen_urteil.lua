-- Szenen fuer Urteil.lua: Behalten (gemerkt, Quest, Beruf) oder Muell, Tooltip, Haendler-Knopf, Alt+Rechtsklick, Reiter.
-- Nachbildung: GetItemInfo liefert Qualitaet 2 und Verkaufspreis 150 fuer jedes Item.
-- SZENE: Urteil - Vorbereiten
local U = __WW.Urteil
if not U then error("WW.Urteil fehlt") end
-- Die Datei muss bis zum Ende laden (unbekannte Ereignisse duerfen sie nicht abbrechen)
if not (__WW.befehle.merken and __WW.befehle.urteil and U.TaschenListe) then error("Urteil.lua nicht ganz geladen") end
__UR_ALT = { iq = __WW.QW.ItemQuests, kt = __WW.QW.KannTragen, eb = __WW.Handwerk.EigeneBerufe,
  num = C_Container.GetContainerNumSlots, info = C_Container.GetContainerItemInfo, alt = IsAltKeyDown }
-- Quests: 8101 im Questlog, 8102 Quest in Stufe 32 (du 30), 8103 Quest in Stufe 50, 8104 erledigt
local fdb = __WW.quelle.fdb
fdb.qcQuests[99901] = "Test nah|32|28|a|0|0|||0|n1|n1|i8102:3||"
fdb.qcQuests[99902] = "Test fern|50|45|a|0|0|||0|n1|n1|i8103:3||"
__WW.QW.ItemQuests = function(id)
  if id == 8101 then return { { q = 99900, status = "log", text = "Quest: Leber – im Questlog 1/3" } }, "log" end
  if id == 8102 then return { { q = 99901, status = "offen", text = "Für Quest: Test nah (noch nicht angenommen)" } }, "offen" end
  if id == 8103 then return { { q = 99902, status = "offen", text = "Für Quest: Test fern (noch nicht angenommen)" } }, "offen" end
  if id == 8104 then return { { q = 99903, status = "weg", text = "Quest erledigt (X) – kann weg" } }, "weg" end
  return {}, nil
end
-- Beruf: Schneiderei 50. Rezept 99950 (gelb 45, grau 60) braucht 8201, wird gelernt mit Rezept-Item 8203.
-- Rezept 99951 ist schon grau (grau 50) und braucht 8202.
fdb.recipes.Tailoring = fdb.recipes.Tailoring or {}
table.insert(fdb.recipes.Tailoring, { 99950, "Test Robe", 40, 45, 50, 60, 8210, 1, "8201:3", "i8203", 0, 0, 0 })
table.insert(fdb.recipes.Tailoring, { 99951, "Test Hose", 1, 30, 40, 50, 8211, 1, "8202:2", "t", 0, 0, 0 })
__WW.Handwerk.EigeneBerufe = function() return { Tailoring = 50 } end
-- Klasse: 8301 kann der Krieger nie tragen
__WW.QW.KannTragen = function(id) if id == 8301 then return false, "Krieger kann das nicht tragen (Stoff)" end return true end
__WW.charDb.rezepte = {}
-- "Klick auf alle Knoepfe" hat die Haken umgeschaltet: Standard wieder herstellen
for k, v in pairs({ tooltip = true, zeichen = true, quest = true, kommende = true, spanne = 5, beruf = true,
  fremde = true, rezepte = true, muell = true, alt = true }) do __WW.db.urteil[k] = v end
__WW.db.urteil.merken = {}
__WW.db.haendler.muell = true
U.VerzeichnisNeu()

-- SZENE: Urteil - Quest im Log, Quest in deiner Stufe, zu weit weg, erledigt
local U = __WW.Urteil
local e = U.Pruefen(8101)
if not (e and e.gruppe == "quest" and e.schutz) then error("8101 soll Quest sein") end
e = U.Pruefen(8102)
if not (e and e.gruppe == "quest" and e.text:find("Test nah", 1, true) and e.text:find("32", 1, true)) then
  error("8102: " .. tostring(e and e.text)) end
if U.Pruefen(8103) then error("8103: Quest Stufe 50 soll nicht zaehlen") end
if U.Pruefen(8104) then error("8104: erledigte Quest soll nicht schuetzen") end
__WW.db.urteil.kommende = false
U.NeuerStand()
if U.Pruefen(8102) then error("ohne 'kommende' soll 8102 frei sein") end
__WW.db.urteil.kommende = true
__WW.db.urteil.quest = false
U.NeuerStand()
if U.Pruefen(8101) then error("ohne 'quest' soll 8101 frei sein") end
__WW.db.urteil.quest = true
U.NeuerStand()

-- SZENE: Urteil - Beruf: Zutat und Rezept, vor und nach dem Berufsfenster
local U = __WW.Urteil
local e = U.Pruefen(8201)
if not (e and e.gruppe == "beruf") then error("8201 soll Beruf sein (nicht gelerntes Rezept, gibt Punkte)") end
if U.Pruefen(8202) then error("8202: Rezept ist grau, soll frei sein") end
e = U.Pruefen(8203)
if not (e and e.gruppe == "beruf" and e.text:find("Berufsfenster", 1, true)) then error("8203 vor dem Scan: " .. tostring(e and e.text)) end
__WW.db.urteil.fremde = false
U.NeuerStand()
if U.Pruefen(8201) then error("ohne 'fremde' und ohne Scan soll 8201 frei sein") end
-- Berufsfenster (alte API) zeigt das Rezept 99950
GetTradeSkillLine = function() return "Schneiderei", 50, 75 end
GetNumTradeSkills = function() return 2 end
GetTradeSkillInfo = function(i) if i == 1 then return "Kleidung", "header" end return "Testrobe", "optimal" end
GetTradeSkillRecipeLink = function(i) return "|cffffd000|Henchant:99950|h[Testrobe]|h|r" end
GetTradeSkillItemLink = function(i) return "|Hitem:8210|h[x]|h" end
__FEUER("TRADE_SKILL_SHOW")
__UPDATE(3)
GetTradeSkillLine, GetNumTradeSkills, GetTradeSkillInfo, GetTradeSkillRecipeLink, GetTradeSkillItemLink = nil, nil, nil, nil, nil
local r = __WW.charDb.rezepte.Tailoring
if not (r and r.s and r.s[99950] == "Testrobe") then error("Rezept nicht gespeichert") end
e = U.Pruefen(8201)
if not (e and e.gruppe == "beruf" and e.text:find("Testrobe", 1, true)) then error("8201 nach dem Scan: " .. tostring(e and e.text)) end
if U.Pruefen(8203) then error("8203: Rezept bekannt, ungebunden, ohne AH-Preis: soll frei bleiben (kein Muell ohne Preis)") end
e = U.Pruefen(8203, 1, true)
if not (e and e.gruppe == "muell" and not e.schutz and e.rand == "rot") then error("8203 gebunden und bekannt soll Muell sein") end
__WW.db.urteil.fremde = true
U.NeuerStand()

-- SZENE: Urteil - Muell: Klasse kann es nie tragen, nur gebunden
local U = __WW.Urteil
if U.Pruefen(8301, 1, false) then error("8301 ungebunden soll frei sein (AH entscheidet)") end
local e = U.Pruefen(8301, 1, true)
if not (e and e.gruppe == "muell" and e.text:find("Stoff", 1, true)) then error("8301 gebunden: " .. tostring(e and e.text)) end
__WW.db.urteil.muell = false
if U.Pruefen(8301, 1, true) then error("ohne 'muell' soll 8301 frei sein") end
__WW.db.urteil.muell = true

-- SZENE: Urteil - Merken schuetzt alles, auch Muell
local U = __WW.Urteil
U.Merken(8301)
local e = U.Pruefen(8301, 1, true)
if not (e and e.gruppe == "merken" and e.schutz) then error("gemerkt soll schuetzen") end
if U.MerkAnzahl() ~= 1 then error("MerkAnzahl " .. U.MerkAnzahl()) end
U.Merken(8301)
if U.Pruefen(8301, 1, true).gruppe ~= "muell" then error("nach Freigeben wieder Muell") end
SlashCmdList.WEGWEISER("merken")
SlashCmdList.WEGWEISER("merken leeren")

-- SZENE: Urteil - Haendler: geschuetzt nie, Muell ja (bis gruen), graues gemerktes nie
local U = __WW.Urteil
__UR_BAGS = { [0] = { { 8101, 1, false, 0 }, { 8301, 1, true, 2 }, { 8401, 2, false, 0 }, { 8203, 1, true, 2 } } }
C_Container.GetContainerNumSlots = function(b) return __UR_BAGS[b] and #__UR_BAGS[b] or 0 end
C_Container.GetContainerItemInfo = function(b, s)
  local x = __UR_BAGS[b] and __UR_BAGS[b][s]
  if x then return { itemID = x[1], stackCount = x[2], isBound = x[3], quality = x[4], isLocked = false } end
end
__WW.db.haendler.graue = true
local function ids()
  local t = {}
  for _, e in ipairs((__WW.Haendler.Liste())) do t[#t + 1] = e.id .. ":" .. e.grund end
  return table.concat(t, ",")
end
local s = ids()
if s ~= "8301:Müll: Klasse kann es nicht tragen,8401:grau,8203:Müll: Rezept schon bekannt" then error("Liste: " .. s) end
U.Merken(8401)
s = ids()
if s:find("8401", 1, true) then error("gemerktes graues Item verkauft: " .. s) end
U.Merken(8401)
__WW.db.haendler.muell = false
s = ids()
if s ~= "8401:grau" then error("ohne Muell: " .. s) end
__WW.db.haendler.muell = true
-- mit Verzauberkunst: gruener Muell bleibt (lieber entzaubern)
__WW.Handwerk.EigeneBerufe = function() return { Tailoring = 50, Enchanting = 1 } end
U.NeuerStand()
s = ids()
if s:find("8301", 1, true) then error("Verzauberer: gruener Muell soll bleiben: " .. s) end
__WW.Handwerk.EigeneBerufe = function() return { Tailoring = 50 } end
U.NeuerStand()

-- SZENE: Urteil - Tooltip-Zeile und keine "Verkaufen: Haendler"-Zeile fuer geschuetzte Items
local U = __WW.Urteil
local zeilen = {}
local altAdd = GameTooltip.AddLine
GameTooltip.AddLine = function(self, text) zeilen[#zeilen + 1] = tostring(text) end
local function tip(id)
  zeilen = {}
  local f = GameTooltip.__scripts.OnTooltipCleared
  if f then f(GameTooltip) end
  GameTooltip.__owner = nil
  U.TooltipZeilen(GameTooltip, { id = id })
  __WW.AH.TooltipZeilen(GameTooltip, { id = id })
  return table.concat(zeilen, "\n")
end
__WW.db.ah["Forever|Alliance"] = { r = "Forever", f = "Alliance", t = time(), n = 3, z = 3, m = "test", i = {
  [8101] = "10,10,9", [8501] = "10,10,9" } }
local t = tip(8101)
if not t:find("Behalten – Quest im Questlog", 1, true) then error("Tooltip 8101: " .. t) end
if t:find("Verkaufen:", 1, true) then error("geschuetztes Item mit Verkaufen-Zeile: " .. t) end
t = tip(8501)
if t:find("Wegweiser: ", 1, true) and t:find("Behalten", 1, true) then error("8501 ohne Urteil: " .. t) end
if not t:find("Verkaufen:", 1, true) then error("8501 soll Verkaufen-Zeile haben: " .. t) end
__WW.db.urteil.tooltip = false
t = tip(8101)
if t:find("Behalten", 1, true) then error("Tooltip trotz Schalter aus") end
__WW.db.urteil.tooltip = true
GameTooltip.AddLine = altAdd
__WW.db.ah["Forever|Alliance"] = nil

-- SZENE: Urteil - Zeichen am Taschenplatz und Alt+Rechtsklick
local U = __WW.Urteil
local b = CreateFrame("Button", "WegweiserTestPlatz", UIParent)
b.GetBagID = function() return 0 end
b:SetID(1)
U.Knopf(b, 8101, 1, false)
local fs
for _, f in ipairs(__FRAMES) do if f.__typ == "FontString" and f.__text == "Q" then fs = f end end
if not fs then error("Zeichen Q fehlt") end
IsAltKeyDown = function() return true end
b.__scripts.OnClick(b, "RightButton")
IsAltKeyDown = __UR_ALT.alt
if not __WW.db.urteil.merken[8101] then error("Alt+Rechtsklick hat nicht gemerkt") end
U.Knopf(b, 8101, 1, false)
if fs.__text ~= "+" then error("Zeichen nach Merken: " .. tostring(fs.__text)) end
b.__scripts.OnClick(b, "RightButton")   -- ohne Alt: nichts
if not __WW.db.urteil.merken[8101] then error("Rechtsklick ohne Alt hat freigegeben") end
U.MerkenLeeren()
U.Knopf(b, nil)
if fs.__shown then error("leerer Platz zeigt Zeichen") end

-- SZENE: Urteil - Taschenliste mit Gruppen, Unterreiter "Behalten", Inventar mit Spalten "Behalten?"
local U = __WW.Urteil
local mitKopf = U.TaschenListe()
local gruppen = {}
for _, x in ipairs(mitKopf) do if x.kopf then gruppen[#gruppen + 1] = x.gruppe end end
local g = table.concat(gruppen, ",")
if g ~= "quest,muell" then error("Gruppen: " .. g) end
__WW:Oeffnen("behalten")
__UPDATE(3)
if not __WW:IstOffen("behalten") or not __WW:IstOffen("einstellungen") then error("Unterreiter Behalten nicht offen") end
for _, f in ipairs(__FRAMES) do
  if f.__shown and f.__scripts.OnClick and f.__typ == "CheckButton" then
    f.__scripts.OnClick(f, "LeftButton") f.__scripts.OnClick(f, "LeftButton")
  end
end
-- Inventar: Spalten "Behalten?" ordnet jedes Item mit U.Einordnen ein
local es = __WW.db.inventarEinst
local altSp = es.spalten
es.spalten = "behalten"
__WW.Inventar.Aktualisieren()
__WW:Oeffnen("inventar")
__UPDATE(3)
local inv
for _, f in ipairs(__FRAMES) do
  if f.itemKlick and f.eintraege and f.eintraege[1] and f.eintraege[1].wotext then inv = f end
end
if not inv then error("Item-Liste im Inventar fehlt") end
local hatGruppe = false
for _, x in ipairs(inv.eintraege) do if x.gruppe then hatGruppe = true end end
if not hatGruppe then error("Inventar: keine Gruppe bei Spalten Behalten") end
-- Klick auf eine Zeile oeffnet die Item-Details, "Zurueck" fuehrt ins Inventar
local zeile = inv.zeilen[1]
zeile.__scripts.OnClick(zeile, "LeftButton")
if not __WW:IstOffen("items") then error("Klick im Inventar oeffnet nicht den Reiter Items") end
local zurueck
for _, f in ipairs(__FRAMES) do if f.__typ == "Button" and f.__shown and f.__text == "Zurück zum Inventar" then zurueck = f end end
if not zurueck then error("Knopf 'Zurück zum Inventar' fehlt") end
zurueck.__scripts.OnClick(zurueck, "LeftButton")
if not __WW:IstOffen("inventar") then error("Zurueck fuehrt nicht ins Inventar") end
es.spalten = altSp

-- SZENE: Urteil - Haendler: bekanntes, ungebundenes Rezept mit einem billigen AH-Preis wird nicht verkauft (rote aus)
local U = __WW.Urteil
__UR_BAGS = { [0] = { { 8203, 1, false, 2 } } }
__WW.db.haendler.rote = false
__WW.db.ah["Forever|Alliance"] = { r = "Forever", f = "Alliance", t = time(), n = 1, z = 1, m = "test", i = { [8203] = "10,10,1" } }
U.NeuerStand()
local liste = __WW.Haendler.Liste()
__WW.db.ah["Forever|Alliance"] = nil
if #liste ~= 0 then error("bekanntes Rezept trotz 'rote' aus verkauft: " .. liste[1].grund) end

-- SZENE: Urteil - Berufsfenster ohne Rezept-Link: zwei Rezepte machen dasselbe Item -> keins wird als gelernt gespeichert
local fdb = __WW.quelle.fdb
table.insert(fdb.recipes.Tailoring, { 99960, "Test A", 1, 30, 40, 70, 8220, 1, "8221:1", "i8222", 0, 0, 0 })
table.insert(fdb.recipes.Tailoring, { 99961, "Test B", 1, 30, 40, 70, 8220, 1, "8223:1", "i8224", 0, 0, 0 })
__WW.Urteil.VerzeichnisNeu()
GetTradeSkillLine = function() return "Schneiderei", 50, 75 end
GetNumTradeSkills = function() return 1 end
GetTradeSkillInfo = function() return "Test A", "optimal" end
GetTradeSkillItemLink = function() return "|Hitem:8220|h[x]|h" end
__FEUER("TRADE_SKILL_SHOW")
__UPDATE(3)
GetTradeSkillLine, GetNumTradeSkills, GetTradeSkillInfo, GetTradeSkillItemLink = nil, nil, nil, nil
local s = __WW.charDb.rezepte.Tailoring.s
if s[99960] or s[99961] then error("mehrdeutiges Produkt als gelernt gespeichert") end

-- SZENE: Urteil - Aufraeumen
__WW.QW.ItemQuests, __WW.QW.KannTragen, __WW.Handwerk.EigeneBerufe = __UR_ALT.iq, __UR_ALT.kt, __UR_ALT.eb
C_Container.GetContainerNumSlots, C_Container.GetContainerItemInfo = __UR_ALT.num, __UR_ALT.info
local fdb = __WW.quelle.fdb
fdb.qcQuests[99901], fdb.qcQuests[99902] = nil, nil
local t = fdb.recipes.Tailoring
for i = #t, 1, -1 do if t[i][1] == 99950 or t[i][1] == 99951 or t[i][1] == 99960 or t[i][1] == 99961 then table.remove(t, i) end end
__WW.charDb.rezepte = {}
__WW.Urteil.VerzeichnisNeu()

-- SZENE: Urteil - Pruef-Befehl /ww urteil
SlashCmdList.WEGWEISER("urteil 3575")
SlashCmdList.WEGWEISER("urteil")
