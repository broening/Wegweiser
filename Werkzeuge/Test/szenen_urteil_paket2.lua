-- Szenen fuer Paket 2: Entzaubern.lua, Twinks.lua, Muell.lua (und ihr Platz im Urteil).
-- SZENE: Paket2 - Vorbereiten
__P2 = { gii = C_Item.GetItemInfo, eb = __WW.Handwerk.EigeneBerufe, num = C_Container.GetContainerNumSlots,
  info = C_Container.GetContainerItemInfo, pick = C_Container.PickupContainerItem }
-- Eigene Items: 8601 gruenes Schwert Stufe 18, 8602 gruene Brust Stufe 23, 8603 blaue Brust Stufe 23 (Qualitaet 3)
C_Item.GetItemInfo = function(id)
  id = tonumber(tostring(id):match("%d+"))
  if id == 8601 then return "Schwert", "|Hitem:8601|h[Schwert]|h", 2, 18, 11, "Waffe", "Schwert", 1, "INVTYPE_WEAPON", 134400, 825, 2, 7 end
  if id == 8602 then return "Brust", "|Hitem:8602|h[Brust]|h", 2, 23, 18, "Ruestung", "Leder", 1, "INVTYPE_CHEST", 134400, 300, 4, 2 end
  if id == 8603 then return "Blau", "|Hitem:8603|h[Blau]|h", 3, 23, 18, "Ruestung", "Leder", 1, "INVTYPE_CHEST", 134400, 300, 4, 2 end
  if id == 8802 or id == 8801 or id == 8804 then return "Grau" .. id, "|Hitem:" .. id .. "|h[x]|h", 0, 5, 1, "Plunder", "Plunder", 20, "", 134400, 150, 15, 0 end
  if id == 8805 then return "Blauer Muell", "|Hitem:8805|h[x]|h", 3, 30, 25, "Ruestung", "Stoff", 1, "INVTYPE_CHEST", 134400, 900, 4, 1 end
  return __P2.gii(id)
end
__WW.Handwerk.EigeneBerufe = function() return { Enchanting = 50 } end
for k, v in pairs({ tooltip = true, zeichen = true, quest = true, kommende = true, beruf = true, fremde = true,
  rezepte = true, muell = true, alt = true, twinks = true, entzaubern = true, loeschen = true }) do __WW.db.urteil[k] = v end
__WW.db.urteil.merken = {}
-- Materialpreise
__WW.db.ah["Forever|Alliance"] = { r = "Forever", f = "Alliance", t = time(), n = 3, z = 3, m = "test", i = {
  [10939] = "3000,3000,9", [10940] = "1000,1000,9", [10978] = "2000,2000,9", [10998] = "5000,5000,9" } }
__WW.Urteil.NeuerStand()

-- SZENE: Paket2 - Entzauber-Tabelle: Waffe und Ruestung
local E = __WW.Entzaubern
local r = E.Ergebnis(8601)
if not r then error("8601 ohne Ergebnis") end
local a, b, c = r.liste[1], r.liste[2], r.liste[3]
if not (a.id == 10939 and a.p == 0.75 and a.min == 1 and a.max == 2) then error("Waffe: zuerst 75% Grosse Magie-Essenz") end
if not (b.id == 10940 and math.abs(b.p - 0.20) < 1e-9 and b.min == 2 and b.max == 3) then error("Waffe: 20% Seltsamer Staub 2-3") end
if not (c.id == 10978 and math.abs(c.p - 0.05) < 1e-9) then error("Waffe: 5% Splitter") end
if r.stufe ~= 1 then error("Stufe 18 braucht Verzauberkunst 1, war " .. r.stufe) end
r = E.Ergebnis(8602)
if not (r.liste[1].id == 10940 and r.liste[1].min == 4 and r.liste[1].max == 6 and math.abs(r.liste[1].p - 0.75) < 1e-9) then
  error("Ruestung 23: 75% Staub 4-6") end
