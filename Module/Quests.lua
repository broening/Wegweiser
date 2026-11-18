-- Wegweiser: Reiter "Quests" und Bewertung von Quest-Belohnungen für deine Klasse.
-- Für jedes Ausrüstungsteil: Kann deine Klasse es tragen? Ist es besser als das, was du trägst
-- (Gewichte von ForeverDB je Spezialisierung)? Ist es selten (blau/lila)? Für welche Klassen ist es gut?
-- Zeigt das im Reiter "Quests" (Questlog mit Belohnungen), als Zeile im Item-Tooltip,
-- als Haken in Blizzards Questlog (Quests mit Upgrade) und in der Dungeon-Karte (WW.QW.Kurz).
-- Daten: WW.quelle.fdb.weights / prof / gear / gfItemText (Daten von ForeverDB.net, GPL-3.0),
--        WW.quelle.fdm.data[q].rewards / choices. Bewertung angelehnt an ForeverDB (Auto.lua, GPL-3.0).
local ADDON, WW = ...
local UI = WW.UI

WW.standardDB.quests = { tooltip = true, marken = true, itemTipp = true, andere = false }
WW.standardCharDB.quests = { spez = "auto" }

local QW = {}
WW.QW = QW

---------------------------------------------------------------------------
-- Hilfen
---------------------------------------------------------------------------
local LEER = {}
local function tab(t) return type(t) == "table" and t or LEER end
local function fdb() return tab(WW.quelle and WW.quelle.fdb) end
local function fdm() return tab(WW.quelle and WW.quelle.fdm) end

-- Ruft f nur, wenn es eine Funktion ist. Gibt ok, ... zurück.
local function ruf(f, ...)
  if type(f) ~= "function" then return false end
  return pcall(f, ...)
end

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

local function runden(x) return math.floor((tonumber(x) or 0) + 0.5) end

local function einst() return WW.db and WW.db.quests end
local function charEinst() return WW.charDb and WW.charDb.quests end

---------------------------------------------------------------------------
-- Namen
---------------------------------------------------------------------------
local KLASSEN = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local KLASSE_DE = {
  WARRIOR = "Krieger", PALADIN = "Paladin", HUNTER = "Jäger", ROGUE = "Schurke", PRIEST = "Priester",
  SHAMAN = "Schamane", MAGE = "Magier", WARLOCK = "Hexenmeister", DRUID = "Druide",
}
local SPEZ_DE = {
  ["Arms"] = "Waffen", ["Fury"] = "Furor", ["Protection"] = "Schutz", ["Holy"] = "Heilig",
  ["Retribution"] = "Vergeltung", ["Beast Mastery"] = "Tierherrschaft", ["Marksmanship"] = "Treffsicherheit",
  ["Survival"] = "Überleben", ["Assassination"] = "Meucheln", ["Combat"] = "Kampf", ["Subtlety"] = "Täuschung",
  ["Discipline"] = "Disziplin", ["Shadow"] = "Schatten", ["Elemental"] = "Elementar", ["Enhancement"] = "Verstärkung",
  ["Restoration"] = "Wiederherstellung", ["Arcane"] = "Arkan", ["Fire"] = "Feuer", ["Frost"] = "Frost",
  ["Affliction"] = "Gebrechen", ["Demonology"] = "Dämonologie", ["Destruction"] = "Zerstörung",
  ["Balance"] = "Gleichgewicht", ["Feral Combat"] = "Wilder Kampf",
}
local SLOT_DE = {
  [1] = "Kopf", [2] = "Hals", [3] = "Schulter", [5] = "Brust", [6] = "Taille", [7] = "Beine", [8] = "Füße",
  [9] = "Handgelenke", [10] = "Hände", [11] = "Finger", [12] = "Finger", [13] = "Schmuck", [14] = "Schmuck",
  [15] = "Rücken", [16] = "Waffenhand", [17] = "Schildhand", [18] = "Distanz",
}
local RUESTUNG_DE = { [1] = "Stoff", [2] = "Leder", [3] = "Kette", [4] = "Platte", [6] = "Schilde" }
local QFARBE = { [0] = "ff9d9d9d", [1] = "ffffffff", [2] = "ff1eff00", [3] = "ff0070dd", [4] = "ffa335ee", [5] = "ffff8000" }

function QW.KlassenName(tok)
  local t = LOCALIZED_CLASS_NAMES_MALE
  if type(t) == "table" then
    local ok, n = pcall(function() return t[tok] end)
    if ok and type(n) == "string" and n ~= "" then return n end
  end
  return KLASSE_DE[tok] or tostring(tok)
end

function QW.SpezName(sp)
  if type(sp) ~= "table" then return "?" end
  return SPEZ_DE[sp.name] or tostring(sp.name)
end

local function meineKlasse()
  local _, k = UnitClass("player")
  return k
end

-- "Krieger, Paladin +2"
local function klassenListe(liste, max)
  local t = {}
  for i, k in ipairs(liste or LEER) do
    if not max or i <= max then t[#t + 1] = QW.KlassenName(k) end
  end
  local s = table.concat(t, ", ")
  if max and #(liste or LEER) > max then s = s .. " +" .. (#liste - max) end
  return s
end

---------------------------------------------------------------------------
-- Gegenstände: Art, Platz, Werte
---------------------------------------------------------------------------
-- Namen der Spielwerte (GetItemStats) -> Wert-IDs der Gewichte (wie ForeverDB)
local STAT = {
  ITEM_MOD_AGILITY_SHORT = 3, ITEM_MOD_STRENGTH_SHORT = 4, ITEM_MOD_INTELLECT_SHORT = 5, ITEM_MOD_SPIRIT_SHORT = 6,
  ITEM_MOD_STAMINA_SHORT = 7, ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = 12, ITEM_MOD_DODGE_RATING_SHORT = 13,
  ITEM_MOD_PARRY_RATING_SHORT = 14, ITEM_MOD_BLOCK_RATING_SHORT = 15, ITEM_MOD_HIT_RATING_SHORT = 31,
  ITEM_MOD_HIT_MELEE_RATING_SHORT = 31, ITEM_MOD_HIT_RANGED_RATING_SHORT = 31, ITEM_MOD_HIT_SPELL_RATING_SHORT = 31,
  ITEM_MOD_CRIT_RATING_SHORT = 32, ITEM_MOD_CRIT_MELEE_RATING_SHORT = 32, ITEM_MOD_CRIT_RANGED_RATING_SHORT = 32,
  ITEM_MOD_CRIT_SPELL_RATING_SHORT = 32, ITEM_MOD_HASTE_RATING_SHORT = 36, ITEM_MOD_EXPERTISE_RATING_SHORT = 37,
  ITEM_MOD_ATTACK_POWER_SHORT = 38, ITEM_MOD_RANGED_ATTACK_POWER_SHORT = 39, ITEM_MOD_SPELL_HEALING_DONE_SHORT = 41,
  ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = 42, ITEM_MOD_MANA_REGENERATION_SHORT = 43, ITEM_MOD_POWER_REGEN0_SHORT = 43,
  ITEM_MOD_SPELL_POWER_SHORT = 45, ITEM_MOD_SPELL_PENETRATION_SHORT = 47, ITEM_MOD_BLOCK_VALUE_SHORT = 48,
  ITEM_MOD_EXTRA_ARMOR_SHORT = 50,
}
-- Inventartyp-Nummer (Daten) -> INVTYPE
local INVTYP = {
  [1] = "INVTYPE_HEAD", [2] = "INVTYPE_NECK", [3] = "INVTYPE_SHOULDER", [4] = "INVTYPE_BODY", [5] = "INVTYPE_CHEST",
  [6] = "INVTYPE_WAIST", [7] = "INVTYPE_LEGS", [8] = "INVTYPE_FEET", [9] = "INVTYPE_WRIST", [10] = "INVTYPE_HAND",
  [11] = "INVTYPE_FINGER", [12] = "INVTYPE_TRINKET", [13] = "INVTYPE_WEAPON", [14] = "INVTYPE_SHIELD",
  [15] = "INVTYPE_RANGED", [16] = "INVTYPE_CLOAK", [17] = "INVTYPE_2HWEAPON", [18] = "INVTYPE_BAG",
  [19] = "INVTYPE_TABARD", [20] = "INVTYPE_ROBE", [21] = "INVTYPE_WEAPONMAINHAND", [22] = "INVTYPE_WEAPONOFFHAND",
  [23] = "INVTYPE_HOLDABLE", [24] = "INVTYPE_AMMO", [25] = "INVTYPE_THROWN", [26] = "INVTYPE_RANGEDRIGHT",
  [27] = "INVTYPE_QUIVER", [28] = "INVTYPE_RELIC",
}
local SLOTS = {
  INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
  INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
  INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 },
  INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 },
  INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 },
  INVTYPE_RELIC = { 18 },
}
local FERN = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true }
local RELIKT = { PALADIN = 7, DRUID = 8, SHAMAN = 9 }

-- ForeverDB-Daten: "inv;klasse;unterklasse;stufe;wert:zahl,...;dps*10;rüstung"
local gearCache = {}
local function gearDaten(id)
  local c = gearCache[id]
  if c ~= nil then return c or nil end
  local g = tab(fdb().gear)[id]
  if type(g) ~= "string" then
    gearCache[id] = false
    return nil
  end
  local f = teile(g, ";")
  local w = {}
  for sid, v in (f[5] or ""):gmatch("(%d+):(%-?[%d%.]+)") do
    sid = tonumber(sid)
    w[sid] = (w[sid] or 0) + (tonumber(v) or 0)
  end
  w.dps = (tonumber(f[6]) or 0) / 10
  w.armor = tonumber(f[7]) or 0
  c = { inv = tonumber(f[1]), klasse = tonumber(f[2]), unter = tonumber(f[3]), stufe = tonumber(f[4]), werte = w }
  gearCache[id] = c
  return c
end

local infoCache = {}
local anfragen, wartend = {}, {}   -- Item-Daten beim Server angefragt: Anzahl, und worauf wir warten

