-- Szenen fuer die Questziele im Dungeon (Ziele\Dungeon.lua, Werkzeuge\Dungeon-Ziele.py).
-- SZENE: Dungeon-Ziele - Daten geladen, alle Punkte auf dem Bild
local Z = __WW.quelle.ziele
if type(Z) ~= "table" then error("WW.quelle.ziele fehlt (Ziele\\Dungeon.lua nicht geladen?)") end
local D = __WW.Dungeon
local art, id, item, xy = D.ZielLesen("n3636>6443:0a0bzzzz")
if art ~= "n" or id ~= 3636 or item ~= 6443 then error("ZielLesen: " .. tostring(art) .. " " .. tostring(id) .. " " .. tostring(item)) end
-- "zzzz": 1295 liegt ueber 1000, dieser Punkt muss wegfallen
if math.abs(xy[1] - 0.010) > 1e-9 or math.abs(xy[2] - 0.011) > 1e-9 then error("ZielLesen: falscher Punkt") end
if #xy ~= 2 then error("Punkt ausserhalb des Bildes nicht verworfen: " .. #xy .. " Werte") end
local a2, i2, it2 = D.ZielLesen("o13891:0a0b")
if a2 ~= "o" or i2 ~= 13891 or it2 ~= nil then error("ZielLesen ohne Item") end
if D.ZielLesen("kaputt") then error("ZielLesen nimmt kaputte Eintraege an") end
local punkte, quests = 0, 0
for inst, qs in pairs(Z) do
  for qid, liste in pairs(qs) do
    quests = quests + 1
    for _, s in ipairs(liste) do
      local a, i, _, p = D.ZielLesen(s)
      if not a then error("kaputter Eintrag " .. inst .. "/" .. qid .. ": " .. tostring(s)) end
      if #p == 0 then error("Eintrag ohne Punkte " .. inst .. "/" .. qid) end
      punkte = punkte + #p / 2
    end
  end
end
if not (Z[43] and Z[43][1486]) then error("Abweichende Haeute (1486) in den Hoehlen des Wehklagens fehlt") end
-- Objekte mit id 0 in der Tabelle gameobject (stehen in gameobject_spawn_entry): Magenta-Kappen in Uldaman
if not (Z[70] and Z[70][17]) then error("Uldaman-Reagenzien (17) fehlen: gameobject_spawn_entry nicht gelesen") end
__LOG[#__LOG + 1] = ("Dungeon-Ziele: %d Quests, %d Punkte"):format(quests, punkte)

-- SZENE: Dungeon-Ziele - gewaehlte Quest zeigt ihre Ziele auf der Karte
local D = __WW.Dungeon
__WW:DungeonKarteZeigen(43)
D.Ansicht("quests")
local zeile
for _, f in ipairs(__FRAMES) do
  if f.__typ == "Button" and type(f.eintrag) == "table" and type(f.eintrag.q) == "table" and f.eintrag.q.id == 1486 and f.__shown then zeile = f end
end
if not zeile then error("Questzeile fuer Abweichende Haeute fehlt") end
D.letzteZielNadeln = 0
zeile.__scripts.OnClick(zeile, "LeftButton")
if (D.letzteZielNadeln or 0) < 5 then error("zu wenige Ziel-Nadeln: " .. tostring(D.letzteZielNadeln)) end
local nadel
for _, f in ipairs(__FRAMES) do
  if f.__typ == "Frame" and f.istZiel and f.__shown and f.label then nadel = f end
end
if not nadel then error("keine sichtbare Ziel-Nadel") end
__TTZ = {} local alt = GameTooltip.AddLine GameTooltip.AddLine = function(self, t) __TTZ[#__TTZ + 1] = tostring(t) end
nadel.__scripts.OnEnter(nadel)
GameTooltip.AddLine = alt
local text = table.concat(__TTZ, " | ")
if not text:find("Deviate", 1, true) and not text:find("Abweichend", 1, true) then error("Nadel-Tooltip ohne Gegnernamen: " .. text) end
__LOG[#__LOG + 1] = "Ziel-Nadel: " .. text .. " (" .. D.letzteZielNadeln .. " Nadeln)"
-- abwaehlen: Ziele verschwinden
zeile.__scripts.OnClick(zeile, "LeftButton")
if D.letzteZielNadeln ~= 0 then error("nach dem Abwaehlen noch " .. D.letzteZielNadeln .. " Ziel-Nadeln") end
-- Ausrottung der Abweichenden (1487): nur normale Gegner, keine Bosse. Ziele stehen auf der Karte,
-- also darf der Detailtext nicht "Ort im Dungeon unbekannt" sagen.
local z2
for _, f in ipairs(__FRAMES) do
  if f.__typ == "Button" and type(f.eintrag) == "table" and type(f.eintrag.q) == "table" and f.eintrag.q.id == 1487 and f.__shown then z2 = f end
end
if not z2 then error("Questzeile fuer 1487 fehlt") end
z2.__scripts.OnClick(z2, "LeftButton")
if (D.letzteZielNadeln or 0) < 1 then error("1487 ohne Ziel-Nadeln") end
for _, f in ipairs(__FRAMES) do
  if f.__typ == "FontString" and f.__shown and type(f.__text) == "string" and f.__text:find("Ziel (englisch)", 1, true)
    and f.__text:find("Ort im Dungeon unbekannt", 1, true) then
    error("Detailtext sagt 'Ort im Dungeon unbekannt', obwohl Ziele auf der Karte sind")
  end
end
z2.__scripts.OnClick(z2, "LeftButton")
-- Uldaman, Replacement Phial (3375): Items 3827 und 1708 haben Punkte, 3857 nicht -> Hinweis muss bleiben
-- (Allianz-Quest der Stufe 42: im Nachbau nicht in der Liste, darum direkt über D.DetailText)
__WW:DungeonKarteZeigen(70)
local t3 = D.DetailText(D.Quest(3375), D.Dungeon(70))
if not t3:find("Ort im Dungeon unbekannt", 1, true) then error("3375: ein Ziel ohne Ort, aber kein Hinweis: " .. t3) end
if not t3:find("auf der Karte markiert", 1, true) then error("3375: Ziele mit Punkten nicht als markiert gezeigt: " .. t3) end
__WW:DungeonKarteUmschalten()
