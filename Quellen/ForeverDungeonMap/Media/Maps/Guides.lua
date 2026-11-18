local _, ns = ...

-- Guide maps from Icy Veins / Warcraft Tavern for new Forever dungeons Wowhead has no map for.
-- These images belong to those sites (credited on screen). They replace the Wowhead entry for
-- the same dungeon.
ns.guideMapData = ns.guideMapData or {}
local M = ns.guideMapData
for id, m in pairs({
    [2959] = { file = "CityOfDalaran", w = 800, h = 416, tw = 1024, th = 512,
               credit = "Icy Veins", note = "Left: the sewers. Right: the city." },
    [2970] = { file = "TheDrownedCity", w = 910, h = 512, tw = 1024, th = 512,
               credit = "Warcraft Tavern", note = "Overhead view (no boss labels)." },
    [2998] = { file = "ExcavationSiteWetlands", w = 572, h = 360, tw = 1024, th = 512, credit = "Icy Veins" },
    [2999] = { file = "RuinsOfLordaeron", w = 689, h = 678, tw = 1024, th = 1024, credit = "Icy Veins" },
    [3065] = { file = "HallOfThanes", w = 445, h = 506, tw = 512, th = 512, credit = "Icy Veins" },
}) do M[id] = m end
