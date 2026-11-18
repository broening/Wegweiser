-- Wegweiser: Reiter "Handwerk". Welches Rezept bringt Gold?
-- Kosten = Zutaten zum günstigsten Preis (AH-Mindestpreis oder Händler-Kaufpreis).
-- Ertrag = bester Verkauf des fertigen Items (AH-Mindestpreis nach Gebühren oder Händler), mal Anzahl pro Herstellung.
-- Daten: WW.quelle.fdb.recipes[Beruf] = { {Zauber, Name, Stufe, gelb, grün, grau, Produkt, Anzahl, "Zutat:n,...",
--        Lernen (i<Rezept-Item> / a automatisch / t Lehrer), ...} }
--        WW.quelle.fdb.items[itemID] = "...|v<Händler>~<erster>~<Zone>~<in Forever gesehen>|..."
-- Händler-Kaufpreise, die du gesehen hast: WW.db.haendlerKauf[itemID] = Kupfer pro Stück.
-- Öffentlich: WW.Handwerk.ZutatPreis(id), WW.Handwerk.Berechnen(beruf, row), WW.Handwerk.Liste(filter)
local ADDON, WW = ...
local UI = WW.UI

WW.standardDB.haendlerKauf = {}
WW.standardDB.handwerk = {
  beruf = "mein",       -- "mein" | "alle" | englischer Berufsname
  nurStufe = true,      -- nur Rezepte bis zur eigenen Fertigkeit
  nurKomplett = false,  -- Rezepte mit fehlenden Preisen ausblenden
  nurGewinn = false,    -- nur Rezepte mit Gewinn
}

local HW = {}
WW.Handwerk = HW

-- Händler verkaufen in Classic meist für das Vierfache ihres Ankaufpreises.
local HAENDLER_FAKTOR = 4

local function fdb() return WW.quelle and WW.quelle.fdb end

---------------------------------------------------------------------------
-- Händler-Kaufpreise mitschreiben (beim Händler)
---------------------------------------------------------------------------
local function merchantPreis(i)
  local preis, menge, extra
  local infoNeu = WW.Neu("C_MerchantFrame", "GetItemInfo")
  if infoNeu then
    local ok, t = pcall(infoNeu, i)
    if ok and type(t) == "table" then
      preis, menge, extra = tonumber(t.price), tonumber(t.stackCount), t.hasExtendedCost
    end
  end
  if not preis then
    local alt = WW.Alt("GetMerchantItemInfo")
    if alt then
      local ok, _, _, p, m, _, _, _, ext = pcall(alt, i)
      if ok then preis, menge, extra = tonumber(p), tonumber(m), ext end
    end
  end
  return preis, menge, extra
end

local function merchantID(i)
  local f = WW.Neu("C_MerchantFrame", "GetItemID") or WW.Alt("GetMerchantItemID")
  if f then
    local ok, id = pcall(f, i)
    if ok and tonumber(id) then return tonumber(id) end
  end
  local l = WW.Alt("GetMerchantItemLink")
  if l then
    local ok, link = pcall(l, i)
    if ok and type(link) == "string" then return WW.ItemID(link) end
  end
  return nil
end

function HW.HaendlerLesen()
  if not WW.db then return 0 end
  local anzahlF = WW.Neu("C_MerchantFrame", "GetNumItems") or WW.Alt("GetMerchantNumItems")
  if not anzahlF then return 0 end
  local ok, n = pcall(anzahlF)
  n = ok and tonumber(n) or 0
  local gelesen = 0
  for i = 1, n do
    local id = merchantID(i)
    local preis, menge, extra = merchantPreis(i)
    if id and preis and preis > 0 and not extra then
      WW.db.haendlerKauf[id] = preis / math.max(1, menge or 1)
      gelesen = gelesen + 1
    end
  end
  return gelesen
end

WW:Event("MERCHANT_SHOW", function() HW.HaendlerLesen() end)
WW:Event("MERCHANT_UPDATE", function() HW.HaendlerLesen() end)

