-- Wegweiser: deutsche Namen für Dinge, die in den Daten nur englisch stehen.
-- Von Hand gepflegt (das Daten-Skript fasst diese Datei nicht an).
local ADDON, WW = ...

-- Berufe: englischer Name (wie in den Daten) -> deutscher Name (wie im Spiel)
WW.beruf = {
  ["Alchemy"] = "Alchemie",
  ["Blacksmithing"] = "Schmiedekunst",
  ["Enchanting"] = "Verzauberkunst",
  ["Engineering"] = "Ingenieurskunst",
  ["Leatherworking"] = "Lederverarbeitung",
  ["Tailoring"] = "Schneiderei",
  ["Herbalism"] = "Kräuterkunde",
  ["Mining"] = "Bergbau",
  ["Skinning"] = "Kürschnerei",
  ["Cooking"] = "Kochkunst",
  ["First Aid"] = "Erste Hilfe",
  ["Fishing"] = "Angeln",
}
-- umgekehrt: deutsch -> englisch
WW.berufEn = {}
for en, de in pairs(WW.beruf) do WW.berufEn[de] = en end

-- Dungeons und Schlachtzüge: Instanz-ID -> deutscher Name.
-- Im Spiel gibt GetRealZoneText(id) den Namen meist selbst; diese Liste ist der Ersatz.
WW.dungeonName = {
  [33] = "Burg Schattenfang",
  [34] = "Das Verlies",
  [36] = "Die Todesminen",
  [43] = "Die Höhlen des Wehklagens",
  [47] = "Kral der Klingenhauer",
  [48] = "Tiefschwarze Grotte",
  [70] = "Uldaman",
  [90] = "Gnomeregan",
  [109] = "Der Tempel von Atal'Hakkar",
  [129] = "Hügel der Klingenhauer",
  [189] = "Das Scharlachrote Kloster",
  [209] = "Zul'Farrak",
  [229] = "Schwarzfelsspitze",
  [230] = "Schwarzfelstiefen",
  [249] = "Onyxias Hort",
  [289] = "Scholomance",
  [309] = "Zul'Gurub",
  [329] = "Stratholme",
  [349] = "Maraudon",
  [389] = "Der Flammenschlund",
  [409] = "Geschmolzener Kern",
  [429] = "Düsterbruch",
  [469] = "Pechschwingenhort",
  [509] = "Ruinen von Ahn'Qiraj",
  [531] = "Tempel von Ahn'Qiraj",
  [533] = "Naxxramas",
}

-- Name eines Dungeons: Spiel, sonst Liste, sonst englisch aus den Daten.
function WW.DungeonName(id)
  local name = GetRealZoneText and GetRealZoneText(id)
  if name and name ~= "" then return name end
  if WW.dungeonName[id] then return WW.dungeonName[id] end
  local h = WW.quelle.helper and WW.quelle.helper.dungeons and WW.quelle.helper.dungeons[id]
  if h and h.n then return h.n end
  local f = WW.quelle.fdm and WW.quelle.fdm.dungeons and WW.quelle.fdm.dungeons[id]
  return f and f.name or ("Dungeon " .. tostring(id))
end
