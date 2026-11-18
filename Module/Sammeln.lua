-- Wegweiser: Reiter "Sammeln". Kräuter, Erz, Kürschnern und Angelorte auf Welt- und Minikarte.
-- Daten: WW.quelle.fdb.gatherData (ForeverDB.net). Deutsche Namen der Sammelpunkte: WW.quelle.gc.nodeNames.deDE.
--   kinds[id] = { n, p = "herb"|"mine"|"skin"|"fish", sk, item, ic, o = {Objekt-IDs}, lv, npc }
--   zones[uiMapID].k[id] = { c = Classic-Punkte, f = von Forever-Spielern gesehen, w }
--   Punkte: je 4 Zeichen Basis 36, x (2) dann y (2), in Zehntel-Prozent (Wert / 1000 = 0..1).
-- Punkte werden erst entschlüsselt, wenn eine Karte sie braucht (pro Gebiet, zwischengespeichert).
-- Nadeln: HereBeDragons-Pins. Weltkarte: nur das Gebiet, das sie gerade zeigt. Minikarte: das Gebiet des Spielers.
-- Farben nach der Classic-Regel (Annahme von ForeverDB): orange < sk+25, gelb < sk+50, grün < sk+100, sonst grau.
-- Angeln (p = "fish"): Fischschwärme und "Open water" (Orte, an denen Forever-Spieler geangelt haben). Die Farbe hängt
-- am Gebiet (zones[m].fish = Classic-Angelstufe des Gebiets): grün = Stufe erreicht (kein Fisch entkommt),
-- gelb = bis FISCH_KNAPP darunter (manchmal), rot = weiter darunter (oft). Eigene Fundorte gibt es beim Angeln nicht.
local ADDON, WW = ...
local UI = WW.UI

local floor, max, min = math.floor, math.max, math.min

local REF = "WegweiserSammeln"      -- Besitzer-Schlüssel für HereBeDragons
local MAX_WELT, MAX_MINI = 1500, 1500
local CACHE_ZONEN = 12               -- so viele Gebiete bleiben entschlüsselt im Speicher
local UNGUELTIG = -1                 -- "Weltkarte muss neu gebaut werden"

local BERUFE = { "herb", "mine", "skin", "fish" }
local BERUF_EN = { herb = "Herbalism", mine = "Mining", skin = "Skinning", fish = "Fishing" }
local CODE_VON_EN = { Herbalism = "herb", Mining = "mine", Skinning = "skin", Fishing = "fish" }
local TYP_NAME = { herb = "Kräuter", mine = "Erz", skin = "Kürschnern", fish = "Angelorte" }
local BERUF_ICON = {
  herb = "Interface\\Icons\\Trade_Herbalism",
  mine = "Interface\\Icons\\Trade_Mining",
  skin = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",
  fish = "Interface\\Icons\\Trade_Fishing",
}
local FISCH_KNAPP = 50         -- so viel unter der Gebietsstufe: gelb (manchmal entkommt ein Fisch)
local FISCH_NAME = { [641] = "Beliebter Angelplatz", [43] = "Fischschwarm" }   -- 641 "Open water": dort haben Forever-Spieler geangelt
-- Zauber der Ränge (Lehrling bis Fachmann): Beruf bekannt, auch wenn die Fertigkeiten-Liste zugeklappt ist
local BERUF_ZAUBER = {
  herb = { 2366, 2368, 3570, 11993 },
  mine = { 2575, 2576, 3564, 10248 },
  skin = { 8613, 8617, 8618, 10768 },
  fish = { 7620, 7731, 7732, 18248 },
}

local FARBE = {
  orange = { 1, 0.5, 0.25 }, gelb = { 1, 1, 0 }, gruen = { 0.25, 0.75, 0.25 },
  grau = { 0.5, 0.5, 0.5 }, rot = { 1, 0.13, 0.13 }, keine = { 0.85, 0.85, 0.85 },
}
local FARBE_WW = { orange = "orange", gelb = "gelb", gruen = "gruen", grau = "grau", rot = "rot", keine = "weiss" }
local FARBE_TEXT = {
  orange = "orange: sicher ein Punkt",
  gelb = "gelb: meist ein Punkt",
  gruen = "grün: selten ein Punkt",
  grau = "grau: kein Punkt mehr",
  rot = "rot: Fertigkeit zu niedrig",
  keine = "",
}
local FARBE_RANG = { orange = 1, gelb = 2, gruen = 3, keine = 3, grau = 4, rot = 5 }
local FISCH_TEXT = {
  gruen = "grün: kein Fisch entkommt",
  gelb = "gelb: manchmal entkommt ein Fisch",
  rot = "rot: Fische entkommen oft",
  keine = "",
}
local GESEHEN_FARBE = { 0.2, 0.85, 0.8 }
local EIGEN_FARBE = { 0.6, 1, 0.6 }
local PUNKT_TEXTUR = "Interface\\CharacterFrame\\TempPortraitAlphaMask"   -- weiße Scheibe (Marke "von dir")

-- Eigene Funde, deren Art die Daten nicht kennen (neue Forever-Vorkommen, Tier ohne bekannte ID)
local PSEUDO = {
  [0] = { n = "Tier (unbekannt)", p = "skin", unbekannt = true },
  [-1] = { n = "Kraut (unbekannt)", p = "herb", unbekannt = true },
  [-2] = { n = "Erz (unbekannt)", p = "mine", unbekannt = true },
}
local PSEUDO_VON = { skin = 0, herb = -1, mine = -2 }

-- Eigene Fundorte: für alle Charaktere. sammelFunde[uiMapID][artID] = Punkte (gleiche Kodierung wie die Daten)
WW.standardDB.sammelFunde = {}

WW.standardCharDB.sammeln = {
  meldung = true,       -- Chatzeile bei neuem eigenem Fundort
  an = true,            -- alle Sammelpunkte an/aus (/ww sammeln)
  typ = {},             -- [herb|mine|skin] = true/false; fehlt: an, wenn der Beruf gelernt ist
  nurKoennen = true,    -- nur was ich schon sammeln kann
  grau = false,         -- auch graue Punkte (keine Fertigkeitspunkte mehr)
  weltkarte = true,
  minikarte = true,
  nurForever = false,   -- nur Punkte, die Forever-Spieler gesehen haben
  groesse = 12,         -- Nadelgröße Weltkarte (Minikarte 2 kleiner)
  route = false,        -- Rundweg durch die Punkte auf der Weltkarte
  miniRinge = true,     -- Minikarte: nur hohle Ringe, damit der echte Punkt der Mineraliensuche sichtbar bleibt
  stufe = {},           -- zuletzt gesehene Fertigkeit (falls die Liste zugeklappt ist)
}

local HBD, Pins
local gestartet = false

