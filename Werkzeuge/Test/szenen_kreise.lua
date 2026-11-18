-- SZENE: Kreise - Minikarte zeigt nur Ringe, Weltkarte rundes Symbol
local e = __WW.charDb.sammeln
e.an, e.minikarte, e.weltkarte, e.miniRinge = true, true, true, true
__KARTE = 1411
WorldMapFrame.__shown = true
WorldMapFrame.GetMapID = function() return 1411 end
__FEUER("ZONE_CHANGED_NEW_AREA")
WorldMapFrame.OnMapChanged(WorldMapFrame)
__UPDATE(3)
-- Pins sind Frames mit .rand (Ring), .icon, .grund
local mini, welt = 0, 0
for _, f in ipairs(__FRAMES) do
  if f.rand and f.icon and f.grund and f.artID then
    if f.icon.__shown then welt = welt + 1 else mini = mini + 1 end
    assert(f.rand.__tex == "Interface\\AddOns\\Wegweiser\\Media\\Ring", "Ring-Textur fehlt")
  end
end
__LOG[#__LOG + 1] = "Kreise: Welt mit Symbol " .. welt .. ", Minikarte nur Ring " .. mini
assert(mini > 0, "keine Ring-Nadeln auf der Minikarte")
assert(welt > 0, "keine Symbol-Nadeln auf der Weltkarte")
-- SZENE: Kreise - Minikarte mit Symbol, wenn Ringe aus
local e = __WW.charDb.sammeln
e.miniRinge = false
__FEUER("ZONE_CHANGED_NEW_AREA")
__UPDATE(3)
local ohne = 0
for _, f in ipairs(__FRAMES) do
  if f.rand and f.icon and f.artID and f.__shown and not f.icon.__shown then ohne = ohne + 1 end
end
e.miniRinge = true
assert(ohne == 0, "Ringe aus, aber noch " .. ohne .. " Nadeln ohne Symbol")