---------------------------------------------------------------------------
-- Preise
---------------------------------------------------------------------------
-- Verkauft ein Händler das Item (laut ForeverDB, in Forever gesehen)?
local function vomHaendler(id)
  local f = fdb()
  local s = f and f.items and f.items[id]
  if type(s) ~= "string" then return false end
  for fakt in (s .. "|"):gmatch("([^|]*)|") do
    if fakt:sub(1, 1) == "v" then
      local gesehen = fakt:match("~([^~]*)$")
      return gesehen ~= "0"
    end
  end
  return false
end
HW.VomHaendler = vomHaendler

-- Preis pro Stück für eine Zutat: kupfer, quelle ("AH" | "Händler" | "Händler ca.") oder nil
function HW.ZutatPreis(id)
  id = tonumber(id)
  if not id then return nil end
  local haendler, hQuelle = WW.db and WW.db.haendlerKauf[id], "Händler"
  if not haendler and vomHaendler(id) then
    local verkauf = tonumber(WW.HaendlerPreis(id))
    if verkauf and verkauf > 0 then haendler, hQuelle = verkauf * HAENDLER_FAKTOR, "Händler ca." end
  end
  local ah = WW.AH and WW.AH.Preis(id)
  if ah and ah > 0 and (not haendler or ah < haendler) then return ah, "AH" end
  if haendler then return haendler, hQuelle end
  return nil
end

local function itemName(id)
  local n = WW.ItemName(id)
  if n then return n end
  local f = fdb()
  return (f and f.names and f.names[id]) or ("Item " .. tostring(id))
end
HW.ItemName = itemName