local function sicher(fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then geterrorhandler()(err) end
end

---------------------------------------------------------------------------
-- Daten
---------------------------------------------------------------------------
local function daten()
  local fdb = WW.quelle and WW.quelle.fdb
  local d = fdb and fdb.gatherData
  if type(d) == "table" and type(d.kinds) == "table" and type(d.zones) == "table" then return d end
  return nil
end

local function art(id)
  if PSEUDO[id] then return PSEUDO[id] end
  local d = daten()
  local k = d and d.kinds[id]
  return type(k) == "table" and k or nil
end

local function einst()
  return WW.charDb and WW.charDb.sammeln
end

-- Eigene Fundorte (WW.db.sammelFunde), oder eine leere Tabelle, solange die gespeicherten Daten fehlen
local function eigeneFunde()
  if not WW.db then return {} end
  if type(WW.db.sammelFunde) ~= "table" then WW.db.sammelFunde = {} end
  return WW.db.sammelFunde
end

-- Hat dieses Gebiet Punkte (Daten oder eigene)?
local function hatZone(m)
  if not m then return false end
  local d = daten()
  if d and type(d.zones[m]) == "table" then return true end
  return type(eigeneFunde()[m]) == "table" and next(eigeneFunde()[m]) ~= nil
end

-- Deutscher Name eines Kraut-/Erzvorkommens, sonst der englische aus den Daten.
-- Tiere: nur englisch (es gibt keine Liste mit deutschen NPC-Namen).
local function artName(k, id)
  if not k then return "?" end
  if id and FISCH_NAME[id] then return FISCH_NAME[id] end
  -- Fischschwärme: deutscher Name des Fangs aus dem Spiel ("Schwarm: Weisenfisch"), Fundstellen ("Fundstelle: ...")
  if k.p == "fish" and tonumber(k.item) and k.item > 0 then
    local fang = WW.ItemName and WW.ItemName(k.item)
    if fang then
      return ((k.n or ""):find("^Patch") and "Fundstelle: " or "Schwarm: ") .. fang
    end
  end
  if k.p ~= "skin" then
    local gc = WW.quelle and WW.quelle.gc
    local de = gc and gc.nodeNames and gc.nodeNames.deDE
    if type(de) == "table" and type(k.o) == "table" then
      for _, o in ipairs(k.o) do
        if de[o] then return de[o] end
      end
    end
  end
  return k.n or "?"
end

local function artIcon(k)
  local ic = k and tonumber(k.ic)
  if ic and ic > 0 then return ic end
  return BERUF_ICON[k and k.p or "herb"] or BERUF_ICON.herb
end

local function berufName(code)
  local en = BERUF_EN[code]
  return en and (WW.beruf and WW.beruf[en] or en) or "?"
end

-- Classic-Angelstufe eines Gebiets (zones[m].fish), oder nil
local function fischStufe(m)
  local d = daten()
  local z = d and m and d.zones[m]
  return type(z) == "table" and tonumber(z.fish) or nil
end

local zonenNamen = {}
local function zoneName(m)
  if zonenNamen[m] then return zonenNamen[m] end
  local name
  if C_Map and C_Map.GetMapInfo then
    local ok, info = pcall(C_Map.GetMapInfo, m)
    if ok and type(info) == "table" and type(info.name) == "string" and info.name ~= "" then name = info.name end
  end
  name = name or ("Karte " .. tostring(m))
  zonenNamen[m] = name
  return name
end

---------------------------------------------------------------------------
-- Berufe des Charakters
---------------------------------------------------------------------------
local stufen, maxStufen, ausZauber = {}, {}, {}

local function zauberBekannt(code)
  local bekannt = IsPlayerSpell or IsSpellKnown
  if not bekannt then return false end
  for _, id in ipairs(BERUF_ZAUBER[code] or {}) do
    local ok, ja = pcall(bekannt, id)
    if ok and ja then return true end
  end
  return false
end

local function leseBerufe()
  local neu, maxi, zauber = {}, {}, {}
  -- WW.Fertigkeiten: C_SkillInfo (Forever), sonst GetProfessions, sonst das alte GetSkillLineInfo.
  -- Forever listet jeden Beruf zweimal (Eltern- und Kindzeile): dort schon der höchste Wert.
  local okF, fert = pcall(WW.Fertigkeiten)
  for name, f in pairs(okF and type(fert) == "table" and fert or {}) do
    local en = (WW.berufEn and WW.berufEn[name]) or name
    local code = CODE_VON_EN[en]
    if code then
      neu[code] = math.max(neu[code] or 0, f.rang)
      maxi[code] = math.max(maxi[code] or 0, f.max)
    end
  end
  local e = einst()
  -- Liste zugeklappt: Beruf über den Zauber erkennen, Stufe vom letzten Mal
  for _, code in ipairs(BERUFE) do
    if not neu[code] and zauberBekannt(code) then
      neu[code] = (e and type(e.stufe) == "table" and tonumber(e.stufe[code])) or 1
      zauber[code] = true
    end
  end
  if e then
    if type(e.stufe) ~= "table" then e.stufe = {} end
    for code, r in pairs(neu) do
      if not zauber[code] then e.stufe[code] = r end
    end
  end
  stufen, maxStufen, ausZauber = neu, maxi, zauber
end

local function berufSchluessel()
  local t = {}
  for _, code in ipairs(BERUFE) do t[#t + 1] = code .. "=" .. tostring(stufen[code]) end
  return table.concat(t, ";")
end

-- Ist die Art (herb/mine/skin) eingeschaltet? Ohne eigene Wahl: an, wenn der Beruf gelernt ist.
local function typAn(code)
  local e = einst()
  if not e then return false end
  if type(e.typ) ~= "table" then e.typ = {} end
  local v = e.typ[code]
  if v == nil then return stufen[code] ~= nil end
  return v and true or false
end

-- Farbe einer Art für eine Fertigkeit (Classic-Regel). Ohne Fertigkeit: "keine".
local function farbe(k, stufe, m)
  if not stufe or k.unbekannt then return "keine" end
  if k.p == "fish" then
    local noetig = fischStufe(m)
    if not noetig then return "keine" end
    if stufe >= noetig then return "gruen" end
    if stufe >= noetig - FISCH_KNAPP then return "gelb" end
    return "rot"
  end
  local sk = tonumber(k.sk) or 0
  if stufe < sk then return "rot" end
  if stufe < sk + 25 then return "orange" end
  if stufe < sk + 50 then return "gelb" end
  if stufe < sk + 100 then return "gruen" end
  return "grau"
end

-- Soll diese Art auf die Karte? Gibt zeigen, farbe.
local function zeigeArt(k, m)
  if type(k) ~= "table" or not BERUF_EN[k.p] then return false end
  if not typAn(k.p) then return false end
  local e = einst()
  local stufe = stufen[k.p]
  local f = farbe(k, stufe, m)
  if f == "rot" and e.nurKoennen then return false end
  if f == "grau" and not e.grau then return false end
  return true, f
end

---------------------------------------------------------------------------
-- Punkte entschlüsseln (pro Gebiet, erst wenn gebraucht)
---------------------------------------------------------------------------
local cache, cacheAnzahl = {}, 0

-- Hängt die Punkte aus s flach an aus an (x1, y1, x2, y2, ...; 0..1).
-- belegt: Raster (0,5 %), damit dieselbe Stelle nicht doppelt kommt (gesehen und Classic).
local function dekodiere(s, aus, belegt)
  if type(s) ~= "string" then return end
  for i = 1, #s - 3, 4 do
    local x = tonumber(s:sub(i, i + 1), 36)
    local y = tonumber(s:sub(i + 2, i + 3), 36)
    if x and y and x <= 1000 and y <= 1000 then
      local feld = floor(x / 5) * 1000 + floor(y / 5)
      if not belegt[feld] then
        belegt[feld] = true
        aus[#aus + 1] = x / 1000
        aus[#aus + 1] = y / 1000
      end
    end
  end
end

-- { [artID] = { e = {x, y, ...}, f = {...}, c = {...} } } für Kräuter, Erz und Kürschnern eines Gebiets, oder nil.
-- e: von dir gefunden, f: von Forever-Spielern gesehen, c: Classic-Daten.
local function zonePunkte(m)
  if not m then return nil end
  local c = cache[m]
  if c then return c end
  local d = daten()
  local z = d and d.zones[m]
  if type(z) ~= "table" or type(z.k) ~= "table" then z = nil end
  local eigene = eigeneFunde()[m]
  if type(eigene) ~= "table" then eigene = nil end
  if not z and not eigene then return nil end
  if cacheAnzahl >= CACHE_ZONEN then
    wipe(cache)
    cacheAnzahl = 0
  end
  c = {}
  local belegtVon = {}
  -- zuerst die eigenen, dann die gesehenen: die gewinnen bei gleicher Stelle
  for id, s in pairs(eigene or {}) do
    local k = art(id)
    if k and BERUF_EN[k.p] then
      local belegt, e = {}, {}
      dekodiere(s, e, belegt)
      if #e > 0 then
        c[id] = { e = e, f = {}, c = {} }
        belegtVon[id] = belegt
      end
    end
  end
  for id, e in pairs(z and z.k or {}) do
    local k = d.kinds[id]
    if type(k) == "table" and BERUF_EN[k.p] and type(e) == "table" then
      local belegt = belegtVon[id] or {}
      local pk = c[id] or { e = {}, f = {}, c = {} }
      dekodiere(e.f, pk.f, belegt)
      dekodiere(e.c, pk.c, belegt)
      if #pk.e + #pk.f + #pk.c > 0 then c[id] = pk end
    end
  end
  cache[m] = c
  cacheAnzahl = cacheAnzahl + 1
  return c
end

-- Gebiet neu entschlüsseln lassen (nach einem neuen eigenen Fund)
local function vergissZone(m)
  if m and cache[m] then
    cache[m] = nil
    cacheAnzahl = max(0, cacheAnzahl - 1)
  end
end

-- Ruft rueckruf(n, id, k, farbe, quelle, x, y) für jeden sichtbaren Punkt eines Gebiets auf,
-- höchstens grenze Stück: erst die eigenen, dann die von Forever-Spielern gesehenen, dann Classic;
-- orange vor gelb vor grün.
local DURCHGAENGE = { "e", "f", "c" }
local function fuerPunkte(m, grenze, rueckruf)
  local z = zonePunkte(m)
  if not z then return 0 end
  local e = einst()
  if not e then return 0 end
  local arten = {}
  for id, pk in pairs(z) do
    local k = art(id)
    local ja, f = zeigeArt(k, m)
    if ja then arten[#arten + 1] = { id = id, k = k, f = f, p = pk } end
  end
  table.sort(arten, function(a, b)
    local ra, rb = FARBE_RANG[a.f] or 9, FARBE_RANG[b.f] or 9
    if ra ~= rb then return ra < rb end
    return a.id < b.id
  end)
  local n = 0
  for _, q in ipairs(DURCHGAENGE) do
    if q ~= "c" or not e.nurForever then
      for _, a in ipairs(arten) do
        local liste = a.p[q] or {}
        for i = 1, #liste - 1, 2 do
          if n >= grenze then return n end
          n = n + 1
          rueckruf(n, a.id, a.k, a.f, q, liste[i], liste[i + 1])
        end
      end
    end
  end
  return n
end

---------------------------------------------------------------------------
-- Nadeln
---------------------------------------------------------------------------
local function pinBetreten(self)
  local k = art(self.artID)
  if not k then return end
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:AddLine(artName(k, self.artID), 1, 1, 1)
  if k.p == "skin" and type(k.lv) == "table" then
    GameTooltip:AddLine(string.format("Tier, Stufe %d-%d", tonumber(k.lv[1]) or 0, tonumber(k.lv[2]) or 0), 0.8, 0.8, 0.8)
  end
  local beruf = berufName(k.p)
  if k.p == "fish" then
    local noetig = fischStufe(self.m)
    GameTooltip:AddLine(noetig and ("Angeln in diesem Gebiet: ab " .. noetig .. " entkommt kein Fisch") or "Angeln", 1, 0.82, 0)
    local stufe = stufen.fish
    if stufe then
      local f = farbe(k, stufe, self.m)
      local r = FARBE[f] or FARBE.keine
      GameTooltip:AddLine("Deine Fertigkeit: " .. stufe .. (FISCH_TEXT[f] ~= "" and (" - " .. FISCH_TEXT[f]) or ""), r[1], r[2], r[3])
    else
      GameTooltip:AddLine("Du hast Angeln nicht gelernt.", 1, 0.4, 0.4)
    end
    if self.quelle == "f" then
      GameTooltip:AddLine("Hier haben Forever-Spieler geangelt", GESEHEN_FARBE[1], GESEHEN_FARBE[2], GESEHEN_FARBE[3])
    else
      GameTooltip:AddLine("Fischschwarm aus Classic-Daten (kann in Forever abweichen)", 0.7, 0.7, 0.7)
    end
    GameTooltip:AddLine("Daten von ForeverDB.net", 0.5, 0.5, 0.5)
    GameTooltip:Show()
    return
  end
  if k.unbekannt then
    GameTooltip:AddLine("Beruf: " .. beruf .. " (Art nicht in den Daten)", 1, 0.82, 0)
  else
    GameTooltip:AddLine("Benötigt: " .. beruf .. " " .. (tonumber(k.sk) or 0), 1, 0.82, 0)
  end
  local stufe = stufen[k.p]
  if k.unbekannt then
    -- keine Farbe: die nötige Fertigkeit ist nicht bekannt
  elseif stufe then
    local f = farbe(k, stufe)
    local r = FARBE[f] or FARBE.keine
    GameTooltip:AddLine("Deine Fertigkeit: " .. stufe .. " - " .. (FARBE_TEXT[f] or ""), r[1], r[2], r[3])
  else
    GameTooltip:AddLine("Du hast " .. beruf .. " nicht gelernt.", 1, 0.4, 0.4)
  end
  if self.quelle == "e" then
    GameTooltip:AddLine("Von dir gefunden", EIGEN_FARBE[1], EIGEN_FARBE[2], EIGEN_FARBE[3])
  elseif self.quelle == "f" then
    GameTooltip:AddLine("Fundort aus: Forever-Spieler (hier gesehen)", GESEHEN_FARBE[1], GESEHEN_FARBE[2], GESEHEN_FARBE[3])
  else
    GameTooltip:AddLine("Fundort aus: Classic-Daten (kann in Forever abweichen)", 0.7, 0.7, 0.7)
  end
  GameTooltip:AddLine("Daten von ForeverDB.net", 0.5, 0.5, 0.5)
  GameTooltip:Show()
end

local function pinVerlassen()
  GameTooltip:Hide()
end

local KREIS = "Interface\\AddOns\\Wegweiser\\Media\\Kreis"
local RING = "Interface\\AddOns\\Wegweiser\\Media\\Ring"

local function neuerPin()
  local pin = CreateFrame("Frame", nil, UIParent)
  pin:SetSize(12, 12)
  -- runder Hintergrund (dunkel), damit das Symbol auf jeder Karte lesbar ist
  pin.grund = pin:CreateTexture(nil, "BACKGROUND")
  pin.grund:SetAllPoints()
  pin.grund:SetTexture(KREIS)
  pin.grund:SetVertexColor(0, 0, 0, 0.6)
  -- rundes Symbol (mit Kreis-Maske)
  pin.icon = pin:CreateTexture(nil, "ARTWORK")
  pin.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  if pin.icon.SetMask then pcall(pin.icon.SetMask, pin.icon, KREIS) end
  -- farbiger Ring (Fertigkeits-Farbe)
  pin.rand = pin:CreateTexture(nil, "OVERLAY", nil, 1)
  pin.rand:SetAllPoints()
  pin.rand:SetTexture(RING)
  -- weißer Punkt oben rechts: von dir gefunden
  pin.marke = pin:CreateTexture(nil, "OVERLAY", nil, 2)
  pin.marke:SetTexture(KREIS)
  pin.marke:SetPoint("CENTER", pin, "TOPRIGHT", -1, -1)
  pin.marke:Hide()
  pin:EnableMouse(true)
  -- Maus nur für den Tooltip: Klicks gehen an Karte bzw. Minikarte weiter
  if pin.SetMouseClickEnabled then pcall(pin.SetMouseClickEnabled, pin, false) end
  pin:SetScript("OnEnter", pinBetreten)
  pin:SetScript("OnLeave", pinVerlassen)
  pin:Hide()
  return pin
end

-- Nadel für einen Punkt einrichten (Nadeln werden wiederverwendet: immer alles setzen).
-- nurRing: nur hohler Ring ohne Symbol (Minikarte), damit der echte Punkt darunter sichtbar bleibt.
local function gestalte(pin, id, k, f, quelle, groesse, nurRing, m)
  pin.artID, pin.quelle, pin.m = id, quelle, m
  pin:SetSize(groesse, groesse)
  local r = FARBE[f] or FARBE.keine
  pin.rand:SetVertexColor(r[1], r[2], r[3], 1)
  pin.grund:SetShown(not nurRing)
  pin.icon:SetShown(not nurRing)
  if not nurRing then
    local rand = max(1, floor(groesse * 0.18 + 0.5))
    pin.icon:ClearAllPoints()
    pin.icon:SetPoint("TOPLEFT", rand, -rand)
    pin.icon:SetPoint("BOTTOMRIGHT", -rand, rand)
    pin.icon:SetTexture(artIcon(k))
  end
  local marke = max(4, floor(groesse * 0.45 + 0.5))
  pin.marke:SetSize(marke, marke)
  pin.marke:SetShown(quelle == "e")
  -- hell: von dir oder von Forever-Spielern gesehen; blass: nur Classic-Daten (Vermutung)
  local a = (quelle == "c") and 0.45 or 1
  if f == "grau" then a = a * 0.7 end
  pin:SetAlpha(a)
end

---------------------------------------------------------------------------
-- Rundweg: verbindet die sichtbaren Punkte eines Gebiets zu einer kurzen Runde (Weltkarte)
---------------------------------------------------------------------------
local MAX_ROUTE = 250            -- mehr Punkte: nur die ersten (eigene, dann gesehene, dann Classic).
                                 -- 250 Punkte: etwa 0,1 s Rechnen in Lua 5.1, einmal pro Gebiet
local ROUTE_DURCHGAENGE = 4      -- Verbesserungs-Runden (2-opt)
local ROUTE_FARBE = { 0.3, 0.9, 1, 0.75 }
local ROUTE_DICKE = 2.5

-- Reihenfolge für eine kurze Runde durch die Punkte.
-- pkt = { x1, y1, x2, y2, ... } (0..1), breite/hoehe = Größe des Gebiets (Yards; ohne Angabe 1,5 : 1).
-- Gibt reihe = { Punktnummer, ... } (1-basiert) und die Länge der Runde (in Yards bzw. Karteneinheiten) zurück.
-- Weg: nächster Nachbar, dann 2-opt (Kreuzungen auflösen).
function WW.SammelRoute(pkt, breite, hoehe)
  local n = floor(#pkt / 2)
  if n == 0 then return {}, 0 end
  breite = (tonumber(breite) or 0) > 0 and breite or 1.5
  hoehe = (tonumber(hoehe) or 0) > 0 and hoehe or 1
  local xs, ys = {}, {}
  for i = 1, n do xs[i], ys[i] = pkt[2 * i - 1] * breite, pkt[2 * i] * hoehe end
  local function d(a, b)
    local dx, dy = xs[a] - xs[b], ys[a] - ys[b]
    return math.sqrt(dx * dx + dy * dy)
  end
  -- nächster Nachbar ab Punkt 1
  local reihe, frei = { 1 }, {}
  for i = 2, n do frei[i] = true end
  local aktuell = 1
  for _ = 2, n do
    local beste, besteD
    for j in pairs(frei) do
      local dj = d(aktuell, j)
      if not besteD or dj < besteD or (dj == besteD and j < beste) then beste, besteD = j, dj end
    end
    frei[beste] = nil
    reihe[#reihe + 1] = beste
    aktuell = beste
  end
  -- 2-opt: Kante (i, i+1) und (k, k+1) tauschen, wenn es kürzer wird
  if n >= 4 then
    for _ = 1, ROUTE_DURCHGAENGE do
      local besser = false
      for i = 1, n - 2 do
        local a, b = reihe[i], reihe[i + 1]
        for k = i + 2, n do
          local c, e = reihe[k], reihe[k % n + 1]
          if e ~= a then
            local delta = d(a, c) + d(b, e) - d(a, b) - d(c, e)
            if delta < -1e-9 then
              -- Stück i+1 .. k umdrehen
              local l, r = i + 1, k
              while l < r do
                reihe[l], reihe[r] = reihe[r], reihe[l]
                l, r = l + 1, r - 1
              end
              a, b = reihe[i], reihe[i + 1]
              besser = true
            end
          end
        end
      end
      if not besser then break end
    end
  end
  local laenge = 0
  for i = 1, n do laenge = laenge + d(reihe[i], reihe[i % n + 1]) end
  return reihe, laenge
end

local routeRahmen, routeLinien = nil, {}
local routeCache = {}    -- [uiMapID] = { sig, reihe, laenge }
local routeInfo = nil    -- { m, punkte, laenge (Yards oder nil) } der zuletzt gezeichneten Runde

local function routeLeinwand()
  if not WorldMapFrame then return nil end
  local c
  if type(WorldMapFrame.GetCanvas) == "function" then
    local ok, x = pcall(WorldMapFrame.GetCanvas, WorldMapFrame)
    if ok then c = x end
  end
  if type(c) ~= "table" then
    c = WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child
  end
  return type(c) == "table" and c or nil
end

local function routeVerstecken()
  for _, l in ipairs(routeLinien) do l:Hide() end
  routeInfo = nil
end

local function zeichneRoute(m, pkt)
  routeVerstecken()
  local n = floor(#pkt / 2)
  if n < 2 then return end
  local leinwand = routeLeinwand()
  if not leinwand then return end
  if not routeRahmen then
    routeRahmen = CreateFrame("Frame", nil, leinwand)
    routeRahmen:SetAllPoints(leinwand)
  end
  -- Ebene: über dem Kartenbild und der Aufdeckung, knapp unter den Nadeln (HereBeDragons: PIN_FRAME_LEVEL_AREA_POI)
  local ebene
  if type(WorldMapFrame.GetPinFrameLevelsManager) == "function" then
    local ok, mgr = pcall(WorldMapFrame.GetPinFrameLevelsManager, WorldMapFrame)
    if ok and type(mgr) == "table" and type(mgr.GetValidFrameLevel) == "function" then
      local ok2, lv = pcall(mgr.GetValidFrameLevel, mgr, "PIN_FRAME_LEVEL_AREA_POI")
      if ok2 and tonumber(lv) then ebene = max(1, tonumber(lv) - 1) end
    end
  end
  if not ebene and leinwand.GetFrameLevel then ebene = (tonumber(leinwand:GetFrameLevel()) or 0) + 1 end
  if ebene and routeRahmen.SetFrameLevel then pcall(routeRahmen.SetFrameLevel, routeRahmen, ebene) end
  local w, h = leinwand:GetSize()
  w, h = tonumber(w) or 0, tonumber(h) or 0
  if w <= 0 or h <= 0 then return end
  local breite, hoehe
  if HBD and HBD.GetZoneSize then
    local ok, bw, bh = pcall(HBD.GetZoneSize, HBD, m)
    if ok then breite, hoehe = bw, bh end
  end
  -- gleiche Punkte wie beim letzten Mal: Reihenfolge nicht neu rechnen
  local summe = 0
  for i = 1, #pkt do summe = summe + pkt[i] * (i % 7 + 1) end
  local sig = n .. ":" .. ("%.6f"):format(summe)
  local alt = routeCache[m]
  local reihe, laenge
  if alt and alt.sig == sig then
    reihe, laenge = alt.reihe, alt.laenge
  else
    reihe, laenge = WW.SammelRoute(pkt, breite, hoehe)
    routeCache[m] = { sig = sig, reihe = reihe, laenge = laenge }
  end
  local kanten = (n == 2) and 1 or n
  for i = 1, kanten do
    local a, b = reihe[i], reihe[i % n + 1]
    local l = routeLinien[i]
    if not l then
      l = routeRahmen:CreateLine(nil, "OVERLAY")
      l:SetColorTexture(ROUTE_FARBE[1], ROUTE_FARBE[2], ROUTE_FARBE[3], ROUTE_FARBE[4])
      l:SetThickness(ROUTE_DICKE)
      routeLinien[i] = l
    end
    l:SetStartPoint("TOPLEFT", routeRahmen, pkt[2 * a - 1] * w, -pkt[2 * a] * h)
    l:SetEndPoint("TOPLEFT", routeRahmen, pkt[2 * b - 1] * w, -pkt[2 * b] * h)
    l:Show()
  end
  routeInfo = { m = m, punkte = n, laenge = (tonumber(breite) or 0) > 0 and laenge or nil }
end

-- Punkte und Länge der Runde auf der Weltkarte (oder nil); für Tests und Fehlersuche
function WW.SammelRouteInfo() return routeInfo end

local weltPool, miniPool = {}, {}
local weltKarte = UNGUELTIG      -- uiMapID, für die Weltkarten-Nadeln stehen
local miniZone = UNGUELTIG       -- uiMapID, für die Minikarten-Nadeln stehen

local function baueWelt(m)
  weltKarte = m
  routeVerstecken()
  if not Pins then return end
  Pins:RemoveAllWorldMapIcons(REF)
  local e = einst()
  if not (m and e and e.an and e.weltkarte) then return end
  if e.route then
    local pkt = {}
    -- nur Kräuter und Erz: Tiere (Kürschnern) laufen herum, eine Runde durch sie hilft nicht
    fuerPunkte(m, MAX_ROUTE * 4, function(_, _, k, _, _, x, y)
      if (k.p == "herb" or k.p == "mine") and #pkt < 2 * MAX_ROUTE then
        pkt[#pkt + 1] = x
        pkt[#pkt + 1] = y
      end
    end)
    sicher(zeichneRoute, m, pkt)
  end
  local g = tonumber(e.groesse) or 12
  fuerPunkte(m, MAX_WELT, function(n, id, k, f, q, x, y)
    local pin = weltPool[n]
    if not pin then
      pin = neuerPin()
      weltPool[n] = pin
    end
    gestalte(pin, id, k, f, q, g, nil, m)
    Pins:AddWorldMapIconMap(REF, pin, m, x, y, 0)   -- 0: nur auf genau dieser Karte
  end)
end

-- Gebiet des Spielers, das Sammeldaten hat (aus Höhlen/Unterkarten zum Gebiet darüber).
local function spielerZone()
  local m
  if C_Map and C_Map.GetBestMapForUnit then
    local ok, id = pcall(C_Map.GetBestMapForUnit, "player")
    if ok then m = id end
  end
  if not m and HBD then m = HBD:GetPlayerZone() end
  local tiefe = 0
  while m and tiefe < 6 do
    if hatZone(m) then return m end
    local info
    if C_Map and C_Map.GetMapInfo then
      local ok, i = pcall(C_Map.GetMapInfo, m)
      if ok then info = i end
    end
    m = type(info) == "table" and info.parentMapID or nil
    if m == 0 then m = nil end
    tiefe = tiefe + 1
  end
  return nil
end

local function baueMini()
  local m = spielerZone()
  miniZone = m
  if not (Pins and HBD) then return end
  Pins:RemoveAllMinimapIcons(REF)
  local e = einst()
  if not (m and e and e.an and e.minikarte) then return end
  local g = max(8, (tonumber(e.groesse) or 12) - 2)
  fuerPunkte(m, MAX_MINI, function(n, id, k, f, q, x, y)
    local wx, wy, inst = HBD:GetWorldCoordinatesFromZone(x, y, m)
    if not (wx and wy and inst) then return end
    local pin = miniPool[n]
    if not pin then
      pin = neuerPin()
      miniPool[n] = pin
    end
    gestalte(pin, id, k, f, q, g, e.miniRinge ~= false, m)
    -- Weltkoordinaten: die Nadel bleibt auch in Höhlen und Unterkarten des Gebiets sichtbar
    Pins:AddMinimapIconWorld(REF, pin, inst, wx, wy, false)
  end)
end

local function weltkarteGeaendert()
  if not gestartet or not WorldMapFrame or not WorldMapFrame:IsShown() then return end
  local m = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
  if m ~= weltKarte then sicher(baueWelt, m) end
end

local panel   -- der Reiter, sobald gebaut

-- Alles neu: Minikarte, Weltkarte (wenn offen, sonst beim nächsten Öffnen), Reiter.
function WW.SammelnAktualisieren()
  if not gestartet then return end
  sicher(baueMini)
  if Pins then sicher(Pins.RemoveAllWorldMapIcons, Pins, REF) end
  weltKarte = UNGUELTIG
  weltkarteGeaendert()
  if panel and panel:IsShown() and panel.OnZeigen then sicher(panel.OnZeigen, panel) end
end

-- Später einmal aktualisieren (fasst schnelle Klicks und Ereignisse zusammen).
local planer = CreateFrame("Frame")
planer:Hide()
local warte = 0
planer:SetScript("OnUpdate", function(self, vergangen)
  warte = warte - vergangen
  if warte > 0 then return end
  self:Hide()
  WW.SammelnAktualisieren()
end)
local function spaeter(sek)
  warte = sek or 0.15
  planer:Show()
end

-- Weltkarte beobachten (falls der Haken auf OnMapChanged nicht greift): alle 0,3 s, nur wenn offen.
local wache = CreateFrame("Frame")
local wacheZeit = 0
wache:SetScript("OnUpdate", function(_, vergangen)
  wacheZeit = wacheZeit + vergangen
  if wacheZeit < 0.3 then return end
  wacheZeit = 0
  if gestartet and WorldMapFrame and WorldMapFrame:IsShown() then weltkarteGeaendert() end
end)

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------
local letzterBerufSchluessel

WW:BeimStart(function()
  if LibStub then
    HBD = LibStub("HereBeDragons-2.0", true)
    Pins = LibStub("HereBeDragons-Pins-2.0", true)
  end
  gestartet = true
  leseBerufe()
  letzterBerufSchluessel = berufSchluessel()
  if WorldMapFrame then
    if WorldMapFrame.OnMapChanged and hooksecurefunc then
      pcall(hooksecurefunc, WorldMapFrame, "OnMapChanged", function() weltkarteGeaendert() end)
    end
    if WorldMapFrame.HookScript then
      pcall(WorldMapFrame.HookScript, WorldMapFrame, "OnShow", function() weltkarteGeaendert() end)
    end
  end
  WW.SammelnAktualisieren()
end)

WW:Event("SKILL_LINES_CHANGED", function()
  if not gestartet then return end
  leseBerufe()
  local s = berufSchluessel()
  if s ~= letzterBerufSchluessel then
    letzterBerufSchluessel = s
    spaeter(0.5)
  end
end)

local function gebietPruefen()
  if not gestartet then return end
  if spielerZone() ~= miniZone then spaeter(0.2) end
end
WW:Event("ZONE_CHANGED_NEW_AREA", gebietPruefen)
WW:Event("ZONE_CHANGED", gebietPruefen)
WW:Event("ZONE_CHANGED_INDOORS", gebietPruefen)
WW:Event("PLAYER_ENTERING_WORLD", gebietPruefen)

WW:Befehl("sammeln", "Sammelpunkte an/aus", function()
  local e = einst()
  if not e then return end
  e.an = not e.an
  WW:Print("Sammelpunkte " .. (e.an and WW.f("gruen", "an") or WW.f("rot", "aus")))
  WW.SammelnAktualisieren()
end)

---------------------------------------------------------------------------
-- Wo lohnt es sich jetzt?
---------------------------------------------------------------------------
-- [artID] = { { m, n = alle Punkte, nf = gesehene Punkte (mit eigenen), ne = eigene } }
-- (aus der Länge der Texte, ohne Entschlüsseln). artZonen = nil: neu zählen.
local artZonen
local function baueArtZonen()
  if artZonen then return artZonen end
  artZonen = {}
  local d = daten()
  if not d then return artZonen end
  for m, z in pairs(d.zones) do
    if type(z) == "table" and type(z.k) == "table" then
      for id, e in pairs(z.k) do
        local k = d.kinds[id]
        if type(k) == "table" and BERUF_EN[k.p] and type(e) == "table" then
          local nf = floor(#(type(e.f) == "string" and e.f or "") / 4)
          local nc = floor(#(type(e.c) == "string" and e.c or "") / 4)
          if nf + nc > 0 then
            local l = artZonen[id]
            if not l then
              l = {}
              artZonen[id] = l
            end
            l[#l + 1] = { m = m, n = nf + nc, nf = nf, ne = 0 }
          end
        end
      end
    end
  end
  -- eigene Fundorte dazu (zählen auch als "in Forever gesehen")
  for m, arten in pairs(eigeneFunde()) do
    if type(arten) == "table" then
      for id, s in pairs(arten) do
        local ne = floor(#(type(s) == "string" and s or "") / 4)
        if ne > 0 and art(id) then
          local l = artZonen[id]
          if not l then
            l = {}
            artZonen[id] = l
          end
          local eintrag
          for _, z in ipairs(l) do
            if z.m == m then eintrag = z break end
          end
          if not eintrag then
            eintrag = { m = m, n = 0, nf = 0, ne = 0 }
            l[#l + 1] = eintrag
          end
          eintrag.n, eintrag.nf, eintrag.ne = eintrag.n + ne, eintrag.nf + ne, eintrag.ne + ne
        end
      end
    end
  end
  return artZonen
end

local function eintraege()
  local aus = {}
  local d = daten()
  if not d then
    aus[1] = { info = "Keine Sammeldaten gefunden (Daten\\FDB_Sammeln.lua)." }
    return aus
  end
  local e = einst()
  local nurF = e and e.nurForever
  local idx = baueArtZonen()
  local function wert(z) return nurF and z.nf or z.n end
  local irgendwas = false

  for _, code in ipairs(BERUFE) do
    local stufe = stufen[code]
    if stufe and typAn(code) then
      irgendwas = true
      local bn = berufName(code)
      if code == "fish" then
        -- Gebiete nach Angelstufe: grün (kein Fisch entkommt) mit der höchsten Stufe zuerst, dann gelb
        local gebiete = {}
        for m, z in pairs(d.zones) do
          local noetig = type(z) == "table" and tonumber(z.fish)
          if noetig and noetig > 0 then
            local platz, schwarm = 0, 0
            for id, eintrag in pairs(type(z.k) == "table" and z.k or {}) do
              local k = d.kinds[id]
              if type(k) == "table" and k.p == "fish" and type(eintrag) == "table" then
                local nf = floor(#(type(eintrag.f) == "string" and eintrag.f or "") / 4)
                local nc = floor(#(type(eintrag.c) == "string" and eintrag.c or "") / 4)
                if id == 641 then platz = platz + nf else schwarm = schwarm + (nurF and nf or nf + nc) end
              end
            end
            local f = farbe({ p = "fish" }, stufe, m)
            if f == "gruen" or f == "gelb" then
              gebiete[#gebiete + 1] = { m = m, noetig = noetig, f = f, platz = platz, schwarm = schwarm }
            end
          end
        end
        table.sort(gebiete, function(a, b)
          if a.f ~= b.f then return a.f == "gruen" end
          if a.noetig ~= b.noetig then return a.noetig > b.noetig end
          if a.platz + a.schwarm ~= b.platz + b.schwarm then return a.platz + a.schwarm > b.platz + b.schwarm end
          return a.m < b.m
        end)
        aus[#aus + 1] = { kopf = true, icon = BERUF_ICON.fish, text = bn .. " " .. stufe .. " - Gebiete für deine Stufe" }
        if #gebiete == 0 then
          aus[#aus + 1] = { info = "Kein Gebiet in den Daten passt zu deiner Stufe." }
        end
        for i = 1, min(8, #gebiete) do
          local g = gebiete[i]
          local teile = {}
          if g.platz > 0 then teile[#teile + 1] = g.platz .. " Angelplätze" end
          if g.schwarm > 0 then teile[#teile + 1] = g.schwarm .. " Schwärme" end
          aus[#aus + 1] = { m = g.m, text = WW.f(FARBE_WW[g.f], zoneName(g.m)) .. "  "
            .. WW.f("grau", "ab " .. g.noetig .. (#teile > 0 and (", " .. table.concat(teile, ", ")) or "")) }
        end
      elseif code == "skin" then
        -- Tiere: pro Gebiet zusammengezählt, sonst wird die Liste endlos
        local proZone = {}
        for id, k in pairs(d.kinds) do
          if type(k) == "table" and k.p == "skin" then
            local f = farbe(k, stufe)
            if f == "orange" or f == "gelb" then
              for _, z in ipairs(idx[id] or {}) do
                local w = wert(z)
                if w > 0 then
                  local pz = proZone[z.m]
                  if not pz then
                    pz = { m = z.m, n = 0, arten = {} }
                    proZone[z.m] = pz
                  end
                  pz.n = pz.n + w
                  pz.arten[#pz.arten + 1] = { k = k, n = w, f = f }
                end
              end
            end
          end
        end
        local liste = {}
        for _, pz in pairs(proZone) do liste[#liste + 1] = pz end
        table.sort(liste, function(a, b)
          if a.n ~= b.n then return a.n > b.n end
          return a.m < b.m
        end)
        aus[#aus + 1] = { kopf = true, icon = BERUF_ICON.skin, text = bn .. " " .. stufe .. " - Tiere in Orange und Gelb" }
        if #liste == 0 then
          aus[#aus + 1] = { info = "Keine passenden Tiere in den Daten." }
        end
        for i = 1, min(5, #liste) do
          local pz = liste[i]
          table.sort(pz.arten, function(a, b) return a.n > b.n end)
          local namen = {}
          for j = 1, min(3, #pz.arten) do
            local a = pz.arten[j]
            namen[#namen + 1] = WW.f(FARBE_WW[a.f] or "weiss", a.k.n or "?")
          end
          aus[#aus + 1] = {
            m = pz.m,
            text = zoneName(pz.m) .. "  " .. WW.f("grau", pz.n .. " Fundorte") .. "  " .. table.concat(namen, ", "),
          }
        end
      else
        local arten = {}
        for id, k in pairs(d.kinds) do
          if type(k) == "table" and k.p == code then
            local f = farbe(k, stufe)
            if f == "orange" or f == "gelb" then arten[#arten + 1] = { id = id, k = k, f = f } end
          end
        end
        table.sort(arten, function(a, b)
          local sa, sb = tonumber(a.k.sk) or 0, tonumber(b.k.sk) or 0
          if sa ~= sb then return sa > sb end
          return a.id < b.id
        end)
        aus[#aus + 1] = { kopf = true, icon = BERUF_ICON[code], text = bn .. " " .. stufe }
        if #arten == 0 then
          aus[#aus + 1] = { info = "Nichts in Orange oder Gelb. Grüne Punkte bringen selten noch etwas." }
        end
        for _, a in ipairs(arten) do
          aus[#aus + 1] = {
            art = true, icon = artIcon(a.k),
            text = WW.f(FARBE_WW[a.f], artName(a.k)) .. WW.f("grau", "  ab " .. (tonumber(a.k.sk) or 0)),
          }
          local zonen = {}
          for _, z in ipairs(idx[a.id] or {}) do
            if wert(z) > 0 then zonen[#zonen + 1] = z end
          end
          table.sort(zonen, function(x, y)
            local wx, wy = wert(x), wert(y)
            if wx ~= wy then return wx > wy end
            return x.m < y.m
          end)
          if #zonen == 0 then
            aus[#aus + 1] = { info = "Keine Fundorte in den Daten." }
          end
          for i = 1, min(5, #zonen) do
            local z = zonen[i]
            local zusatz = ""
            if not nurF and z.nf > z.ne then zusatz = ", davon " .. (z.nf - z.ne) .. " von Forever-Spielern" end
            if z.ne > 0 then zusatz = zusatz .. ", " .. z.ne .. " von dir" end
            aus[#aus + 1] = { m = z.m, text = zoneName(z.m) .. "  " .. WW.f("grau", wert(z) .. " Fundorte" .. zusatz) }
          end
        end
      end
    end
  end

  if not irgendwas then
    aus[#aus + 1] = { info = "Kein Sammelberuf gelernt oder eingeschaltet (Kräuterkunde, Bergbau, Kürschnerei, Angeln)." }
    aus[#aus + 1] = { info = "Links eine Art einschalten zeigt ihre Punkte trotzdem auf der Karte." }
  end
  return aus
end

local function oeffneKarte(m)
  if not (m and WorldMapFrame) then return end
  local fenster = _G.WegweiserFenster
  if fenster and fenster:IsShown() then fenster:Hide() end
  if OpenWorldMap and pcall(OpenWorldMap, m) and WorldMapFrame:IsShown() then return end
  if not WorldMapFrame:IsShown() then
    if ShowUIPanel then pcall(ShowUIPanel, WorldMapFrame) else WorldMapFrame:Show() end
  end
  if WorldMapFrame.SetMapID then pcall(WorldMapFrame.SetMapID, WorldMapFrame, m) end
end

---------------------------------------------------------------------------
-- Eigene Fundorte aufzeichnen
--   1. UNIT_SPELLCAST_SUCCEEDED ("player") mit Bergbau, Kräutersammeln oder Kürschnern:
--      Beruf, Ort (C_Map) und beim Kürschnern das tote Tier (Ziel oder Maus) merken.
--   2. LOOT_READY / LOOT_OPENED innerhalb von 5 s: Quelle (GetLootSourceInfo: Objekt- oder NPC-ID) und Items
--      lesen, daraus die Art (kinds[k].o, .npc, .item). Nicht in den Daten: "Kraut/Erz/Tier (unbekannt)".
--   3. Speichern in WW.db.sammelFunde, wenn kein eigener oder bekannter Punkt derselben Art näher als 0,6 % liegt.
-- So machen es auch Gathercraft (Core.lua, SkinLog.lua) und ForeverDB (captureNode): ohne COMBAT_LOG_EVENT_UNFILTERED,
-- den Forever für Addons sperrt.
---------------------------------------------------------------------------
local WURF_FENSTER = 5      -- Sekunden vom Zauber bis zur Beute
local NAH = 6               -- Zehntel-Prozent: so nah gilt als derselbe Fundort (0,6 %)
local B36 = "0123456789abcdefghijklmnopqrstuvwxyz"

local ZAUBER_CODE = {}
for code, ids in pairs(BERUF_ZAUBER) do
  if code ~= "fish" then   -- Angeln: keine eigenen Fundorte
    for _, id in ipairs(ids) do ZAUBER_CODE[id] = code end
  end
end

-- C_Spell.GetSpellName / C_Spell.GetSpellInfo (Forever), sonst das alte GetSpellInfo
local function zauberName(id)
  return WW.SpellName(id)
end

-- Zaubername (klein) -> Beruf. Feste Namen plus die Namen, die der Client den bekannten Zauber-IDs gibt.
local NAME_CODE
local function zauberNamen()
  if NAME_CODE then return NAME_CODE end
  NAME_CODE = {
    ["bergbau"] = "mine", ["mining"] = "mine",
    ["kräutersammeln"] = "herb", ["kräuter sammeln"] = "herb", ["kräuterkunde"] = "herb", ["herb gathering"] = "herb", ["herbalism"] = "herb",
    ["kürschnerei"] = "skin", ["kürschnern"] = "skin", ["skinning"] = "skin",
  }
  for id, code in pairs(ZAUBER_CODE) do
    local n = zauberName(id)
    if n and not NAME_CODE[n:lower()] then NAME_CODE[n:lower()] = code end
  end
  return NAME_CODE
end

-- "GameObject-0-1-2-3-1731-..." -> "GameObject", 1731
local function guidTeile(guid)
  if type(guid) ~= "string" then return nil end
  local typ, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)")
  return typ, tonumber(id)
end

-- Objekt-ID, NPC-ID und Item -> Art (einmal gebaut)
local objektIndex, npcIndex, itemIndex
local function baueIndex()
  if objektIndex then return end
  objektIndex, npcIndex, itemIndex = {}, {}, { herb = {}, mine = {} }
  local d = daten()
  if not d then return end
  for id, k in pairs(d.kinds) do
    if type(k) == "table" then
      if k.p == "herb" or k.p == "mine" then
        for _, o in ipairs(type(k.o) == "table" and k.o or {}) do
          if not objektIndex[o] then objektIndex[o] = id end
        end
        local it = tonumber(k.item)
        if it and it > 0 then
          local alt = itemIndex[k.p][it]
          -- dasselbe Item bei mehreren Arten (kleines und reiches Thorium): die mit der kleinsten Fertigkeit
          if not alt or (tonumber(k.sk) or 0) < (tonumber(d.kinds[alt].sk) or 0) then itemIndex[k.p][it] = id end
        end
      elseif k.p == "skin" then
        for _, npc in ipairs(type(k.npc) == "table" and k.npc or {}) do
          if not npcIndex[npc] then npcIndex[npc] = id end
        end
      end
    end
  end
end

-- Wo der Spieler steht: uiMapID, x, y (0..1), oder nil (Instanz, keine Position).
-- Höhlen und Unterkarten ohne eigene Daten werden auf das Gebiet darüber umgerechnet.
local function spielerOrt()
  if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
  local ok, m = pcall(C_Map.GetBestMapForUnit, "player")
  if not ok or not m then return nil end
  local ok2, pos = pcall(C_Map.GetPlayerMapPosition, m, "player")
  if not ok2 or type(pos) ~= "table" then return nil end
  local x, y
  if pos.GetXY then x, y = pos:GetXY() else x, y = pos.x, pos.y end
  x, y = tonumber(x), tonumber(y)
  if not (x and y) or (x == 0 and y == 0) or x < 0 or x > 1 or y < 0 or y > 1 then return nil end
  if not hatZone(m) and HBD and HBD.TranslateZoneCoordinates and C_Map.GetMapInfo then
    local ok3, info = pcall(C_Map.GetMapInfo, m)
    local eltern = ok3 and type(info) == "table" and tonumber(info.parentMapID)
    if eltern and eltern ~= 0 and (tonumber(info.mapType) or 0) > 3 then
      local ok4, nx, ny = pcall(HBD.TranslateZoneCoordinates, HBD, x, y, m, eltern)
      if ok4 and nx and ny and nx >= 0 and nx <= 1 and ny >= 0 and ny <= 1 then m, x, y = eltern, nx, ny end
    end
  end
  return m, x, y
end

local function b36(n)
  local hi, lo = floor(n / 36), n % 36
  return B36:sub(hi + 1, hi + 1) .. B36:sub(lo + 1, lo + 1)
end

-- Liegt in s (Punkte-Text) ein Punkt näher als NAH an tx, ty (Zehntel-Prozent)?
local function istNahe(s, tx, ty)
  if type(s) ~= "string" then return false end
  for i = 1, #s - 3, 4 do
    local x = tonumber(s:sub(i, i + 1), 36)
    local y = tonumber(s:sub(i + 2, i + 3), 36)
    if x and y then
      local dx, dy = x - tx, y - ty
      if dx * dx + dy * dy <= NAH * NAH then return true end
    end
  end
  return false
end

-- Speichert einen Fundort. Gibt "neu", "bekannt" (eigener oder Daten-Punkt in der Nähe) oder nil zurück.
local function speichereFund(m, x, y, id)
  if not (WW.db and m and x and y and id) then return nil end
  local tx = max(0, min(1000, floor(x * 1000 + 0.5)))
  local ty = max(0, min(1000, floor(y * 1000 + 0.5)))
  local funde = eigeneFunde()
  local arten = type(funde[m]) == "table" and funde[m] or nil
  local s = arten and type(arten[id]) == "string" and arten[id] or ""
  if istNahe(s, tx, ty) then return "bekannt" end
  local d = daten()
  local z = d and type(d.zones[m]) == "table" and type(d.zones[m].k) == "table" and d.zones[m].k[id]
  if type(z) == "table" and (istNahe(z.f, tx, ty) or istNahe(z.c, tx, ty)) then return "bekannt" end
  if not arten then
    arten = {}
    funde[m] = arten
  end
  arten[id] = s .. b36(tx) .. b36(ty)
  return "neu"
end

local function rufe(fn, ...)
  if not fn then return nil end
  local ok, a = pcall(fn, ...)
  if ok then return a end
  return nil
end

-- Das tote Tier, das du häutest: Ziel oder Maus. NPC-ID oder nil.
local function totesTier()
  for _, unit in ipairs({ "target", "mouseover" }) do
    local typ, id = guidTeile(rufe(UnitGUID, unit))
    if (typ == "Creature" or typ == "Vehicle") and id and rufe(UnitIsDead, unit) then return id end
  end
  return nil
end

-- Was im Beutefenster liegt: Anzahl, Objekt-IDs, NPC-IDs, Item-IDs
local function liesBeute()
  local b = { anzahl = tonumber(rufe(GetNumLootItems)) or 0, objekte = {}, npcs = {}, items = {} }
  for slot = 1, b.anzahl do
    local typ, id = guidTeile(rufe(GetLootSourceInfo, slot))
    if typ == "GameObject" and id then
      b.objekte[#b.objekte + 1] = id
    elseif (typ == "Creature" or typ == "Vehicle") and id then
      b.npcs[#b.npcs + 1] = id
    end
    local link = rufe(GetLootSlotLink, slot)
    local item = type(link) == "string" and tonumber(link:match("item:(%d+)"))
    if item then b.items[#b.items + 1] = item end
  end
  return b
end

-- Welche Art war es? Art-ID oder nil (nicht diese Beute).
local function artAusBeute(code, b, tierNpc)
  baueIndex()
  if code == "skin" then
    if #b.objekte > 0 then return nil end          -- Truhe oder Vorkommen, kein Tier
    for _, npc in ipairs(b.npcs) do
      if npcIndex[npc] then return npcIndex[npc] end
    end
    if tierNpc and npcIndex[tierNpc] then return npcIndex[tierNpc] end
    if #b.items > 0 then return PSEUDO_VON.skin end
    return nil
  end
  if #b.npcs > 0 and #b.objekte == 0 then return nil end   -- Beute einer Leiche, kein Vorkommen
  for _, o in ipairs(b.objekte) do
    local id = objektIndex[o]
    local k = id and art(id)
    if k and k.p == code then return id end
  end
  for _, it in ipairs(b.items) do
    local id = itemIndex[code] and itemIndex[code][it]
    if id then return id end
  end
  if #b.items > 0 then return PSEUDO_VON[code] end
  return nil
end

-- Der letzte Sammelzauber: { code, at, m, x, y, tier, fertig }. Die Beute kommt danach (wie bei Gathercraft und
-- ForeverDB: erst UNIT_SPELLCAST_SUCCEEDED, dann LOOT_READY/LOOT_OPENED).
local wurf

-- Beute zu einem Sammelzauber auswerten. true: erledigt.
local function verarbeite(w, b)
  if not (w and b) or b.anzahl == 0 then return false end
  local id = artAusBeute(w.code, b, w.tier)
  if not id then return false end
  w.fertig = true
  if speichereFund(w.m, w.x, w.y, id) == "neu" then
    vergissZone(w.m)
    artZonen = nil
    local e = einst()
    if not e or e.meldung ~= false then
      WW:Print("Neuer Fundort gespeichert: " .. artName(art(id)) .. " (" .. zoneName(w.m) .. ")")
    end
    WW.SammelnAktualisieren()
  end
  return true
end

WW:Event("UNIT_SPELLCAST_SUCCEEDED", function(unit, a2, a3, a4, a5)
  if unit ~= "player" or not gestartet then return end
  -- (unit, castGUID, spellID); ältere Clients: (unit, Name, Rang, lineID, spellID)
  local spellID = tonumber(a3) or tonumber(a5)
  local code = spellID and ZAUBER_CODE[spellID]
  if not code then
    local name = spellID and zauberName(spellID)
    if not name and type(a2) == "string" and not a2:find("^Cast%-") then name = a2 end
    code = name and zauberNamen()[name:lower()]
  end
  if not code then return end
  local m, x, y = spielerOrt()
  if not m then
    wurf = nil
    return
  end
  wurf = { code = code, at = GetTime(), m = m, x = x, y = y, tier = (code == "skin") and totesTier() or nil }
end)

local function beuteEreignis()
  if not gestartet then return end
  local w = wurf
  if w and not w.fertig and GetTime() - w.at <= WURF_FENSTER then
    verarbeite(w, liesBeute())
  end
end
WW:Event("LOOT_READY", beuteEreignis)
WW:Event("LOOT_OPENED", beuteEreignis)

local function eigeneAnzahl()
  local n = 0
  for _, arten in pairs(eigeneFunde()) do
    if type(arten) == "table" then
      for _, s in pairs(arten) do
        if type(s) == "string" then n = n + floor(#s / 4) end
      end
    end
  end
  return n
end

local function eigeneLoeschen()
  if not WW.db then return end
  WW.db.sammelFunde = {}
  wipe(cache)
  cacheAnzahl = 0
  artZonen = nil
  WW:Print("Eigene Fundorte gelöscht.")
  WW.SammelnAktualisieren()
end

if type(StaticPopupDialogs) == "table" then
  StaticPopupDialogs["WEGWEISER_FUNDORTE_LOESCHEN"] = {
    text = "Alle %s eigenen Fundorte löschen?\nDas gilt für alle Charaktere und lässt sich nicht rückgängig machen.",
    button1 = "Löschen",
    button2 = "Abbrechen",
    OnAccept = function() eigeneLoeschen() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
  }
end

---------------------------------------------------------------------------
-- Reiter
---------------------------------------------------------------------------
WW:Reiter("sammeln", "Sammeln", 4, function(p)
  local e = einst()
  if not e then
    local t = UI.Text(p)
    t:SetPoint("TOPLEFT", 4, -4)
    t:SetText("Gespeicherte Daten fehlen. Bitte /reload.")
    return
  end
  panel = p

  -- linke Spalte: Berufe und Einstellungen
  local titel = UI.Text(p, "gross")
  titel:SetPoint("TOPLEFT", 4, -4)
  titel:SetText("Deine Berufe")

  local berufText = UI.Text(p)
  berufText:SetPoint("TOPLEFT", titel, "BOTTOMLEFT", 0, -6)
  berufText:SetWidth(320)
  berufText:SetSpacing(2)

  local t2 = UI.Text(p, "gross")
  t2:SetPoint("TOPLEFT", berufText, "BOTTOMLEFT", 0, -12)
  t2:SetText("Anzeige")

  local haken = {}
  local vorher = t2
  local function neuerHaken(text, get, set, einzug)
    local h = UI.Haken(p, text, get, function(an)
      set(an)
      spaeter()
    end)
    h:SetPoint("TOPLEFT", vorher, "BOTTOMLEFT", (einzug or 0), (vorher == t2) and -4 or 2)
    h.get = get
    haken[#haken + 1] = h
    vorher = h
    return h
  end
  neuerHaken("Sammelpunkte zeigen", function() return e.an end, function(an) e.an = an end)
  -- die drei Arten eingerückt (Einzug gilt relativ zum Haken davor)
  for i, code in ipairs(BERUFE) do
    neuerHaken(TYP_NAME[code] .. " (" .. berufName(code) .. ")",
      function() return typAn(code) end,
      function(an)
        if type(e.typ) ~= "table" then e.typ = {} end
        e.typ[code] = an
      end, (i == 1) and 16 or 0)
  end
  neuerHaken("Nur was ich schon sammeln kann", function() return e.nurKoennen end,
    function(an) e.nurKoennen = an end, -16)
  neuerHaken("Auch graue (bringen keine Punkte mehr)", function() return e.grau end,
    function(an) e.grau = an end)
  neuerHaken("Auf der Weltkarte", function() return e.weltkarte end, function(an) e.weltkarte = an end)
  neuerHaken("Rundweg (Linie durch die Punkte)", function() return e.route end, function(an) e.route = an end, 16)
  neuerHaken("Auf der Minikarte", function() return e.minikarte end, function(an) e.minikarte = an end, -16)
  neuerHaken("Minikarte: nur Ringe (echter Punkt bleibt sichtbar)", function() return e.miniRinge ~= false end,
    function(an) e.miniRinge = an end, 16)
  neuerHaken("Nur von Forever-Spielern gesehene Punkte", function() return e.nurForever end,
    function(an) e.nurForever = an end, -16)
  neuerHaken("Chatmeldung bei neuem eigenem Fundort", function() return e.meldung ~= false end,
    function(an) e.meldung = an end)

  -- Größe der Nadeln
  local groesseText = UI.Text(p)
  local kleiner = UI.Knopf(p, "-", 24)
  local groesser = UI.Knopf(p, "+", 24)
  kleiner:SetPoint("TOPLEFT", vorher, "BOTTOMLEFT", 4, -6)
  groesseText:SetPoint("LEFT", kleiner, "RIGHT", 8, 0)
  groesser:SetPoint("LEFT", kleiner, "RIGHT", 100, 0)
  local function zeigeGroesse()
    groesseText:SetText("Größe: " .. (tonumber(e.groesse) or 12))
  end
  local function aendereGroesse(um)
    e.groesse = max(8, min(24, (tonumber(e.groesse) or 12) + um))
    zeigeGroesse()
    spaeter(0.3)
  end
  kleiner:SetScript("OnClick", function() aendereGroesse(-2) end)
  groesser:SetScript("OnClick", function() aendereGroesse(2) end)

  -- Eigene Fundorte: Anzahl und Löschen (mit Rückfrage)
  local loeschen = UI.Knopf(p, "Eigene Fundorte löschen", 170, function()
    if StaticPopup_Show then
      StaticPopup_Show("WEGWEISER_FUNDORTE_LOESCHEN", tostring(eigeneAnzahl()))
    end
  end)
  loeschen:SetPoint("TOPLEFT", kleiner, "BOTTOMLEFT", 0, -6)
  local fundText = UI.Text(p)
  fundText:SetPoint("LEFT", loeschen, "RIGHT", 8, 0)
  local function zeigeFunde()
    fundText:SetText("Eigene Fundorte: " .. eigeneAnzahl())
  end

  -- Legende als Tooltip eines Knopfs: als Text passt sie im Unterreiter (474 hoch) nicht mehr unter die Haken
  local LEGENDE = "Rand: " .. WW.f("orange", "orange") .. " sicher ein Punkt, " .. WW.f("gelb", "gelb") .. " meist, "
    .. WW.f("gruen", "grün") .. " selten, " .. WW.f("grau", "grau") .. " keiner mehr "
    .. "(Classic-Regel, Annahme von ForeverDB).\n"
    .. "Kräftig: von Forever-Spielern gesehen. Blass: Vermutung aus Classic-Daten. "
    .. "Weißer Punkt: von dir gefunden (wird beim Sammeln gespeichert).\n"
    .. "Minikarte: Der gelbe Punkt der Mineralien- oder Kräutersuche ist echt. "
    .. "Ein Ring ohne Punkt darin ist nur eine Vermutung.\n"
    .. "/ww sammeln schaltet alle Punkte an oder aus. Daten von ForeverDB.net."
  -- rechts neben den Größen-Knöpfen (eigene Zeile darunter passt im Unterreiter nicht mehr)
  local legendeKnopf = UI.Knopf(p, "Farben erklärt", 120)
  legendeKnopf:SetPoint("LEFT", kleiner, "RIGHT", 140, 0)
  legendeKnopf:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Sammelpunkte")
    for zeile in (LEGENDE .. "\n"):gmatch("(.-)\n") do
      if zeile ~= "" then GameTooltip:AddLine(zeile, 1, 1, 1, true) end
    end
    GameTooltip:Show()
  end)
  legendeKnopf:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- rechte Spalte: Wo lohnt es sich jetzt?
  local LINKS = 344
  local t3 = UI.Text(p, "gross")
  t3:SetPoint("TOPLEFT", LINKS, -4)
  t3:SetText("Wo lohnt es sich jetzt?")
  local hinweis = UI.Text(p, "klein", 0.8, 0.8, 0.8)
  hinweis:SetPoint("TOPLEFT", t3, "BOTTOMLEFT", 0, -4)
  hinweis:SetWidth(WW.INHALT_BREITE - LINKS - 10)
  if hinweis.SetWordWrap then hinweis:SetWordWrap(false) end
  hinweis:SetText("Orange und Gelb für dich (Angeln: Grün und Gelb), die besten Gebiete. Klick: Weltkarte.")

  local liste = UI.Liste(p, WW.INHALT_BREITE - LINKS, p:GetHeight() - 44, 18,
    function(z)
      z.icon = z:CreateTexture(nil, "ARTWORK")
      z.icon:SetSize(16, 16)
      z.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      z.text = UI.Text(z)
      if z.text.SetWordWrap then z.text:SetWordWrap(false) end
      z:SetScript("OnClick", function(self)
        if self.eintrag and self.eintrag.m then oeffneKarte(self.eintrag.m) end
      end)
      z:SetScript("OnEnter", function(self)
        if not (self.eintrag and self.eintrag.m) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(zoneName(self.eintrag.m), 1, 1, 1)
        GameTooltip:AddLine("Klicken: Weltkarte mit diesem Gebiet öffnen", 0.8, 0.8, 0.8)
        GameTooltip:Show()
      end)
      z:SetScript("OnLeave", pinVerlassen)
    end,
    function(z, ein)
      local einzug = 2
      if ein.art then einzug = 14 elseif ein.m or ein.info then einzug = 32 end
      z.icon:ClearAllPoints()
      z.icon:SetPoint("LEFT", z, "LEFT", einzug, 0)
      z.text:ClearAllPoints()
      if ein.icon then
        z.icon:SetTexture(ein.icon)
        z.icon:Show()
        z.text:SetPoint("LEFT", z.icon, "RIGHT", 4, 0)
      else
        z.icon:Hide()
        z.text:SetPoint("LEFT", z, "LEFT", einzug, 0)
      end
      z.text:SetPoint("RIGHT", z, "RIGHT", -4, 0)
      if ein.kopf then
        z.text:SetText(WW.f("titel", ein.text or ""))
      elseif ein.info then
        z.text:SetText(WW.f("grau", ein.info))
      else
        z.text:SetText(ein.text or "")
      end
    end)
  liste:SetPoint("TOPLEFT", LINKS, -40)

  function p:OnZeigen()
    leseBerufe()
    local zeilen = {}
    for _, code in ipairs(BERUFE) do
      local st = stufen[code]
      local wert
      if not st then
        wert = WW.f("grau", "nicht gelernt")
      elseif ausZauber[code] then
        wert = "ca. " .. st .. WW.f("grau", " (Fertigkeiten-Liste zugeklappt)")
      else
        wert = tostring(st) .. (maxStufen[code] and (" / " .. maxStufen[code]) or "")
      end
      zeilen[#zeilen + 1] = berufName(code) .. ": " .. wert
    end
    if not daten() then zeilen[#zeilen + 1] = WW.f("rot", "Keine Sammeldaten gefunden.") end
    if not Pins then zeilen[#zeilen + 1] = WW.f("rot", "HereBeDragons fehlt: keine Kartennadeln.") end
    berufText:SetText(table.concat(zeilen, "\n"))
    for _, h in ipairs(haken) do h:SetChecked(h.get() and true or false) end
    zeigeGroesse()
    zeigeFunde()
    liste:Setze(eintraege())
  end
end, "einstellungen")
