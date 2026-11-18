-- SZENE: Fluege - Vorbereitung (Zeit, Flugkarte, Nadeln zaehlen)
__F = { zeit = 1000, taxi = false, tip = {}, nadeln = 0, ids = {} }
__F.altGetTime = GetTime
GetTime = function() return __F.zeit end
UnitOnTaxi = function() return __F.taxi end
GetTaxiMapID = function() return 1415 end
C_TaxiMap = {
  GetAllTaxiNodes = function()
    return {
      { nodeID = 2, slotIndex = 1, name = "Sturmwind, Elwynn", state = 0 },
      { nodeID = 4, slotIndex = 2, name = "Späherkuppe, Westfall", state = 1 },
    }
  end,
}
TaxiNodeOnButtonEnter = function(knopf) end
TakeTaxiNode = function(slot) end
local pins = LibStub("HereBeDragons-Pins-2.0")
__F.altAdd, __F.altRemove = pins.AddWorldMapIconMap, pins.RemoveAllWorldMapIcons
pins.AddWorldMapIconMap = function(self, ref, icon, m, x, y, flag)
  if ref == "WegweiserFluege" then
    assert(type(x) == "number" and x >= 0 and x <= 1 and type(y) == "number" and y >= 0 and y <= 1, "Flugpunkt ausserhalb 0..1")
    assert(type(flag) == "number", "Flag keine Zahl")
    __F.nadeln = __F.nadeln + 1
    __F.ids[icon.knotenID or -1] = true
  end
  return __F.altAdd(self, ref, icon, m, x, y, flag)
end
pins.RemoveAllWorldMapIcons = function(self, ref)
  if ref == "WegweiserFluege" then __F.nadeln = 0 __F.ids = {} end
  return __F.altRemove(self, ref)