if r.stufe ~= 25 then error("Stufe 23 braucht 25, war " .. r.stufe) end
r = E.Ergebnis(8603)
if not (#r.liste == 1 and r.liste[1].id == 10978 and r.liste[1].p == 1) then error("Blau 23: Kleiner Glitzersplitter") end
local w = E.Wert(8601)
local soll = math.floor(0.75 * 1.5 * 3000 * 0.95 + 0.20 * 2.5 * 1000 * 0.95 + 0.05 * 1 * 2000 * 0.95)
if w ~= soll then error("Wert 8601: " .. tostring(w) .. " statt " .. soll) end
if #E.Zeilen(8601) ~= 3 then error("Tooltip-Zeilen fehlen") end

-- SZENE: Paket2 - Entzaubern im Urteil: nur mit Verzauberkunst, genug Fertigkeit und Preisen
local U = __WW.Urteil
local e = U.Pruefen(8601, 1, false)
if not (e and e.gruppe == "entzaubern" and e.schutz) then error("8601 soll Entzaubern sein: " .. tostring(e and e.gruppe)) end
local e2 = U.Pruefen(8602, 1, false)
if not (e2 and e2.gruppe == "entzaubern") then error("8602 mit Verzauberkunst 50 soll Entzaubern sein") end
__WW.Handwerk.EigeneBerufe = function() return { Enchanting = 10 } end
U.NeuerStand()
if U.Pruefen(8602, 1, false) then error("8602 mit Verzauberkunst 10 nicht entzauberbar") end
__WW.Handwerk.EigeneBerufe = function() return {} end
U.NeuerStand()
if U.Pruefen(8601, 1, false) then error("ohne Verzauberkunst kein Entzaubern") end
__WW.Handwerk.EigeneBerufe = function() return { Enchanting = 50 } end
__WW.db.ah["Forever|Alliance"].i[10940] = nil
U.NeuerStand()
if U.Pruefen(8601, 1, false) then error("ohne Preis fuer den Staub kein Entzaubern") end
__WW.db.ah["Forever|Alliance"].i[10940] = "1000,1000,9"
U.NeuerStand()

-- SZENE: Paket2 - Twinks: Zutat fuer ein Rezept, das einem Twink noch Punkte gibt
local U = __WW.Urteil
table.insert(__WW.quelle.fdb.recipes.Tailoring, { 99970, "Twink Robe", 40, 45, 50, 60, 8710, 1, "8701:2", "t", 0, 0, 0 })
U.VerzeichnisNeu()
__WW.db.inventar.Forever = __WW.db.inventar.Forever or {}
__WW.db.inventar.Forever.Fred = { fraktion = "Alliance", klasse = "WARLOCK", berufe = { Tailoring = 50 },
  rezepte = { Tailoring = { [99970] = true } } }
__WW.db.inventar.Forever.Horst = { fraktion = "Horde", berufe = { Tailoring = 50 }, rezepte = { Tailoring = { [99970] = true } } }
U.NeuerStand()
local e = U.Pruefen(8701, 2, false)
if not (e and e.gruppe == "twink" and e.schutz and e.text:find("Fred (Schneiderei)", 1, true)) then
  error("8701 fuer Fred: " .. tostring(e and e.text)) end
if e.text:find("Horst", 1, true) then error("Horde-Twink mitgezaehlt") end
if U.Pruefen(8701, 2, true) then error("gebunden geht nicht per Post") end
__WW.db.inventar.Forever.Fred.twinkAus = true
U.NeuerStand()
if U.Pruefen(8701, 2, false) then error("ausgeschlossener Twink zaehlt noch") end
SlashCmdList.WEGWEISER("twink fred")
if __WW.db.inventar.Forever.Fred.twinkAus then error("/ww twink fred hat ihn nicht wieder eingeschlossen") end
SlashCmdList.WEGWEISER("twink")
__WW.db.inventar.Forever.Fred.berufe.Tailoring = 60
U.NeuerStand()
if U.Pruefen(8701, 2, false) then error("Rezept fuer Fred grau: kein Twink-Item") end
__WW.db.inventar.Forever.Fred.berufe.Tailoring = 50
U.NeuerStand()
-- eigene Berufe und Rezepte werden gespeichert
__WW.Handwerk.EigeneBerufe = function() return { Enchanting = 50, Tailoring = 12 } end
__WW.Twinks.Speichern()
if __WW.db.inventar.Forever.Dan.berufe.Tailoring ~= 12 then error("eigene Berufe nicht gespeichert") end
__WW.Handwerk.EigeneBerufe = function() return { Enchanting = 50 } end
U.NeuerStand()

-- SZENE: Paket2 - Briefkasten: Name eintragen, Items anhaengen
__P2_BAGS = { [0] = { { 8701, 2, false, 1 }, { 8601, 1, false, 2 }, { 8701, 5, false, 1 } } }
C_Container.GetContainerNumSlots = function(b) return __P2_BAGS[b] and #__P2_BAGS[b] or 0 end
C_Container.GetContainerItemInfo = function(b, s)
  local x = __P2_BAGS[b] and __P2_BAGS[b][s]
  if x then return { itemID = x[1], stackCount = x[2], isBound = x[3], quality = x[4], isLocked = false } end
end
__P2_CURSOR, __P2_ANHANG = nil, {}
C_Container.PickupContainerItem = function(b, s) local x = __P2_BAGS[b][s] __P2_CURSOR = x and x[1] end
CursorHasItem = function() return __P2_CURSOR ~= nil end
GetCursorInfo = function() if __P2_CURSOR then return "item", __P2_CURSOR end end
ClearCursor = function() __P2_CURSOR = nil end
ClickSendMailItemButton = function(i) __P2_ANHANG[i] = __P2_CURSOR __P2_CURSOR = nil end
GetSendMailItem = function(i) return __P2_ANHANG[i] and "x" or nil end
MailFrame = CreateFrame("Frame", "MailFrame", UIParent)
SendMailFrame = CreateFrame("Frame", "SendMailFrame", MailFrame)
SendMailFrame:Show()
SendMailNameEditBox = CreateFrame("EditBox", "SendMailNameEditBox", SendMailFrame)
__FEUER("MAIL_SHOW")
local k = WegweiserTwinkPost
if not k then error("Knopf am Briefkasten fehlt") end
if k.__text ~= "An Twinks: 2" then error("Knopftext: " .. tostring(k.__text)) end
k.__scripts.OnEnter(k)
k.__scripts.OnClick(k, "LeftButton")
if SendMailNameEditBox.__text ~= "Fred" then error("Name: " .. tostring(SendMailNameEditBox.__text)) end
if not (__P2_ANHANG[1] == 8701 and __P2_ANHANG[2] == 8701 and __P2_ANHANG[3] == nil) then error("Anhaenge falsch") end
if __P2_CURSOR then error("Maus nicht leer") end

-- SZENE: Paket2 - Muell-Knopf: billigster Muell, nie geschuetzt, nie blau
local M = __WW.Muell
__WW.QW.KannTragen = function(id) if id == 8805 then return false, "Krieger kann das nicht tragen (Stoff)" end return true end
__P2_BAGS = { [0] = { { 8801, 3, false, 0 }, { 8802, 2, false, 0 }, { 8804, 1, false, 0 }, { 8805, 1, true, 3 }, { 8601, 1, false, 2 } } }
__WW.Urteil.Merken(8804)
local kd = M.Kandidat()
if not (kd and kd.id == 8802 and kd.wert == 300) then error("Kandidat: " .. tostring(kd and kd.id)) end
local w = M.Taschenwert()
if w.muellN ~= 2 or w.muell ~= 750 then error("Taschenwert Muell: " .. w.muellN .. " / " .. w.muell) end
__P2_GELOESCHT = {}
DeleteCursorItem = function() __P2_GELOESCHT[#__P2_GELOESCHT + 1] = __P2_CURSOR __P2_CURSOR = nil end
if not M.Loeschen() then error("Loeschen hat nicht geklappt") end
if __P2_GELOESCHT[1] ~= 8802 then error("falsches Item geloescht: " .. tostring(__P2_GELOESCHT[1])) end
-- etwas an der Maus: nichts loeschen
__P2_CURSOR = 1234
if M.Loeschen() then error("trotz Item an der Maus geloescht") end
__P2_CURSOR = nil
__WW.Urteil.Merken(8804)
-- Knopf an der Tasche
ContainerFrame1:Show()
M.KnopfAktualisieren()
if not (WegweiserMuellKnopf and WegweiserMuellKnopf.__shown) then error("Muell-Knopf fehlt an der Tasche") end
WegweiserMuellKnopf.__scripts.OnEnter(WegweiserMuellKnopf)
__WW.db.urteil.loeschen = false
M.KnopfAktualisieren()
if WegweiserMuellKnopf.__shown then error("Muell-Knopf trotz Schalter aus") end
__WW.db.urteil.loeschen = true
ContainerFrame1:Hide()
M.KnopfAktualisieren()
if WegweiserMuellKnopf.__shown then error("Muell-Knopf ohne offene Tasche") end
-- Reiter zeigt Twinks und Wert
__WW:Oeffnen("behalten")
__UPDATE(3)

-- SZENE: Paket2 - Review: Muell mit unbekanntem Wert wird nie geloescht
local M = __WW.Muell
local altGii = C_Item.GetItemInfo
C_Item.GetItemInfo = function(id) if tonumber(id) == 8806 then return nil end return altGii(id) end
__P2_BAGS = { [0] = { { 8801, 1, false, 0 }, { 8806, 1, false, 0 } } }
local kd = M.Kandidat()
C_Item.GetItemInfo = altGii
if kd and kd.id == 8806 then error("Item ohne bekannten Wert als Muell gewaehlt") end

-- SZENE: Paket2 - Review: wartender Zauber (SpellIsTargeting) -> nichts aufnehmen
local M = __WW.Muell
__P2_BAGS = { [0] = { { 8801, 1, false, 0 } } }
SpellIsTargeting = function() return true end
__P2_GELOESCHT = {}
local ok = M.Loeschen()
__P2_ANHANG = {}
__P2_BAGS = { [0] = { { 8701, 2, false, 1 } } }
SendMailNameEditBox.__text = ""
__WW.Twinks.Anhaengen()
SpellIsTargeting = nil
if ok or #__P2_GELOESCHT > 0 then error("Loeschen trotz wartendem Zauber") end
if __P2_ANHANG[1] then error("Anhaengen trotz wartendem Zauber") end

-- SZENE: Paket2 - Review: zweiter Klick adressiert einen angefangenen Brief nicht um
local U = __WW.Urteil
table.insert(__WW.quelle.fdb.recipes.Tailoring, { 99971, "Gustav Robe", 40, 45, 50, 60, 8711, 1, "8702:2", "t", 0, 0, 0 })
U.VerzeichnisNeu()
__WW.db.inventar.Forever.Gustav = { fraktion = "Alliance", berufe = { Tailoring = 50 }, rezepte = { Tailoring = { [99971] = true } } }
U.NeuerStand()
__P2_BAGS = { [0] = { { 8702, 1, false, 1 }, { 8702, 1, false, 1 }, { 8701, 1, false, 1 } } }
__P2_ANHANG, __P2_CURSOR = {}, nil
SendMailNameEditBox.__text = ""
__WW.Twinks.Anhaengen()
if SendMailNameEditBox.__text ~= "Gustav" then error("Klick 1 soll Gustav sein: " .. tostring(SendMailNameEditBox.__text)) end
-- angehängte Plätze sind jetzt gesperrt
local altInfo = C_Container.GetContainerItemInfo
C_Container.GetContainerItemInfo = function(b, s)
  local r = altInfo(b, s)
  if r and s <= 2 then r.isLocked = true end
  return r
end
__WW.Twinks.Anhaengen()
C_Container.GetContainerItemInfo = altInfo
if SendMailNameEditBox.__text ~= "Gustav" then error("Brief umadressiert an " .. tostring(SendMailNameEditBox.__text)) end
for i = 1, 12 do if __P2_ANHANG[i] == 8701 then error("Freds Item in Gustavs Brief") end end

-- SZENE: Paket2 - Review: Twink, der das Rezept kennt, kommt zuerst
local U = __WW.Urteil
-- Fred kennt 99971 nicht, kann es aber lernen (fremde an); Gustav kennt es
local e = U.Pruefen(8702, 1, false)
if not (e and e.twinks and e.twinks[1].name == "Gustav") then error("Empfaenger: " .. tostring(e and e.twinks and e.twinks[1].name)) end
__WW.db.inventar.Forever.Gustav = nil
local t = __WW.quelle.fdb.recipes.Tailoring
for i = #t, 1, -1 do if t[i][1] == 99971 then table.remove(t, i) end end

-- SZENE: Paket2 - Aufraeumen
C_Item.GetItemInfo, __WW.Handwerk.EigeneBerufe = __P2.gii, __P2.eb
C_Container.GetContainerNumSlots, C_Container.GetContainerItemInfo, C_Container.PickupContainerItem = __P2.num, __P2.info, __P2.pick
CursorHasItem, GetCursorInfo, ClearCursor, ClickSendMailItemButton, GetSendMailItem, DeleteCursorItem = nil, nil, nil, nil, nil, nil
__WW.QW.KannTragen = __UR_ALT.kt
__WW.db.inventar.Forever.Fred, __WW.db.inventar.Forever.Horst = nil, nil
__WW.db.ah["Forever|Alliance"] = nil
local t = __WW.quelle.fdb.recipes.Tailoring
for i = #t, 1, -1 do if t[i][1] == 99970 then table.remove(t, i) end end
__WW.Urteil.VerzeichnisNeu()

-- SZENE: Paket2 - Taschenwert-Text: keine "0 Items, -" und kein "1 Items"
local t = __WW.Muell.WertText({ muellN = 0, muell = 0, ahN = 1, ah = 500, ahListe = {} })
if t:find("0 Items", 1, true) or t:find("1 Items", 1, true) or t:find(" - ", 1, true) then error("Text: " .. t) end

-- SZENE: Paket2 - Twink ohne gespeicherte Berufe wird im Knopf-Tooltip genannt
__WW.db.inventar.Forever.Olaf = { fraktion = "Alliance", klasse = "MAGE" }
local o = table.concat(__WW.Twinks.OhneDaten(), ",")
__WW.db.inventar.Forever.Olaf = nil
if not o:find("Olaf", 1, true) then error("Olaf fehlt in OhneDaten: " .. o) end