-- Alles über einen Gegenstand (ID oder Link):
-- { id, link, name, qualitaet, minStufe, loc (INVTYPE), klasse, unter, icon, da (vom Spiel bekannt), gear }
function QW.Info(x)
  local id = WW.ItemID(x)
  if not id then return nil end
  local link = type(x) == "string" and x:find("item:", 1, true) and x or nil
  local c = infoCache[id]
  if c and not link then return c end
  local r = { id = id, link = link }
  local gii = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  local ok, iid, _, _, loc, icon, kl, ukl = ruf(gii, link or id)
  if ok and iid then r.loc, r.icon, r.klasse, r.unter = loc, icon, kl, ukl end
  local ok2, name, ilink, q, _, minL, _, _, _, loc2, icon2, _, kl2, ukl2 = ruf(WW.GetItemInfo, link or id)
  if ok2 and type(name) == "string" then
    r.name, r.qualitaet, r.minStufe, r.da = name, tonumber(q), tonumber(minL), true
    r.link = r.link or ilink
    if r.loc == nil then r.loc = loc2 end
    r.icon = r.icon or icon2
    if r.klasse == nil then r.klasse, r.unter = kl2, ukl2 end
  end
  local g = gearDaten(id)
  if g then
    r.gear = g
    if r.loc == nil then r.loc = INVTYP[g.inv] end
    if r.klasse == nil then r.klasse, r.unter = g.klasse, g.unter end
    if not r.da and g.stufe and g.stufe > 0 then r.minStufe = g.stufe end
  end
  if r.qualitaet == nil then
    local okq, qq = ruf(C_Item and C_Item.GetItemQualityByID, id)
    if okq and tonumber(qq) then r.qualitaet = tonumber(qq) end
  end
  local ci = tab(fdm().classicItems)[id]
  if type(ci) == "table" then
    if r.qualitaet == nil then r.qualitaet = tonumber(ci[2]) end
    r.name = r.name or ci[1]
  end
  if not r.name then
    local okn, n = pcall(WW.ItemName, id)
    r.name = (okn and n) or ("Gegenstand " .. id)
  end
  if not r.icon then
    local oki, ic = ruf(C_Item and C_Item.GetItemIconByID, id)
    if not (oki and ic) then oki, ic = ruf(WW.GetItemIcon, id) end
    r.icon = oki and ic or nil
  end
  if r.da then
    infoCache[id] = r
  elseif (anfragen[id] or 0) < 3 then
    -- beim Server anfragen (höchstens dreimal, falls es den Gegenstand nicht gibt)
    anfragen[id] = (anfragen[id] or 0) + 1
    wartend[id] = true
    ruf(C_Item and C_Item.RequestLoadItemDataByID, id)
  end
  return r
end

local werteCache = {}

local belCache, versuche = {}, {}   -- Belohnungen je Quest (siehe logBelohnungen)

-- Zwischenspeicher leeren (Tests, oder wenn sich Daten geändert haben)
function QW.Vergessen()
  wipe(infoCache)
  wipe(werteCache)
  wipe(gearCache)
  wipe(belCache)
  wipe(versuche)
end

local function werte(info)
  local key = info.link or info.id
  local c = werteCache[key]
  if c then return c end
  local s
  if info.link then
    local gis = (C_Item and C_Item.GetItemStats) or GetItemStats
    local ok, t = ruf(gis, info.link)
    if ok and type(t) == "table" then
      local etwas = false
      s = {}
      for k, v in pairs(t) do
        local sid = STAT[k]
        if sid then
          s[sid] = (s[sid] or 0) + (tonumber(v) or 0)
          etwas = true
        elseif k == "ITEM_MOD_DAMAGE_PER_SECOND_SHORT" then
          s.dps, etwas = tonumber(v), true
        elseif k == "RESISTANCE0_NAME" then
          s.armor, etwas = tonumber(v), true
        end
      end
      if not etwas then s = nil end
    end
  end
  if not s and info.gear then s = info.gear.werte end
  s = s or {}
  if info.da or info.gear then werteCache[key] = s end
  return s
end

local function hatWerte(s)
  for k, v in pairs(s) do
    if type(k) == "number" and v ~= 0 then return true end
  end
  return false
end

local function punkte(s, w, loc, cls, nurWerte)
  local summe = 0
  for sid, v in pairs(s) do
    if type(sid) == "number" and type(w[sid]) == "number" then summe = summe + w[sid] * v end
  end
  if nurWerte then return summe end
  local fern = FERN[loc or ""] or false
  if (s.dps or 0) > 0 and type(w.dps) == "number" and fern == (cls == "HUNTER") then
    summe = summe + w.dps * s.dps
  end
  if (s.armor or 0) > 0 and type(w.armor) == "number" then summe = summe + w.armor * s.armor end
  return summe
end

local function gewichtSumme(w)
  local s = 0
  for k, v in pairs(w) do
    if type(k) == "number" and type(v) == "number" and v > 0 then s = s + v end
  end
  return s > 0 and s or 1
end

-- Kann die Klasse es tragen? ok, ab Stufe
local function kannTragen(info, cls)
  local p = tab(fdb().prof)[cls]
  local kl, ukl, loc = tonumber(info.klasse), tonumber(info.unter), info.loc or ""
  if type(p) ~= "table" or not kl then return true, 1 end
  if kl == 4 then
    if ukl and ukl >= 7 and ukl <= 10 then return RELIKT[cls] == ukl, 1 end
    if loc == "INVTYPE_CLOAK" or not ukl or ukl == 0 then return true, 1 end
    local key = (ukl == 5 or ukl == 6) and 6 or ukl
    local lv = tab(p.armor)[key]
    return lv ~= nil, lv or 99
  elseif kl == 2 then
    if ukl == 14 or ukl == 20 then return true, 1 end
    local lv = tab(p.weapon)[ukl]
    return lv ~= nil, lv or 99
  end
  return true, 1
end

-- Die beste Rüstungsart (1 Stoff .. 4 Platte), die die Klasse auf dieser Stufe trägt.
local function hoechsteRuestung(cls, stufe)
  local beste = 0
  local p = tab(fdb().prof)[cls]
  for typ, lv in pairs(tab(type(p) == "table" and p.armor)) do
    if type(typ) == "number" and typ >= 1 and typ <= 4 and tonumber(lv) and lv <= stufe and typ > beste then beste = typ end
  end
  return beste
end

local function enthaelt(liste, x)
  for _, v in ipairs(liste or LEER) do if v == x then return true end end
  return false
end