-- Ein Rezept durchrechnen. Ergebnis-Tabelle:
--   produkt, anzahl, zutaten = { {id, n, preis, quelle} }, kosten, fehlt (Liste der Zutaten ohne Preis),
--   ertrag, ertragQuelle ("AH" | "Händler" | "gebunden"), gewinn (nil, wenn etwas fehlt)
function HW.Berechnen(beruf, row)
  if type(row) ~= "table" then return nil end
  local produkt = tonumber(row[7])
  if not produkt or produkt <= 0 then return nil end
  local e = { beruf = beruf, row = row, produkt = produkt, anzahl = math.max(1, tonumber(row[8]) or 1),
    stufe = tonumber(row[3]) or 0, zutaten = {}, kosten = 0, fehlt = {} }
  if type(row[9]) == "string" then
    for zid, n in row[9]:gmatch("(%d+):(%d+)") do
      zid, n = tonumber(zid), tonumber(n)
      local preis, quelle = HW.ZutatPreis(zid)
      e.zutaten[#e.zutaten + 1] = { id = zid, n = n, preis = preis, quelle = quelle }
      if preis then e.kosten = e.kosten + preis * n else e.fehlt[#e.fehlt + 1] = zid end
    end
  end
  -- Ertrag: ein Stück bewerten, dann mal Anzahl (Anzahl kann ein Durchschnitt sein)
  -- Verkaufen heißt: den Mindestpreis im AH treffen (nicht den Median), dann zieht das AH seinen Anteil ab.
  local _, text, erloes, haendler, bInfo = "grau", "kein AH-Preis", 0, 0, nil
  if WW.AH and WW.AH.Bewertung then _, text, erloes, haendler, bInfo = WW.AH.Bewertung(produkt, 1) end
  erloes, haendler = tonumber(erloes) or 0, tonumber(haendler) or 0
  local mindest = WW.AH and WW.AH.Preis and tonumber((WW.AH.Preis(produkt)))
  if erloes > 0 and mindest and mindest > 0 then
    local abzug = type(bInfo) == "table" and tonumber(bInfo.abzug) or 0.05
    erloes = math.floor(mindest * (1 - abzug))
  end
  if text == "gebunden" then
    e.ertrag, e.ertragQuelle = haendler * e.anzahl, "gebunden"
  elseif erloes > 0 and erloes >= haendler then
    e.ertrag, e.ertragQuelle = erloes * e.anzahl, "AH"
  elseif haendler > 0 then
    e.ertrag, e.ertragQuelle = haendler * e.anzahl, "Händler"
  end
  if not e.ertrag then e.fehltErtrag = true end
  if #e.fehlt == 0 and e.ertrag then e.gewinn = e.ertrag - e.kosten end
  return e
end

---------------------------------------------------------------------------
-- Liste bauen
---------------------------------------------------------------------------
-- Eigene Berufe: [englischer Name] = Fertigkeit
local function eigeneBerufe()
  local raus = {}
  local ok, liste = pcall(WW.Fertigkeiten)
  if not ok or type(liste) ~= "table" then return raus end
  for name, w in pairs(liste) do
    local en = WW.berufEn[name] or (WW.beruf[name] and name)
    if en then raus[en] = tonumber(w.rang) or 0 end
  end
  return raus
end
HW.EigeneBerufe = eigeneBerufe

-- Berufe mit Rezepten (englisch), in der Reihenfolge der Daten
function HW.Berufe()
  local f = fdb()
  local alle, raus = f and f.recipes, {}
  if type(alle) ~= "table" then return raus end
  local schon = {}
  for _, en in ipairs(f.professions or {}) do
    if type(alle[en]) == "table" then raus[#raus + 1] = en; schon[en] = true end
  end
  local rest = {}
  for en, l in pairs(alle) do if not schon[en] and type(l) == "table" then rest[#rest + 1] = en end end
  table.sort(rest)
  for _, en in ipairs(rest) do raus[#raus + 1] = en end
  return raus
end

local function sortieren(a, b)
  if (a.gewinn ~= nil) ~= (b.gewinn ~= nil) then return a.gewinn ~= nil end
  if a.gewinn and b.gewinn and a.gewinn ~= b.gewinn then return a.gewinn > b.gewinn end
  if a.stufe ~= b.stufe then return a.stufe < b.stufe end
  return (tonumber(a.row[1]) or 0) < (tonumber(b.row[1]) or 0)
end

-- filter = { beruf = "mein"|"alle"|en, nurStufe, nurKomplett, nurGewinn }
-- Gibt eintraege, info = { berufe = Anzahl eigener Berufe, ohnePreis = Anzahl } zurück.
function HW.Liste(filter)
  filter = filter or {}
  local f = fdb()
  local alle = f and f.recipes
  local eigene = eigeneBerufe()
  local info = { berufe = 0, ohnePreis = 0, ausgeblendet = 0, ahPreise = 0 }
  for _ in pairs(eigene) do info.berufe = info.berufe + 1 end
  local raus = {}
  if type(alle) ~= "table" then return raus, info end
  for beruf, liste in pairs(alle) do
    local passt = filter.beruf == "alle" or filter.beruf == beruf
      or ((filter.beruf == "mein" or filter.beruf == nil) and eigene[beruf] ~= nil)
    if passt and type(liste) == "table" then
      local rang = eigene[beruf]
      for _, row in ipairs(liste) do
        if type(row) == "table" and not (filter.nurStufe and rang and (tonumber(row[3]) or 0) > rang) then
          local e = HW.Berechnen(beruf, row)
          if e then
            e.rang = rang
            if not e.gewinn then info.ohnePreis = info.ohnePreis + 1 end
            local ah = e.ertragQuelle == "AH"
            for _, zt in ipairs(e.zutaten) do if zt.quelle == "AH" then ah = true end end
            if ah then info.ahPreise = info.ahPreise + 1 end
            local weg = (filter.nurKomplett and not e.gewinn) or (filter.nurGewinn and not (e.gewinn and e.gewinn > 0))
            if weg then
              if not e.gewinn then info.ausgeblendet = info.ausgeblendet + 1 end
            else
              raus[#raus + 1] = e
            end
          end
        end
      end
    end
  end
  table.sort(raus, sortieren)
  return raus, info
end

-- Farbe der Stufe wie im Berufsfenster: orange, gelb, grün, grau (nil ohne eigene Fertigkeit)
local function stufenFarbe(e)
  local r = e.rang
  if not r then return nil end
  local row = e.row
  local gelb, gruen, grau = tonumber(row[4]) or 0, tonumber(row[5]) or 0, tonumber(row[6]) or 0
  if r < e.stufe then return "rot" end
  if r >= grau then return "grau" end
  if r >= gruen then return "gruen" end
  if r >= gelb then return "gelb" end
  return "orange"
end

local function lernText(row)
  local l = row[10]
  if type(l) ~= "string" then return nil end
  if l == "a" then return "automatisch" end
  if l == "t" then return "beim Lehrer" end
  local id = tonumber(l:match("^i(%d+)"))
  if id then return "Rezept: " .. itemName(id) end
  return nil
end

---------------------------------------------------------------------------
-- Reiter
---------------------------------------------------------------------------
local SP = { name = 24, stufe = 300, kosten = 345, ertrag = 455, gewinn = 565, hinweis = 680 }

WW:Reiter("handwerk", "Handwerk", 22, function(p)
  local db = WW.db.handwerk

  local titel = UI.Text(p, "gross")
  titel:SetPoint("TOPLEFT", 4, -4)
  titel:SetText("Handwerk")

  local liste
  local function neuRechnen() if p.OnZeigen then p.OnZeigen() end end

  local function berufText()
    if db.beruf == "mein" then return "Beruf: meine Berufe" end
    if db.beruf == "alle" then return "Beruf: alle" end
    return "Beruf: " .. (WW.beruf[db.beruf] or tostring(db.beruf))
  end
  local berufKnopf = UI.Knopf(p, berufText(), 200, function(self)
    local reihe = { "mein", "alle" }
    for _, en in ipairs(HW.Berufe()) do reihe[#reihe + 1] = en end
    local naechste = reihe[1]
    for i, k in ipairs(reihe) do
      if k == db.beruf then naechste = reihe[i + 1] or reihe[1] end
    end
    db.beruf = naechste
    self:SetText(berufText())
    neuRechnen()
  end)
  berufKnopf:SetPoint("TOPLEFT", 150, -4)

  local neuKnopf = UI.Knopf(p, "Neu rechnen", 124, function() neuRechnen() end)
  neuKnopf:SetPoint("TOPRIGHT", -4, -4)

  local status = UI.Text(p)
  status:SetPoint("TOPLEFT", titel, "BOTTOMLEFT", 0, -6)
  status:SetWidth(WW.INHALT_BREITE - 8)
  status:SetSpacing(2)
  status:SetJustifyV("TOP")

  local h1 = UI.Haken(p, "Nur bis meine Stufe", function() return db.nurStufe end,
    function(an) db.nurStufe = an; neuRechnen() end)
  h1:SetPoint("TOPLEFT", 0, -72)
  local h2 = UI.Haken(p, "Nur mit allen Preisen", function() return db.nurKomplett end,
    function(an) db.nurKomplett = an; neuRechnen() end)
  h2:SetPoint("TOPLEFT", 180, -72)
  local h3 = UI.Haken(p, "Nur mit Gewinn", function() return db.nurGewinn end,
    function(an) db.nurGewinn = an; neuRechnen() end)
  h3:SetPoint("TOPLEFT", 370, -72)

  local legende = UI.Text(p, "klein", 0.8, 0.8, 0.8)
  legende:SetPoint("TOPLEFT", 4, -98)
  legende:SetWidth(WW.INHALT_BREITE - 8)
  legende:SetWordWrap(false)
  legende:SetText("Kosten: Zutaten zum günstigsten Preis (AH-Mindestpreis oder Händler).  Ertrag: AH-Mindestpreis nach Gebühren oder Händler.  "
    .. WW.f("gelb", "ca.") .. " = Händlerpreis geschätzt.")

  local kopfY = -118
  local function kopf(text, x)
    local t = UI.Text(p, "klein", 0.9, 0.8, 0.3)
    t:SetPoint("TOPLEFT", 10 + x, kopfY)
    t:SetText(text)
  end
  kopf("Rezept", SP.name)
  kopf("Stufe", SP.stufe)
  kopf("Kosten", SP.kosten)
  kopf("Ertrag", SP.ertrag)
  kopf("Gewinn", SP.gewinn)
  kopf("Hinweis", SP.hinweis)

  local function spalte(z, x, bis)
    local t = UI.Text(z)
    t:SetPoint("LEFT", x, 0)
    t:SetWidth(bis - x - 6)
    t:SetWordWrap(false)
    return t
  end

  local function tooltip(self)
    local e = self.eintrag
    if not e then return end
    UI.ItemTooltip(self, e.produkt)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(("%s, Stufe %d%s"):format(WW.beruf[e.beruf] or e.beruf, e.stufe,
      e.anzahl > 1 and (", macht " .. e.anzahl .. " Stück") or ""), 1, 0.82, 0)
    local lernen = lernText(e.row)
    if lernen then GameTooltip:AddLine("Lernen: " .. lernen, 0.8, 0.8, 0.8) end
    GameTooltip:AddLine("Zutaten:", 1, 0.82, 0)
    for _, z in ipairs(e.zutaten) do
      local preis = z.preis and (WW.Geld(z.preis * z.n) .. " (" .. z.quelle .. ")") or WW.f("rot", "kein Preis")
      GameTooltip:AddDoubleLine(z.n .. "x " .. itemName(z.id), preis, 1, 1, 1, 1, 1, 1)
    end
    GameTooltip:AddDoubleLine("Kosten", WW.Geld(e.kosten), 1, 0.82, 0, 1, 1, 1)
    local ertragText = e.ertrag and (WW.Geld(e.ertrag) .. " (" .. e.ertragQuelle .. ")") or WW.f("rot", "kein Preis")
    GameTooltip:AddDoubleLine("Ertrag", ertragText, 1, 0.82, 0, 1, 1, 1)
    if e.gewinn then
      GameTooltip:AddDoubleLine("Gewinn", WW.f(e.gewinn > 0 and "gruen" or "rot", (e.gewinn < 0 and "-" or "") .. WW.Geld(math.abs(e.gewinn))),
        1, 0.82, 0, 1, 1, 1)
    end
    if e.ertragQuelle == "AH" then
      GameTooltip:AddLine("Die Einstellgebühr ist nicht abgezogen. Du bekommst sie zurück, wenn das Item verkauft wird.", 0.7, 0.7, 0.7, true)
    end
    GameTooltip:Show()
  end

  local function baueZeile(z)
    z.icon = z:CreateTexture(nil, "ARTWORK")
    z.icon:SetSize(20, 20)
    z.icon:SetPoint("LEFT", 0, 0)
    z.name = spalte(z, SP.name, SP.stufe)
    z.stufe = spalte(z, SP.stufe, SP.kosten)
    z.kosten = spalte(z, SP.kosten, SP.ertrag)
    z.ertrag = spalte(z, SP.ertrag, SP.gewinn)
    z.gewinn = spalte(z, SP.gewinn, SP.hinweis)
    z.hinweis = spalte(z, SP.hinweis, SP.hinweis + 140)
    z:SetScript("OnEnter", tooltip)
    z:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end

  local function fuelleZeile(z, e)
    z.icon:SetTexture(WW.GetItemIcon(e.produkt) or "Interface\\Icons\\INV_Misc_QuestionMark")
    local name = itemName(e.produkt)
    z.name:SetText(name .. (e.anzahl > 1 and WW.f("grau", " x" .. e.anzahl) or ""))
    local farbe = stufenFarbe(e)
    z.stufe:SetText(farbe and WW.f(farbe, e.stufe) or tostring(e.stufe))
    local geschaetzt = false
    for _, zt in ipairs(e.zutaten) do if zt.quelle == "Händler ca." then geschaetzt = true end end
    z.kosten:SetText(#e.fehlt > 0 and WW.f("grau", "?") or (WW.Geld(e.kosten) .. (geschaetzt and WW.f("gelb", " ca.") or "")))
    z.ertrag:SetText(e.ertrag and WW.Geld(e.ertrag) or WW.f("grau", "?"))
    if e.gewinn then
      local g = e.gewinn
      z.gewinn:SetText(WW.f(g > 0 and "gruen" or (g == 0 and "grau" or "rot"), (g < 0 and "-" or "") .. WW.Geld(math.abs(g))))
    else
      z.gewinn:SetText(WW.f("grau", "-"))
    end
    local hinweis
    if #e.fehlt > 0 then
      hinweis = WW.f("grau", "Preis fehlt: " .. itemName(e.fehlt[1]) .. (#e.fehlt > 1 and (" +" .. (#e.fehlt - 1)) or ""))
    elseif e.fehltErtrag then
      hinweis = WW.f("grau", "Ertrag unbekannt")
    elseif e.ertragQuelle == "AH" then
      hinweis = "im AH verkaufen"
    elseif e.ertragQuelle == "gebunden" then
      hinweis = WW.f("grau", "gebunden")
    else
      hinweis = "beim Händler verkaufen"
    end
    z.hinweis:SetText(hinweis)
  end

  liste = UI.Liste(p, WW.INHALT_BREITE - 8, WW.INHALT_HOEHE - 138, 22, baueZeile, fuelleZeile)
  liste:SetPoint("TOPLEFT", 4, -134)
  HW._liste = liste   -- für Tests

  local leer = UI.Text(liste, "klein", 0.75, 0.75, 0.75)
  leer:SetPoint("TOPLEFT", 16, -16)
  leer:SetWidth(WW.INHALT_BREITE - 60)
  leer:SetSpacing(3)
  leer:SetJustifyV("TOP")

  p.OnZeigen = function()
    berufKnopf:SetText(berufText())
    local eintraege, info = HW.Liste(db)
    liste:Setze(eintraege)
    local mitGewinn = 0
    for _, e in ipairs(eintraege) do if e.gewinn and e.gewinn > 0 then mitGewinn = mitGewinn + 1 end end
    local zeilen = {}
    local satz = ("%d Rezepte, %d mit Gewinn."):format(#eintraege, mitGewinn)
    if info.ohnePreis > 0 then
      satz = satz .. (" %d Rezepte haben nicht alle Preise"):format(info.ohnePreis)
        .. (info.ausgeblendet > 0 and (" (%d ausgeblendet)."):format(info.ausgeblendet) or ".")
    end
    zeilen[#zeilen + 1] = satz
    if info.ahPreise == 0 then
      zeilen[#zeilen + 1] = WW.f("gelb", "Scanne das Auktionshaus (Reiter \"Auktionshaus\"), dann stimmen die Preise.")
    else
      zeilen[#zeilen + 1] = WW.f("grau", "Preise aus dem letzten Scan. Beim Händler merkt sich Wegweiser die Kaufpreise.")
    end
    status:SetText(table.concat(zeilen, "\n"))
    if #eintraege > 0 then
      leer:SetText("")
    elseif db.beruf == "mein" and info.berufe == 0 then
      leer:SetText("Dein Charakter hat keinen Beruf. Klicke auf \"" .. berufText() .. "\", um andere Berufe zu sehen.")
    else
      leer:SetText("Keine Rezepte für diese Auswahl. Nimm einen Haken weg oder wähle einen anderen Beruf.")
    end
  end
end)