end
GameTooltip.AddLine = function(self, t) __F.tip[#__F.tip + 1] = tostring(t) end

-- SZENE: Fluege - alle Flugpunkte der Allianz und neutrale auf der Weltkarte
local e = __WW.charDb.fluege
e.karte, e.unentdeckt, e.timer, e.zeiten = true, true, true, true
e.bekannt = {}
__WW.Fluege.baueNadeln()
local erwartet = 0
for id, k in pairs(__WW.quelle.fdb.travelData.nodes) do
  -- 84-87: Türme der Östlichen Pestländer (nur untereinander verbunden, 0 Kupfer): keine Flugmeister
  if (k[7] == "a" or k[7] == "n") and not (id >= 84 and id <= 87) then erwartet = erwartet + 1 end
end
for id = 84, 87 do
  if __F.ids[id] then error("Turm " .. id .. " als Flugpunkt auf der Karte") end
end
if __F.nadeln ~= erwartet then error("Flugpunkte auf der Karte: " .. __F.nadeln .. ", erwartet " .. erwartet) end
e.unentdeckt = false
__WW.Fluege.baueNadeln()
if __F.nadeln ~= 0 then error("Ohne unentdeckte: " .. __F.nadeln .. " Nadeln, erwartet 0") end
__LOG[#__LOG + 1] = "Fluege: " .. erwartet .. " Flugpunkte fuer die Allianz"

-- SZENE: Fluege - Flugkarte lernt bekannte Flugpunkte und deutsche Namen
__FEUER("TAXIMAP_OPENED")
local b = __WW.charDb.fluege.bekannt
if not (b[2] and b[4]) then error("Bekannte Flugpunkte nicht gelernt") end
if __WW.db.flugNamen[4] ~= "Späherkuppe" then error("Deutscher Name fehlt: " .. tostring(__WW.db.flugNamen[4])) end
if __F.nadeln ~= 2 then error("Nach dem Lernen " .. __F.nadeln .. " Nadeln, erwartet 2") end
__WW.charDb.fluege.unentdeckt = true

-- SZENE: Fluege - Flugzeit im Tooltip der Flugkarte (Forever-Messung)
__F.tip = {}
TaxiNodeOnButtonEnter({ GetID = function() return 2 end })
local zeile = table.concat(__F.tip, " | ")
if not zeile:find("Flugzeit: 1:18") then error("Tooltip ohne Flugzeit: " .. zeile) end
__LOG[#__LOG + 1] = "Fluege: " .. zeile

-- SZENE: Fluege - Flug messen, Timer zaehlt runter, Zeit wird gespeichert
TakeTaxiNode(2)
__F.zeit = 1002
__F.taxi = true
__UPDATE(1)
__F.zeit = 1032
__UPDATE(1)
local timer = WegweiserFlugTimer
if not (timer and timer:IsShown()) then error("Flug-Timer nicht sichtbar") end
local text = timer.text:GetText() or ""
if not text:find("Späherkuppe") or not text:find("noch 0:48") then error("Timer-Text falsch: " .. text) end
__LOG[#__LOG + 1] = "Fluege: " .. text
__F.zeit = 1082
__F.taxi = false
__UPDATE(1)
local f = __WW.db.fluege["2>4"]
if not (f and f.n == 1 and f.summe == 80) then error("Flugzeit nicht gespeichert") end
if timer:IsShown() then error("Timer nach der Landung noch sichtbar") end

-- SZENE: Fluege - eigene Messung gewinnt, Schaetzung fuer ungemessene Strecke
local s, q, n = __WW.Fluege.zeit(2, 4)
if not (s == 80 and q == "du" and n == 1) then error("Eigene Messung nicht genutzt: " .. tostring(s) .. " " .. tostring(q)) end
local raw = __WW.quelle.fdb.travelData
local gefunden
for a, z in raw.flights:gmatch("(%d+)>(%d+)>%d+>%d+") do
  if not raw.measured:find("%f[%d]" .. a .. ">" .. z .. ">") then gefunden = { tonumber(a), tonumber(z) } break end
end
if gefunden then
  local s2, q2 = __WW.Fluege.zeit(gefunden[1], gefunden[2])
  if not (s2 and s2 > 0 and q2 == "schaetzung") then error("Keine Schaetzung fuer " .. gefunden[1] .. ">" .. gefunden[2]) end
  __LOG[#__LOG + 1] = "Fluege: Schaetzung " .. gefunden[1] .. ">" .. gefunden[2] .. " = " .. s2 .. " s"
end

-- SZENE: Fluege - Flug ohne bekannte Zeit zeigt die vergangene Zeit
__F.tip = {}
C_TaxiMap.GetAllTaxiNodes = function()
  return {
    { nodeID = 2, slotIndex = 1, name = "Sturmwind, Elwynn", state = 0 },
    { nodeID = 999999, slotIndex = 2, name = "Irgendwo", state = 1 },
  }
end
__FEUER("TAXIMAP_OPENED")
TakeTaxiNode(2)
__F.zeit = 2000
__F.taxi = true
__UPDATE(1)
__F.zeit = 2045
__UPDATE(1)
local text = WegweiserFlugTimer.text:GetText() or ""
if not text:find("unterwegs 0:45") then error("Timer ohne Zeit falsch: " .. text) end
__F.taxi = false
__F.zeit = 2050
__UPDATE(1)

-- SZENE: Fluege - ohne GetTaxiMapID: alte Flugkarten-API, alle Ziele
GetTaxiMapID = function() return nil end
C_TaxiMap.GetAllTaxiNodes = function(m)
  -- nur das Gebiet: unvollständig
  return { { nodeID = 2, slotIndex = 1, name = "Sturmwind, Elwynn", state = 0 } }
end
NumTaxiNodes = function() return 3 end
local namen = { "Stormwind, Elwynn", "Sentinel Hill, Westfall", "Lakeshire, Redridge" }
TaxiNodeName = function(i) return namen[i] end
TaxiNodeGetType = function(i) return i == 1 and "CURRENT" or "REACHABLE" end
__WW.db.flugNamen = {}
__FEUER("TAXIMAP_OPENED")
local s = __WW.Fluege.slots
if not (s[1] and s[1].id == 2 and s[2] and s[2].id == 4 and s[3] and s[3].id == 5) then
  error("Flugkarte unvollständig: " .. tostring(s[3] and s[3].id))
end
__F.tip = {}
TaxiNodeOnButtonEnter({ GetID = function() return 3 end })
if not table.concat(__F.tip, " "):find("Flugzeit: 1:53") then error("Keine Flugzeit nach Lakeshire: " .. table.concat(__F.tip, " | ")) end
NumTaxiNodes, TaxiNodeName, TaxiNodeGetType = nil, nil, nil

-- SZENE: Fluege - Reiter
__WW:Oeffnen("fluege")
__WW.Fluege.baueNadeln()

-- SZENE: Fluege - Aufraeumen
GetTime = __F.altGetTime
local pins = LibStub("HereBeDragons-Pins-2.0")
pins.AddWorldMapIconMap, pins.RemoveAllWorldMapIcons = __F.altAdd, __F.altRemove
GameTooltip.AddLine = nil
UnitOnTaxi, GetTaxiMapID, C_TaxiMap = nil, nil, nil
