-- Wegweiser: Entzaubern. Was kommt beim Entzaubern wahrscheinlich heraus, und was ist es im AH wert?
-- Tabelle: die bekannte Classic-Entzauber-Tabelle (Gegenstandsstufe, Qualität, Rüstung oder Waffe). Forever kann abweichen:
-- darum steht im Tooltip "ungefähr". Preise der Materialien aus dem eigenen AH-Scan (WW.AH.Preis), nach 5 % Gebühr.
-- Öffentlich: WW.Entzaubern.Ergebnis(id) -> { stufe (nötige Verzauberkunst), liste = { {id, p, min, max} } } oder nil
--             WW.Entzaubern.Wert(id) -> Kupfer (Erwartungswert) oder nil (kein Preis für ein Material)
local ADDON, WW = ...

local E = {}
WW.Entzaubern = E

-- Materialien
local STAUB = { seltsam = 10940, seele = 11083, vision = 11137, traum = 11176, illusion = 16204 }
local ESSENZ = {
  magieK = 10938, magieG = 10939, astralK = 10998, astralG = 11082, mystikK = 11134, mystikG = 11135,
  netherK = 11174, netherG = 11175, ewigK = 16202, ewigG = 16203,
}
local SPLITTER = {
  glimmerK = 10978, glimmerG = 11084, gluehK = 11138, gluehG = 11139, strahlK = 11177, strahlG = 11178,
  glanzK = 14343, glanzG = 14344, nexus = 20725,
}
E.MATERIAL = { STAUB, ESSENZ, SPLITTER }

-- Grün (Qualität 2): { bis Gegenstandsstufe, Staub {id, min, max}, Essenz {id, min, max}, Splitter-id (oder nil),
--                       Anteil Essenz (sonst 20 %), Anteil Splitter (sonst 5 %) }
local GRUEN = {
  { 15, { STAUB.seltsam, 1, 2 }, { ESSENZ.magieK, 1, 2 }, nil },
  { 20, { STAUB.seltsam, 2, 3 }, { ESSENZ.magieG, 1, 2 }, SPLITTER.glimmerK },
  { 25, { STAUB.seltsam, 4, 6 }, { ESSENZ.astralK, 1, 2 }, SPLITTER.glimmerK, 0.15, 0.10 },
  { 30, { STAUB.seele, 1, 2 }, { ESSENZ.astralG, 1, 2 }, SPLITTER.glimmerG },
  { 35, { STAUB.seele, 2, 5 }, { ESSENZ.mystikK, 1, 2 }, SPLITTER.gluehK },
  { 40, { STAUB.vision, 1, 2 }, { ESSENZ.mystikG, 1, 2 }, SPLITTER.gluehG },
  { 45, { STAUB.vision, 2, 5 }, { ESSENZ.netherK, 1, 2 }, SPLITTER.strahlK },
  { 50, { STAUB.traum, 1, 2 }, { ESSENZ.netherG, 1, 2 }, SPLITTER.strahlG },
  { 55, { STAUB.traum, 2, 5 }, { ESSENZ.ewigK, 1, 2 }, SPLITTER.glanzK },
  { 60, { STAUB.illusion, 1, 2 }, { ESSENZ.ewigG, 1, 2 }, SPLITTER.glanzG },
  { 65, { STAUB.illusion, 2, 5 }, { ESSENZ.ewigG, 2, 3 }, SPLITTER.glanzG },
}
-- Blau (Qualität 3): { bis Stufe, Splitter }
local BLAU = {
  { 25, SPLITTER.glimmerK }, { 30, SPLITTER.glimmerG }, { 35, SPLITTER.gluehK }, { 40, SPLITTER.gluehG },
  { 45, SPLITTER.strahlK }, { 50, SPLITTER.strahlG }, { 55, SPLITTER.glanzK }, { 65, SPLITTER.glanzG },
}
-- Lila (Qualität 4): { bis Stufe, Material, min, max }
local LILA = {
  { 45, SPLITTER.strahlK, 2, 4 }, { 50, SPLITTER.strahlG, 2, 4 }, { 55, SPLITTER.glanzK, 2, 4 },
  { 60, SPLITTER.nexus, 1, 1 }, { 80, SPLITTER.nexus, 1, 2 },
}

-- Nötige Verzauberkunst nach Gegenstandsstufe (Classic)
local function noetig(stufe, q)
  if q == 4 and stufe >= 56 then return 225 end
  if stufe <= 20 then return 1 end
  return math.min(300, 25 * (math.floor((stufe - 21) / 5) + 1))
