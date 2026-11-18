-- Wegweiser: Dungeon-Karte (eigenes Fenster "WegweiserDungeonKarte") und Reiter "Dungeons".
-- Links das Kartenbild mit Boss-Nadeln (Mausrad: zoomen, Ziehen: verschieben, Rechtsklick: zurück),
-- rechts Dungeon-Wahl, Quests des Dungeons mit Status und der Ziel-Text der gewählten Quest.
-- Daten: WW.quelle.fdm (Karten, Dungeons, Quests, Korrekturen), WW.quelle.helper (Stufen, Eingänge),
--        WW.quelle.fdb (Questziele, Drop-Quellen). Fehlt etwas, bleibt die Anzeige leer statt zu brechen.
-- Questziele im Dungeon: WW.quelle.ziele[Instanz][Quest] = { "<n|o><id>[><item>]:<punkte>" } aus Ziele\Dungeon.lua
-- (Werkzeuge\Dungeon-Ziele.py, cMaNGOS). Punkte: je 4 Zeichen Basis 36, x und y in Tausendstel des Kartenbilds.
-- Teile übernommen aus ForeverDungeonMap (GPL-3.0): Quest-Zusammenführung, Ketten, Zoom der Karte.
local ADDON, WW = ...
local UI = WW.UI

local KARTEN_PFAD = "Interface\\AddOns\\Wegweiser\\Daten\\Karten\\"
local BREITE, HOEHE = 1000, 620
local KARTE_B, KARTE_H = 640, 540
local RECHTS_B = BREITE - 12 - KARTE_B - 10 - 12
local NADEL = 22
local ZIEL_RASTER = 0.06   -- Questziele: Punkte näher als 6 % des Bildes teilen sich eine Nadel
local MIN_ZOOM, MAX_ZOOM = 1, 4

-- pos = { p, rp, x, y }, auswahl = Instanz-ID; Weltkarte: Questgeber an/aus, nur passende Stufe, auch graue
WW.standardDB.dungeonKarte = { weltPins = true, nurPassend = true, graue = false }

local D = {}
WW.Dungeon = D

---------------------------------------------------------------------------
-- Texte
---------------------------------------------------------------------------
local STATUS_TEXT = { log = "im Questlog", erledigt = "erledigt", verfuegbar = "verfügbar", spaeter = "später" }
local STATUS_FARBE = { log = "gruen", erledigt = "grau", verfuegbar = "gelb", spaeter = "rot" }
local STATUS_RANG = { log = 1, verfuegbar = 2, spaeter = 3, erledigt = 4 }

local NOTIZ = {
  ["All four wings on one map."] = "Alle vier Flügel auf einer Karte.",
  ["All three wings on one map."] = "Alle drei Flügel auf einer Karte.",
  ["Left: the sewers. Right: the city."] = "Links: die Kanalisation. Rechts: die Stadt.",
  ["Overhead view (no boss labels)."] = "Ansicht von oben (ohne Boss-Beschriftung).",
  ["Overhead view: floors overlap."] = "Ansicht von oben: Etagen liegen übereinander.",
  ["Overhead view: upper and lower levels overlap."] = "Ansicht von oben: obere und untere Ebene liegen übereinander.",
}
local QUELLE_URL = { ["Wowhead"] = "wowhead.com", ["Icy Veins"] = "icy-veins.com", ["Warcraft Tavern"] = "warcrafttavern.com" }
local FLUEGEL = { Graveyard = "Friedhof", Library = "Bibliothek", Armory = "Waffenkammer", Cathedral = "Kathedrale" }

---------------------------------------------------------------------------
-- Datenzugriff (alles abgesichert: fehlende Tabellen sind leer)
---------------------------------------------------------------------------
local LEER = {}
local function tab(t) return type(t) == "table" and t or LEER end
local function quelle(name) return tab(WW.quelle and WW.quelle[name]) end
local function fdm() return quelle("fdm") end
local function fdb() return quelle("fdb") end
local function helper() return quelle("helper") end