-- Für welche Klassen ist das gut? Liste von Klassen-Tokens oder nil (kein Ausrüstungsteil).
-- Klassen, die es tragen (bei Rüstung: ihre beste Rüstungsart auf der Stufe des Gegenstands), und deren
-- Gewichte zu den Werten passen (mindestens 60 % der besten Klasse).
function QW.GutFuer(info)
  if not info or not SLOTS[info.loc or ""] then return nil end
  local s = werte(info)
  local stufe = math.max(tonumber(info.minStufe) or 1, 1)
  local ruestung = tonumber(info.klasse) == 4 and tonumber(info.unter)
  local kandidaten = {}
  for _, cls in ipairs(KLASSEN) do
    local ok = kannTragen(info, cls)
    if ok and ruestung and ruestung >= 1 and ruestung <= 4 and info.loc ~= "INVTYPE_CLOAK" then
      ok = ruestung == hoechsteRuestung(cls, stufe)
    end
    if ok then kandidaten[#kandidaten + 1] = cls end
  end
  -- ohne Werte (z. B. weiße Rüstung): alle, die es tragen; "alle Klassen" sagt nichts
  if not hatWerte(s) then return #kandidaten < #KLASSEN and kandidaten or {} end
  local norm, max = {}, 0
  local gewichte = tab(fdb().weights)
  for _, cls in ipairs(kandidaten) do
    local beste = 0
    for _, sp in ipairs(tab(gewichte[cls])) do
      if type(sp) == "table" and type(sp.w) == "table" then
        local n = punkte(s, sp.w, info.loc, cls, true) / gewichtSumme(sp.w)
        if n > beste then beste = n end
      end
    end
    norm[cls] = beste
    if beste > max then max = beste end
  end
  if max <= 0 then return #kandidaten < #KLASSEN and kandidaten or {} end
  local raus = {}
  for _, cls in ipairs(kandidaten) do
    if norm[cls] >= max * 0.6 then raus[#raus + 1] = cls end
  end
  return raus
end

---------------------------------------------------------------------------
-- Spezialisierung: gewählt, aus den Talenten, aus der Ausrüstung, sonst die erste
---------------------------------------------------------------------------
local spezCache

local function spezAusTalenten(anzahl)
  -- alte Talent-Tabellen (Classic); Forever hat sie nicht, dort zählt spezAusTraits
  local ok, n = ruf(WW.Alt("GetNumTalentTabs"))
  n = ok and tonumber(n) or 0
  local beste, punkteMax = nil, 0
  local tabInfo = WW.Alt("GetTalentTabInfo")
  for i = 1, math.min(n, anzahl) do
    local r = { ruf(tabInfo, i) }
    if r[1] then
      -- ältere Clients: name, icon, punkte; neuere: id, name, beschreibung, icon, punkte
      local p = tonumber(type(r[2]) == "number" and r[6] or r[4]) or 0
      if p > punkteMax then beste, punkteMax = i, p end
    end
  end
  return beste
end

-- Forever: das Talentfenster ist ein Trait-Baum. Wie ForeverDB (Auto.lua ns.talentRanksNow): die Abschnitte
-- des Baums (WW.quelle.fdb.talentTrees, Knoten-ID an Stelle 5) über C_Traits auszählen; der Abschnitt mit den
-- meisten Punkten ist die Spezialisierung. Ohne diese Daten oder ohne C_Traits: nil.
local function spezAusTraits(liste, cls)
  local baeume = tab(tab(fdb().talentTrees)[cls])
  if #baeume == 0 then return nil end
  local CT, TR = C_ClassTalents, C_Traits
  if not (type(CT) == "table" and type(CT.GetActiveConfigID) == "function"
    and type(TR) == "table" and type(TR.GetNodeInfo) == "function") then
    return nil
  end
  local ok, cfg = pcall(CT.GetActiveConfigID)
  if not ok or type(cfg) ~= "number" then return nil end
  local beste, max = nil, 0
  for ti, baum in ipairs(baeume) do
    local summe = 0
    for _, t in ipairs(tab(type(baum) == "table" and baum.talents)) do
      local knoten = type(t) == "table" and tonumber(t[5])
      if knoten then
        local ok2, inf = pcall(TR.GetNodeInfo, cfg, knoten)
        if ok2 and type(inf) == "table" then
          summe = summe + (tonumber(inf.ranksPurchased) or tonumber(inf.activeRank) or 0)
        end
      end
    end
    if summe > max then
      local idx = ti
      for i, sp in ipairs(liste) do
        if type(sp) == "table" and type(baum) == "table" and sp.name == baum.name then idx = i end
      end
      beste, max = idx, summe
    end
  end
  return beste
end

local function spezAusAusruestung(liste, cls)
  local summen = {}
  local etwas = false
  for slot = 1, 18 do
    local ok, link = ruf(GetInventoryItemLink, "player", slot)
    if ok and type(link) == "string" then
      local info = QW.Info(link)
      if info then
        local s = werte(info)
        for i, sp in ipairs(liste) do
          if type(sp) == "table" and type(sp.w) == "table" then
            summen[i] = (summen[i] or 0) + punkte(s, sp.w, info.loc, cls, true) / gewichtSumme(sp.w)
            etwas = true
          end
        end
      end
    end
  end
  if not etwas then return nil end
  local beste, max = nil, 0
  for i = 1, #liste do
    if (summen[i] or 0) > max then beste, max = i, summen[i] end
  end
  return beste
end

-- sp ({ name, role, w }), index, wie ("gewählt" | "Talente" | "Ausrüstung" | "Standard") oder nil
function QW.Spez()
  local cls = meineKlasse()
  local liste = tab(tab(fdb().weights)[cls])
  if #liste == 0 then return nil end
  local ce = charEinst()
  local wahl = ce and ce.spez
  if type(wahl) == "string" and wahl ~= "auto" then
    for i, sp in ipairs(liste) do
      if type(sp) == "table" and sp.name == wahl then return sp, i, "gewählt" end
    end
  end
  if spezCache and liste[spezCache.i] then return liste[spezCache.i], spezCache.i, spezCache.wie end
  local i, wie = spezAusTraits(liste, cls) or spezAusTalenten(#liste), "Talente"
  if not i then i, wie = spezAusAusruestung(liste, cls), "Ausrüstung" end
  if not i or type(liste[i]) ~= "table" then i, wie = 1, "Standard" end
  spezCache = { i = i, wie = wie }
  return liste[i], i, wie
end

function QW.SpezText()
  local sp, _, wie = QW.Spez()
  local k = QW.KlassenName(meineKlasse())
  if not sp then return k end
  return k .. " - " .. QW.SpezName(sp) .. (wie and (" (" .. (wie == "gewählt" and "gewählt" or ("automatisch: " .. wie)) .. ")") or "")
end

---------------------------------------------------------------------------
-- Bewertung eines Gegenstands für dich
---------------------------------------------------------------------------
local function warumNicht(info, cls)
  local name = QW.KlassenName(cls)
  if tonumber(info.klasse) == 4 then
    local art = RUESTUNG_DE[tonumber(info.unter) or -1]
    return name .. " kann das nicht tragen" .. (art and (" (" .. art .. ")") or "")
  end
  return name .. " kann diese Waffe nicht benutzen"
end

-- { info, art, pct, slot, ab, gutFuer, passtNicht, selten, warum }
-- art: "upgrade" | "leer" (freier Platz) | "gleich" | "schlechter" | "angelegt" | "nicht" (kann nicht tragen)
--      | "werte" (Werte bringen dir nichts) | "kein" (kein Ausrüstungsteil) | "unbekannt" (keine Gewichte)
-- Kann deine Klasse das je tragen? true, false + Grund, oder nil (kein Ausrüstungsteil / unbekannt).
-- Für das Urteil "Müll" (Module\Urteil.lua): billiger als QW.Bewerte, rechnet keine Upgrade-Punkte.
function QW.KannTragen(x)
  local info = QW.Info(x)
  if not info or not SLOTS[info.loc or ""] then return nil end
  local cls = meineKlasse()
  if not cls then return nil end
  if kannTragen(info, cls) then return true end
  return false, warumNicht(info, cls)
end

function QW.Bewerte(x)
  local info = QW.Info(x)
  if not info then return nil end
  local r = { info = info, selten = (tonumber(info.qualitaet) or 0) >= 3 }
  local slots = SLOTS[info.loc or ""]
  if not slots then
    r.art = "kein"
    return r
  end
  local cls = meineKlasse()
  r.gutFuer = QW.GutFuer(info)
  local ok, abStufe = kannTragen(info, cls)
  if not ok then
    r.art, r.warum = "nicht", warumNicht(info, cls)
    return r
  end
  local stufe = UnitLevel("player") or 1
  local braucht = math.max(tonumber(abStufe) or 1, tonumber(info.minStufe) or 1)
  if braucht > stufe then r.ab = braucht end
  local s = werte(info)
  r.passtNicht = hatWerte(s) and r.gutFuer and #r.gutFuer > 0 and not enthaelt(r.gutFuer, cls) or false
  local sp = QW.Spez()
  if not sp or type(sp.w) ~= "table" then
    r.art = "unbekannt"
    return r
  end
  local neu = punkte(s, sp.w, info.loc, cls)
  if info.loc == "INVTYPE_WEAPON" then
    local dw = tab(tab(fdb().prof)[cls]).dw
    if not (tonumber(dw) and dw <= stufe) then slots = { 16 } end
  end
  -- angelegte Teile: Link und Punkte
  local function angelegt(slot)
    local okL, link = ruf(GetInventoryItemLink, "player", slot)
    if not (okL and type(link) == "string") then return nil, 0 end
    local ci = QW.Info(link)
    return link, ci and punkte(werte(ci), sp.w, ci.loc, cls) or 0, ci
  end
  local haupt, hauptPunkte, hauptInfo = angelegt(16)
  local neben, nebenPunkte = angelegt(17)
  local zweihandAn = hauptInfo and hauptInfo.loc == "INVTYPE_2HWEAPON"
  local beste
  for _, slot in ipairs(slots) do
    local cur, alt = angelegt(slot)
    if cur and WW.ItemID(cur) == info.id then
      r.art, r.slot = "angelegt", slot
      return r
    end
    local leer = cur == nil
    if info.loc == "INVTYPE_2HWEAPON" then
      -- ein Zweihänder ersetzt Waffenhand und Schildhand zusammen
      alt = hauptPunkte + nebenPunkte
      leer = haupt == nil and neben == nil
    elseif zweihandAn and (slot == 16 or slot == 17) then
      -- neben einem Zweihänder ist die Schildhand nicht "frei": das neue Teil müsste den Zweihänder ersetzen
      alt = hauptPunkte
      leer = false
    end
    local pct = alt > 0 and (neu - alt) / alt * 100 or (neu > 0 and 100 or 0)
    if not beste or pct > beste.pct then beste = { pct = pct, slot = slot, leer = leer } end
  end
  r.pct, r.slot = beste.pct, beste.slot
  if neu <= 0 then
    r.art = "werte"
  elseif beste.leer then
    r.art = "leer"
  elseif beste.pct >= 1 then
    r.art = "upgrade"
  elseif beste.pct > -1 then
    r.art = "gleich"
  else
    r.art = "schlechter"
  end
  return r
end

local function istGut(r) return r and (r.art == "upgrade" or r.art == "leer") end

-- "+12 %"; sehr große Werte (das angelegte Teil hat fast keine passenden Werte) gedeckelt
local function prozent(p)
  p = tonumber(p) or 0
  if p > 300 then return "300 % und mehr" end
  return runden(p) .. " %"
end

-- Ein Satz zur Bewertung (farbig), oder nil bei Nicht-Ausrüstung.
function QW.UrteilText(r)
  if not r then return nil end
  local slot = r.slot and SLOT_DE[r.slot]
  local t
  if r.art == "upgrade" then
    t = WW.f("gruen", "Upgrade +" .. prozent(r.pct) .. (slot and (" (" .. slot .. ")") or ""))
  elseif r.art == "leer" then
    t = WW.f("gruen", "füllt einen leeren Platz" .. (slot and (" (" .. slot .. ")") or ""))
  elseif r.art == "gleich" then
    t = WW.f("grau", "etwa gleich wie dein angelegtes Teil")
  elseif r.art == "schlechter" then
    t = WW.f("rot", "schlechter (" .. runden(r.pct) .. " %)")
  elseif r.art == "angelegt" then
    t = WW.f("grau", "trägst du schon")
  elseif r.art == "nicht" then
    t = WW.f("grau", r.warum or "nicht für dich")
  elseif r.art == "werte" then
    t = WW.f("grau", "Werte bringen dir nichts")
  elseif r.art == "unbekannt" then
    t = WW.f("grau", "keine Gewichte für deine Klasse")
  else
    return nil
  end
  if r.ab and r.art ~= "nicht" then t = t .. WW.f("orange", " - ab Stufe " .. r.ab) end
  if r.passtNicht and (r.art == "upgrade" or r.art == "leer" or r.art == "gleich") then
    t = t .. WW.f("grau", " (eher für " .. klassenListe(r.gutFuer, 3) .. ")")
  end
  return t
end

-- Kurz für Listen (Dungeon-Karte): "(Upgrade +12 %, selten)" oder nil
function QW.Kurz(x)
  local ok, r = pcall(QW.Bewerte, x)
  if not ok or not r then return nil end
  local t = {}
  if istGut(r) then
    t[#t + 1] = r.art == "leer" and WW.f("gruen", "Upgrade: leerer Platz") or WW.f("gruen", "Upgrade +" .. prozent(r.pct))
  elseif r.art == "nicht" or r.art == "werte" then
    t[#t + 1] = WW.f("grau", "nichts für dich")
  end
  if r.selten then
    t[#t + 1] = WW.f(QFARBE[tonumber(r.info.qualitaet)] or QFARBE[3], "selten")
  end
  if (not istGut(r) or r.passtNicht) and r.gutFuer and #r.gutFuer > 0 then
    t[#t + 1] = "für " .. klassenListe(r.gutFuer, 3)
  end
  if #t == 0 then return nil end
  return "(" .. table.concat(t, ", ") .. ")"
end

-- Farbiger Name mit Symbol
function QW.ItemZeile(info)
  local icon = info.icon or "Interface\\Icons\\INV_Misc_QuestionMark"
  local farbe = QFARBE[tonumber(info.qualitaet) or 1] or QFARBE[1]
  return "|T" .. tostring(icon) .. ":16:16|t " .. WW.f(farbe, info.name or "?")
end

---------------------------------------------------------------------------
-- Belohnungen einer Quest: aus dem Questlog oder aus den Daten
---------------------------------------------------------------------------
local gfIdx
-- [questID] = { itemIDs } aus den Quellen-Zeilen von ForeverDB ("q^quest^titel^...")
local function gfIndex()
  if gfIdx then return gfIdx end
  gfIdx = {}
  local text = fdb().gfItemText
  if type(text) ~= "string" then return gfIdx end
  for zeile in text:gmatch("[^\n]+") do
    if zeile:find("q^", 1, true) then
      local id36, quellen = zeile:match("^(%w+)|[^|]*|[^|]*|[^|]*|[^|]*|[^|]*|[^|]*|(.*)$")
      local id = id36 and tonumber(id36, 36)
      if id and quellen then
        for src in (quellen .. "~"):gmatch("(.-)~") do
          local q = tonumber(src:match("^q%^(%d+)%^"))
          if q then
            gfIdx[q] = gfIdx[q] or {}
            if not enthaelt(gfIdx[q], id) then table.insert(gfIdx[q], id) end
          end
        end
      end
    end
  end
  return gfIdx
end

local function kopie(l)
  local t = {}
  for _, v in ipairs(tab(l)) do
    if tonumber(v) then t[#t + 1] = tonumber(v) end
  end
  return t
end

-- { rewards = {...}, choices = {...}, quelle = "daten", unsicher } oder nil
function QW.DatenBelohnungen(questID)
  questID = tonumber(questID)
  if not questID then return nil end
  local c = tab(tab(fdm().curated)[questID])
  local q = tab(tab(fdm().data)[questID])
  local rewards = (type(c.rewards) == "table" and c.rewards) or q.rewards
  local choices = (type(c.choices) == "table" and c.choices) or q.choices
  if type(rewards) == "table" or type(choices) == "table" then
    local b = { rewards = kopie(rewards), choices = kopie(choices), quelle = "daten" }
    if #b.rewards + #b.choices > 0 then return b end
  end
  local gf = gfIndex()[questID]
  if gf and #gf > 0 then
    return { rewards = {}, choices = kopie(gf), quelle = "daten", unsicher = true }
  end
  return nil
end

-- Belohnungen einer Quest im Log (eintrag = { questID, index }).
local function logBelohnungen(eintrag)
  local id = eintrag.questID
  local c = belCache[id]
  if c then return c end
  local wahlArt = WW.QuestWahlArt()
  if type(GetQuestLogItemLink) ~= "function" or not wahlArt then
    local d = QW.DatenBelohnungen(id)
    belCache[id] = d or { rewards = {}, choices = {}, quelle = "daten" }
    return belCache[id]
  end
  -- Ersatz aus den Daten, wenn wir die Quest im Log nicht wählen können (nicht merken: später neu versuchen)
  local function ausDaten()
    versuche[id] = (versuche[id] or 0) + 1
    local d = QW.DatenBelohnungen(id) or { rewards = {}, choices = {}, quelle = "daten" }
    if versuche[id] >= 5 then belCache[id] = d end
    return d
  end
  if wahlArt ~= "modern" and not eintrag.index then return ausDaten() end
  -- Auswahl im Questlog merken, Quest wählen, prüfen (wie ForeverDB Q.withSelected), lesen, Auswahl zurück.
  -- Forever: C_QuestLog.SetSelectedQuest(questID); die Belohnungs-Funktionen lesen dann die gewählte Quest.
  local gewaehltOk, zurueck = WW.QuestWaehlen(id, eintrag.index)
  if not gewaehltOk then
    zurueck()
    return ausDaten()
  end
  local res = { rewards = {}, choices = {}, quelle = "log" }
  local vollstaendig = true
  local function lies(art, ziel, anzahlFn, infoFn)
    local ok, n = ruf(anzahlFn, id)
    n = ok and tonumber(n) or 0
    for i = 1, n do
      local okL, link = pcall(GetQuestLogItemLink, art, i, id)
      local x = okL and type(link) == "string" and link:find("item:", 1, true) and link or nil
      if not x then
        local okI, _, _, _, _, _, itemID = ruf(infoFn, i, id)
        if okI and tonumber(itemID) then x = tonumber(itemID) end
      end
      if x then table.insert(res[ziel], x) else vollstaendig = false end
    end
  end
  lies("reward", "rewards", GetNumQuestLogRewards, GetQuestLogRewardInfo)
  lies("choice", "choices", GetNumQuestLogChoices, GetQuestLogChoiceInfo)
  zurueck()
  if #res.rewards + #res.choices == 0 and vollstaendig then
    local d = QW.DatenBelohnungen(id)
    if d then res = d end
  end
  versuche[id] = (versuche[id] or 0) + 1
  if vollstaendig or versuche[id] >= 5 then belCache[id] = res end
  return res
end

-- Urteil über alle Belohnungen einer Quest:
-- { art = "upgrade"|"selten"|"fuer"|"nichts"|"kein"|"leer", text, farbe, alle = { {x, wahl, r} }, beste, laedt }
function QW.QuestUrteil(bel)
  if not bel then return { art = "leer", text = "keine Daten", farbe = "grau", alle = {} } end
  local alle = {}
  for _, x in ipairs(tab(bel.rewards)) do alle[#alle + 1] = { x = x, wahl = false } end
  for _, x in ipairs(tab(bel.choices)) do alle[#alle + 1] = { x = x, wahl = true } end
  if #alle == 0 then return { art = "leer", text = "keine Gegenstände", farbe = "grau", alle = alle } end
  local bestUp, maxQ, bestFuer, laedt, ausruestung = nil, 0, nil, false, false
  for _, e in ipairs(alle) do
    local ok, r = pcall(QW.Bewerte, e.x)
    e.r = ok and r or nil
    if e.r then
      if not e.r.info.da then laedt = true end
      if e.r.art ~= "kein" then ausruestung = true end
      local q = tonumber(e.r.info.qualitaet) or 0
      if istGut(e.r) then
        local p = e.r.art == "leer" and 1000 or e.r.pct
        if not bestUp or p > bestUp.p then bestUp = { p = p, e = e } end
      end
      if q > maxQ then maxQ = q end
      if e.r.gutFuer and #e.r.gutFuer > 0 and (not bestFuer or q > bestFuer.q) then bestFuer = { q = q, e = e } end
    end
  end
  local u
  if bestUp then
    u = { art = "upgrade", text = "Upgrade für dich", farbe = "gruen" }
  elseif maxQ >= 3 then
    u = { art = "selten", text = "Selten", farbe = QFARBE[maxQ] or QFARBE[3] }
  elseif bestFuer then
    u = { art = "fuer", text = "Für: " .. klassenListe(bestFuer.e.r.gutFuer, 2), farbe = "weiss" }
  elseif ausruestung then
    u = { art = "nichts", text = "Nichts für dich", farbe = "grau" }
  else
    u = { art = "kein", text = "keine Ausrüstung", farbe = "grau" }
  end
  u.alle, u.laedt = alle, laedt
  if bestUp and bestUp.e.wahl then u.beste = bestUp.e end
  if bestUp then u.upgrade = bestUp.e end
  return u
end

---------------------------------------------------------------------------
-- Questlog lesen
---------------------------------------------------------------------------
-- Quests im Log auf der aktuellen Karte und allen Zonen des Kontinents (C_QuestLog.GetQuestsOnMap).
-- So findet ForeverDB (QuestData.lua questsFromGameMaps) Quests unter eingeklappten Überschriften.
local function questsVonKarten()
  local ids = {}
  local CQ, CM = C_QuestLog, C_Map
  if not (type(CQ) == "table" and type(CQ.GetQuestsOnMap) == "function" and type(CM) == "table"
    and type(CM.GetBestMapForUnit) == "function") then
    return ids
  end
  local okHier, hier = pcall(CM.GetBestMapForUnit, "player")
  if not okHier or not tonumber(hier) then return ids end
  local karten, gesehenK = {}, {}
  local function karte(m) if m and not gesehenK[m] then gesehenK[m] = true karten[#karten + 1] = m end end
  karte(hier)
  local typen = type(Enum) == "table" and type(Enum.UIMapType) == "table" and Enum.UIMapType or LEER
  local zone, kontinent = tonumber(typen.Zone) or 3, tonumber(typen.Continent) or 2
  if type(CM.GetMapInfo) == "function" then
    local okI, info = pcall(CM.GetMapInfo, hier)
    local eltern, schutz = okI and type(info) == "table" and info.parentMapID, 0
    while tonumber(eltern) and eltern ~= 0 and schutz < 4 do
      local okE, einfo = pcall(CM.GetMapInfo, eltern)
      if not okE or type(einfo) ~= "table" then break end
      if einfo.mapType == kontinent then
        if type(CM.GetMapChildrenInfo) == "function" then
          local okK, kinder = pcall(CM.GetMapChildrenInfo, eltern, zone, false)
          if okK and type(kinder) == "table" then
            for _, k in ipairs(kinder) do if type(k) == "table" then karte(k.mapID) end end
          end
        end
        break
      end
      eltern, schutz = einfo.parentMapID, schutz + 1
    end
  end
  for _, m in ipairs(karten) do
    local ok, liste = pcall(CQ.GetQuestsOnMap, m)
    if ok and type(liste) == "table" then
      for _, p in ipairs(liste) do
        if type(p) == "table" and tonumber(p.questID) then ids[#ids + 1] = tonumber(p.questID) end
      end
    end
  end
  return ids
end

-- { {kopf = true, titel}, {questID, titel, stufe, index, fertig}, ... }
local function leseQuestlog()
  local liste = {}
  local ql = C_QuestLog
  -- WW.QuestLogEintraege: C_QuestLog.GetInfo (Forever), sonst das alte GetQuestLogTitle
  for _, e in ipairs(WW.QuestLogEintraege()) do
    if e.kopf then
      liste[#liste + 1] = { kopf = true, titel = e.titel or "?" }
    elseif e.questID then
      liste[#liste + 1] = { questID = e.questID, titel = e.titel or "?", stufe = e.stufe, index = e.index, fertig = e.fertig }
    end
  end
  -- Quests unter eingeklappten Überschriften: GetInfo / GetQuestLogTitle sehen hier nur sichtbare Zeilen.
  -- Ohne die Überschriften des Spielers aufzuklappen: Quests auf den Karten, und bekannte Dungeon-Quests.
  local gelistet = {}
  for _, e in ipairs(liste) do if e.questID then gelistet[e.questID] = true end end
  local imLog = ql and type(ql.IsOnQuest) == "function" and function(id)
    local ok, r = pcall(ql.IsOnQuest, id)
    return ok and r and true or false
  end
  local versteckt = {}
  local function dazu(id, sicher)
    if not id or id <= 0 or gelistet[id] then return end
    if not sicher and not (imLog and imLog(id)) then return end
    gelistet[id] = true
    versteckt[#versteckt + 1] = id
  end
  -- GetQuestsOnMap liefert nur Quests aus dem Log; mit IsOnQuest zusätzlich prüfen, wenn es das gibt
  for _, id in ipairs(questsVonKarten()) do dazu(id, not imLog) end
  if imLog then
    for id in pairs(tab(fdm().data)) do if type(id) == "number" then dazu(id, false) end end
  end
  if #versteckt > 0 then
    table.sort(versteckt)
    liste[#liste + 1] = { kopf = true, titel = "Unter eingeklappten Überschriften" }
    for _, id in ipairs(versteckt) do
      local titel
      if ql and type(ql.GetTitleForQuestID) == "function" then
        local ok, t = pcall(ql.GetTitleForQuestID, id)
        if ok and type(t) == "string" and t ~= "" then titel = t end
      end
      titel = titel or tab(tab(fdm().data)[id]).name or ("Quest " .. id)
      local index
      if ql and type(ql.GetLogIndexForQuestID) == "function" then
        local ok, x = pcall(ql.GetLogIndexForQuestID, id)
        if ok and tonumber(x) and x > 0 then index = tonumber(x) end
      end
      local stufe = tonumber(tab(tab(fdm().data)[id]).level)
      liste[#liste + 1] = { questID = id, titel = titel, stufe = stufe, index = index, versteckt = true }
    end
  end
  return liste
end

local logListe = {}
local upgradeQuest = {}   -- [questID] = true, wenn eine Belohnung ein Upgrade ist (für die Haken im Questlog)

-- Questlog und Belohnungen neu lesen und bewerten.
function QW.Scannen()
  local neu = leseQuestlog()
  wipe(upgradeQuest)
  for _, e in ipairs(neu) do
    if not e.kopf then
      e.bel = logBelohnungen(e)
      e.urteil = QW.QuestUrteil(e.bel)
      if e.urteil.art == "upgrade" then upgradeQuest[e.questID] = true end
    end
  end
  logListe = neu
  return neu
end

function QW.HatUpgrade(questID) return upgradeQuest[questID] == true end

---------------------------------------------------------------------------
-- Quest-Items: welcher Gegenstand gehört zu welcher Quest?
-- Index (einmal): ForeverDB-Quests (Ziele "i<item>:<anzahl>", Start "i<item>") und FDM-Startgegenstände.
-- Dazu live aus dem Questlog: Ziele vom Typ Gegenstand, über den deutschen Namen (Forever-eigene Quests).
---------------------------------------------------------------------------
local itemIdx           -- [itemID] = { {q, art = "ziel" | "start", anzahl} }
local qcFeldCache = {}
local logStand          -- { quests = {[questID] = {titel, fertig, ziele}}, namen = {[Itemname] = { {q, z} }} }

local function qcFelder(q)
  local c = qcFeldCache[q]
  if c == nil then
    local s = tab(fdb().qcQuests)[q]
    c = type(s) == "string" and teile(s, "|") or false
    qcFeldCache[q] = c
  end
  return c or nil
end

local function baueItemIndex()
  itemIdx = {}
  local function dazu(item, q, art, anzahl)
    item, q = tonumber(item), tonumber(q)
    if not item or not q then return end
    local l = itemIdx[item]
    if not l then
      l = {}
      itemIdx[item] = l
    end
    for _, e in ipairs(l) do if e.q == q and e.art == art then return end end
    l[#l + 1] = { q = q, art = art, anzahl = anzahl }
  end
  -- "titel|stufe|min|seite|klassen|völker|alle|eins|gruppe|start|ende|ziele|..."
  for q, s in pairs(tab(fdb().qcQuests)) do
    if type(q) == "number" and type(s) == "string" then
      local start, ziele = s:match("^[^|]*|[^|]*|[^|]*|[^|]*|[^|]*|[^|]*|[^|]*|[^|]*|[^|]*|([^|]*)|[^|]*|([^|]*)")
      if start then for it in start:gmatch("i(%d+)") do dazu(it, q, "start") end end
      if ziele then for it, n in ziele:gmatch("i(%d+):(%d+)") do dazu(it, q, "ziel", tonumber(n)) end end
    end
  end
  for _, quelle in ipairs({ fdm().data, fdm().curated }) do
    for q, d in pairs(tab(quelle)) do
      if type(q) == "number" and type(d) == "table" and tonumber(d.item) then dazu(d.item, q, "start") end
    end
  end
end

-- Darf der Spieler die Quest annehmen (Seite, Klassen- und Völkermaske)?
local function questPasst(q)
  local meine = UnitFactionGroup and UnitFactionGroup("player")
  local f = qcFelder(q)
  if f then
    if (f[4] == "a" and meine == "Horde") or (f[4] == "h" and meine == "Alliance") then return false end
    if bit and bit.band and bit.lshift then
      local km = tonumber(f[5])
      local kid = tonumber((select(3, UnitClass("player"))))
      if km and km > 0 and kid and kid >= 1 and kid <= 31 and bit.band(km, bit.lshift(1, kid - 1)) == 0 then return false end
      local vm = tonumber(f[6])
      local vid = tonumber((select(3, UnitRace("player"))))
      -- Forevers neue Völker liegen außerhalb der Classic-Maske: erlauben
      if vm and vm > 0 and vid and vid >= 1 and vid <= 8 and bit.band(vm, bit.lshift(1, vid - 1)) == 0 then return false end
    end
    return true
  end
  local d = tab(fdm().curated)[q]
  local fr = (type(d) == "table" and d.faction) or tab(tab(fdm().data)[q]).faction
  if fr and fr ~= "Both" and meine and (meine == "Alliance" or meine == "Horde") and fr ~= meine then return false end
  return true
end

local function questErledigt(q)
  local f = qcFelder(q)
  if (f and f[14] and f[14]:find("p", 1, true)) or tab(tab(fdm().data)[q]).repeatable then return false end
  return WW.QuestErledigt(q) or false
end

local questTitel = {}   -- deutsche Namen vom Spiel (Sitzung)
local function questNameQ(q)
  local lq = logStand and logStand.quests[q]
  if lq and type(lq.titel) == "string" and lq.titel ~= "" then return lq.titel end
  if questTitel[q] then return questTitel[q] end
  local ql = C_QuestLog
  if ql then
    for _, fn in ipairs({ ql.GetTitleForQuestID, ql.GetQuestInfo }) do
      local ok, t = ruf(fn, q)
      if ok and type(t) == "string" and t ~= "" then
        questTitel[q] = t
        return t
      end
    end
  end
  local f = qcFelder(q)
  if f and f[1] and f[1] ~= "" then return f[1] end
  return tab(tab(fdm().data)[q]).name or ("Quest " .. q)
end

-- "Name: 3/10" -> name, 3, 10
local function zielTeile(text)
  local n, a, b = text:match("^(.-):%s*(%d+)%s*/%s*(%d+)")
  return n, tonumber(a), tonumber(b)
end

local function baueLogStand()
  local st = { quests = {}, namen = {} }
  local ql = C_QuestLog
  for _, e in ipairs(leseQuestlog()) do
    if e.questID then
      local ziele = {}
      local ok, objs = ruf(ql and ql.GetQuestObjectives, e.questID)
      if ok and type(objs) == "table" then
        for _, o in ipairs(objs) do
          if type(o) == "table" and type(o.text) == "string" then ziele[#ziele + 1] = { text = o.text, art = o.type } end
        end
      end
      if #ziele == 0 and e.index then
        local okN, n = ruf(GetNumQuestLeaderBoards, e.index)
        n = okN and tonumber(n) or 0
        for j = 1, n do
          local okZ, text, art = ruf(GetQuestLogLeaderBoard, j, e.index)
          if okZ and type(text) == "string" then ziele[#ziele + 1] = { text = text, art = art } end
        end
      end
      for _, z in ipairs(ziele) do
        z.name, z.hat, z.braucht = zielTeile(z.text)
        if z.name and z.name ~= "" and (z.art == "item" or z.art == nil) then
          st.namen[z.name] = st.namen[z.name] or {}
          table.insert(st.namen[z.name], { q = e.questID, z = z })
        end
      end
      st.quests[e.questID] = { titel = e.titel, fertig = e.fertig, ziele = ziele }
    end
  end
  logStand = st
  return st
end

-- Nach Questlog-Änderungen neu lesen (der Index aus den Daten bleibt)
function QW.QuestItemsNeu()
  logStand = nil
end

local STATUS_RANG = { log = 1, start = 2, offen = 3, weg = 4 }

-- Quests eines Gegenstands für dich: Liste { {q, status = "log"|"start"|"offen"|"weg", text, farbe} }
-- und ein Gesamtstatus ("weg" nur, wenn alle Quests erledigt sind) oder nil (kein Quest-Item).
function QW.ItemQuests(itemID)
  local out = {}
  itemID = tonumber(itemID)
  if not itemID then return out, nil end
  if not itemIdx then baueItemIndex() end
  local st = logStand or baueLogStand()
  local okN, name = pcall(WW.ItemName, itemID)
  name = okN and name or nil
  local gesehenQ = {}
  local function eintrag(q, art)
    if gesehenQ[q] then return end
    gesehenQ[q] = true
    local qn = questNameQ(q)
    local lq = st.quests[q]
    local e
    if lq then
      local stand
      for _, z in ipairs(lq.ziele) do
        if name and z.name == name and z.braucht then stand = z.hat .. "/" .. z.braucht end
      end
      e = { status = "log", farbe = "gruen",
        text = "Quest: " .. qn .. " – im Questlog" .. (stand and (" " .. stand) or "") .. (lq.fertig and " (fertig)" or "") }
    elseif questErledigt(q) then
      e = { status = "weg", farbe = "orange", text = "Quest erledigt (" .. qn .. ") – kann weg" }
    elseif art == "start" then
      e = { status = "start", farbe = "gelb", text = "Startet Quest: " .. qn }
    else
      e = { status = "offen", farbe = "grau", text = "Für Quest: " .. qn .. " (noch nicht angenommen)" }
    end
    e.q = q
    out[#out + 1] = e
  end
  for _, x in ipairs(itemIdx[itemID] or LEER) do
    if st.quests[x.q] or questPasst(x.q) then eintrag(x.q, x.art) end
  end
  if name then
    for _, x in ipairs(st.namen[name] or LEER) do eintrag(x.q, "ziel") end
  end
  if #out == 0 then return out, nil end
  table.sort(out, function(a, b)
    if STATUS_RANG[a.status] ~= STATUS_RANG[b.status] then return STATUS_RANG[a.status] < STATUS_RANG[b.status] end
    return a.q < b.q
  end)
  return out, out[1].status
end

-- Gegenstände in den eigenen Taschen, live: { [itemID] = anzahl }
local function taschenLive()
  local ids = {}
  local C = C_Container
  local slotsFn = (C and C.GetContainerNumSlots) or GetContainerNumSlots
  local infoFn = (C and C.GetContainerItemInfo) or GetContainerItemInfo
  local idFn = (C and C.GetContainerItemID) or GetContainerItemID
  local taschen
  if type(WW.TaschenIDs) == "function" then
    local ok, t = pcall(WW.TaschenIDs)
    if ok and type(t) == "table" and #t > 0 then taschen = t end
  end
  taschen = taschen or { 0, 1, 2, 3, 4 }
  for _, bag in ipairs(taschen) do
    local ok, n = ruf(slotsFn, bag)
    n = ok and tonumber(n) or 0
    for s = 1, n do
      local ok2, a, b = ruf(infoFn, bag, s)
      local id, anz
      if ok2 and type(a) == "table" then
        id, anz = tonumber(a.itemID), tonumber(a.stackCount)
      elseif ok2 and a then
        anz = tonumber(b)
        local ok3, i = ruf(idFn, bag, s)
        id = ok3 and tonumber(i) or nil
      end
      if id then ids[id] = (ids[id] or 0) + (anz or 1) end
    end
  end
  return ids
end

-- gespeicherter Stand "id:anzahl:gebunden,..." -> { [id] = anzahl }
local function standLesen(s)
  local ids = {}
  if type(s) ~= "string" then return ids end
  for id, n in s:gmatch("(%d+):(%d+)") do
    id = tonumber(id)
    ids[id] = (ids[id] or 0) + (tonumber(n) or 0)
  end
  return ids
end

local ZEILEN_RANG = { weg = 1, log = 2, start = 3, offen = 4, anders = 5 }

-- Zeilen für den Reiter: { id, anzahl, wo, ich, liste, gesamt }, sortiert: kann weg, im Questlog, startet Quest, ...
-- Eigene Taschen live, eigene Bank und (wenn eingeschaltet) andere Charaktere aus dem Inventar-Modul.
function QW.QuestItemZeilen()
  logStand = nil
  local zeilen = {}
  local function quelle(ids, wo, ich)
    for id, n in pairs(ids) do
      local liste, gesamt = QW.ItemQuests(id)
      if gesamt then
        zeilen[#zeilen + 1] = { id = id, anzahl = n, wo = wo, ich = ich, liste = liste, gesamt = ich and gesamt or "anders" }
      end
    end
  end
  quelle(taschenLive(), "Tasche", true)
  local e = einst()
  local inv = WW.Inventar
  if inv and type(inv.Charaktere) == "function" then
    local ok, chars = pcall(inv.Charaktere)
    if ok and type(chars) == "table" then
      for _, c in ipairs(chars) do
        if type(c) == "table" and type(c.e) == "table" then
          if c.ich then
            quelle(standLesen(c.e.bank), "Bank", true)
          elseif e and e.andere then
            quelle(standLesen(c.e.tasche), tostring(c.name) .. ": Tasche", false)
            quelle(standLesen(c.e.bank), tostring(c.name) .. ": Bank", false)
          end
        end
      end
    end
  end
  for _, z in ipairs(zeilen) do
    local info = QW.Info(z.id)
    z.name = info and info.name or ("Gegenstand " .. z.id)
    z.info = info
  end
  table.sort(zeilen, function(a, b)
    if ZEILEN_RANG[a.gesamt] ~= ZEILEN_RANG[b.gesamt] then return ZEILEN_RANG[a.gesamt] < ZEILEN_RANG[b.gesamt] end
    if a.ich ~= b.ich then return a.ich end
    if a.name ~= b.name then return a.name < b.name end
    return a.wo < b.wo
  end)
  return zeilen
end

---------------------------------------------------------------------------
-- Tooltip: "Für dich (Krieger): Upgrade +12 % (Waffenhand)" und "Gut für: ..."
---------------------------------------------------------------------------
local gesehen = setmetatable({}, { __mode = "k" })

local function ausruestungZeilen(tt, x)
  local r = QW.Bewerte(x)
  if not r or r.art == "kein" then return end
  local cls = meineKlasse()
  if r.art == "nicht" then
    tt:AddLine(r.warum, 0.6, 0.6, 0.6)
  else
    local sp = QW.Spez()
    local wer = QW.KlassenName(cls) .. (sp and (", " .. QW.SpezName(sp)) or "")
    local text = QW.UrteilText(r)
    if text then tt:AddLine("Für dich (" .. wer .. "): " .. text, 1, 1, 1) end
  end
  if r.gutFuer and #r.gutFuer > 0 and not (#r.gutFuer == 1 and r.gutFuer[1] == cls) then
    tt:AddLine("Gut für: " .. klassenListe(r.gutFuer), 0.5, 0.8, 1, true)
  end
end

-- Quest-Items: bis zu drei Zeilen "Quest: X – im Questlog 3/10" / "Quest erledigt (X) – kann weg" / "Startet Quest: X"
local function questItemZeilen(tt, id)
  local liste = QW.ItemQuests(id)
  for i, e in ipairs(liste) do
    if i > 3 then
      tt:AddLine("... und " .. (#liste - 3) .. " weitere Quests", 0.6, 0.6, 0.6)
      break
    end
    tt:AddLine(WW.f(e.farbe, e.text), 1, 1, 1, true)
  end
end

function QW.TooltipZeilen(tt, data)
  local e = einst()
  if not e or not (e.tooltip or e.itemTipp) then return end
  if tt ~= GameTooltip and tt ~= ItemRefTooltip then return end
  local id = data and tonumber(data.id)
  local link
  if tt.GetItem then
    local ok, _, l = pcall(tt.GetItem, tt)
    if ok and type(l) == "string" then link = l end
  end
  id = id or WW.ItemID(link)
  if not id or gesehen[tt] == id then return end
  gesehen[tt] = id
  if link and WW.ItemID(link) ~= id then link = nil end
  if e.tooltip then
    local ok, err = pcall(ausruestungZeilen, tt, link or id)
    if not ok then geterrorhandler()(err) end
  end
  if e.itemTipp then
    local ok, err = pcall(questItemZeilen, tt, id)
    if not ok then geterrorhandler()(err) end
  end
  if tt.Show then tt:Show() end
end

local function tooltipsAnschliessen()
  local gehakt = false
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType
     and Enum.TooltipDataType.Item then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data)
      pcall(QW.TooltipZeilen, tt, data)
    end)
    gehakt = true
  end
  for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
    if tt and tt.HookScript then
      if not gehakt then
        pcall(tt.HookScript, tt, "OnTooltipSetItem", function(self) pcall(QW.TooltipZeilen, self) end)
      end
      pcall(tt.HookScript, tt, "OnTooltipCleared", function(self) gesehen[self] = nil end)
    end
  end
  if not gehakt and GameTooltip then
    for _, name in ipairs({ "SetBagItem", "SetHyperlink", "SetInventoryItem", "SetLootItem", "SetMerchantItem",
      "SetItemByID", "SetQuestLogItem", "SetQuestItem" }) do
      if type(GameTooltip[name]) == "function" then
        hooksecurefunc(GameTooltip, name, function(self) pcall(QW.TooltipZeilen, self) end)
      end
    end
  end
end
WW:BeimStart(tooltipsAnschliessen)

---------------------------------------------------------------------------
-- Haken in Blizzards Questlog bei Quests mit Upgrade (nur eigene Texturen, nur hooksecurefunc)
---------------------------------------------------------------------------
local haken = setmetatable({}, { __mode = "k" })   -- Blizzard-Knopf -> eigene Textur

local function setzeHaken(knopf, an)
  local h = haken[knopf]
  if not h then
    if not an then return end
    h = knopf:CreateTexture(nil, "OVERLAY")
    h:SetSize(14, 14)
    h:SetPoint("RIGHT", knopf, "RIGHT", -2, 0)
    h:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    haken[knopf] = h
  end
  if an then h:Show() else h:Hide() end
end

-- Klassischer Questlog: QuestLogTitle1..n, GetID() = Index im Log
local function hakenKlassisch()
  local e = einst()
  local an = e and e.marken
  local n = tonumber(QUESTS_DISPLAYED) or 6
  for i = 1, n do
    local knopf = _G["QuestLogTitle" .. i]
    if type(knopf) == "table" and knopf.GetID then
      local zeigen = false
      if an and knopf.IsShown and knopf:IsShown() then
        local ok, e = pcall(WW.QuestLogEintrag, knopf:GetID())
        if ok and e and not e.kopf and e.questID then zeigen = upgradeQuest[e.questID] == true end
      end
      setzeHaken(knopf, zeigen)
    end
  end
end

-- Moderner Questlog (Karte & Questlog): Knöpfe aus QuestScrollFrame.titleFramePool mit .questID
local function hakenModern()
  local e = einst()
  local an = e and e.marken
  local sf = QuestScrollFrame
  local pool = type(sf) == "table" and sf.titleFramePool
  if type(pool) ~= "table" or type(pool.EnumerateActive) ~= "function" then return end
  for knopf in pool:EnumerateActive() do
    if type(knopf) == "table" then
      setzeHaken(knopf, an and tonumber(knopf.questID) and upgradeQuest[tonumber(knopf.questID)] == true or false)
    end
  end
end

local function hakenAktualisieren()
  pcall(hakenKlassisch)
  pcall(hakenModern)
end

local gehakt = {}
local function questlogAnschliessen()
  for _, name in ipairs({ "QuestLog_Update", "QuestLogQuests_Update" }) do
    if not gehakt[name] and type(_G[name]) == "function" then
      gehakt[name] = true
      hooksecurefunc(name, function() pcall(hakenAktualisieren) end)
    end
  end
end
WW:BeimStart(questlogAnschliessen)
WW:Event("ADDON_LOADED", function() pcall(questlogAnschliessen) end)

---------------------------------------------------------------------------
-- Reiter "Quests"
---------------------------------------------------------------------------
local panel, liste, detail, gewaehlt
local LISTE_B = 500

local function zeigeDetail()
  if not detail then return end
  local e
  for _, x in ipairs(logListe) do
    if not x.kopf and x.questID == gewaehlt then e = x end
  end
  local z = {}
  if not e then
    z[1] = WW.f("grau", "Klick links auf eine Quest: alle Belohnungen und was sie dir bringen.")
  else
    z[#z + 1] = WW.f("gelb", (e.stufe and ("[" .. e.stufe .. "] ") or "") .. e.titel)
    z[#z + 1] = "Bewertet für: " .. QW.SpezText()
    local u = e.urteil or QW.QuestUrteil(e.bel)
    local function eintrag(a)
      if not a.r then return end
      local zeile = "  " .. QW.ItemZeile(a.r.info)
      if u.beste == a then zeile = WW.f("gruen", "> Beste Wahl: ") .. QW.ItemZeile(a.r.info) end
      z[#z + 1] = zeile
      local t = QW.UrteilText(a.r)
      if t then z[#z + 1] = "      " .. t end
      if a.r.selten then z[#z + 1] = "      " .. WW.f(QFARBE[tonumber(a.r.info.qualitaet)] or QFARBE[3], "selten") end
      if a.r.gutFuer and #a.r.gutFuer > 0 then
        z[#z + 1] = "      " .. WW.f("ff80ccff", "Gut für: " .. klassenListe(a.r.gutFuer))
      end
      if not a.r.info.da then z[#z + 1] = "      " .. WW.f("grau", "(Daten werden geladen)") end
    end
    local hatR, hatC = false, false
    for _, a in ipairs(u.alle or LEER) do
      if a.wahl then hatC = true else hatR = true end
    end
    local daten = e.bel and e.bel.quelle == "daten"
    if hatR then
      z[#z + 1] = " "
      z[#z + 1] = WW.f("titel", "Belohnung" .. (daten and " (aus den Daten)" or "") .. ":")
      for _, a in ipairs(u.alle) do if not a.wahl then eintrag(a) end end
    end
    if hatC then
      z[#z + 1] = " "
      local kopf = (e.bel and e.bel.unsicher) and "Mögliche Belohnungen (aus den Daten):"
        or ("Zur Wahl, eine davon" .. (daten and " (aus den Daten)" or "") .. ":")
      z[#z + 1] = WW.f("titel", kopf)
      for _, a in ipairs(u.alle) do if a.wahl then eintrag(a) end end
    end
    if not hatR and not hatC then
      z[#z + 1] = " "
      z[#z + 1] = WW.f("grau", "Keine Gegenstände als Belohnung bekannt.")
    end
  end
  detail.text:SetText(table.concat(z, "\n"))
  detail.kind:SetHeight(math.max(1, detail.text:GetStringHeight() + 8))
  -- dieselbe Quest wie zuletzt (Aktualisierung): Bildlauf behalten; andere Quest: nach oben
  if detail.zuletzt ~= gewaehlt and detail.scroll.SetVerticalScroll then detail.scroll:SetVerticalScroll(0) end
  detail.zuletzt = gewaehlt
end

local function fuelleZeile(z, e)
  for _, ic in ipairs(z.icons) do
    ic.rand:Hide()
    ic.bild:Hide()
  end
  if e.kopf then
    z.name:SetText(WW.f("gelb", e.titel))
    z.urteil:SetText("")
    z.markiert:Hide()
    return
  end
  z.name:SetText("   " .. (e.stufe and ("[" .. e.stufe .. "] ") or "") .. e.titel
    .. (e.fertig and WW.f("gruen", " (fertig)") or ""))
  local u = e.urteil
  local n = 0
  for _, a in ipairs(u and u.alle or LEER) do
    if a.r and n < #z.icons then
      n = n + 1
      local ic = z.icons[n]
      ic.bild:SetTexture(a.r.info.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
      local farbe = QFARBE[tonumber(a.r.info.qualitaet) or 1] or QFARBE[1]
      local rr, gg, bb = tonumber(farbe:sub(3, 4), 16) / 255, tonumber(farbe:sub(5, 6), 16) / 255, tonumber(farbe:sub(7, 8), 16) / 255
      if istGut(a.r) then rr, gg, bb = 0.25, 1, 0.25 end
      ic.rand:SetColorTexture(rr, gg, bb, 0.9)
      ic.rand:Show()
      ic.bild:Show()
    end
  end
  if u then
    z.urteil:SetText(WW.f(u.farbe or "grau", u.text) .. (u.laedt and WW.f("grau", " ...") or ""))
  else
    z.urteil:SetText("")
  end
  z.markiert:SetShown(e.questID == gewaehlt)
end

local function baueZeile(z)
  z.markiert = z:CreateTexture(nil, "BACKGROUND")
  z.markiert:SetAllPoints()
  z.markiert:SetColorTexture(0.3, 0.6, 1, 0.2)
  z.markiert:Hide()
  z.name = UI.Text(z)
  z.name:SetPoint("LEFT", 2, 0)
  z.name:SetWidth(222)
  if z.name.SetWordWrap then z.name:SetWordWrap(false) end
  z.icons = {}
  for i = 1, 6 do
    local rand = z:CreateTexture(nil, "BORDER")
    rand:SetSize(18, 18)
    rand:SetPoint("LEFT", 228 + (i - 1) * 19, 0)
    local bild = z:CreateTexture(nil, "ARTWORK")
    bild:SetSize(16, 16)
    bild:SetPoint("CENTER", rand, "CENTER", 0, 0)
    z.icons[i] = { rand = rand, bild = bild }
  end
  z.urteil = UI.Text(z, "klein")
  z.urteil:SetPoint("RIGHT", -2, 0)
  z.urteil:SetWidth(118)
  z.urteil:SetJustifyH("RIGHT")
  if z.urteil.SetWordWrap then z.urteil:SetWordWrap(false) end
  z:SetScript("OnClick", function(self)
    local e = self.eintrag
    if not e or e.kopf then return end
    gewaehlt = (gewaehlt ~= e.questID) and e.questID or nil
    liste:Aktualisiere()
    zeigeDetail()
  end)
  z:SetScript("OnEnter", function(self)
    local e = self.eintrag
    if not e or e.kopf or not e.urteil then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(e.titel, 1, 0.82, 0)
    GameTooltip:AddLine(e.urteil.text, 1, 1, 1)
    if e.urteil.upgrade and e.urteil.upgrade.r then
      GameTooltip:AddLine(e.urteil.upgrade.r.info.name .. ": " .. (QW.UrteilText(e.urteil.upgrade.r) or ""), 1, 1, 1, true)
    end
    GameTooltip:AddLine("Klick: alle Belohnungen", 0.55, 0.55, 0.55)
    GameTooltip:Show()
  end)
  z:SetScript("OnLeave", GameTooltip_Hide)
end

-- Ansicht "Quest-Items in Taschen"
local itemListe
local ansicht = "quests"   -- "quests" | "items"
local ITEM_FARBE = { weg = "orange", log = "gruen", start = "gelb", offen = "grau", anders = "grau" }

local function aktualisiereItems()
  if not itemListe then return end
  local ziel = itemListe.eintraege or {}
  itemListe.eintraege = ziel
  wipe(ziel)
  for _, z in ipairs(QW.QuestItemZeilen()) do ziel[#ziel + 1] = z end
  itemListe:Aktualisiere()
  panel.itemLeer:SetShown(#ziel == 0)
end

local function baueItemZeile(z)
  z.icon = z:CreateTexture(nil, "ARTWORK")
  z.icon:SetSize(16, 16)
  z.icon:SetPoint("LEFT", 2, 0)
  local function text(x, breite, klein)
    local fs = UI.Text(z, klein and "klein" or nil)
    fs:SetPoint("LEFT", x, 0)
    fs:SetWidth(breite)
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    return fs
  end
  z.name = text(22, 230)
  z.anzahl = text(256, 40, true)
  z.wo = text(300, 150, true)
  z.quests = text(454, 362, true)
  z:SetScript("OnEnter", function(self)
    if self.eintrag then UI.ItemTooltip(self, self.eintrag.id) end
  end)
  z:SetScript("OnLeave", GameTooltip_Hide)
end

local function fuelleItemZeile(z, e)
  local info = e.info
  z.icon:SetTexture(info and info.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
  z.name:SetText(WW.f(QFARBE[tonumber(info and info.qualitaet) or 1] or QFARBE[1], e.name))
  z.anzahl:SetText("x" .. tostring(e.anzahl))
  z.wo:SetText(e.ich and e.wo or WW.f("grau", e.wo))
  local erste = e.liste[1]
  local t = erste and erste.text or ""
  if not e.ich then t = WW.f("grau", t) else t = WW.f(ITEM_FARBE[erste and erste.status] or "grau", t) end
  if #e.liste > 1 then t = t .. WW.f("grau", " (+" .. (#e.liste - 1) .. ")") end
  z.quests:SetText(t)
end

local function zeigeAnsicht()
  if not panel then return end
  local items = ansicht == "items"
  liste:SetShown(not items)
  panel.kasten:SetShown(not items)
  itemListe:SetShown(items)
  panel.neuLaden:SetShown(items)
  panel.andere:SetShown(items)
  panel.marken:SetShown(not items)
  panel.ansichtKnopf:SetText(items and "Zurück zu den Quests" or "Quest-Items in Taschen")
  panel.hinweis:SetText(items
    and "Orange = Quest erledigt, kann weg. Grün = Quest im Questlog. Gelb = startet eine Quest. Maus drauf: alle Quests."
    or "Grün = Upgrade für dich, blau/lila = selten. Knopf oben rechts: Spezialisierung. Klick auf eine Quest: alle Belohnungen.")
end

local function aktualisiereReiter()
  if not panel then return end
  if ansicht == "items" then
    aktualisiereItems()
    return
  end
  QW.Scannen()
  liste.eintraege = liste.eintraege or {}
  local ziel = liste.eintraege
  wipe(ziel)
  for _, e in ipairs(logListe) do ziel[#ziel + 1] = e end
  liste:Aktualisiere()
  panel.spezKnopf:SetText("Bewertet für: " .. QW.SpezText())
  panel.leer:SetShown(#ziel == 0)
  zeigeDetail()
end

-- Ansicht wählen: an = true -> "Quest-Items in Taschen", sonst Quests im Questlog
function QW.ZeigeQuestItems(an)
  ansicht = an and "items" or "quests"
  if not panel then return end
  zeigeAnsicht()
  aktualisiereReiter()
end

-- Spezialisierung durchschalten: automatisch -> 1 -> 2 -> 3 -> automatisch
local function naechsteSpez()
  local ce = charEinst()
  if not ce then return end
  local liste2 = tab(tab(fdb().weights)[meineKlasse()])
  local jetzt = 0
  for i, sp in ipairs(liste2) do
    if type(sp) == "table" and sp.name == ce.spez then jetzt = i end
  end
  local n = jetzt + 1
  if n > #liste2 or type(liste2[n]) ~= "table" then ce.spez = "auto" else ce.spez = liste2[n].name end
  spezCache = nil
  aktualisiereReiter()
end

WW:Reiter("quests", "Quests", 35, function(p)
  panel = p
  local titel = UI.Text(p, "gross")
  titel:SetPoint("TOPLEFT", 4, -4)
  titel:SetText("Quests im Questlog")

  p.spezKnopf = UI.Knopf(p, "Bewertet für: ...", 300, naechsteSpez)
  p.spezKnopf:SetPoint("TOPRIGHT", -4, -2)

  p.ansichtKnopf = UI.Knopf(p, "Quest-Items in Taschen", 190, function()
    QW.ZeigeQuestItems(ansicht ~= "items")
  end)
  p.ansichtKnopf:SetPoint("TOPLEFT", 190, -2)
  p.neuLaden = UI.Knopf(p, "Taschen neu laden", 150, function()
    if WW.Inventar and type(WW.Inventar.Aktualisieren) == "function" then pcall(WW.Inventar.Aktualisieren) end
    QW.QuestItemsNeu()
    aktualisiereItems()
  end)
  p.neuLaden:SetPoint("LEFT", p.ansichtKnopf, "RIGHT", 4, 0)

  local hinweis = UI.Text(p, "klein", 0.8, 0.8, 0.8)
  hinweis:SetPoint("TOPLEFT", titel, "BOTTOMLEFT", 0, -6)
  hinweis:SetWidth(WW.INHALT_BREITE - 8)
  hinweis:SetHeight(14)
  if hinweis.SetWordWrap then hinweis:SetWordWrap(false) end   -- eine Zeile: darunter liegen die Haken
  p.hinweis = hinweis

  local tipp = UI.Haken(p, "Bewertung im Item-Tooltip",
    function() local e = einst() return e and e.tooltip end,
    function(an) local e = einst() if e then e.tooltip = an end end)
  tipp:SetPoint("TOPLEFT", hinweis, "BOTTOMLEFT", -4, -2)
  local itemTipp = UI.Haken(p, "Quest-Items im Tooltip",
    function() local e = einst() return e and e.itemTipp end,
    function(an) local e = einst() if e then e.itemTipp = an end end)
  itemTipp:SetPoint("LEFT", tipp, "RIGHT", 186, 0)
  local marken = UI.Haken(p, "Haken im Questlog bei Upgrades",
    function() local e = einst() return e and e.marken end,
    function(an)
      local e = einst()
      if e then e.marken = an end
      hakenAktualisieren()
    end)
  marken:SetPoint("LEFT", itemTipp, "RIGHT", 186, 0)
  p.marken = marken
  local andere = UI.Haken(p, "Auch andere Charaktere",
    function() local e = einst() return e and e.andere end,
    function(an)
      local e = einst()
      if e then e.andere = an end
      aktualisiereItems()
    end)
  andere:SetPoint("LEFT", itemTipp, "RIGHT", 186, 0)
  p.andere = andere

  liste = UI.Liste(p, LISTE_B, WW.INHALT_HOEHE - 72, 22, baueZeile, fuelleZeile)
  liste:SetPoint("TOPLEFT", 0, -72)
  p.leer = UI.Text(liste, "klein", 0.6, 0.6, 0.6)
  p.leer:SetPoint("TOPLEFT", 10, -10)
  p.leer:SetText("Dein Questlog ist leer.")
  p.leer:Hide()

  itemListe = UI.Liste(p, WW.INHALT_BREITE, WW.INHALT_HOEHE - 72, 22, baueItemZeile, fuelleItemZeile)
  itemListe:SetPoint("TOPLEFT", 0, -72)
  p.itemLeer = UI.Text(itemListe, "klein", 0.6, 0.6, 0.6)
  p.itemLeer:SetPoint("TOPLEFT", 10, -10)
  p.itemLeer:SetText("Keine Quest-Gegenstände in deinen Taschen (und in der zuletzt gesehenen Bank).")
  p.itemLeer:Hide()

  local kasten = UI.Kasten(p)
  p.kasten = kasten
  kasten:SetPoint("TOPLEFT", LISTE_B + 8, -72)
  kasten:SetSize(WW.INHALT_BREITE - LISTE_B - 8, WW.INHALT_HOEHE - 72)
  local scroll = CreateFrame("ScrollFrame", "WegweiserQuestDetailScroll", kasten, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 8, -8)
  scroll:SetPoint("BOTTOMRIGHT", -28, 8)
  local kind = CreateFrame("Frame", nil, scroll)
  kind:SetSize(WW.INHALT_BREITE - LISTE_B - 50, 1)
  scroll:SetScrollChild(kind)
  local text = UI.Text(kind, "klein")
  text:SetPoint("TOPLEFT", 0, 0)
  text:SetWidth(WW.INHALT_BREITE - LISTE_B - 54)
  text:SetSpacing(3)
  detail = { scroll = scroll, kind = kind, text = text }

  zeigeAnsicht()
  p.OnZeigen = function() aktualisiereReiter() end
end)

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------
local geplant = false
local function planen()
  if geplant then return end
  geplant = true
  local function los()
    geplant = false
    local ok, err = true, nil
    if panel and panel:IsShown() then
      ok, err = pcall(aktualisiereReiter)
    else
      local e = einst()
      if e and e.marken then ok, err = pcall(QW.Scannen) end
    end
    hakenAktualisieren()
    if not ok then geterrorhandler()(err) end
  end
  if C_Timer and C_Timer.After then C_Timer.After(1, los) else los() end
end

WW:Event("QUEST_LOG_UPDATE", function() QW.QuestItemsNeu() planen() end)
WW:Event("QUEST_ACCEPTED", function() QW.QuestItemsNeu() planen() end)
WW:Event("QUEST_TURNED_IN", function() QW.QuestItemsNeu() planen() end)
-- Taschen geändert: nur neu zeichnen, wenn die Quest-Item-Ansicht offen ist
WW:Event("BAG_UPDATE_DELAYED", function()
  if panel and panel:IsShown() and ansicht == "items" then planen() end
end)
-- nur neu bewerten, wenn ein Gegenstand kommt, auf den wir warten
WW:Event("GET_ITEM_INFO_RECEIVED", function(itemID)
  itemID = tonumber(itemID)
  if itemID and wartend[itemID] then
    wartend[itemID] = nil
    planen()
  end
end)
WW:Event("PLAYER_EQUIPMENT_CHANGED", function() spezCache = nil planen() end)
WW:Event("PLAYER_LEVEL_UP", function() spezCache = nil planen() end)
-- Talente geändert: eigener Rahmen, weil manche dieser Ereignisse im Classic-Client fehlen können
-- (RegisterEvent mit unbekanntem Namen bricht ab; hier per pcall). TRAIT_CONFIG_UPDATED: Forevers Talentfenster.
local talentRahmen = CreateFrame("Frame")
for _, ev in ipairs({ "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE", "TRAIT_CONFIG_UPDATED",
  "ACTIVE_TALENT_GROUP_CHANGED" }) do
  pcall(talentRahmen.RegisterEvent, talentRahmen, ev)
end
talentRahmen:SetScript("OnEvent", function()
  spezCache = nil
  planen()
end)