end

local function zeile(liste, mat, p, min, max)
  if mat and p > 0 then liste[#liste + 1] = { id = mat, p = p, min = min or 1, max = max or min or 1 } end
end

local cache = {}
function E.Ergebnis(id)
  id = tonumber(id)
  if not id then return nil end
  local c = cache[id]
  if c ~= nil then return c or nil end
  local _, _, q, stufe, _, _, _, _, ort, _, _, klasse = WW.GetItemInfo(id)
  q, stufe, klasse = tonumber(q), tonumber(stufe), tonumber(klasse)
  if not q then return nil end   -- noch nicht geladen: nichts merken
  local r
  if (klasse == 2 or klasse == 4) and stufe and stufe >= 5 and type(ort) == "string" and ort ~= ""
     and ort ~= "INVTYPE_NON_EQUIP_IGNORE" and ort ~= "INVTYPE_BAG" and ort ~= "INVTYPE_AMMO" then
    local liste = {}
    if q == 2 then
      for _, t in ipairs(GRUEN) do
        if stufe <= t[1] then
          -- Rüstung: meist 75 % Staub, 20 % Essenz, 5 % Splitter (Stufe 21-25: 15 % Essenz, 10 % Splitter).
          -- Waffen: Staub und Essenz getauscht.
          local splitter = t[4] and (t[6] or 0.05) or 0
          local essenz = t[5] or 0.20
          local staub = 1 - essenz - splitter
          if klasse == 2 then staub, essenz = essenz, staub end
          zeile(liste, t[3][1], essenz, t[3][2], t[3][3])
          zeile(liste, t[2][1], staub, t[2][2], t[2][3])
          zeile(liste, t[4], splitter, 1, 1)
          break
        end
      end
    elseif q == 3 then
      for _, t in ipairs(BLAU) do
        if stufe <= t[1] then
          if stufe >= 56 then
            zeile(liste, t[2], 0.995, 1, 1)
            zeile(liste, SPLITTER.nexus, 0.005, 1, 1)
          else
            zeile(liste, t[2], 1, 1, 1)
          end
          break
        end
      end
    elseif q == 4 then
      for _, t in ipairs(LILA) do
        if stufe <= t[1] then zeile(liste, t[2], 1, t[3], t[4]) break end
      end
    end
    if #liste > 0 then
      table.sort(liste, function(a, b) return a.p > b.p end)
      r = { stufe = noetig(stufe, q), liste = liste }
    end
  end
  cache[id] = r or false
  return r
end

-- Preis eines Materials nach Gebühren (Kupfer pro Stück) oder nil
local function matPreis(id)
  local AH = WW.AH
  if not (AH and AH.Preis) then return nil end
  local lo, med = AH.Preis(id)
  local einheit = (tonumber(med) and med > 0) and med or tonumber(lo)
  if not einheit or einheit <= 0 then return nil end
  return einheit * 0.95
end
E.MatPreis = matPreis

-- Erwartungswert in Kupfer; nil, wenn für ein wichtiges Material (Anteil über 1 %) kein Preis da ist
function E.Wert(id)
  local r = E.Ergebnis(id)
  if not r then return nil end
  local summe = 0
  for _, m in ipairs(r.liste) do
    local p = matPreis(m.id)
    if not p then
      if m.p > 0.01 then return nil end
    else
      summe = summe + m.p * (m.min + m.max) / 2 * p
    end
  end
  return math.floor(summe)
end

-- Kann der Charakter es entzaubern? rang (oder nil ohne Verzauberkunst), nötig
function E.Kann(id, berufe)
  local r = E.Ergebnis(id)
  if not r then return false end
  local rang = type(berufe) == "table" and tonumber(berufe.Enchanting)
  return rang ~= nil and rang >= r.stufe, rang, r.stufe
end

-- Zeilen für den Tooltip: "75% Großes magisches Essenz ×1-2"
function E.Zeilen(id)
  local r = E.Ergebnis(id)
  if not r then return {} end
  local out = {}
  for _, m in ipairs(r.liste) do
    local p = m.p * 100
    local pText = (p >= 1) and ("%d%%"):format(math.floor(p + 0.5)) or ("%.1f%%"):format(p)
    local anz = (m.min == m.max) and ((m.min > 1) and (" ×" .. m.min) or "") or (" ×" .. m.min .. "-" .. m.max)
    out[#out + 1] = pText .. " " .. (WW.ItemName(m.id) or ("Item " .. m.id)) .. anz
  end
  return out
end