-- "a|b||c" -> { "a", "b", "", "c" }
local function teile(s, trenner)
  local t, start = {}, 1
  while true do
    local i = string.find(s, trenner, start, true)
    if not i then
      t[#t + 1] = string.sub(s, start)
      return t
    end
    t[#t + 1] = string.sub(s, start, i - 1)
    start = i + 1
  end
end

local function koord(x, y)
  x, y = tonumber(x), tonumber(y)
  if not x or not y then return nil end
  return string.format("%.1f, %.1f", x, y)
end

-- Deutscher Zonenname zu einer uiMap-ID (aus dem Spiel).
local zonenCache = {}
local function zonenName(uiMap)
  uiMap = tonumber(uiMap)
  if not uiMap then return nil end
  if zonenCache[uiMap] ~= nil then return zonenCache[uiMap] or nil end
  local name = false
  if C_Map and C_Map.GetMapInfo then
    local ok, info = pcall(C_Map.GetMapInfo, uiMap)
    if ok and type(info) == "table" and type(info.name) == "string" and info.name ~= "" then name = info.name end
  end
  zonenCache[uiMap] = name
  return name or nil
end

-- Englischer NPC-/Objektname aus ForeverDB ("Name|Orte").
local function npcName(id)
  local s = tab(fdb().qcNpc)[id]
  if type(s) == "string" then
    local n = s:match("^([^|]*)")
    if n and n ~= "" then return n end
  end
end
local function objName(id)
  local s = tab(fdb().qcObj)[id]
  if type(s) == "string" then
    local n = s:match("^([^|]*)")
    if n and n ~= "" then return n end
  end
end

-- Name eines Questziels: ForeverDB, sonst der Ersatz aus Ziele\Dungeon.lua
local function zielName(art, id)
  local n = (art == "o") and objName(id) or npcName(id)
  if n then return n end
  local zn = tab(tab(WW.quelle and WW.quelle.zielNamen)[art])[id]
  if type(zn) == "string" and zn ~= "" then return zn end
  return (art == "o" and "Objekt " or "Gegner ") .. tostring(id)
end

-- "n3636>6443:bmat..." -> art, id, item (oder nil), { x1, y1, x2, y2, ... }
local function zielLesen(s)
  if type(s) ~= "string" then return nil end
  local art, id, rest = s:match("^([no])(%d+)(.*)$")
  if not art then return nil end
  local item, punkte = rest:match("^>(%d+):(.*)$")
  if not item then punkte = rest:match("^:(.*)$") end
  if not punkte then return nil end
  local xy = {}
  for i = 1, #punkte - 3, 4 do
    local x, y = tonumber(punkte:sub(i, i + 1), 36), tonumber(punkte:sub(i + 2, i + 3), 36)
    if x and y and x <= 1000 and y <= 1000 then
      xy[#xy + 1] = x / 1000
      xy[#xy + 1] = y / 1000
    end
  end
  return art, tonumber(id), tonumber(item), xy
end
D.ZielLesen = zielLesen

local function itemText(id)
  return (id and WW.ItemName(id)) or ("Gegenstand " .. tostring(id))
end

---------------------------------------------------------------------------
-- Quests: Classic-Daten + Korrekturen + Ketten (wie ForeverDungeonMap)
---------------------------------------------------------------------------
local quests, folger, questsNachDungeon

local function wendeKetteAn(id, kette)
  local q, vorher = quests[id], nil
  if not q then return end
  local stufen = tab(fdm().stepLevels)
  for _, schritt in ipairs(kette) do
    if type(schritt) == "number" and schritt ~= id then
      local s = quests[schritt]
      if not s then
        s = { id = schritt }
        quests[schritt] = s
      end
      s.prev = vorher or s.prev
      if s.faction == nil and s.kettenFraktion == nil then
        s.faction, s.kettenFraktion = q.faction, q.faction or "Both"
      elseif s.kettenFraktion and s.kettenFraktion ~= (q.faction or "Both") then
        s.faction, s.kettenFraktion = nil, "Both"
      end
      s.level = s.level or stufen[schritt]
      vorher = schritt
    end
  end
  if vorher then q.prev = vorher end
end

local function baueQuests()
  quests, folger, questsNachDungeon = {}, {}, {}
  local f = fdm()
  for id, b in pairs(tab(f.data)) do
    if type(id) == "number" and type(b) == "table" then
      local q = { id = id }
      for k, v in pairs(b) do q[k] = v end
      quests[id] = q
    end
  end
  for id, c in pairs(tab(f.curated)) do
    if type(id) == "number" and type(c) == "table" then
      local q = quests[id] or { id = id }
      for k, v in pairs(c) do q[k] = v end
      q.id = id
      quests[id] = q
    end
  end
  for id, c in pairs(tab(f.curated)) do
    if type(c) == "table" and type(c.chain) == "table" then wendeKetteAn(id, c.chain) end
  end

  local mengen = {}
  local function dazu(inst, id)
    inst = tonumber(inst)
    if not inst then return end
    mengen[inst] = mengen[inst] or {}
    mengen[inst][id] = true
  end
  for id, q in pairs(quests) do
    if q.prev then
      folger[q.prev] = folger[q.prev] or {}
      table.insert(folger[q.prev], id)
    end
    if q.instance and not q.hide then dazu(q.instance, id) end
  end
  -- Flügel (Scharlachrotes Kloster): ihre Quests gehören auch dazu
  for inst, d in pairs(tab(f.dungeons)) do
    if type(d) == "table" and type(d.wings) == "table" then
      for _, w in ipairs(d.wings) do
        if type(w) == "table" then
          for _, qid in ipairs(tab(w.quests)) do
            local q = quests[qid]
            if q and not q.hide then
              q.fluegel = q.fluegel or w.name
              dazu(inst, qid)
            end
          end
        end
      end
    end
  end
  for inst, menge in pairs(mengen) do
    local liste = {}
    for id in pairs(menge) do liste[#liste + 1] = id end
    table.sort(liste)
    questsNachDungeon[inst] = liste
  end
end

local function Quests()
  if not quests then baueQuests() end
  return quests
end

function D.Quest(id)
  id = tonumber(id)
  return id and Quests()[id] or nil
end

-- Felder aus ForeverDB: "title|level|min level|side|classes|races|needs all|needs one|excl|starts|ends|objectives|skill|flags"
local qcCache = {}
local function qcFelder(id)
  local c = qcCache[id]
  if c == nil then
    local s = tab(fdb().qcQuests)[id]
    c = type(s) == "string" and teile(s, "|") or false
    qcCache[id] = c
  end
  return c or nil
end

local function questStufe(q)
  local l = tonumber(q.level)
  if l and l > 0 then return l end
  local qc = qcFelder(q.id)
  l = qc and tonumber(qc[2])
  if l and l > 0 then return l end
  return nil
end

-- Mindeststufe: aus ForeverDB, sonst Queststufe - 5 (Schätzung).
local function questMinStufe(q)
  local qc = qcFelder(q.id)
  local l = qc and tonumber(qc[3])
  if l and l > 0 then return l end
  local s = questStufe(q)
  if s and s > 5 then return s - 5 end
  return nil
end

local function questFraktion(q)
  if q.faction then return q.faction end
  local qc = qcFelder(q.id)
  if qc then
    if qc[4] == "a" then return "Alliance" elseif qc[4] == "h" then return "Horde" end
  end
  return nil
end

-- Kann der Spieler (Fraktion, Klasse, Volk) die Quest annehmen?
local function kannAnnehmen(q)
  local fraktion = questFraktion(q)
  local meine = UnitFactionGroup and UnitFactionGroup("player")
  if fraktion and fraktion ~= "Both" and meine and (meine == "Alliance" or meine == "Horde") and fraktion ~= meine then
    return false
  end
  if type(q.classes) == "table" and #q.classes > 0 then
    local _, klasse = UnitClass("player")
    local passt = false
    for _, c in ipairs(q.classes) do if c == klasse then passt = true end end
    if not passt then return false end
  end
  local maske = tonumber(q.races)
  if maske and bit and bit.band and bit.lshift then
    local rasse = tonumber((select(3, UnitRace("player"))))
    if rasse and rasse >= 1 and rasse <= 8 and bit.band(maske, bit.lshift(1, rasse - 1)) == 0 then
      return false
    end
  end
  return true
end
D.KannAnnehmen = kannAnnehmen

---------------------------------------------------------------------------
-- Questlog und Status
---------------------------------------------------------------------------
local logDaten          -- [questID] = { index, titel, fertig, ziele } oder false
local erledigtCache = {}
local namenCache = {}   -- deutsche Questnamen aus dem Spiel
local angefragt = {}

local function leseLog()
  logDaten = {}
  local ql = C_QuestLog
  -- WW.QuestLogEintraege: C_QuestLog.GetInfo (Forever), sonst das alte GetQuestLogTitle
  for _, e in ipairs(WW.QuestLogEintraege()) do
    if not e.kopf and e.questID then
      local fertig = e.fertig
      if not fertig and ql and ql.IsComplete then
        local ok3, r = pcall(ql.IsComplete, e.questID)
        if ok3 and r then fertig = true end
      end
      logDaten[e.questID] = { index = e.index, titel = e.titel, fertig = fertig }
    end
  end
end

-- Eintrag im Questlog oder nil.
local function imLog(id)
  if not logDaten then leseLog() end
  local e = logDaten[id]
  if e ~= nil then return e or nil end
  -- Quests unter eingeklappten Überschriften
  local ql = C_QuestLog
  e = false
  if ql and ql.GetLogIndexForQuestID then
    local ok, idx = pcall(ql.GetLogIndexForQuestID, id)
    if ok and tonumber(idx) and idx > 0 then e = { index = idx, fertig = false } end
  end
  if not e and ql and ql.IsOnQuest then
    local ok, r = pcall(ql.IsOnQuest, id)
    if ok and r then e = { fertig = false } end
  end
  if e and ql and ql.IsComplete then
    local ok, r = pcall(ql.IsComplete, id)
    if ok and r then e.fertig = true end
  end
  logDaten[id] = e
  return e or nil
end

-- Ziele aus dem Questlog (deutsch, mit Fortschritt): { {text, fertig}, ... } oder nil.
local function logZiele(id)
  local e = imLog(id)
  if not e then return nil end
  if e.ziele then return e.ziele end
  local ziele = {}
  local ql = C_QuestLog
  if ql and ql.GetQuestObjectives then
    local ok, objs = pcall(ql.GetQuestObjectives, id)
    if ok and type(objs) == "table" then
      for _, o in ipairs(objs) do
        if type(o) == "table" and type(o.text) == "string" and o.text ~= "" then
          ziele[#ziele + 1] = { text = o.text, fertig = o.finished and true or false }
        end
      end
    end
  end
  if #ziele == 0 and e.index and GetNumQuestLeaderBoards and GetQuestLogLeaderBoard then
    local ok, n = pcall(GetNumQuestLeaderBoards, e.index)
    n = ok and tonumber(n) or 0
    for j = 1, n do
      local ok2, text, _, fertig = pcall(GetQuestLogLeaderBoard, j, e.index)
      if ok2 and type(text) == "string" and text ~= "" then
        ziele[#ziele + 1] = { text = text, fertig = fertig and true or false }
      end
    end
  end
  e.ziele = ziele
  return ziele
end

-- Questname: deutsch aus dem Questlog oder vom Spiel, sonst englisch aus den Daten.
function D.QuestName(q)
  local id = q.id
  if namenCache[id] then return namenCache[id] end
  local e = imLog(id)
  if e and type(e.titel) == "string" and e.titel ~= "" then
    namenCache[id] = e.titel
    return e.titel
  end
  local ql = C_QuestLog
  if ql then
    local t
    if ql.GetTitleForQuestID then
      local ok, r = pcall(ql.GetTitleForQuestID, id)
      if ok and type(r) == "string" and r ~= "" then t = r end
    end
    if not t and ql.GetQuestInfo then
      local ok, r = pcall(ql.GetQuestInfo, id)
      if ok and type(r) == "string" and r ~= "" then t = r end
    end
    if t then
      namenCache[id] = t
      return t
    end
    if not angefragt[id] and ql.RequestLoadQuestByID then
      angefragt[id] = true
      pcall(ql.RequestLoadQuestByID, id)
    end
  end
  local qc = qcFelder(id)
  return q.name or (qc and qc[1] ~= "" and qc[1]) or ("Quest " .. tostring(id))
end

local function questNameID(id)
  return D.QuestName(D.Quest(id) or { id = id })
end

local function istAbgeschlossen(id)
  return WW.QuestErledigt(id) or false
end

-- Erledigt. Ein Schritt zählt auch als erledigt, wenn ein späterer Schritt erledigt oder im Log ist.
local function istErledigt(id, tiefe)
  local s = erledigtCache[id]
  if s ~= nil then return s end
  erledigtCache[id] = false
  local r = istAbgeschlossen(id)
  tiefe = tiefe or 0
  if not r and tiefe < 15 then
    Quests()
    for _, f in ipairs(folger[id] or LEER) do
      local fq = quests[f]
      if not (fq and fq.repeatable) and (imLog(f) or istErledigt(f, tiefe + 1)) then
        r = true
        break
      end
    end
  end
  erledigtCache[id] = r
  return r
end

-- Quests, die man nur machen kann, solange eine andere im Log ist (ForeverDB qcDuring): [quest] = die andere
local waehrendIdx
local function waehrend(id)
  if not waehrendIdx then
    waehrendIdx = {}
    for haupt, s in pairs(tab(fdb().qcDuring)) do
      if type(s) == "string" then
        for h in s:gmatch("(%d+)") do waehrendIdx[tonumber(h)] = tonumber(haupt) end
      end
    end
  end
  return waehrendIdx[id]
end

-- Voraussetzung p erfüllt? (Quests, die du nie annehmen kannst, z. B. die der anderen Fraktion, zählen nicht)
local function vorausErfuellt(p)
  local pq = D.Quest(p) or { id = p }
  if not kannAnnehmen(pq) then return true end
  return istErledigt(p)
end

-- "log" | "erledigt" | "verfuegbar" | "spaeter", dazu ein Grund bei "spaeter".
function D.Status(q)
  if imLog(q.id) then return "log" end
  if istErledigt(q.id) then return "erledigt" end
  local qc = qcFelder(q.id)
  if qc then
    -- exklusive Gruppe: nur eine der Quests geht
    local gruppe = tonumber(qc[9])
    local mitglieder = gruppe and gruppe > 0 and tab(fdb().qcExcl)[gruppe]
    if type(mitglieder) == "string" then
      for o in mitglieder:gmatch("%d+") do
        o = tonumber(o)
        if o ~= q.id then
          if istErledigt(o) then return "erledigt", "eine andere Quest dieser Auswahl ist erledigt" end
          if imLog(o) then return "spaeter", "nur eine davon: " .. questNameID(o) .. " ist im Questlog" end
        end
      end
    end
    -- braucht alle
    for p in (qc[7] or ""):gmatch("%d+") do
      p = tonumber(p)
      if not vorausErfuellt(p) then
        if imLog(p) then return "spaeter", "Vorquest im Questlog: " .. questNameID(p) end
        return "spaeter", "Vorquest fehlt: " .. questNameID(p)
      end
    end
    -- braucht eine von
    local eine, erste = nil, nil
    for p in (qc[8] or ""):gmatch("%d+") do
      p = tonumber(p)
      erste = erste or p
      if istErledigt(p) then eine = true end
    end
    if erste and not eine then return "spaeter", "Vorquest fehlt: " .. questNameID(erste) end
  end
  local haupt = waehrend(q.id)
  if haupt and not imLog(haupt) then
    return "spaeter", "nur solange " .. questNameID(haupt) .. " im Questlog ist"
  end
  if q.prev then
    local p = D.Quest(q.prev)
    if (not p or kannAnnehmen(p)) and not istErledigt(q.prev) then
      if imLog(q.prev) then return "spaeter", "Vorquest im Questlog: " .. questNameID(q.prev) end
      return "spaeter", "Vorquest fehlt: " .. questNameID(q.prev)
    end
  end
  local minS = questMinStufe(q)
  local stufe = UnitLevel("player") or 1
  if minS and stufe < minS then return "spaeter", "ab Stufe " .. minS end
  return "verfuegbar"
end

-- Alle Zwischenspeicher für den Questlog leeren (nach Questlog-Änderungen).
local function frischeDaten()
  logDaten = nil
  wipe(erledigtCache)
end

---------------------------------------------------------------------------
-- Was eine Quest braucht (welche NPCs/Bosse, welche Gegenstände)
---------------------------------------------------------------------------
local bedarfCache = {}

-- { teile = { {art = "npc"|"item"|"obj", id, anzahl, npcs = {[npcID]=true}, wer = "Name/Name"} },
--   npcs = {[npcID] = true}, namen = {[englischer Name] = true} }
local function questBedarf(q, instanz)
  local c = bedarfCache[q.id]
  if c then return c end
  local bedarf = { teile = {}, npcs = {}, namen = {} }
  local qc = qcFelder(q.id)
  local zielText = qc and qc[12]
  if zielText and zielText ~= "" then
    for stueck in zielText:gmatch("[^;]+") do
      local art, rest = stueck:match("^(%a)(.+)$")
      if art == "c" then
        local id, anz, kredit = rest:match("^(%d+):?(%d*):?(.*)$")
        id = tonumber(id)
        if id then
          local t = { art = "npc", id = id, anzahl = tonumber(anz), npcs = { [id] = true } }
          for k in (kredit or ""):gmatch("%d+") do t.npcs[tonumber(k)] = true end
          bedarf.teile[#bedarf.teile + 1] = t
        end
      elseif art == "i" then
        local id, anz = rest:match("^(%d+):?(%d*)")
        id = tonumber(id)
        if id then
          local t = { art = "item", id = id, anzahl = tonumber(anz), npcs = {} }
          local quellen = tab(fdb().qcItem)[id]
          if type(quellen) == "string" then
            -- nur die wahrscheinlichsten Quellen (nicht jeder Gegner, der es selten fallen lässt)
            local liste, beste = {}, 0
            for n, p in quellen:gmatch("n(%d+):([%d%.]+)") do
              n, p = tonumber(n), tonumber(p) or 0
              if n then
                liste[#liste + 1] = { n, p }
                if p > beste then beste = p end
              end
            end
            for _, e in ipairs(liste) do
              if e[2] >= 25 or e[2] >= beste * 0.5 then t.npcs[e[1]] = true end
            end
          end
          bedarf.teile[#bedarf.teile + 1] = t
        end
      elseif art == "o" then
        local id, anz = rest:match("^(%d+):?(%d*)")
        id = tonumber(id)
        if id then bedarf.teile[#bedarf.teile + 1] = { art = "obj", id = id, anzahl = tonumber(anz), npcs = {} } end
      end
    end
  end
  -- Gegenstände, die im Dungeon fallen: "Gegenstand:Quest:wer/wer;..."
  local dg = tab(fdb().dgClassic)[tonumber(instanz) or q.instance]
  if type(dg) == "table" and type(dg.qi) == "string" then
    for eintrag in dg.qi:gmatch("[^;]+") do
      local item, quest, wer = eintrag:match("^(%d+):(%d+):(.*)$")
      if tonumber(quest) == q.id and wer and wer ~= "" then
        item = tonumber(item)
        local gefunden
        for _, t in ipairs(bedarf.teile) do
          if t.art == "item" and t.id == item then gefunden = t end
        end
        if not gefunden then
          gefunden = { art = "item", id = item, npcs = {} }
          bedarf.teile[#bedarf.teile + 1] = gefunden
        end
        gefunden.wer = wer
        for name in wer:gmatch("[^/]+") do bedarf.namen[name] = true end
      end
    end
  end
  for _, n in ipairs(tab(q.npcs)) do
    if tonumber(n) then bedarf.npcs[tonumber(n)] = true end
  end
  for _, t in ipairs(bedarf.teile) do
    for n in pairs(t.npcs) do bedarf.npcs[n] = true end
  end
  bedarfCache[q.id] = bedarf
  return bedarf
end

---------------------------------------------------------------------------
-- Dungeons
---------------------------------------------------------------------------
local function gueltigeKarte(m)
  if type(m) ~= "table" or type(m.file) ~= "string" or m.file == "" then return nil end
  local w, h = tonumber(m.w), tonumber(m.h)
  if not w or not h or w <= 0 or h <= 0 then return nil end
  local tw, th = tonumber(m.tw) or w, tonumber(m.th) or h
  if tw < w then tw = w end
  if th < h then th = h end
  return { file = m.file, w = w, h = h, tw = tw, th = th, credit = m.credit, note = m.note, bosses = tab(m.bosses) }
end

-- Bosse in Reihenfolge: Daten + Korrekturen (Reihenfolge, npcID). Ersatz: Helper-Bosse.
local function bosseZusammen(src, fix, h)
  local liste = {}
  if src and type(src.bosses) == "table" then
    for _, b in ipairs(src.bosses) do
      if type(b) == "table" and b.name then liste[#liste + 1] = b end
    end
  end
  if #liste == 0 and h and type(h.bosses) == "table" then
    for _, b in ipairs(h.bosses) do
      if type(b) == "table" and b.n then liste[#liste + 1] = { name = b.n, encounter = b.enc } end
    end
  end
  local nachName = {}
  for _, b in ipairs(liste) do nachName[b.name] = b end
  local namen = fix and type(fix.order) == "table" and fix.order
  if not namen then
    namen = {}
    for i, b in ipairs(liste) do namen[i] = b.name end
  end
  local raus = {}
  for _, name in ipairs(namen) do
    if type(name) == "string" then
      local m = {}
      for k, v in pairs(nachName[name] or { name = name }) do m[k] = v end
      local f = fix and type(fix.bosses) == "table" and fix.bosses[name]
      if type(f) == "table" then
        for k, v in pairs(f) do m[k] = v end
      end
      m.name = name
      m.npcID = tonumber(m.npcID)
      raus[#raus + 1] = m
    end
  end
  return raus
end

-- Bossnamen vergleichen: gleiche Schreibweise ohne Zeichen, enthalten, oder höchstens 2 Buchstaben anders
local function normName(s)
  s = tostring(s or ""):lower():gsub("^the ", "")
  return (s:gsub("[^%w]", ""))
end

local function abstand(a, b)
  if math.abs(#a - #b) > 2 then return 99 end
  local vorher = {}
  for j = 0, #b do vorher[j] = j end
  for i = 1, #a do
    local jetzt = { [0] = i }
    for j = 1, #b do
      local kosten = (a:sub(i, i) == b:sub(j, j)) and 0 or 1
      jetzt[j] = math.min(vorher[j] + 1, jetzt[j - 1] + 1, vorher[j - 1] + kosten)
    end
    vorher = jetzt
  end
  return vorher[#b]
end

local function namePasst(a, b)
  a, b = normName(a), normName(b)
  if a == "" or b == "" then return false end
  if a == b then return true end
  if #a < 5 or #b < 5 then return false end
  if a:find(b, 1, true) or b:find(a, 1, true) then return true end
  return abstand(a, b) <= 2
end

-- Helper-Bosse (Forever-Client) den Bossen der Liste zuordnen: { [helperIndex] = boss }.
-- Erst Encounter-ID, dann Name, dann ähnliche Schreibweise; bleibt auf beiden Seiten genau einer übrig,
-- ist es derselbe Boss unter neuem Namen (z. B. Infurnus/Magmatus).
local function helperZuordnung(bosse, hb)
  local zu, genommen = {}, {}
  if type(hb) ~= "table" then return zu end
  local function versuche(pruef)
    for i, h in ipairs(hb) do
      if type(h) == "table" and not zu[i] then
        for _, b in ipairs(bosse) do
          if not genommen[b] and pruef(h, b) then
            zu[i], genommen[b] = b, true
            break
          end
        end
      end
    end
  end
  versuche(function(h, b) return tonumber(h.enc) ~= nil and tonumber(b.encounter) == tonumber(h.enc) end)
  versuche(function(h, b) return normName(h.n) == normName(b.name) end)
  versuche(function(h, b) return namePasst(h.n, b.name) end)
  local offenH, offenB = {}, {}
  for i, h in ipairs(hb) do if type(h) == "table" and not zu[i] then offenH[#offenH + 1] = i end end
  for _, b in ipairs(bosse) do if not genommen[b] then offenB[#offenB + 1] = b end end
  if #offenH == 1 and #offenB == 1 then zu[offenH[1]] = offenB[1] end
  return zu
end

local dungeonCache = {}

-- Dungeon-Eintrag: { id, name, min, max, raid, karte, bosse, bossNachNpc, quests = {IDs} } oder nil.
function D.Dungeon(id)
  id = tonumber(id)
  if not id then return nil end
  local d = dungeonCache[id]
  if d ~= nil then return d or nil end
  Quests()
  local f = fdm()
  local src = tab(f.dungeons)[id]
  if type(src) ~= "table" then src = nil end
  local fix = tab(f.curatedDungeons)[id]
  if type(fix) ~= "table" then fix = nil end
  local h = tab(helper().dungeons)[id]
  if type(h) ~= "table" then h = nil end
  local karte = gueltigeKarte(tab(f.guideMapData)[id])
  local qliste = questsNachDungeon[id] or {}
  if not src and not h and not karte and #qliste == 0 then
    dungeonCache[id] = false
    return nil
  end
  local minS, maxS
  if h and type(h.lv) == "table" then minS, maxS = tonumber(h.lv[1]), tonumber(h.lv[2]) end
  if not minS and src then minS, maxS = tonumber(src.min), tonumber(src.max) end
  local ok, name = pcall(WW.DungeonName, id)
  if not ok or type(name) ~= "string" or name == "" then
    name = (src and src.name) or (h and h.n) or ("Dungeon " .. id)
  end
  d = {
    id = id, name = name, min = minS, max = maxS or minS,
    raid = (src and src.raid) or (h and h.kind == "raid") or false,
    karte = karte, bosse = bosseZusammen(src, fix, h), quests = qliste,
    src = src, fix = fix, h = h, bossNachNpc = {},
  }
  -- Helper-Bosse den Bossen zuordnen (Encounter, Name, Schreibweise, umbenannt): helperZu[i] = Boss
  d.helperZu = helperZuordnung(d.bosse, h and h.bosses)
  for i, b in pairs(d.helperZu) do
    local hb = h.bosses[i]
    if b.encounter == nil and type(hb) == "table" then b.encounter = tonumber(hb.enc) end
  end
  -- NPC-IDs aus ForeverDB dgClassic ("reihenfolge:npc") für Bosse ohne ID (z. B. Schlachtzüge nur aus dem Helper)
  local dg = tab(fdb().dgClassic)[id]
  if type(dg) == "table" and type(dg.npc) == "string" then
    for npc in dg.npc:gmatch("%d+:(%d+)") do
      npc = tonumber(npc)
      local nm = npcName(npc)
      local schon = false
      for _, b in ipairs(d.bosse) do if b.npcID == npc then schon = true end end
      if nm and not schon then
        for _, b in ipairs(d.bosse) do
          if not b.npcID and namePasst(nm, b.name) then
            b.npcID = npc
            break
          end
        end
      end
    end
    -- NPC ohne Namen in den Daten (z. B. Ragnaros): Boss über die Drop-Quellen seiner Beute bestimmen
    -- (ForeverDB-Itemfakten "d<Quelle>~...")
    if type(dg.loot) == "string" then
      local npcVon, frei = {}, {}
      for o, npc in dg.npc:gmatch("(%d+):(%d+)") do npcVon[tonumber(o)] = tonumber(npc) end
      for o, npc in pairs(npcVon) do
        local schon = false
        for _, b in ipairs(d.bosse) do if b.npcID == npc then schon = true end end
        if not schon then frei[o] = {} end
      end
      local items = tab(fdb().items)
      for it, o in dg.loot:gmatch("(%d+):(%d+):[%d%.]+") do
        local stimmen = frei[tonumber(o)]
        local s = stimmen and items[tonumber(it)]
        if type(s) == "string" then
          for feld in s:gmatch("[^|]+") do
            local quelleName = feld:match("^d([^~]+)~")
            if quelleName then
              for _, b in ipairs(d.bosse) do
                if not b.npcID and namePasst(quelleName, b.name) then stimmen[b] = (stimmen[b] or 0) + 1 end
              end
            end
          end
        end
      end
      for o, stimmen in pairs(frei) do
        local beste, n = nil, 0
        for b, z in pairs(stimmen) do if z > n and not b.npcID then beste, n = b, z end end
        if beste then beste.npcID = npcVon[o] end
      end
    end
  end
  for _, b in ipairs(d.bosse) do
    if b.npcID then d.bossNachNpc[b.npcID] = b end
  end
  dungeonCache[id] = d
  return d
end

local alleListe
-- Alle Dungeons mit Karte oder Quests, nach Stufe.
function D.Alle()
  if alleListe then return alleListe end
  Quests()
  local ids = {}
  for id in pairs(tab(fdm().dungeons)) do ids[id] = true end
  for id in pairs(tab(fdm().guideMapData)) do ids[id] = true end
  for id in pairs(tab(helper().dungeons)) do ids[id] = true end
  for id in pairs(questsNachDungeon) do ids[id] = true end
  alleListe = {}
  for id in pairs(ids) do
    local d = type(id) == "number" and D.Dungeon(id)
    if d and (d.karte or #d.quests > 0 or #d.bosse > 0) then alleListe[#alleListe + 1] = d end
  end
  table.sort(alleListe, function(a, b)
    if (a.min or 99) ~= (b.min or 99) then return (a.min or 99) < (b.min or 99) end
    return a.name < b.name
  end)
  return alleListe
end

-- Eingang: Zone (deutsch, wenn das Spiel sie kennt) und Koordinaten als Text, oder nil.
function D.Eingang(d)
  local map, x, y, zone
  local e = d.fix and d.fix.entrance
  if type(e) == "table" and e.map then
    map, x, y = e.map, e.x, e.y
  else
    local he = d.h and type(d.h.ent) == "table" and d.h.ent[1]
    if type(he) == "table" and he.m then
      map, x, y, zone = he.m, he.x, he.y, he.zone
    else
      e = d.src and d.src.entrance
      if type(e) == "table" and e[1] then map, x, y = e[1], e[2], e[3] end
    end
  end
  if not map then return nil end
  local name = zonenName(map) or zone
  local k = koord(x, y)
  if name and k then return name .. " " .. k end
  return name or k
end

-- Quests, die der Spieler annehmen kann.
function D.QuestsFuer(d)
  local raus = {}
  if not d then return raus end
  for _, id in ipairs(d.quests) do
    local q = quests[id]
    if q and kannAnnehmen(q) then raus[#raus + 1] = q end
  end
  return raus
end

function D.Zaehle(d)
  local z = { log = 0, verfuegbar = 0, spaeter = 0, erledigt = 0, alle = 0 }
  for _, q in ipairs(D.QuestsFuer(d)) do
    local s = D.Status(q)
    z[s] = (z[s] or 0) + 1
    z.alle = z.alle + 1
  end
  return z
end

---------------------------------------------------------------------------
-- Bosse und Beute
-- Quellen: ForeverDB_Helper (loot: in Forever gesehen "s" / Hinweis aus dem Client "c", b = Boss-Nummer, 0 = Trash),
-- DungeonMaster (Boss-Beute: Korrekturen = Forever-Liste "f", sonst Classic "k"),
-- ForeverDB dgClassic ("item:boss:prozent", Boss-Nummer -> NPC über dg.npc) für Classic-Chancen.
---------------------------------------------------------------------------
D.QUELLE_TEXT = { s = "in Forever gesehen", c = "Hinweis, unbestätigt", k = "Classic-Daten", f = "Forever-Liste" }

-- { boss = { [Bossname] = { {id, pct, kpct, quelle, why, from} } }, trash = {...} }, nach Chance sortiert
function D.Beute(d)
  if type(d) ~= "table" then return { boss = {}, trash = {} } end
  if d.beute then return d.beute end
  local b = { boss = {}, trash = {} }
  local function liste(name)
    if not name then return b.trash end
    b.boss[name] = b.boss[name] or {}
    return b.boss[name]
  end
  local function dazu(l, id, felder)
    id = tonumber(id)
    if not id then return end
    for _, e in ipairs(l) do
      if e.id == id then
        for k, v in pairs(felder) do if e[k] == nil then e[k] = v end end
        return
      end
    end
    local e = { id = id }
    for k, v in pairs(felder) do e[k] = v end
    l[#l + 1] = e
  end
  -- Helper: Boss-Nummer zeigt in dessen Bossliste
  local h = d.h
  if type(h) == "table" then
    local hb = tab(h.bosses)
    for _, x in ipairs(tab(h.loot)) do
      if type(x) == "table" then
        local nr = tonumber(x.b)
        local bn = nr and nr > 0 and type(hb[nr]) == "table" and hb[nr].n or nil
        local zu = nr and tab(d.helperZu)[nr]
        if bn and zu then bn = zu.name end   -- gleicher Boss, Name aus der Bossliste
        dazu(liste(bn), x.id, { pct = tonumber(x.pct), kpct = tonumber(x.kpct),
          quelle = x.src == "c" and "c" or "s", why = x.why, from = x.from })
      end
    end
  end
  -- DungeonMaster: Beute je Boss
  for _, boss in ipairs(tab(d.bosse)) do
    local fixB = d.fix and type(d.fix.bosses) == "table" and d.fix.bosses[boss.name]
    for _, id in ipairs(tab(type(fixB) == "table" and fixB.loot)) do dazu(liste(boss.name), id, { quelle = "f" }) end
    for _, sb in ipairs(tab(d.src and d.src.bosses)) do
      if type(sb) == "table" and sb.name == boss.name then
        for _, id in ipairs(tab(sb.loot)) do dazu(liste(boss.name), id, { quelle = "k" }) end
      end
    end
  end
  -- ForeverDB dgClassic: Classic-Chancen
  local dg = tab(fdb().dgClassic)[d.id]
  if type(dg) == "table" and type(dg.loot) == "string" then
    local npcVon = {}
    if type(dg.npc) == "string" then
      for o, n in dg.npc:gmatch("(%d+):(%d+)") do npcVon[tonumber(o)] = tonumber(n) end
    end
    for it, o, p in dg.loot:gmatch("(%d+):(%d+):([%d%.]+)") do
      o = tonumber(o)
      local bn
      if o and o > 0 then
        local boss = npcVon[o] and tab(d.bossNachNpc)[npcVon[o]]
        bn = boss and boss.name
      end
      if o == 0 or bn then dazu(liste(bn), it, { kpct = tonumber(p), quelle = "k" }) end
    end
  end
  local function chance(e) return e.pct or e.kpct or -1 end
  local function sortiere(l)
    table.sort(l, function(a, c)
      if chance(a) ~= chance(c) then return chance(a) > chance(c) end
      return a.id < c.id
    end)
  end
  for _, l in pairs(b.boss) do sortiere(l) end
  sortiere(b.trash)
  d.beute = b
  return b
end

-- Bosse in Reihenfolge, dazu Bosse, die nur in der Beute vorkommen, und der Trash:
-- { {name, boss, rare, secret, nur, beute, trash} }
function D.BossListe(d)
  local raus = {}
  if type(d) ~= "table" then return raus end
  local b = D.Beute(d)
  local gesehen = {}
  local nurNormal = {}
  for i, hb in ipairs(tab(d.h and d.h.bosses)) do
    if type(hb) == "table" and hb.n and hb.only then
      local zu = tab(d.helperZu)[i]
      nurNormal[zu and zu.name or hb.n] = hb.only
    end
  end
  for _, boss in ipairs(tab(d.bosse)) do
    gesehen[boss.name] = true
    raus[#raus + 1] = { name = boss.name, boss = boss, rare = boss.rare and true or false,
      nur = nurNormal[boss.name], beute = b.boss[boss.name] or {} }
  end
  local extra = {}
  for name in pairs(b.boss) do if not gesehen[name] then extra[#extra + 1] = name end end
  table.sort(extra)
  for _, name in ipairs(extra) do raus[#raus + 1] = { name = name, rare = false, beute = b.boss[name] } end
  if #b.trash > 0 then raus[#raus + 1] = { name = "Trash und ganze Instanz", trash = true, beute = b.trash } end
  return raus
end

---------------------------------------------------------------------------
-- Questgeber und Folgequests auf der Weltkarte (HereBeDragons)
-- "!" beim Geber jeder Dungeon-Quest (und jedes Kettenschritts), die du jetzt annehmen kannst;
-- nach einem Schritt erscheint der Geber des nächsten von selbst. "?" beim Abgabe-NPC fertiger Quests.
---------------------------------------------------------------------------
local WELT_REF = "WegweiserDungeonQuests"
local weltPool, weltGruppen = {}, {}
local dungeonVonCache = {}

-- Dungeon einer Quest: ihr eigener, sonst der des nächsten Kettenschritts mit Dungeon
local function dungeonVon(q, tiefe)
  if q.instance then return tonumber(q.instance) end
  local c = dungeonVonCache[q.id]
  if c ~= nil then return c or nil end
  tiefe = tiefe or 0
  local r
  if tiefe < 12 then
    for _, f in ipairs(folger[q.id] or LEER) do
      local fq = quests[f]
      if fq then r = dungeonVon(fq, tiefe + 1) end
      if r then break end
    end
  end
  dungeonVonCache[q.id] = r or false
  return r
end

-- Schritt und Länge der Kette (nur Schritte, die du annehmen kannst): pos, gesamt
local function kettenPos(q)
  local zurueck, p, gesehen = 0, q.prev, { [q.id] = true }
  while p and not gesehen[p] and zurueck < 25 do
    gesehen[p] = true
    local pq = quests[p]
    if not pq then break end
    if kannAnnehmen(pq) then zurueck = zurueck + 1 end
    p = pq.prev
  end
  local vor, n = 0, q.id
  while vor < 25 do
    local naechste
    for _, f in ipairs(folger[n] or LEER) do
      local fq = quests[f]
      if fq and not gesehen[f] and kannAnnehmen(fq) then naechste = f break end
    end
    if not naechste then break end
    gesehen[naechste] = true
    vor = vor + 1
    n = naechste
  end
  return zurueck + 1, zurueck + 1 + vor
end

-- Ort eines NPC/Objekts aus ForeverDB: "Name|ort ort" mit ort = Basis 36 von karte*1e6 + x*10*1e3 + y*10
-- erster Ort einer Liste "ort ort ..." -> karte, x, y (0..1) oder nil
local function ortAusSpots(s)
  local ort = type(s) == "string" and s:match("(%w+)")
  local v = ort and tonumber(ort, 36)
  if not v then return nil end
  local m = math.floor(v / 1000000)
  local rest = v % 1000000
  local x, y = math.floor(rest / 1000) / 1000, (rest % 1000) / 1000
  if m <= 0 or x < 0 or x > 1 or y < 0 or y > 1 then return nil end
  return m, x, y
end

local function ortAusFDB(art, id)
  local s = tab(art == "o" and fdb().qcObj or fdb().qcNpc)[id]
  local m, x, y
  if type(s) == "string" then m, x, y = ortAusSpots(s:match("|(.*)$")) end
  -- Forever-Daten: wo Spieler den NPC gesehen haben
  if not m and art ~= "o" then m, x, y = ortAusSpots(tab(fdb().qfNpcSpots)[id]) end
  return m, x, y
end

-- ForeverDB-Forever-Quests: "titel|stufe|min|ziel|start|ende|spieler|neu|vorquest|niedrigste|seite"
local qfCache = {}
local function qfFelder(id)
  local c = qfCache[id]
  if c == nil then
    local s = tab(fdb().qfQuests)[id]
    c = type(s) == "string" and teile(s, "|") or false
    qfCache[id] = c
  end
  return c or nil
end

-- Name eines NPCs (Forever-Daten, sonst Classic)
local function npcNameForever(id)
  local n = tab(fdb().qfNpcNames)[id]
  if type(n) == "string" and n ~= "" then return n end
  return npcName(id)
end

-- Wo startet ("s") bzw. endet ("e") eine Quest laut den Forever-Daten?
-- Questpunkt des Clients, sonst was Spieler gesehen haben, sonst der Ort des Start-/Abgabe-NPCs.
-- karte, x, y (0..1), npcID oder nil
local function forOrt(q, wo)
  local m, x, y
  for _, quelleT in ipairs({ fdb().qfPoi, fdb().qfSeen }) do
    local p = tab(quelleT)[q.id]
    if not m and type(p) == "table" then m, x, y = ortAusSpots(p[wo]) end
  end
  local f = qfFelder(q.id)
  local feld = f and f[wo == "s" and 5 or 6]
  local art, id = (feld or ""):match("^(%a)(%d+)")
  id = tonumber(id)
  if not m and id then m, x, y = ortAusFDB(art, id) end
  if not m then return nil end
  return m, x, y, art == "n" and id or nil
end

-- Abgabe-NPC: ForeverDB-Classic (Feld "ende"), sonst die Forever-Daten. karte, x, y (0..1), npcID oder nil
local function abgabeOrt(q)
  local qc = qcFelder(q.id)
  local ende = qc and qc[11]
  local art, id = (ende or ""):match("^(%a)(%d+)")
  id = tonumber(id)
  if id then
    local m, x, y = ortAusFDB(art, id)
    if m then return m, x, y, art == "n" and id or nil end
  end
  return forOrt(q, "e")
end

local function grauGrenze()
  local f = WW.Alt("GetQuestGreenRange")
  if f then
    local ok, r = pcall(f)
    if ok and tonumber(r) then return tonumber(r) end
  end
  return 8
end

-- Welche Nadeln gehören auf die Weltkarte? Gruppen { art = "geber"|"abgabe", map, x, y, quests = {q...} }
function D.WeltPinsBerechnen()
  local raus = {}
  local e = WW.db and WW.db.dungeonKarte
  if not (e and e.weltPins) then return raus end
  Quests()
  local stufe = UnitLevel("player") or 1
  local grau = grauGrenze()
  local nachOrt = {}
  local function dazu(art, q, m, x, y)
    m, x, y = tonumber(m), tonumber(x), tonumber(y)
    if not m or not x or not y or x < 0 or x > 1 or y < 0 or y > 1 then return end
    local key = art .. ":" .. m .. ":" .. math.floor(x * 200) .. ":" .. math.floor(y * 200)
    local g = nachOrt[key]
    if not g then
      g = { art = art, map = m, x = x, y = y, quests = {}, npc = {} }
      nachOrt[key] = g
      raus[#raus + 1] = g
    end
    g.quests[#g.quests + 1] = q
    return g
  end
  for _, q in pairs(quests) do
    if not q.hide then
      local le = imLog(q.id)
      if le then
        if le.fertig then
          local m, x, y, npc = abgabeOrt(q)
          if m then
            local g = dazu("abgabe", q, m, x, y)
            if g and npc then g.npc[q.id] = npc end
          end
        end
      elseif not q.inside and kannAnnehmen(q) and D.Status(q) == "verfuegbar" then
        -- Ort des Gebers: DungeonMaster-Daten, sonst die Forever-Daten (Questpunkt, Sichtungen, NPC)
        local gm, gx, gy
        if q.map and q.x and q.y then
          gm, gx, gy = q.map, q.x / 100, q.y / 100
        else
          gm, gx, gy = forOrt(q, "s")
        end
        local lv = questStufe(q)
        -- Stufenfenster: oben +3 (nur passende Stufe), unten -5 bzw. die Grau-Grenze;
        -- "auch graue Quests" nimmt die untere Grenze weg
        local passt = true
        if lv then
          local unten = e.graue and -math.huge or (e.nurPassend and (stufe - 5) or (stufe - grau))
          local oben = e.nurPassend and (stufe + 3) or math.huge
          passt = lv >= unten and lv <= oben
        end
        if passt and gm then dazu("geber", q, gm, gx, gy) end
      end
    end
  end
  for _, g in ipairs(raus) do
    table.sort(g.quests, function(a, b) return (questStufe(a) or 0) < (questStufe(b) or 0) end)
  end
  return raus
end

local function weltPinTooltip(self)
  local g = self.gruppe
  if not g then return end
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  for i, q in ipairs(g.quests) do
    if i > 1 then GameTooltip:AddLine(" ") end
    local lv = questStufe(q)
    GameTooltip:AddLine((lv and ("[" .. lv .. "] ") or "") .. D.QuestName(q), 1, 0.82, 0)
    local inst = dungeonVon(q)
    if inst then
      local okN, dn = pcall(WW.DungeonName, inst)
      GameTooltip:AddLine("Dungeon: " .. ((okN and dn) or ("Dungeon " .. inst)), 0.6, 0.75, 1)
    end
    if g.art == "abgabe" then
      local npc = g.npc and g.npc[q.id]
      local wer = npc and npcNameForever(npc)
      GameTooltip:AddLine("Fertig - hier abgeben" .. (wer and (": " .. wer) or ""), 0.4, 1, 0.4)
    elseif q.npc then
      GameTooltip:AddLine("Questgeber: " .. q.npc, 1, 1, 1)
    end
    if q.prev then GameTooltip:AddLine("Folgequest von: " .. questNameID(q.prev), 0.8, 0.8, 0.8, true) end
    local pos, gesamt = kettenPos(q)
    if gesamt > 1 then GameTooltip:AddLine("Teil " .. pos .. " von " .. gesamt, 0.8, 0.8, 0.8) end
  end
  GameTooltip:AddLine("Daten: DungeonMaster (cMaNGOS), ForeverDB.net", 0.5, 0.5, 0.5)
  GameTooltip:Show()
end

local function weltPin(i)
  local pin = weltPool[i]
  if pin then return pin end
  pin = CreateFrame("Frame", nil, UIParent)
  pin:SetSize(16, 16)
  pin.icon = pin:CreateTexture(nil, "ARTWORK")
  pin.icon:SetAllPoints()
  pin:EnableMouse(true)
  if pin.SetMouseClickEnabled then pcall(pin.SetMouseClickEnabled, pin, false) end
  pin:SetScript("OnEnter", weltPinTooltip)
  pin:SetScript("OnLeave", GameTooltip_Hide)
  pin:Hide()
  weltPool[i] = pin
  return pin
end

local function hbdPins()
  if not LibStub then return nil end
  local ok, p = pcall(LibStub, "HereBeDragons-Pins-2.0", true)
  return ok and p or nil
end

-- Nadeln neu setzen. Gibt die Gruppen zurück (je Gruppe .pin).
function D.WeltPinsNeu()
  frischeDaten()
  local Pins = hbdPins()
  if Pins then pcall(Pins.RemoveAllWorldMapIcons, Pins, WELT_REF) end
  weltGruppen = D.WeltPinsBerechnen()
  local flag = tonumber(rawget(_G, "HBD_PINS_WORLDMAP_SHOW_CONTINENT")) or 2
  for i, g in ipairs(weltGruppen) do
    local pin = weltPin(i)
    pin.gruppe = g
    pin.icon:SetTexture(g.art == "abgabe" and "Interface\\GossipFrame\\ActiveQuestIcon"
      or "Interface\\GossipFrame\\AvailableQuestIcon")
    g.pin = pin
    if Pins then
      local ok, err = pcall(Pins.AddWorldMapIconMap, Pins, WELT_REF, pin, g.map, g.x, g.y, flag)
      if not ok and geterrorhandler then geterrorhandler()(err) end
    end
  end
  return weltGruppen
end

-- "71 %" (Forever), sonst "Classic 10 %", sonst ""
function D.ChanceText(e)
  if e.pct then return string.format("%d %%", math.floor(e.pct + 0.5)) end
  if e.kpct then return string.format("Classic %d %%", math.floor(e.kpct + 0.5)) end
  return ""
end

local function stufenText(d)
  if not d.min then return "" end
  if not d.max or d.max == d.min then return "(" .. d.min .. ")" end
  return "(" .. d.min .. "-" .. d.max .. ")"
end

local function stufenFarbe(d)
  local stufe = UnitLevel("player") or 1
  local mn, mx = d.min or 1, d.max or d.min or 60
  if stufe < mn - 2 then return "rot" end
  if stufe < mn then return "orange" end
  if stufe > mx then return "grau" end
  return "gelb"
end

local function zaehlText(z)
  if z.alle == 0 then return WW.f("grau", "keine Quests für dich") end
  local t = {}
  if z.verfuegbar > 0 then t[#t + 1] = WW.f("gelb", z.verfuegbar .. " verfügbar") end
  if z.log > 0 then t[#t + 1] = WW.f("gruen", z.log .. " im Log") end
  if z.erledigt > 0 then t[#t + 1] = WW.f("grau", z.erledigt .. " erledigt") end
  if z.spaeter > 0 then t[#t + 1] = WW.f("rot", z.spaeter .. " später") end
  return table.concat(t, " · ")
end

local function aktuelleInstanz()
  if not IsInInstance or not GetInstanceInfo then return nil end
  local drin, typ = IsInInstance()
  if not drin or not (typ == "party" or typ == "raid" or typ == "scenario") then return nil end
  return tonumber((select(8, GetInstanceInfo())))
end

-- Questgeber als Text.
local function geberText(q)
  if q.inside then
    if q.drop and q.npc then return "Start: fällt bei " .. q.npc .. " (im Dungeon)" end
    return "Questgeber im Dungeon" .. (q.npc and (": " .. q.npc) or "")
  end
  if q.npc then
    local t = "bei " .. q.npc
    local zone = zonenName(q.map)
    local k = koord(q.x, q.y)
    if k then
      t = t .. ", " .. (zone and (zone .. " ") or "") .. k
    elseif zone then
      t = t .. ", " .. zone
    end
    return t
  end
  if q.item then return "Start: Gegenstand " .. itemText(q.item) end
  return "Questgeber unbekannt"
end

---------------------------------------------------------------------------
-- Kartenfenster
---------------------------------------------------------------------------
local fenster, port, canvas, bild
local auswahl            -- Instanz-ID im Fenster
local gewaehlteQuest     -- questID
local karte              -- gueltigeKarte() des gezeigten Dungeons
local zoom, ox, oy = 1, 0, 0
local ziehen
local nadeln, zielNadeln = {}, {}
local zeigeDungeon       -- vorwärts
local tabPanel           -- Reiter-Panel (zum Aktualisieren)
local ansicht = "quests" -- rechte Seite: "quests" | "bosse"
local gewaehlterBoss     -- Name des gewählten Bosses (Ansicht "bosse")

local function cursorImPort()
  local x, y = GetCursorPosition()
  local s = port:GetEffectiveScale()
  local cx, cy = port:GetCenter()
  if not cx or not s or s == 0 then return 0, 0 end
  return x / s - cx, y / s - cy
end

local function platziereNadeln()
  local cw, ch = canvas:GetSize()
  for _, liste in ipairs({ nadeln, zielNadeln }) do
    for _, n in ipairs(liste) do
      if n:IsShown() then
        n:ClearAllPoints()
        n:SetPoint("CENTER", canvas, "TOPLEFT", n.x * cw, -n.y * ch)
      end
    end
  end
end

-- Bild in den Rahmen einpassen (Seitenverhältnis bleibt), Zoom und Verschiebung anwenden.
local function passeAn()
  if not karte then return end
  local vw, vh = port:GetSize()
  if not vw or not vh or vw <= 0 or vh <= 0 then return end
  local s = math.min(vw / karte.w, vh / karte.h)
  local cw, ch = karte.w * s * zoom, karte.h * s * zoom
  canvas:SetSize(cw, ch)
  local mx, my = math.max(0, (cw - vw) / 2), math.max(0, (ch - vh) / 2)
  ox = math.max(-mx, math.min(mx, ox))
  oy = math.max(-my, math.min(my, oy))
  canvas:ClearAllPoints()
  canvas:SetPoint("CENTER", port, "CENTER", ox, oy)
  fenster.zoomText:SetText(zoom > 1.01 and string.format("%.1fx", zoom) or "")
  platziereNadeln()
end

local function nadelTooltip(self)
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  if self.istZiel then
    GameTooltip:AddLine(self.questName or "Quest", 1, 0.82, 0)
    if self.label and self.label ~= "" then GameTooltip:AddLine(self.label, 1, 1, 1, true) end
  else
    GameTooltip:AddLine(self.name or "?", 1, 1, 1)
    if self.boss and self.boss.rare then GameTooltip:AddLine("Seltener Gegner", 0.6, 0.75, 1) end
    local inf = self.info
    if inf then
      for _, n in ipairs(inf.log) do GameTooltip:AddLine("Quest: " .. n, 1, 0.82, 0, true) end
      for _, n in ipairs(inf.start) do GameTooltip:AddLine("Questgeber: " .. n, 0.4, 1, 0.4, true) end
      if inf.gewaehlt and #inf.log == 0 then GameTooltip:AddLine("Gehört zur gewählten Quest", 0.5, 0.8, 1) end
    end
    -- die drei wahrscheinlichsten Drops
    local beute = D.Beute(D.Dungeon(auswahl)).boss[self.name or ""]
    if beute and #beute > 0 then
      GameTooltip:AddLine("Beute:", 1, 0.82, 0)
      for i = 1, math.min(3, #beute) do
        local e = beute[i]
        local c = D.ChanceText(e)
        GameTooltip:AddLine("  " .. itemText(e.id) .. (c ~= "" and (" (" .. c .. ")") or ""), 1, 1, 1)
      end
      if #beute > 3 then GameTooltip:AddLine("  ... " .. (#beute - 3) .. " weitere (Ansicht Bosse)", 0.6, 0.6, 0.6) end
    end
  end
  GameTooltip:Show()
end

local function neueNadel(istZiel)
  local n = CreateFrame("Frame", nil, canvas)
  n:SetSize(istZiel and 14 or NADEL, istZiel and 14 or NADEL)
  n:EnableMouse(true)
  n.istZiel = istZiel
  n.glanz = n:CreateTexture(nil, "BACKGROUND")
  n.glanz:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  n.glanz:SetBlendMode("ADD")
  n.glanz:SetPoint("CENTER")
  local g = (istZiel and 14 or NADEL) * 1.9
  n.glanz:SetSize(g, g)
  n.glanz:Hide()
  if istZiel then
    n.icon = n:CreateTexture(nil, "ARTWORK")
    n.icon:SetTexture("Interface\\GossipFrame\\ActiveQuestIcon")
    n.icon:SetAllPoints()
  else
    n.grund = n:CreateTexture(nil, "BORDER")
    n.grund:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    n.grund:SetAllPoints()
    n.grund:SetVertexColor(0, 0, 0, 0.85)
    n.icon = n:CreateTexture(nil, "ARTWORK")
    n.icon:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
    n.icon:SetPoint("CENTER")
    n.icon:SetSize(NADEL - 6, NADEL - 6)
    n.ausruf = n:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    n.ausruf:SetPoint("BOTTOMLEFT", n, "TOPRIGHT", -9, -9)
    n.ausruf:SetText("!")
    n.ausruf:SetTextColor(1, 0.82, 0)
    n.ausruf:Hide()
  end
  if n.glanz.CreateAnimationGroup then
    local ok, ag = pcall(n.glanz.CreateAnimationGroup, n.glanz)
    if ok and ag then
      ag:SetLooping("BOUNCE")
      local a = ag:CreateAnimation("Alpha")
      if a and a.SetFromAlpha then
        a:SetFromAlpha(0.3)
        a:SetToAlpha(1)
        a:SetDuration(0.9)
        n.puls = ag
      end
    end
  end
  n:SetScript("OnEnter", nadelTooltip)
  n:SetScript("OnLeave", GameTooltip_Hide)
  -- Ziehen und Rechtsklick gehen an die Karte weiter
  n:SetScript("OnMouseDown", function(_, taste) port:GetScript("OnMouseDown")(port, taste) end)
  n:SetScript("OnMouseUp", function(_, taste) port:GetScript("OnMouseUp")(port, taste) end)
  return n
end

local function setzeGlanz(n, r, g, b)
  if r then
    n.glanz:SetVertexColor(r, g, b)
    n.glanz:Show()
    if n.puls and not n.puls:IsPlaying() then n.puls:Play() end
  else
    n.glanz:Hide()
    if n.puls then n.puls:Stop() end
  end
end

-- Welche Bosse/NPCs Quests im Log (und die gewählte Quest) brauchen.
-- info[npcID] und info["n:" .. englischerName] = { log = {Questnamen}, start = {Questnamen}, gewaehlt }
local function bossQuestInfo(d)
  local info = {}
  local nameZuNpc = {}
  for _, b in ipairs(d.bosse) do
    if b.npcID then nameZuNpc[b.name] = b.npcID end
  end
  if d.karte then
    for npcID in pairs(d.karte.bosses) do
      local nm = tonumber(npcID) and npcName(npcID)
      if nm and not nameZuNpc[nm] then nameZuNpc[nm] = npcID end
    end
  end
  local function eintrag(npc, name)
    local schluessel = npc or ("n:" .. name)
    local e = info[schluessel]
    if not e then
      e = { log = {}, start = {}, gewaehlt = false }
      info[schluessel] = e
    end
    local nm = name or (npc and (npcName(npc) or (d.bossNachNpc[npc] and d.bossNachNpc[npc].name)))
    if nm and not info["n:" .. nm] then info["n:" .. nm] = e end
    return e
  end
  for _, q in ipairs(D.QuestsFuer(d)) do
    local e = imLog(q.id)
    local offen = e and not e.fertig
    local gew = q.id == gewaehlteQuest
    if offen or gew then
      local bed = questBedarf(q, d.id)
      local ziele = {}
      for n in pairs(bed.npcs) do ziele[#ziele + 1] = eintrag(n) end
      for name in pairs(bed.namen) do ziele[#ziele + 1] = eintrag(nameZuNpc[name], name) end
      local name = D.QuestName(q)
      local gesehen = {}
      for _, x in ipairs(ziele) do
        if not gesehen[x] then
          gesehen[x] = true
          if offen then table.insert(x.log, name) end
          if gew then x.gewaehlt = true end
        end
      end
    end
    if q.inside and tonumber(q.npcID) and (gew or D.Status(q) == "verfuegbar") then
      local x = eintrag(tonumber(q.npcID))
      table.insert(x.start, D.QuestName(q))
      if gew then x.gewaehlt = true end
    end
  end
  return info, nameZuNpc
end

local function infoFuer(info, npcID, name)
  return (npcID and info[npcID]) or (name and info["n:" .. name]) or nil
end

-- Nadeln und Boss-Liste neu zeichnen.
local function aktualisiereKarte(d)
  for _, n in ipairs(nadeln) do n:Hide() end
  for _, n in ipairs(zielNadeln) do n:Hide() end
  local bossKasten = fenster.bossKasten
  if not d then
    bossKasten:Hide()
    return
  end
  local info = bossQuestInfo(d)

  local platziert = {}
  if karte then
    local i = 0
    for npcID, pos in pairs(karte.bosses) do
      local x, y = type(pos) == "table" and tonumber(pos[1]), type(pos) == "table" and tonumber(pos[2])
      if tonumber(npcID) and x and y then
        i = i + 1
        local n = nadeln[i] or neueNadel(false)
        nadeln[i] = n
        local b = d.bossNachNpc[npcID]
        n.x, n.y, n.npcID, n.boss = x, y, npcID, b
        n.name = (b and b.name) or npcName(npcID) or ("NPC " .. npcID)
        local inf = infoFuer(info, npcID, n.name)
        n.info = inf
        local imLogNoetig = inf and #inf.log > 0
        n.ausruf:SetShown(imLogNoetig and true or false)
        if (inf and inf.gewaehlt) or (ansicht == "bosse" and gewaehlterBoss and gewaehlterBoss == n.name) then
          setzeGlanz(n, 0.3, 0.8, 1)
        elseif imLogNoetig then
          setzeGlanz(n, 1, 0.8, 0.2)
        elseif inf and #inf.start > 0 then
          setzeGlanz(n, 0.3, 1, 0.3)
        else
          setzeGlanz(n)
        end
        n.icon:SetVertexColor(1, 1, 1)
        n:SetFrameLevel(canvas:GetFrameLevel() + ((inf and (inf.gewaehlt or imLogNoetig)) and 3 or 1))
        n:Show()
        platziert[npcID] = true
      end
    end

    -- Questziele im Dungeon: gewählte Quest und Quests im Log, die noch nicht fertig sind
    local ziele = tab(tab(WW.quelle and WW.quelle.ziele)[d.id])
    local j = 0
    for _, q in ipairs(D.QuestsFuer(d)) do
      local e = imLog(q.id)
      local liste = ziele[q.id]
      if (q.id == gewaehlteQuest or (e and not e.fertig)) and type(liste) == "table" then
        local gewaehlt = q.id == gewaehlteQuest
        local zellen = {}   -- nahe Punkte einer Quest teilen sich eine Nadel (ZIEL_RASTER)
        for _, s in ipairs(liste) do
          local art, id, item, xy = zielLesen(s)
          if art then
            local label = zielName(art, id) .. (item and (" - " .. itemText(item)) or "")
            for k = 1, #xy - 1, 2 do
              local zelle = math.floor(xy[k] / ZIEL_RASTER) * 1000 + math.floor(xy[k + 1] / ZIEL_RASTER)
              local n = zellen[zelle]
              if n then
                if not n.labelSchon[label] and #n.labels < 4 then
                  n.labelSchon[label] = true
                  n.labels[#n.labels + 1] = label
                  n.label = table.concat(n.labels, "\n")
                end
              else
                j = j + 1
                n = zielNadeln[j] or neueNadel(true)
                zielNadeln[j] = n
                zellen[zelle] = n
                n.x, n.y = xy[k], xy[k + 1]
                n.questName = D.QuestName(q)
                n.labels, n.labelSchon, n.label = { label }, { [label] = true }, label
                setzeGlanz(n, gewaehlt and 0.3 or 1, 0.8, gewaehlt and 1 or 0.2)
                n:SetFrameLevel(canvas:GetFrameLevel() + (gewaehlt and 5 or 4))
                n:Show()
              end
            end
          end
        end
      end
    end
    D.letzteZielNadeln = j   -- für Tests
    platziereNadeln()
  end

  -- Bosse ohne Ort auf der Karte (oder alle, wenn es keine Karte gibt)
  local zeilen = {}
  for _, b in ipairs(d.bosse) do
    if not (b.npcID and platziert[b.npcID]) then
      local t = b.name
      if b.rare then t = t .. WW.f("grau", " (selten)") end
      local inf = infoFuer(info, b.npcID, b.name)
      if inf and #inf.log > 0 then
        t = WW.f("gelb", "! ") .. t .. WW.f("gelb", " - Quest: " .. table.concat(inf.log, ", "))
      elseif inf and inf.gewaehlt then
        t = WW.f("ff4dccff", "> ") .. t
      end
      if inf and #inf.start > 0 then t = t .. WW.f("gruen", " - Questgeber") end
      zeilen[#zeilen + 1] = t
    end
  end
  if #zeilen > 0 then
    local kopf = karte and "Bosse ohne Ort auf der Karte:" or "Bosse:"
    bossKasten.text:SetText(WW.f("titel", kopf) .. "\n" .. table.concat(zeilen, "\n"))
    bossKasten:SetHeight(bossKasten.text:GetStringHeight() + 14)
    bossKasten:ClearAllPoints()
    if karte then
      bossKasten:SetPoint("TOPLEFT", port, "TOPLEFT", 6, -6)
    else
      bossKasten:SetPoint("TOP", fenster.keineKarte, "BOTTOM", 0, -16)
    end
    bossKasten:Show()
  else
    bossKasten:Hide()
  end
end

-- Detailtext zur gewählten Quest.
local function detailText(q, d)
  local z = {}
  local function zeile(t) z[#z + 1] = t end
  local status, grund = D.Status(q)
  local stufe = questStufe(q)
  zeile(WW.f("gelb", D.QuestName(q)))
  local kopf = {}
  if stufe then kopf[#kopf + 1] = "Stufe " .. stufe end
  local minS = questMinStufe(q)
  if minS then kopf[#kopf + 1] = "ab " .. minS end
  kopf[#kopf + 1] = WW.f(STATUS_FARBE[status], STATUS_TEXT[status])
  zeile(table.concat(kopf, " · ") .. (grund and (" - " .. grund) or ""))
  if q.fluegel then zeile("Flügel: " .. (FLUEGEL[q.fluegel] or q.fluegel)) end
  zeile("Start: " .. geberText(q))

  -- Kette rückwärts (nur Schritte, die du annehmen kannst)
  local kette, p, gesehen = {}, q.prev, { [q.id] = true }
  while p and not gesehen[p] and #kette < 10 do
    gesehen[p] = true
    local pq = D.Quest(p) or { id = p }
    if kannAnnehmen(pq) then table.insert(kette, 1, pq) end
    p = pq.prev
  end
  if #kette > 0 then
    zeile(" ")
    zeile(WW.f("titel", "Vorquests:"))
    for _, pq in ipairs(kette) do
      local s = D.Status(pq)
      local t = "- " .. WW.f(STATUS_FARBE[s], D.QuestName(pq)) .. WW.f("grau", " (" .. STATUS_TEXT[s] .. ")")
      if s ~= "erledigt" then t = t .. "\n   " .. WW.f("grau", geberText(pq)) end
      zeile(t)
    end
  end

  zeile(" ")
  zeile(WW.f("titel", "Ziel (englisch):"))
  zeile(type(q.objective) == "string" and q.objective ~= "" and q.objective or WW.f("grau", "kein Text in den Daten"))

  local ziele = logZiele(q.id)
  if ziele then
    zeile(" ")
    zeile(WW.f("titel", "Fortschritt im Questlog:"))
    local e = imLog(q.id)
    if e and e.fertig then zeile(WW.f("gruen", "Fertig - jetzt abgeben.")) end
    for _, o in ipairs(ziele) do
      zeile("- " .. (o.fertig and WW.f("grau", o.text) or o.text))
    end
  end

  -- Was gebraucht wird und ob es auf der Karte steht
  local bed = questBedarf(q, d and d.id)
  local _, nameZuNpc = bossQuestInfo(d)
  local function aufKarte(npc) return karte and npc and type(karte.bosses[npc]) == "table" end
  local alleAufKarte = #bed.teile > 0
  -- Ziel-Punkte dieser Quest auf dieser Karte: "n<id>", "o<id>", "i<item>"
  local hatPunkte = {}
  if karte and d then
    for _, s in ipairs(tab(tab(tab(WW.quelle and WW.quelle.ziele)[d.id])[q.id])) do
      local art, id, item = zielLesen(s)
      if art then
        hatPunkte[art .. id] = true
        if item then hatPunkte["i" .. item] = true end
      end
    end
  end
  if #bed.teile > 0 then
    zeile(" ")
    zeile(WW.f("titel", "Gebraucht:"))
    for _, t in ipairs(bed.teile) do
      local schluessel = (t.art == "npc" and "n" or t.art == "item" and "i" or "o") .. tostring(t.id)
      local markiert = hatPunkte[schluessel] or false
      for n in pairs(t.npcs) do if aufKarte(n) then markiert = true end end
      if t.wer then
        for name in t.wer:gmatch("[^/]+") do if aufKarte(nameZuNpc[name]) then markiert = true end end
      end
      local anz = (t.anzahl and t.anzahl > 1) and (" x" .. t.anzahl) or ""
      local text
      if t.art == "npc" then
        text = "Töten: " .. (npcName(t.id) or ("NPC " .. t.id)) .. anz
      elseif t.art == "item" then
        text = "Gegenstand: " .. itemText(t.id) .. anz
        local wer = t.wer
        if not wer then
          local namen = {}
          for n in pairs(t.npcs) do
            local nm = npcName(n)
            if nm and #namen < 4 then namen[#namen + 1] = nm end
          end
          if #namen > 0 then wer = table.concat(namen, ", ") end
        else
          wer = wer:gsub("/", ", ")
        end
        if wer then text = text .. WW.f("grau", " - von " .. wer) end
      else
        text = "Objekt: " .. (objName(t.id) or ("Objekt " .. t.id)) .. anz
      end
      if markiert then
        text = text .. WW.f("ff4dccff", " - auf der Karte markiert")
      else
        alleAufKarte = false
      end
      zeile("- " .. text)
    end
  end
  if not alleAufKarte then
    zeile(" ")
    zeile(WW.f("orange", "Ort im Dungeon unbekannt – siehe Ziel-Text"))
  end

  if type(q.tip) == "string" and q.tip ~= "" then
    zeile(" ")
    zeile(WW.f("titel", "Hinweis (englisch):"))
    zeile(q.tip)
  end
  -- Belohnungen mit Bewertung für deine Klasse (Module\Quests.lua: WW.QW.Kurz)
  local function itemListe(l)
    local t = {}
    for _, id in ipairs(tab(l)) do
      local s = "- " .. itemText(id)
      if WW.QW and WW.QW.Kurz then
        local ok, k = pcall(WW.QW.Kurz, id)
        if ok and k then s = s .. " " .. k end
      end
      t[#t + 1] = s
    end
    return table.concat(t, "\n")
  end
  if type(q.rewards) == "table" and #q.rewards > 0 then
    zeile(" ")
    zeile(WW.f("titel", "Belohnung:"))
    zeile(itemListe(q.rewards))
  end
  if type(q.choices) == "table" and #q.choices > 0 then
    zeile(WW.f("titel", "Zur Wahl (eine davon):"))
    zeile(itemListe(q.choices))
  end
  return table.concat(z, "\n")
end

D.DetailText = detailText   -- für Tests

local function zeigeDetails()
  local d = D.Dungeon(auswahl)
  local q = gewaehlteQuest and D.Quest(gewaehlteQuest)
  local text
  if q and d then
    text = detailText(q, d)
  elseif d then
    text = WW.f("grau", "Klick auf eine Quest: Ziel, Fortschritt und die passenden Bosse auf der Karte.")
  else
    text = WW.f("grau", "Keine Dungeon-Daten gefunden.")
  end
  local dt = fenster.detailText
  dt:SetText(text)
  fenster.detailKind:SetHeight(math.max(1, dt:GetStringHeight() + 8))
  fenster.detailScroll:SetVerticalScroll(0)
end

-- Kurzer Fortschritt für die Questzeile (nur im Log).
local function fortschrittKurz(q)
  local e = imLog(q.id)
  if not e then return nil end
  if e.fertig then return WW.f("gruen", "Fertig - jetzt abgeben") end
  local ziele = logZiele(q.id)
  if not ziele or #ziele == 0 then return nil end
  local t = {}
  for _, o in ipairs(ziele) do t[#t + 1] = o.fertig and WW.f("grau", o.text) or o.text end
  return table.concat(t, "; ")
end

local function fuelleQuestListe(d, behalten)
  local liste = fenster.questListe
  local eintraege = liste.eintraege
  if not behalten or type(eintraege) ~= "table" then eintraege = {} end
  wipe(eintraege)
  for _, q in ipairs(D.QuestsFuer(d)) do
    local s, grund = D.Status(q)
    eintraege[#eintraege + 1] = { q = q, status = s, grund = grund, stufe = questStufe(q) or 0 }
  end
  table.sort(eintraege, function(a, b)
    if a.status ~= b.status then return STATUS_RANG[a.status] < STATUS_RANG[b.status] end
    if a.stufe ~= b.stufe then return a.stufe < b.stufe end
    return a.q.id < b.q.id
  end)
  if behalten then
    liste:Aktualisiere()
  else
    liste:Setze(eintraege)
  end
  local n = #eintraege
  fenster.questKopf:SetText("Quests" .. (n > 0 and (" (" .. n .. ")") or ""))
  fenster.keineQuests:SetShown(n == 0)
end

-- Dungeon im Fenster zeigen. behalten: Auswahl, Zoom und Liste behalten (nur aktualisieren).
zeigeDungeon = function(id, behalten)
  if not fenster then return end
  local d = D.Dungeon(id)
  if not d or not (d.karte or #d.quests > 0 or #d.bosse > 0) then
    d = nil
    local stufe = UnitLevel("player") or 1
    for _, x in ipairs(D.Alle()) do
      if not d and x.min and stufe >= x.min and stufe <= (x.max or x.min) then d = x end
    end
    d = d or D.Alle()[1]
    behalten = false
  end
  if not d then
    auswahl, karte = nil, nil
    fenster.titel:SetText("Dungeon-Karte")
    fenster.wahlKnopf:SetText("Keine Dungeon-Daten")
    fenster.info:SetText(WW.f("rot", "Keine Daten geladen. Siehe Reiter Einstellungen."))
    canvas:Hide()
    fenster.keineKarte:Show()
    fenster.credit:SetText("")
    fenster.hinweis:SetText("")
    fenster.questListe:Setze({})
    fenster.questKopf:SetText("Quests")
    fenster.keineQuests:Show()
    aktualisiereKarte(nil)
    zeigeDetails()
    return
  end
  if d.id ~= auswahl then behalten = false end
  auswahl = d.id
  if WW.db and WW.db.dungeonKarte then WW.db.dungeonKarte.auswahl = d.id end
  if not behalten then gewaehlteQuest, gewaehlterBoss = nil, nil end

  fenster.titel:SetText("Dungeon-Karte - " .. d.name)
  fenster.wahlKnopf:SetText(d.name .. " " .. stufenText(d) .. "  [ändern]")
  local info = {}
  if d.min then info[#info + 1] = "Stufe " .. stufenText(d):gsub("[()]", "") end
  if d.raid then info[#info + 1] = "Schlachtzug" end
  local eingang = D.Eingang(d)
  if eingang then info[#info + 1] = "Eingang: " .. eingang end
  fenster.info:SetText(table.concat(info, " · ") .. "\n" .. zaehlText(D.Zaehle(d)))

  -- Karte
  if not behalten or karte ~= d.karte then
    karte = d.karte
    zoom, ox, oy, ziehen = 1, 0, 0, nil
    if karte then
      bild:SetTexture(KARTEN_PFAD .. karte.file)
      bild:SetTexCoord(0, karte.w / karte.tw, 0, karte.h / karte.th)
      canvas:Show()
      fenster.keineKarte:Hide()
      local credit = karte.credit and ("Karte: " .. karte.credit .. (QUELLE_URL[karte.credit] and (" (" .. QUELLE_URL[karte.credit] .. ")") or "")) or ""
      if karte.note then
        credit = credit .. (credit ~= "" and "  ·  " or "") .. (NOTIZ[karte.note] or karte.note)
      end
      fenster.credit:SetText(credit)
      fenster.hinweis:SetText("Mausrad: zoomen · Ziehen: verschieben · Rechtsklick: zurücksetzen")
      passeAn()
    else
      canvas:Hide()
      fenster.keineKarte:Show()
      fenster.credit:SetText("")
      fenster.hinweis:SetText("")
      fenster.zoomText:SetText("")
    end
  end

  fuelleQuestListe(d, behalten)
  if ansicht == "bosse" then D.Ansicht("bosse") end
  aktualisiereKarte(d)
  zeigeDetails()
end

local function waehleQuest(id)
  if gewaehlteQuest == id then gewaehlteQuest = nil else gewaehlteQuest = id end
  local d = D.Dungeon(auswahl)
  fenster.questListe:Aktualisiere()
  aktualisiereKarte(d)
  zeigeDetails()
end

local function baueQuestZeile(z)
  z.markiert = z:CreateTexture(nil, "BACKGROUND")
  z.markiert:SetAllPoints()
  z.markiert:SetColorTexture(0.3, 0.6, 1, 0.2)
  z.markiert:Hide()
  z.name = UI.Text(z)
  z.name:SetPoint("TOPLEFT", 2, -2)
  z.name:SetWidth(RECHTS_B - 34 - 84)
  z.name:SetHeight(14)
  if z.name.SetWordWrap then z.name:SetWordWrap(false) end
  z.status = UI.Text(z, "klein")
  z.status:SetPoint("TOPRIGHT", -2, -3)
  z.status:SetWidth(80)
  z.status:SetJustifyH("RIGHT")
  z.unter = UI.Text(z, "klein", 0.75, 0.75, 0.75)
  z.unter:SetPoint("TOPLEFT", 2, -17)
  z.unter:SetWidth(RECHTS_B - 38)
  z.unter:SetHeight(12)
  if z.unter.SetWordWrap then z.unter:SetWordWrap(false) end
  z:SetScript("OnClick", function(self)
    if self.eintrag then waehleQuest(self.eintrag.q.id) end
  end)
  z:SetScript("OnEnter", function(self)
    local e = self.eintrag
    if not e then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(D.QuestName(e.q), 1, 0.82, 0)
    GameTooltip:AddLine(STATUS_TEXT[e.status] .. (e.grund and (" - " .. e.grund) or ""), 1, 1, 1, true)
    GameTooltip:AddLine(geberText(e.q), 0.75, 0.75, 0.75, true)
    if type(e.q.objective) == "string" then GameTooltip:AddLine(e.q.objective, 0.6, 0.75, 1, true) end
    GameTooltip:AddLine("Klick: Ziel und Bosse auf der Karte", 0.55, 0.55, 0.55)
    GameTooltip:Show()
  end)
  z:SetScript("OnLeave", GameTooltip_Hide)
end

local function fuelleQuestZeile(z, e)
  local farbe = STATUS_FARBE[e.status]
  z.name:SetText(WW.f(farbe, (e.stufe > 0 and ("[" .. e.stufe .. "] ") or "") .. D.QuestName(e.q)))
  z.status:SetText(WW.f(farbe, STATUS_TEXT[e.status]))
  local unter
  if e.status == "log" then unter = fortschrittKurz(e.q) end
  if not unter and e.status == "spaeter" and e.grund then unter = WW.f("rot", e.grund) end
  z.unter:SetText(unter or geberText(e.q))
  z.markiert:SetShown(e.q.id == gewaehlteQuest)
end

-- Dungeon-Wahl (eigene Aufklappliste, keine Dropdown-Vorlage)
---------------------------------------------------------------------------
-- Ansicht "Bosse": Bossliste und Beute
---------------------------------------------------------------------------
local QFARBE = { [0] = "ff9d9d9d", [1] = "ffffffff", [2] = "ff1eff00", [3] = "ff0070dd", [4] = "ffa335ee", [5] = "ffff8000" }

-- Qualität und Symbol eines Gegenstands (Quests.lua kennt mehr Quellen; sonst Spiel und Classic-Liste)
local function itemQualitaetSymbol(id)
  if WW.QW and type(WW.QW.Info) == "function" then
    local ok, info = pcall(WW.QW.Info, id)
    if ok and type(info) == "table" then return tonumber(info.qualitaet), info.icon end
  end
  local ok, _, _, q = pcall(WW.GetItemInfo, id)
  local qual = ok and tonumber(q) or nil
  if not qual then
    local ci = tab(fdm().classicItems)[id]
    qual = type(ci) == "table" and tonumber(ci[2]) or nil
  end
  local okI, icon = pcall(WW.GetItemIcon, id)
  return qual, okI and icon or nil
end

local function fuelleBeute()
  local l = fenster.beuteListe
  local ziel = l.eintraege or {}
  l.eintraege = ziel
  wipe(ziel)
  local d = D.Dungeon(auswahl)
  local name = gewaehlterBoss
  if name then
    for _, bo in ipairs(D.BossListe(d)) do
      if bo.name == name then
        for _, e in ipairs(bo.beute) do ziel[#ziel + 1] = e end
      end
    end
  end
  l:Aktualisiere()
  fenster.beuteLeer:SetText(not name and "Klick auf einen Boss: seine Beute mit Chance und Bewertung."
    or (#ziel == 0 and "Keine Beute in den Daten." or ""))
  fenster.beuteLeer:SetShown(#ziel == 0)
end

local function baueBossZeile(z)
  z.markiert = z:CreateTexture(nil, "BACKGROUND")
  z.markiert:SetAllPoints()
  z.markiert:SetColorTexture(0.3, 0.6, 1, 0.2)
  z.markiert:Hide()
  z.name = UI.Text(z)
  z.name:SetPoint("LEFT", 2, 0)
  z.name:SetWidth(RECHTS_B - 34 - 70)
  if z.name.SetWordWrap then z.name:SetWordWrap(false) end
  z.rechts = UI.Text(z, "klein", 0.7, 0.7, 0.7)
  z.rechts:SetPoint("RIGHT", -2, 0)
  z.rechts:SetWidth(68)
  z.rechts:SetJustifyH("RIGHT")
  z:SetScript("OnClick", function(self)
    if not self.eintrag then return end
    gewaehlterBoss = (gewaehlterBoss ~= self.eintrag.name) and self.eintrag.name or nil
    fenster.bossListe:Aktualisiere()
    fuelleBeute()
    aktualisiereKarte(D.Dungeon(auswahl))
  end)
end

local function fuelleBossZeile(z, e)
  local t = e.trash and WW.f("grau", e.name) or ((e.nr and (e.nr .. ". ") or "") .. e.name)
  if e.rare then t = t .. WW.f("ff80ccff", " (selten)") end
  if e.nur then t = t .. WW.f("grau", " (nur " .. e.nur .. ")") end
  z.name:SetText(t)
  z.rechts:SetText(#e.beute > 0 and (#e.beute .. " Drops") or "")
  z.markiert:SetShown(e.name == gewaehlterBoss)
end

local function baueBeuteZeile(z)
  z.icon = z:CreateTexture(nil, "ARTWORK")
  z.icon:SetSize(18, 18)
  z.icon:SetPoint("TOPLEFT", 2, -2)
  z.name = UI.Text(z)
  z.name:SetPoint("TOPLEFT", 24, -2)
  z.name:SetWidth(RECHTS_B - 34 - 26)
  if z.name.SetWordWrap then z.name:SetWordWrap(false) end
  z.unter = UI.Text(z, "klein", 0.75, 0.75, 0.75)
  z.unter:SetPoint("TOPLEFT", 24, -17)
  z.unter:SetWidth(RECHTS_B - 34 - 26)
  if z.unter.SetWordWrap then z.unter:SetWordWrap(false) end
  z:SetScript("OnEnter", function(self)
    if self.eintrag then UI.ItemTooltip(self, self.eintrag.id) end
  end)
  z:SetScript("OnLeave", GameTooltip_Hide)
end

local function fuelleBeuteZeile(z, e)
  local qual, icon = itemQualitaetSymbol(e.id)
  z.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
  local c = D.ChanceText(e)
  z.name:SetText(WW.f(QFARBE[qual or 1] or QFARBE[1], itemText(e.id)) .. (c ~= "" and (" – " .. c) or ""))
  local teile2 = { D.QUELLE_TEXT[e.quelle] or "" }
  if e.from then teile2[#teile2 + 1] = "von " .. e.from end
  if WW.QW and type(WW.QW.Kurz) == "function" then
    local ok, k = pcall(WW.QW.Kurz, e.id)
    if ok and k then teile2[#teile2 + 1] = k end
  end
  if WW.AH and type(WW.AH.Bewertung) == "function" then
    local ok, farbe, kurz = pcall(WW.AH.Bewertung, e.id, 1)
    if ok and type(kurz) == "string" and farbe ~= "grau" then teile2[#teile2 + 1] = WW.f(farbe, kurz) end
  end
  z.unter:SetText(table.concat(teile2, " · "))
end

-- rechte Seite umschalten: "quests" | "bosse"
function D.Ansicht(a)
  ansicht = (a == "bosse") and "bosse" or "quests"
  if not fenster then return end
  local bosse = ansicht == "bosse"
  fenster.questListe:SetShown(not bosse)
  fenster.detailKasten:SetShown(not bosse)
  fenster.bossListe:SetShown(bosse)
  fenster.beuteListe:SetShown(bosse)
  fenster.ansichtKnopf:SetText(bosse and "Quests zeigen" or "Bosse zeigen")
  local d = D.Dungeon(auswahl)
  if bosse then
    fenster.keineQuests:Hide()
    local l = fenster.bossListe
    local ziel = l.eintraege or {}
    l.eintraege = ziel
    wipe(ziel)
    local nr = 0
    for _, bo in ipairs(D.BossListe(d)) do
      if not bo.trash then
        nr = nr + 1
        bo.nr = nr
      end
      ziel[#ziel + 1] = bo
    end
    l:Aktualisiere()
    fenster.questKopf:SetText("Bosse" .. (nr > 0 and (" (" .. nr .. ")") or ""))
    fuelleBeute()
  elseif d then
    fuelleQuestListe(d, true)
  end
  if d then aktualisiereKarte(d) end
end

local function baueWahl(f)
  local wahl = CreateFrame("Frame", nil, f)
  wahl:SetFrameStrata("DIALOG")
  wahl:SetSize(RECHTS_B, 440)
  wahl:SetPoint("TOPLEFT", f.wahlKnopf, "BOTTOMLEFT", 0, -2)
  wahl:EnableMouse(true)
  local bg = wahl:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0.02, 0.02, 0.03, 0.96)
  local liste = UI.Liste(wahl, RECHTS_B, 440, 18,
    function(z)
      z.text = UI.Text(z)
      z.text:SetPoint("LEFT", 2, 0)
      z.text:SetWidth(RECHTS_B - 34 - 50)
      if z.text.SetWordWrap then z.text:SetWordWrap(false) end
      z.rechts = UI.Text(z, "klein")
      z.rechts:SetPoint("RIGHT", -2, 0)
      z.rechts:SetWidth(48)
      z.rechts:SetJustifyH("RIGHT")
      z:SetScript("OnClick", function(self)
        wahl:Hide()
        if self.eintrag then zeigeDungeon(self.eintrag.id) end
      end)
    end,
    function(z, d)
      local t = WW.f(stufenFarbe(d), d.name .. " " .. stufenText(d))
      if d.id == auswahl then t = "> " .. t end
      z.text:SetText(t)
      local r = {}
      if d.karte then r[#r + 1] = WW.f("gruen", "Karte") end
      if #d.quests > 0 then r[#r + 1] = WW.f("grau", #d.quests .. "Q") end
      z.rechts:SetText(table.concat(r, " "))
    end)
  liste:SetAllPoints()
  wahl.liste = liste
  wahl:Hide()
  f.wahl = wahl
end

local function baueKartenFenster()
  local f = CreateFrame("Frame", "WegweiserDungeonKarte", UIParent, "BasicFrameTemplateWithInset")
  fenster = f
  f:SetSize(BREITE, HOEHE)
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    if WW.db and WW.db.dungeonKarte then WW.db.dungeonKarte.pos = { p, rp, x, y } end
  end)
  local pos = WW.db and WW.db.dungeonKarte and WW.db.dungeonKarte.pos
  if type(pos) == "table" and pos[1] then
    f:SetPoint(pos[1], UIParent, pos[2] or pos[1], tonumber(pos[3]) or 0, tonumber(pos[4]) or 0)
  else
    f:SetPoint("CENTER")
  end
  local titel = f.TitleText or (f.TitleContainer and f.TitleContainer.TitleText)
  if not titel then
    titel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    titel:SetPoint("TOP", 0, -5)
  end
  f.titel = titel
  titel:SetText("Dungeon-Karte")
  tinsert(UISpecialFrames, "WegweiserDungeonKarte")

  -- Kartenbereich: Ausschnitt (port) mit beweglicher Fläche (canvas)
  port = CreateFrame("Frame", nil, f)
  port:SetPoint("TOPLEFT", 12, -30)
  port:SetSize(KARTE_B, KARTE_H)
  if port.SetClipsChildren then port:SetClipsChildren(true) end
  local hg = port:CreateTexture(nil, "BACKGROUND")
  hg:SetAllPoints()
  hg:SetColorTexture(0.03, 0.03, 0.04, 0.95)
  canvas = CreateFrame("Frame", nil, port)
  canvas:SetPoint("CENTER")
  canvas:SetSize(KARTE_B, KARTE_H)
  bild = canvas:CreateTexture(nil, "ARTWORK")
  bild:SetAllPoints()

  f.keineKarte = UI.Text(port, "gross", 0.7, 0.7, 0.7)
  f.keineKarte:SetPoint("TOP", 0, -40)
  f.keineKarte:SetJustifyH("CENTER")
  f.keineKarte:SetText("Keine Karte für diesen Dungeon.")
  f.keineKarte:Hide()

  f.bossKasten = UI.Kasten(port)
  f.bossKasten:SetWidth(280)
  f.bossKasten:SetFrameLevel(canvas:GetFrameLevel() + 10)
  f.bossKasten:SetBackdropColor(0, 0, 0, 0.8)
  f.bossKasten.text = UI.Text(f.bossKasten, "klein")
  f.bossKasten.text:SetPoint("TOPLEFT", 8, -7)
  f.bossKasten.text:SetWidth(264)
  f.bossKasten.text:SetSpacing(2)
  f.bossKasten:EnableMouse(false)
  f.bossKasten:Hide()

  local zoomRahmen = CreateFrame("Frame", nil, port)
  zoomRahmen:SetAllPoints()
  zoomRahmen:SetFrameLevel(canvas:GetFrameLevel() + 11)
  f.zoomText = UI.Text(zoomRahmen, "klein")
  f.zoomText:SetPoint("TOPRIGHT", -6, -6)

  f.credit = UI.Text(f, "klein", 0.6, 0.6, 0.6)
  f.credit:SetPoint("TOPLEFT", port, "BOTTOMLEFT", 2, -5)
  f.credit:SetWidth(KARTE_B)
  f.hinweis = UI.Text(f, "klein", 0.6, 0.6, 0.6)
  f.hinweis:SetPoint("TOPLEFT", port, "BOTTOMLEFT", 2, -21)
  f.hinweis:SetWidth(KARTE_B)

  port:EnableMouse(true)
  if port.EnableMouseWheel then port:EnableMouseWheel(true) end
  port:SetScript("OnMouseWheel", function(_, delta)
    if not karte then return end
    local alt = zoom
    local neu = math.max(MIN_ZOOM, math.min(MAX_ZOOM, alt * (delta > 0 and 1.25 or 0.8)))
    if neu == alt then return end
    local cx, cy = cursorImPort()
    ox = cx - (cx - ox) * (neu / alt)
    oy = cy - (cy - oy) * (neu / alt)
    zoom = neu
    passeAn()
  end)
  port:SetScript("OnMouseDown", function(_, taste)
    if taste == "LeftButton" and karte then
      local x, y = cursorImPort()
      ziehen = { x = x, y = y, ox = ox, oy = oy }
    end
  end)
  port:SetScript("OnMouseUp", function(_, taste)
    ziehen = nil
    if taste == "RightButton" and karte then
      zoom, ox, oy = 1, 0, 0
      passeAn()
    end
  end)
  port:SetScript("OnUpdate", function()
    if not ziehen then return end
    if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
      ziehen = nil
      return
    end
    local x, y = cursorImPort()
    ox = ziehen.ox + (x - ziehen.x)
    oy = ziehen.oy + (y - ziehen.y)
    passeAn()
  end)

  -- Rechte Seite
  local rechts = CreateFrame("Frame", nil, f)
  rechts:SetPoint("TOPLEFT", port, "TOPRIGHT", 10, 0)
  rechts:SetSize(RECHTS_B, HOEHE - 42)

  f.wahlKnopf = UI.Knopf(rechts, "Dungeon wählen", RECHTS_B, function()
    if f.wahl:IsShown() then
      f.wahl:Hide()
    else
      f.wahl:Show()
      f.wahl.liste:Setze(D.Alle())
    end
  end)
  f.wahlKnopf:SetPoint("TOPLEFT", 0, 0)

  f.info = UI.Text(rechts, "klein", 0.85, 0.85, 0.85)
  f.info:SetPoint("TOPLEFT", f.wahlKnopf, "BOTTOMLEFT", 2, -6)
  f.info:SetWidth(RECHTS_B - 4)
  f.info:SetSpacing(2)

  f.questKopf = UI.Text(rechts)
  f.questKopf:SetPoint("TOPLEFT", 2, -62)
  f.questKopf:SetText("Quests")

  f.questListe = UI.Liste(rechts, RECHTS_B, 250, 30, baueQuestZeile, fuelleQuestZeile)
  f.questListe:SetPoint("TOPLEFT", 0, -78)
  f.keineQuests = UI.Text(f.questListe, "klein", 0.6, 0.6, 0.6)
  f.keineQuests:SetPoint("TOPLEFT", 8, -8)
  f.keineQuests:SetWidth(RECHTS_B - 40)
  f.keineQuests:SetText("Keine Quests für deine Fraktion und Klasse in diesem Dungeon.")
  f.keineQuests:Hide()

  local kasten = UI.Kasten(rechts)
  kasten:SetPoint("TOPLEFT", 0, -334)
  kasten:SetPoint("BOTTOMRIGHT", rechts, "BOTTOMRIGHT", 0, 0)
  local scroll = CreateFrame("ScrollFrame", "WegweiserDungeonZielScroll", kasten, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 8, -8)
  scroll:SetPoint("BOTTOMRIGHT", -28, 8)
  local kind = CreateFrame("Frame", nil, scroll)
  kind:SetSize(RECHTS_B - 40, 1)
  scroll:SetScrollChild(kind)
  local dt = UI.Text(kind, "klein")
  dt:SetPoint("TOPLEFT", 0, 0)
  dt:SetWidth(RECHTS_B - 44)
  dt:SetSpacing(2)
  f.detailScroll, f.detailKind, f.detailText = scroll, kind, dt
  f.detailKasten = kasten

  -- Ansicht "Bosse": Bossliste oben, Beute des gewählten Bosses unten
  f.ansichtKnopf = UI.Knopf(rechts, "Bosse zeigen", 110, function()
    D.Ansicht(ansicht == "bosse" and "quests" or "bosse")
  end)
  f.ansichtKnopf:SetPoint("TOPRIGHT", rechts, "TOPRIGHT", 0, -56)
  f.bossListe = UI.Liste(rechts, RECHTS_B, 250, 20, baueBossZeile, fuelleBossZeile)
  f.bossListe:SetPoint("TOPLEFT", 0, -78)
  f.bossListe:Hide()
  f.beuteListe = UI.Liste(rechts, RECHTS_B, HOEHE - 42 - 334, 30, baueBeuteZeile, fuelleBeuteZeile)
  f.beuteListe:SetPoint("TOPLEFT", 0, -334)
  f.beuteListe:Hide()
  f.beuteLeer = UI.Text(f.beuteListe, "klein", 0.6, 0.6, 0.6)
  f.beuteLeer:SetPoint("TOPLEFT", 8, -8)
  f.beuteLeer:SetWidth(RECHTS_B - 40)

  baueWahl(f)

  f:SetScript("OnHide", function()
    ziehen = nil
    if f.wahl then f.wahl:Hide() end
  end)
  f:Hide()
end

-- Startauswahl: aktuelle Instanz, sonst zuletzt gewählter Dungeon.
local function startAuswahl()
  local drin = aktuelleInstanz()
  if drin and D.Dungeon(drin) then return drin end
  return auswahl or (WW.db and WW.db.dungeonKarte and WW.db.dungeonKarte.auswahl)
end

function WW:DungeonKarteZeigen(instanceID)
  if not WW.db then return end
  if not fenster then baueKartenFenster() end
  frischeDaten()
  fenster:Show()
  if fenster.Raise then fenster:Raise() end
  zeigeDungeon(tonumber(instanceID) or startAuswahl())
end

function WW:DungeonKarteUmschalten()
  if fenster and fenster:IsShown() then
    fenster:Hide()
  else
    WW:DungeonKarteZeigen()
  end
end

WW:Befehl("karte", "Dungeon-Karte (optional mit Instanz-ID)", function(rest)
  local id = tonumber(rest)
  if id then WW:DungeonKarteZeigen(id) else WW:DungeonKarteUmschalten() end
end)

---------------------------------------------------------------------------
-- Reiter "Dungeons" im Hauptfenster
---------------------------------------------------------------------------
WW:Reiter("dungeon", "Dungeons", 30, function(p)
  tabPanel = p
  local titel = UI.Text(p, "gross")
  titel:SetPoint("TOPLEFT", 4, -4)
  titel:SetText("Dungeons")

  local knopf = UI.Knopf(p, "Dungeon-Karte öffnen", 180, function() WW:DungeonKarteZeigen() end)
  knopf:SetPoint("TOPRIGHT", -4, -2)

  local hinweis = UI.Text(p, "klein", 0.8, 0.8, 0.8)
  hinweis:SetPoint("TOPLEFT", titel, "BOTTOMLEFT", 0, -6)
  hinweis:SetWidth(WW.INHALT_BREITE - 200)
  hinweis:SetHeight(14)
  if hinweis.SetWordWrap then hinweis:SetWordWrap(false) end
  hinweis:SetText("Klick auf eine Zeile: Karte des Dungeons. Gelb = deine Stufe, rot = zu niedrig, grau = darunter.")

  -- Questgeber auf der Weltkarte
  local function einst() return WW.db and WW.db.dungeonKarte end
  local function haken(text, feld, x)
    local h = UI.Haken(p, text,
      function() local e = einst() return e and e[feld] end,
      function(an)
        local e = einst()
        if e then e[feld] = an end
        pcall(D.WeltPinsNeu)
      end)
    h:SetPoint("TOPLEFT", x, -42)
    return h
  end
  haken("Questgeber auf der Weltkarte", "weltPins", 0)
  haken("nur passende Stufe", "nurPassend", 260)
  haken("auch graue Quests", "graue", 470)

  local spalten = { { 10, "Dungeon (Stufe)" }, { 316, "Eingang" }, { 562, "Quests" }, { 786, "Karte" } }
  for _, s in ipairs(spalten) do
    local k = UI.Text(p, "klein", 1, 0.82, 0)
    k:SetPoint("TOPLEFT", s[1], -70)
    k:SetText(s[2])
  end

  local liste = UI.Liste(p, WW.INHALT_BREITE, WW.INHALT_HOEHE - 86, 20,
    function(z)
      z.name = UI.Text(z)
      z.name:SetPoint("LEFT", 4, 0)
      z.name:SetWidth(300)
      z.eingang = UI.Text(z, "klein", 0.85, 0.85, 0.85)
      z.eingang:SetPoint("LEFT", 310, 0)
      z.eingang:SetWidth(240)
      z.quests = UI.Text(z, "klein")
      z.quests:SetPoint("LEFT", 556, 0)
      z.quests:SetWidth(230)
      z.karte = UI.Text(z, "klein")
      z.karte:SetPoint("LEFT", 780, 0)
      z.karte:SetWidth(40)
      for _, fs in ipairs({ z.name, z.eingang, z.quests, z.karte }) do
        if fs.SetWordWrap then fs:SetWordWrap(false) end
      end
      z:SetScript("OnClick", function(self)
        if self.eintrag then WW:DungeonKarteZeigen(self.eintrag.id) end
      end)
    end,
    function(z, d)
      z.name:SetText(WW.f(stufenFarbe(d), d.name .. " " .. stufenText(d)) .. (d.raid and WW.f("grau", " Schlachtzug") or ""))
      z.eingang:SetText(D.Eingang(d) or WW.f("grau", "-"))
      z.quests:SetText(zaehlText(D.Zaehle(d)))
      z.karte:SetText(d.karte and WW.f("gruen", "ja") or WW.f("grau", "-"))
    end)
  liste:SetPoint("TOPLEFT", 0, -84)

  local gesetzt = false
  p.OnZeigen = function()
    frischeDaten()
    if not gesetzt then
      gesetzt = true
      liste:Setze(D.Alle())
    else
      liste:Aktualisiere()
    end
  end
end)

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------
local geplant = false
local function planeAktualisierung()
  frischeDaten()
  if geplant then return end
  local karteOffen = fenster and fenster:IsShown()
  local reiterOffen = tabPanel and tabPanel:IsShown() and WW.IstOffen and WW:IstOffen("dungeon")
  if not karteOffen and not reiterOffen then return end
  geplant = true
  local function los()
    geplant = false
    frischeDaten()
    if fenster and fenster:IsShown() and auswahl then zeigeDungeon(auswahl, true) end
    if tabPanel and tabPanel:IsShown() and tabPanel.OnZeigen then tabPanel.OnZeigen() end
  end
  if C_Timer and C_Timer.After then C_Timer.After(0.5, los) else los() end
end

WW:Event("QUEST_LOG_UPDATE", planeAktualisierung)
WW:Event("QUEST_TURNED_IN", planeAktualisierung)
WW:Event("QUEST_ACCEPTED", planeAktualisierung)
WW:Event("PLAYER_LEVEL_UP", planeAktualisierung)

-- Weltkarten-Nadeln: gebündelt neu setzen (Questlog-Ereignisse kommen oft in Schüben)
local weltGeplant = false
local function weltPlanen()
  if weltGeplant then return end
  weltGeplant = true
  local function los()
    weltGeplant = false
    local ok, err = pcall(D.WeltPinsNeu)
    if not ok then geterrorhandler()(err) end
  end
  if C_Timer and C_Timer.After then C_Timer.After(2, los) else los() end
end
WW:BeimStart(weltPlanen)
for _, ev in ipairs({ "QUEST_LOG_UPDATE", "QUEST_TURNED_IN", "QUEST_ACCEPTED", "PLAYER_LEVEL_UP" }) do
  WW:Event(ev, weltPlanen)
end

local gemeldet = false
WW:Event("PLAYER_ENTERING_WORLD", function()
  local id = aktuelleInstanz()
  if not id then return end
  local d = D.Dungeon(id)
  if not d then return end
  if d.karte and not gemeldet then
    gemeldet = true
    WW:Print("Dungeon-Karte mit Rechtsklick auf den Minimap-Knopf oder /ww karte.")
  end
  if fenster and fenster:IsShown() then zeigeDungeon(id) end
end)
