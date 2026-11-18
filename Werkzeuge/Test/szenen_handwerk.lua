-- Szenen fuer Handwerk.lua: Kosten, Ertrag, Gewinn, Haendlerpreise, Reiter.
-- Nachbildung: jedes Item hat Haendler-Verkaufspreis 150 Kupfer (mockwow GetItemInfo).
-- SZENE: Handwerk - Vorbereiten (eigener Scan)
function __HW_GLEICH(ist, soll, was)
  if ist ~= soll then error((was or "?") .. ": erwartet " .. tostring(soll) .. ", war " .. tostring(ist), 2) end
end
local db = __WW.db
db.haendlerKauf = {}
-- Preisformat: "min,median,menge"
db.ah["Forever|Alliance"] = { r = "Forever", f = "Alliance", t = time(), n = 10, z = 4, m = "test", i = {
  [785] = "300,400,20",     -- Maguskönigskraut: AH 300
  [2447] = "1000,1000,5",   -- Friedensblume: AH 1000, aber Haendler billiger (geschaetzt 600)
  [2455] = "5000,6000,9",   -- Produkt: Mindestpreis 5000, nach 5 % Abzug 4750
} }
__HW_ALT = { [2447] = __WW.quelle.fdb.items[2447], [3371] = __WW.quelle.fdb.items[3371] }
__WW.quelle.fdb.items[2447] = "v3~Händler~Zone~1"
__WW.quelle.fdb.items[3371] = "v5~Händler~Zone~1"

-- SZENE: Handwerk - Zutatpreis: AH, geschaetzter und gesehener Haendlerpreis
local db = __WW.db
local H = __WW.Handwerk
local p, q = H.ZutatPreis(785)
__HW_GLEICH(p, 300, "785 Preis") __HW_GLEICH(q, "AH", "785 Quelle")
p, q = H.ZutatPreis(2447)
__HW_GLEICH(p, 600, "2447 geschaetzt (4 x 150)") __HW_GLEICH(q, "Händler ca.", "2447 Quelle")
p, q = H.ZutatPreis(999998)
__HW_GLEICH(p, nil, "ohne AH und ohne Haendler kein Preis")
-- beim Haendler gesehen: 5 Stueck fuer 20 Kupfer -> 4 pro Stueck
GetMerchantNumItems = function() return 2 end
GetMerchantItemID = function(i) return ({ 3371, 2447 })[i] end
GetMerchantItemInfo = function(i)
  if i == 1 then return "Phiole", 1, 20, 5, -1, true, true, false end
  return "Blume", 1, 500, 1, -1, true, true, true   -- Sonderwaehrung: nicht merken
end
__FEUER("MERCHANT_SHOW")
__HW_GLEICH(db.haendlerKauf[3371], 4, "Phiole pro Stueck")
__HW_GLEICH(db.haendlerKauf[2447], nil, "Sonderwaehrung nicht gemerkt")
p, q = H.ZutatPreis(3371)
__HW_GLEICH(p, 4, "3371 gesehen") __HW_GLEICH(q, "Händler", "3371 Quelle")

