-- Szenen fuer den Rundweg (Sammeln.lua): Reihenfolge, Laenge, Linien auf der Weltkarte.
-- SZENE: Sammeln - Rundweg: Quadrat wird ohne Kreuzung umrundet
local reihe, laenge = __WW.SammelRoute({ 0, 0, 1, 1, 1, 0, 0, 1 }, 1, 1)
if #reihe ~= 4 then error("Quadrat: 4 Punkte erwartet, war " .. #reihe) end
if math.abs(laenge - 4) > 1e-6 then error("Quadrat: Laenge 4 erwartet, war " .. laenge) end
local r0, l0 = __WW.SammelRoute({}, 1, 1)
if #r0 ~= 0 or l0 ~= 0 then error("leere Liste") end
local r1 = __WW.SammelRoute({ 0.5, 0.5 }, 1, 1)
if #r1 ~= 1 then error("ein Punkt") end

-- SZENE: Sammeln - Rundweg: jeder Punkt genau einmal, kuerzer als die Rohreihenfolge, schnell genug
local function zufall(n, saat)
  local x, pkt = saat, {}
  for i = 1, 2 * n do
    x = (x * 1103515245 + 12345) % 2147483648
    pkt[i] = (x % 10000) / 10000
  end
  return pkt
end
local function laengeVon(pkt, reihe, b, h)
  local s, n = 0, #reihe
  for i = 1, n do
    local a, c = reihe[i], reihe[i % n + 1]
    local dx, dy = (pkt[2 * a - 1] - pkt[2 * c - 1]) * b, (pkt[2 * a] - pkt[2 * c]) * h
    s = s + math.sqrt(dx * dx + dy * dy)
  end
  return s
end
for _, n in ipairs({ 5, 50, 400 }) do
  local pkt = zufall(n, n * 7 + 1)
  local t0 = os.clock()
  local reihe, laenge = __WW.SammelRoute(pkt, 3000, 2000)
  local dauer = os.clock() - t0
  if #reihe ~= n then error(n .. " Punkte: Reihe hat " .. #reihe) end
  local gesehen = {}
  for _, i in ipairs(reihe) do
    if gesehen[i] then error(n .. " Punkte: Punkt doppelt " .. i) end
    gesehen[i] = true
  end
  local roh = {}
  for i = 1, n do roh[i] = i end
  local lRoh = laengeVon(pkt, roh, 3000, 2000)
  if math.abs(laengeVon(pkt, reihe, 3000, 2000) - laenge) > 1e-3 then error("gemeldete Laenge stimmt nicht") end
  if n > 4 and laenge >= lRoh then error(n .. " Punkte: Runde nicht kuerzer als die Rohreihenfolge") end
  __LOG[#__LOG + 1] = ("Rundweg %d Punkte: %.0f statt %.0f Yards, %.3f s"):format(n, laenge, lRoh, dauer)
  if dauer > 1 then error(n .. " Punkte: zu langsam (" .. dauer .. " s)") end
end

-- SZENE: Sammeln - Rundweg auf der Weltkarte an und aus
local e = __WW.charDb.sammeln
e.an, e.weltkarte, e.route, e.grau, e.nurKoennen = true, true, true, true, false
e.typ = { herb = true, mine = true, skin = true }
__KARTE = 1429
WorldMapFrame.GetMapID = function() return 1429 end
WorldMapFrame.__shown = true
__WW.SammelnAktualisieren()
__UPDATE(2)
local info = __WW.SammelRouteInfo()
if not info or info.m ~= 1429 then error("kein Rundweg fuer Elwynn") end
if info.punkte < 3 then error("zu wenige Punkte im Rundweg: " .. info.punkte) end
local sichtbar = 0
for _, f in ipairs(__FRAMES) do if f.__typ == "Line" and f.__shown and f.__start then sichtbar = sichtbar + 1 end end
if sichtbar ~= info.punkte then error("Linien: " .. sichtbar .. ", Punkte: " .. info.punkte) end
__LOG[#__LOG + 1] = ("Rundweg Elwynn: %d Punkte, %s Yards"):format(info.punkte, tostring(info.laenge and math.floor(info.laenge)))
-- nur Kuerschnern an: kein Rundweg
e.typ = { herb = false, mine = false, skin = true }
__WW.SammelnAktualisieren()
__UPDATE(2)
if __WW.SammelRouteInfo() then error("Rundweg durch Tiere (Kuerschnern) gezeichnet") end
e.typ = {}
e.route = false
__WW.SammelnAktualisieren()
__UPDATE(2)
local noch = 0
for _, f in ipairs(__FRAMES) do if f.__typ == "Line" and f.__shown then noch = noch + 1 end end
if noch ~= 0 then error("Rundweg aus, aber noch " .. noch .. " Linien sichtbar") end
if __WW.SammelRouteInfo() then error("Rundweg aus, aber Info noch da") end
WorldMapFrame.__shown = false
e.grau, e.nurKoennen = false, true