-- SZENE: Handwerk - Rezept rechnen
local H = __WW.Handwerk
local row = { 2331, "Minor Mana Potion", 25, 65, 85, 105, 2455, 1, "785:1,2447:1,3371:1", "t" }
local e = H.Berechnen("Alchemy", row)
__HW_GLEICH(e.kosten, 300 + 600 + 4, "Kosten")
__HW_GLEICH(e.ertragQuelle, "AH", "Ertrag aus dem AH")
__HW_GLEICH(e.ertrag, 4750, "Ertrag: Mindestpreis nach 5 % Abzug")
__HW_GLEICH(e.gewinn, 4750 - 904, "Gewinn")
-- zwei Stueck pro Herstellung
row[8] = 2
e = H.Berechnen("Alchemy", row)
__HW_GLEICH(e.ertrag, 9500, "Ertrag mal Anzahl")
-- fehlende Zutat: kein Gewinn
local row2 = { 1, "Test", 1, 1, 1, 1, 2455, 1, "785:2,999998:1", "a" }
e = H.Berechnen("Alchemy", row2)
__HW_GLEICH(e.gewinn, nil, "Gewinn fehlt ohne Zutatpreis")
__HW_GLEICH(#e.fehlt, 1, "eine Zutat fehlt")
__HW_GLEICH(e.kosten, 600, "Kosten der bekannten Zutaten")
-- Produkt ohne AH-Preis: Haendler
local row3 = { 2, "Test2", 1, 1, 1, 1, 999997, 3, "785:1", "a" }
e = H.Berechnen("Alchemy", row3)
__HW_GLEICH(e.ertragQuelle, "Händler", "ohne AH-Preis an den Haendler")
__HW_GLEICH(e.ertrag, 450, "3 x 150")
__HW_GLEICH(e.gewinn, 150, "Gewinn beim Haendler")
-- Verzauberung ohne Item: keine Zeile
__HW_GLEICH(H.Berechnen("Enchanting", { 3, "Ench", 1, 1, 1, 1, 0, 1, "785:1", "t" }), nil, "Verzauberung ohne Produkt")

-- SZENE: Handwerk - Liste: meine Berufe, Stufe, Sortierung
local H = __WW.Handwerk
local l, info = H.Liste({ beruf = "mein", nurStufe = true })
local _, info2 = H.Liste({ beruf = "Alchemy", nurGewinn = true })
if not info2.ahPreise or info2.ahPreise == 0 then error("info.ahPreise fehlt: Scan wird nicht erkannt") end
local l3, info3 = H.Liste({ beruf = "Alchemy", nurKomplett = true })
if not info3.ausgeblendet or info3.ausgeblendet ~= info3.ohnePreis then error("ausgeblendete Rezepte werden nicht gezaehlt") end
__HW_GLEICH(info.berufe, 2, "zwei eigene Berufe (Kraeuterkunde, Bergbau)")
for _, x in ipairs(l) do
  if x.beruf ~= "Mining" and x.beruf ~= "Herbalism" then error("fremder Beruf in meiner Liste: " .. x.beruf) end
  if x.stufe > 80 then error("Rezept ueber Bergbau 80: " .. x.row[2] .. " " .. x.stufe) end
end
local alle = H.Liste({ beruf = "alle" })
if #alle < 1000 then error("zu wenige Rezepte bei 'alle': " .. #alle) end
local vorher
for _, x in ipairs(alle) do
  if vorher and vorher.gewinn and x.gewinn and x.gewinn > vorher.gewinn then error("nicht nach Gewinn sortiert") end
  if vorher and not vorher.gewinn and x.gewinn then error("Rezepte ohne Preis stehen vor Rezepten mit Preis") end
  vorher = x
end
local mana
for _, x in ipairs(H.Liste({ beruf = "Alchemy", nurGewinn = true })) do
  if x.produkt == 2455 then mana = x end
  if not (x.gewinn and x.gewinn > 0) then error("ohne Gewinn trotz Haken") end
end
if not mana then error("Schwaches Manatrankrezept fehlt in Alchemie mit Gewinn") end
__LOG[#__LOG + 1] = ("Handwerk: %d Rezepte gesamt, Manatrank Gewinn %s"):format(#alle, tostring(mana.gewinn))

-- SZENE: Handwerk - Reiter, Knoepfe, Tooltip
local H = __WW.Handwerk
__WW.db.handwerk.beruf = "mein"
__WW:Oeffnen("handwerk")
local function knopf(anfang)
  for _, f in ipairs(__FRAMES) do
    if f.__typ == "Button" and type(f.__text) == "string" and f.__text:sub(1, #anfang) == anfang then return f end
  end
end
local k = knopf("Beruf:")
if not k then error("Beruf-Knopf fehlt") end
__HW_GLEICH(k.__text, "Beruf: meine Berufe", "Start: meine Berufe")
k.__scripts.OnClick(k, "LeftButton")
__HW_GLEICH(k.__text, "Beruf: alle", "nach einem Klick: alle")
k.__scripts.OnClick(k, "LeftButton")
__HW_GLEICH(k.__text, "Beruf: Alchemie", "dann Alchemie")
local liste = H._liste
if not liste or #liste.eintraege == 0 then error("Handwerk-Liste leer") end
for _, z in ipairs(liste.zeilen) do
  if z.eintrag then z.__scripts.OnEnter(z) end
end
-- alle Berufe einmal durchklicken bis zurueck zu "meine Berufe"
for _ = 1, 20 do
  k.__scripts.OnClick(k, "LeftButton")
  if k.__text == "Beruf: meine Berufe" then break end
end
__HW_GLEICH(k.__text, "Beruf: meine Berufe", "Kreis zurueck zum Anfang")

-- SZENE: Handwerk - Aufraeumen
__WW.db.ah["Forever|Alliance"] = nil
__WW.db.haendlerKauf = {}
__WW.db.handwerk.beruf = "mein"
GetMerchantNumItems, GetMerchantItemID, GetMerchantItemInfo = nil, nil, nil
for id, v in pairs(__HW_ALT) do __WW.quelle.fdb.items[id] = v end
