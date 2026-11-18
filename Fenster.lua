-- Wegweiser: Hauptfenster mit Reitern, gemeinsame UI-Bausteine, Minimap-Knopf.
local ADDON, WW = ...

local BREITE, HOEHE = 880, 580
WW.INHALT_BREITE, WW.INHALT_HOEHE = BREITE - 24, HOEHE - 78

---------------------------------------------------------------------------
-- UI-Bausteine (für alle Module gleich)
---------------------------------------------------------------------------
local UI = {}
WW.UI = UI

-- Text. groesse: "klein" | "normal" | "gross"
function UI.Text(parent, groesse, r, g, b)
  local vorlage = (groesse == "gross" and "GameFontNormalLarge")
               or (groesse == "klein" and "GameFontHighlightSmall")
               or "GameFontHighlight"
  local fs = parent:CreateFontString(nil, "OVERLAY", vorlage)
  if r then fs:SetTextColor(r, g, b) end
  fs:SetJustifyH("LEFT")
  return fs
end

function UI.Knopf(parent, text, breite, onClick)
  local k = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  k:SetSize(breite or 120, 22)
  k:SetText(text)
  if onClick then k:SetScript("OnClick", onClick) end
  return k
end

-- Eingabefeld. onAenderung(text) läuft bei jeder Änderung durch den Spieler.
function UI.Eingabe(parent, breite, onAenderung)
  local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  e:SetSize(breite or 200, 20)
  e:SetAutoFocus(false)
  e:SetScript("OnEscapePressed", e.ClearFocus)
  e:SetScript("OnEnterPressed", e.ClearFocus)
  if onAenderung then
    e:SetScript("OnTextChanged", function(self, vomSpieler)
      if vomSpieler then onAenderung(self:GetText() or "") end
    end)
  end
  return e
end

-- Haken. get() -> bool, set(bool)
function UI.Haken(parent, text, get, set)
  local h = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  h:SetSize(24, 24)
  local t = h.text or h.Text
  if not t then
    t = h:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    t:SetPoint("LEFT", h, "RIGHT", 2, 0)
  end
  t:SetText(text)
  h:SetScript("OnShow", function(self) self:SetChecked(get() and true or false) end)
  h:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
  h:SetChecked(get() and true or false)
  return h
end

-- Kasten mit Rand als Hintergrund.
function UI.Kasten(parent)
  local k = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  k:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  k:SetBackdropColor(0, 0, 0, 0.5)
  k:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
  return k
end

-- Liste mit Rollbalken, die nur sichtbare Zeilen baut (auch für 20.000 Einträge schnell).
--   liste = UI.Liste(parent, breite, hoehe, zeilenHoehe, baueZeile(zeile), fuelleZeile(zeile, eintrag, index))
--   liste:Setze(eintraege)   -- Tabelle mit beliebigen Einträgen
-- baueZeile bekommt einen Button (zeile) und legt Texte/Icons darauf an.
-- Klicks: zeile:SetScript("OnClick", ...) in baueZeile; zeile.eintrag ist der aktuelle Eintrag.
local listenZaehler = 0
function UI.Liste(parent, breite, hoehe, zeilenHoehe, baueZeile, fuelleZeile)
  local rahmen = UI.Kasten(parent)
  rahmen:SetSize(breite, hoehe)
  local sichtbar = math.floor((hoehe - 8) / zeilenHoehe)
  -- Eindeutiger Name: ältere FauxScrollFrame-Funktionen brauchen GetName()
  listenZaehler = listenZaehler + 1
  local scroll = CreateFrame("ScrollFrame", "WegweiserListe" .. listenZaehler, rahmen, "FauxScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 4, -4)
  scroll:SetPoint("BOTTOMRIGHT", -26, 4)
  rahmen.eintraege = {}
  rahmen.zeilen = {}

  local function aktualisiere()
    local daten = rahmen.eintraege
    FauxScrollFrame_Update(scroll, #daten, sichtbar, zeilenHoehe)
    local versatz = FauxScrollFrame_GetOffset(scroll)
    for i = 1, sichtbar do
      local zeile = rahmen.zeilen[i]
      local index = versatz + i
      local eintrag = daten[index]
      if eintrag then
        zeile.eintrag, zeile.index = eintrag, index
        fuelleZeile(zeile, eintrag, index)
        zeile:Show()
      else
        zeile.eintrag, zeile.index = nil, nil
        zeile:Hide()
      end
    end
  end

  for i = 1, sichtbar do
    local zeile = CreateFrame("Button", nil, rahmen)
    zeile:SetHeight(zeilenHoehe)
    zeile:SetPoint("TOPLEFT", 6, -4 - (i - 1) * zeilenHoehe)
    zeile:SetPoint("RIGHT", rahmen, "RIGHT", -28, 0)
    local hl = zeile:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    -- Listen mit rahmen.itemKlick = true: Klick auf eine Item-Zeile öffnet die Item-Details.
    -- baueZeile darf das mit einem eigenen OnClick ersetzen.
    zeile:SetScript("OnClick", function(self)
      local id = rahmen.itemKlick and self.eintrag and not self.eintrag.kopf and tonumber(self.eintrag.id)
      if id and WW.ItemZeigen then WW:ItemZeigen(id) end
    end)
    -- Rechtsklick (OnMouseUp kommt auch ohne RegisterForClicks): Menü "Mehr Information"
    zeile:SetScript("OnMouseUp", function(self, maus)
      if maus ~= "RightButton" or not rahmen.itemKlick then return end
      local id = self.eintrag and not self.eintrag.kopf and tonumber(self.eintrag.id)
      if id then UI.ItemMenue(id) end
    end)
    baueZeile(zeile)
    rahmen.zeilen[i] = zeile
  end

  scroll:SetScript("OnVerticalScroll", function(self, wert)
    FauxScrollFrame_OnVerticalScroll(self, wert, zeilenHoehe, aktualisiere)
  end)

  function rahmen:Setze(eintraege)
    self.eintraege = eintraege or {}
    FauxScrollFrame_SetOffset(scroll, 0)
    scroll:SetVerticalScroll(0)
    aktualisiere()
  end
  function rahmen:Aktualisiere() aktualisiere() end

  return rahmen
end

-- Kleines Menü an der Maus (eigener Rahmen, kein UIDropDownMenu: das kann Blizzards Fenster stören).
-- eintraege = { { text = "...", aktion = function() end }, ... }. Klick auf einen Eintrag schließt das Menü;
-- es schließt auch, wenn die Maus 1,5 Sekunden nicht darüber ist.
local menue
function UI.Menue(eintraege)
  if not menue then
    menue = CreateFrame("Frame", "WegweiserMenue", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    menue:SetFrameStrata("TOOLTIP")
    menue:SetClampedToScreen(true)
    if menue.SetBackdrop then
      menue:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
      menue:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    end
    menue.knoepfe = {}
    local weg = 0
    menue:SetScript("OnUpdate", function(self, dt)
      if self:IsMouseOver() then weg = 0 else weg = weg + (dt or 0) end
      if weg > 1.5 then weg = 0; self:Hide() end
    end)
    tinsert(UISpecialFrames, "WegweiserMenue")   -- Esc schließt
  end
  for _, k in ipairs(menue.knoepfe) do k:Hide() end
  local breite = 160
  for i, e in ipairs(eintraege) do
    local k = menue.knoepfe[i]
    if not k then
      k = CreateFrame("Button", nil, menue)
      k:SetHeight(18)
      k:SetPoint("TOPLEFT", 6, -6 - (i - 1) * 18)
      k:SetPoint("RIGHT", menue, "RIGHT", -6, 0)
      local hl = k:CreateTexture(nil, "HIGHLIGHT")
      hl:SetAllPoints()
      hl:SetColorTexture(1, 1, 1, 0.15)
      k.text = UI.Text(k)
      k.text:SetPoint("LEFT", 4, 0)
      menue.knoepfe[i] = k
    end
    k.text:SetText(e.text)
    k:SetScript("OnClick", function()
      menue:Hide()
      if e.aktion then pcall(e.aktion) end
    end)
    k:Show()
    local w = (k.text.GetStringWidth and k.text:GetStringWidth() or 0) + 24
    if w > breite then breite = w end
  end
  menue:SetSize(breite, 12 + #eintraege * 18)
  local x, y = GetCursorPosition()
  local s = UIParent:GetEffectiveScale()
  menue:ClearAllPoints()
  menue:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", (x or 0) / s - 8, (y or 0) / s + 8)
  menue:Show()
  return menue
end

-- Rechtsklick-Menü für ein Item: "Mehr Information" öffnet die Item-Details im Reiter "Items"
function UI.ItemMenue(id)
  id = tonumber(id)
  if not id then return end
  GameTooltip:Hide()
  local name = WW.ItemName and WW.ItemName(id) or ("Item " .. id)
  return UI.Menue({
    { text = WW.f("titel", name) },
    { text = "Mehr Information", aktion = function() WW:ItemZeigen(id) end },
  })
end

-- Preis-Grafik (wie bei Preisvergleich-Seiten): oben eine Linie mit dem günstigsten Preis pro Tag
-- (letzte 30 Tage), unten Balken mit dem mittleren Preis je Uhrzeit (0-23 Uhr).
-- g:Setze(daten) mit daten aus WW.AH.Grafikdaten(id); gibt false zurück, wenn es nichts zu zeigen gibt.
UI.GRAFIK_HOEHE = 176
function UI.PreisGrafik(parent, breite)
  local H = UI.GRAFIK_HOEHE
  local g = CreateFrame("Frame", nil, parent)
  g:SetSize(breite, H)
  local LINKS = 86                      -- Platz für die Preis-Beschriftung (z. B. 12g 34s 56c)
  local W = breite - LINKS - 4
  local L_OBEN, L_H = 16, 62            -- Linienfeld
  local B_OBEN, B_H = 112, 44           -- Balkenfeld

  local function text(groesse, x, y, punkt)
    local t = UI.Text(g, groesse or "klein", 0.8, 0.8, 0.8)
    t:SetPoint(punkt or "TOPLEFT", g, "TOPLEFT", x, y)
    return t
  end
  local t1 = text("klein", 0, 0)
  t1:SetText(WW.f("titel", "Günstigster Preis pro Tag") .. WW.f("grau", " (letzte 30 Tage)"))
  local t2 = text("klein", 0, -(B_OBEN - 16))
  t2:SetText(WW.f("titel", "Preis nach Uhrzeit") .. WW.f("grau", " (Mittel, grün = günstig)"))

  local function feld(oben, hoehe)
    local f = g:CreateTexture(nil, "BACKGROUND")
    f:SetPoint("TOPLEFT", g, "TOPLEFT", LINKS, -oben)
    f:SetSize(W, hoehe)
    f:SetColorTexture(1, 1, 1, 0.05)
  end
  feld(L_OBEN, L_H)
  feld(B_OBEN, B_H)

  local yMax, yMin = text("klein", 0, -L_OBEN), text("klein", 0, -(L_OBEN + L_H - 10))
  local xLinks, xRechts = text("klein", LINKS, -(L_OBEN + L_H + 2)), text("klein", LINKS + W - 40, -(L_OBEN + L_H + 2))
  local leer = text("klein", LINKS + 8, -(L_OBEN + 22))
  leer:SetWidth(W - 16)
  local bMax = text("klein", 0, -B_OBEN)
  for _, t in ipairs({ yMax, yMin, bMax }) do   -- Preis links neben dem Feld, nie hinein
    t:SetWidth(LINKS - 4)
    t:SetJustifyH("RIGHT")
    if t.SetWordWrap then t:SetWordWrap(false) end
  end
  local uhr = {}
  for _, h in ipairs({ 0, 6, 12, 18 }) do
    uhr[h] = text("klein", LINKS + h * (W / 24), -(B_OBEN + B_H + 2))
    uhr[h]:SetText(h .. " Uhr")
  end

  -- gestrichelte Linie "üblicher Mindestpreis"
  local ueblich = g:CreateTexture(nil, "ARTWORK")
  ueblich:SetHeight(1)
  ueblich:SetColorTexture(0.7, 0.7, 0.7, 0.5)

  local punkte, linien, balken = {}, {}, {}
  local function punkt(i)
    local p = punkte[i]
    if not p then
      p = g:CreateTexture(nil, "OVERLAY")
      p:SetSize(4, 4)
      p:SetColorTexture(0.4, 0.8, 1, 1)
      punkte[i] = p
    end
    return p
  end
  local function linie(i)
    if not g.CreateLine then return nil end
    local l = linien[i]
    if not l then
      l = g:CreateLine(nil, "ARTWORK")
      if l.SetThickness then l:SetThickness(2) end
      if l.SetColorTexture then l:SetColorTexture(0.4, 0.8, 1, 0.9) end
      linien[i] = l
    end
    return l
  end
  for h = 0, 23 do
    local b = g:CreateTexture(nil, "ARTWORK")
    b:SetWidth(math.max(2, W / 24 - 2))
    balken[h] = b
  end

  function g:Setze(d)
    for _, p in pairs(punkte) do p:Hide() end
    for _, l in pairs(linien) do l:Hide() end
    for h = 0, 23 do balken[h]:Hide() end
    ueblich:Hide()
    if type(d) ~= "table" then self:Hide() return false end
    local heute = tonumber(d.heute) or 0
    local start = heute - 29
    -- Tage im Fenster
    local tage = {}
    for _, t in ipairs(d.tage or {}) do
      if t[1] >= start and t[1] <= heute and t[2] and t[2] > 0 then tage[#tage + 1] = t end
    end
    local stunden, nStunden = d.stunden or {}, 0
    for h = 0, 23 do if stunden[h] then nStunden = nStunden + 1 end end
    if #tage == 0 and nStunden == 0 then self:Hide() return false end
    self:Show()

    -- Linie
    local lo, hi
    for _, t in ipairs(tage) do
      lo = (not lo or t[2] < lo) and t[2] or lo
      hi = (not hi or t[2] > hi) and t[2] or hi
    end
    local nm = tonumber(d.normalMin)
    if lo and nm and nm > 0 then lo, hi = math.min(lo, nm), math.max(hi, nm) end
    xLinks:SetText(date("%d.%m.", start * 86400 + 43200))
    xRechts:SetText("heute")
    if #tage >= 1 then
      if hi == lo then hi, lo = hi * 1.1 + 1, lo * 0.9 end
      local function xy(tag, preis)
        local x = LINKS + (tag - start) / 29 * W
        local y = -(L_OBEN + L_H - (preis - lo) / (hi - lo) * L_H)
        return x, y
      end
      local vx, vy
      for i, t in ipairs(tage) do
        local x, y = xy(t[1], t[2])
        local p = punkt(i)
        p:ClearAllPoints()
        p:SetPoint("CENTER", g, "TOPLEFT", x, y)
        p:Show()
        if vx then
          local l = linie(i)
          if l then
            l:SetStartPoint("TOPLEFT", g, vx, vy)
            l:SetEndPoint("TOPLEFT", g, x, y)
            l:Show()
          end
        end
        vx, vy = x, y
      end
      if nm and nm > 0 then
        local _, y = xy(start, nm)
        ueblich:ClearAllPoints()
        ueblich:SetPoint("TOPLEFT", g, "TOPLEFT", LINKS, y)
        ueblich:SetWidth(W)
        ueblich:Show()
      end
      yMax:SetText(WW.Geld(math.floor(hi + 0.5)))
      yMin:SetText(WW.Geld(math.floor(lo + 0.5)))
      leer:SetText(#tage < 2 and WW.f("grau", "Erst 1 Tag. Die Linie wächst mit jedem Tag, an dem du scannst.") or "")
    else
      yMax:SetText("")
      yMin:SetText("")
      leer:SetText(WW.f("grau", "Noch keine Tagespreise. Sie werden ab jetzt bei jedem Scan gespeichert."))
    end

    -- Balken
    local bLo, bHi
    for h = 0, 23 do
      local p = stunden[h]
      if p then
        bLo = (not bLo or p < bLo) and p or bLo
        bHi = (not bHi or p > bHi) and p or bHi
      end
    end
    local jetzt = tonumber(date("%H")) or -1
    if bHi then
      bMax:SetText(WW.Geld(math.floor(bHi + 0.5)))
      for h = 0, 23 do
        local p = stunden[h]
        if p then
          local anteil = (bHi > bLo) and (p - bLo) / (bHi - bLo) or 0.5
          local b = balken[h]
          b:ClearAllPoints()
          b:SetPoint("BOTTOMLEFT", g, "TOPLEFT", LINKS + h * (W / 24) + 1, -(B_OBEN + B_H))
          b:SetHeight(math.max(2, (0.25 + 0.75 * (p / bHi)) * B_H))
          -- günstig grün, teuer rot; die aktuelle Stunde heller
          local a = (h == jetzt) and 1 or 0.75
          b:SetColorTexture(0.2 + 0.8 * anteil, 0.9 - 0.6 * anteil, 0.2, a)
          b:Show()
        end
      end
    else
      bMax:SetText("")
    end
    return true
  end
  return g
end

-- Tooltip für ein Item an einem Rahmen zeigen.
function UI.ItemTooltip(rahmen, itemID)
  if not itemID then return end
  GameTooltip:SetOwner(rahmen, "ANCHOR_RIGHT")
  GameTooltip:SetHyperlink("item:" .. itemID)
  GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Hauptfenster
---------------------------------------------------------------------------
local fenster
local reiter = {}       -- Hauptreiter: { schluessel, titel, reihenfolge, bauen, panel, knopf, kinder }
local unter = {}        -- [schluessel] = Unterreiter: { schluessel, titel, reihenfolge, bauen, eltern, panel, knopf }
local aktiv             -- Schlüssel des sichtbaren Reiters (bei Unterreitern der Unterreiter)
local aktivHaupt        -- Schlüssel des sichtbaren Hauptreiters
local UNTER_ZEILE = 28  -- Höhe der Knopfzeile für Unterreiter
WW.UNTER_HOEHE = WW.INHALT_HOEHE - UNTER_ZEILE

local function hauptReiter(schluessel)
  for _, r in ipairs(reiter) do if r.schluessel == schluessel then return r end end
end

-- Modul meldet einen Reiter an. bauen(panel) läuft beim ersten Öffnen.
-- panel:OnZeigen() (optional) läuft bei jedem Öffnen des Reiters.
-- eltern (optional): Schlüssel eines Hauptreiters; dann ist es ein Unterreiter in dessen Knopfzeile.
--   Ein Unterreiter-Panel ist WW.UNTER_HOEHE hoch (nicht WW.INHALT_HOEHE): Höhe mit p:GetHeight() lesen.
-- Ein Hauptreiter ohne bauen ist nur ein Behälter für seine Unterreiter.
function WW:Reiter(schluessel, titel, reihenfolge, bauen, eltern)
  if eltern then
    unter[schluessel] = { schluessel = schluessel, titel = titel, reihenfolge = reihenfolge, bauen = bauen, eltern = eltern }
    return
  end
  table.insert(reiter, { schluessel = schluessel, titel = titel, reihenfolge = reihenfolge, bauen = bauen })
  table.sort(reiter, function(a, b) return a.reihenfolge < b.reihenfolge end)
end

-- Unterreiter eines Hauptreiters, sortiert
local function kinderVon(schluessel)
  local k = {}
  for _, u in pairs(unter) do if u.eltern == schluessel then k[#k + 1] = u end end
  table.sort(k, function(a, b) return a.reihenfolge < b.reihenfolge end)
  return k
end

-- Fehler eines Reiters im Chat zeigen (WoW blendet Lua-Fehler oft aus).
local function meldeFehler(titel, err)
  local erste = tostring(err):match("^[^\n]+") or tostring(err)
  WW:Print(WW.f("rot", "Fehler im Reiter " .. titel .. ": ") .. erste)
  if geterrorhandler then pcall(geterrorhandler(), err) end
end

local function mitStapel(e) return tostring(e) .. "\n" .. (debugstack and debugstack(2) or "") end

-- Panel bauen (einmal) und zeigen, dann OnZeigen
local function panelZeigen(r, eltern, x, y, h)
  if not r.panel then
    r.panel = CreateFrame("Frame", nil, eltern)
    r.panel:SetPoint("TOPLEFT", x, y)
    r.panel:SetSize(WW.INHALT_BREITE, h)
    if r.bauen then
      local ok, err = xpcall(function() r.bauen(r.panel) end, mitStapel)
      if not ok then meldeFehler(r.titel, err) end
    end
  end
  r.panel:Show()
  if r.panel.OnZeigen then
    local ok, err = xpcall(function() r.panel:OnZeigen() end, mitStapel)
    if not ok then meldeFehler(r.titel, err) end
  end
end

-- Knopfzeile der Unterreiter oben im Hauptreiter (einmal gebaut)
local zeigeReiter
local function knopfZeile(haupt)
  if haupt.kinder then return end
  haupt.kinder = kinderVon(haupt.schluessel)
  local x = 0
  for _, u in ipairs(haupt.kinder) do
    local k = UI.Knopf(haupt.panel, u.titel, 110, function() zeigeReiter(u.schluessel) end)
    k:SetPoint("TOPLEFT", x, 0)
    u.knopf = k
    x = x + 114
  end
end

zeigeReiter = function(schluessel)
  local u = unter[schluessel]
  local haupt = hauptReiter(u and u.eltern or schluessel)
  if not haupt then return end
  -- Hauptreiter mit Unterreitern: ohne Wahl den zuletzt gezeigten Unterreiter nehmen
  if not u and #kinderVon(haupt.schluessel) > 0 then
    local merk = type(WW.db.fenster.unter) == "table" and WW.db.fenster.unter[haupt.schluessel]
    u = (merk and unter[merk] and unter[merk].eltern == haupt.schluessel) and unter[merk] or kinderVon(haupt.schluessel)[1]
  end
  -- Erst alle anderen verstecken, damit nie zwei Seiten übereinander liegen.
  for _, r in ipairs(reiter) do
    if r ~= haupt then
      if r.panel then r.panel:Hide() end
      r.knopf:UnlockHighlight()
    end
  end
  haupt.knopf:LockHighlight()
  aktivHaupt = haupt.schluessel
  aktiv = u and u.schluessel or haupt.schluessel
  WW.db.fenster.reiter = aktiv
  panelZeigen(haupt, fenster, 12, -66, WW.INHALT_HOEHE)
  if u then
    knopfZeile(haupt)
    if type(WW.db.fenster.unter) ~= "table" then WW.db.fenster.unter = {} end
    WW.db.fenster.unter[haupt.schluessel] = u.schluessel
    for _, k in ipairs(haupt.kinder) do
      if k ~= u then
        if k.panel then k.panel:Hide() end
        k.knopf:UnlockHighlight()
      end
    end
    u.knopf:LockHighlight()
    panelZeigen(u, haupt.panel, 0, -UNTER_ZEILE, WW.UNTER_HOEHE)
  end
end

local angedockt   -- Rahmen, an dem das Fenster gerade liegt (Blizzards Auktionshaus), sonst nil

-- Fenster an die gespeicherte Stelle setzen
local function setzePosition()
  fenster:ClearAllPoints()
  local pos = WW.db.fenster.pos
  if pos then
    fenster:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
  else
    fenster:SetPoint("CENTER")
  end
end

local function baueFenster()
  fenster = CreateFrame("Frame", "WegweiserFenster", UIParent, "BasicFrameTemplateWithInset")
  fenster:SetSize(BREITE, HOEHE)
  fenster:SetFrameStrata("HIGH")
  fenster:SetToplevel(true)
  fenster:SetClampedToScreen(true)
  fenster:SetMovable(true)
  fenster:EnableMouse(true)
  fenster:RegisterForDrag("LeftButton")
  fenster:SetScript("OnDragStart", fenster.StartMoving)
  fenster:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    WW.db.fenster.pos = { p, rp, x, y }
    angedockt = nil   -- selbst verschoben: gilt ab jetzt als normale Stelle
  end)
  setzePosition()
  -- Geschlossen (X, Esc, Abdocken): nicht mehr angedockt, zurück an die gespeicherte Stelle
  fenster:HookScript("OnHide", function()
    if angedockt then
      angedockt = nil
      setzePosition()
    end
  end)
  local titel = fenster.TitleText or (fenster.TitleContainer and fenster.TitleContainer.TitleText)
  if not titel then
    titel = fenster:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    titel:SetPoint("TOP", 0, -5)
  end
  titel:SetText("Wegweiser")
  tinsert(UISpecialFrames, "WegweiserFenster")

  -- Reiter-Knöpfe so breit, dass alle in eine Zeile passen (höchstens 120).
  -- Unter 90 Pixel: kleinere Schrift, damit lange Namen ("Einstellungen") noch passen.
  local n = math.max(1, #reiter)
  local knopfBreite = math.min(120, math.floor((BREITE - 24 - (n - 1) * 4) / n))
  local x = 12
  for _, r in ipairs(reiter) do
    local k = UI.Knopf(fenster, r.titel, knopfBreite, function() zeigeReiter(r.schluessel) end)
    if knopfBreite < 90 and k.SetNormalFontObject then
      k:SetNormalFontObject("GameFontNormalSmall")
      k:SetHighlightFontObject("GameFontHighlightSmall")
      if k.SetDisabledFontObject then k:SetDisabledFontObject("GameFontDisableSmall") end
    end
    k:SetPoint("TOPLEFT", x, -32)
    r.knopf = k
    x = x + knopfBreite + 4
  end
  fenster:Hide()
end

-- Fenster öffnen, optional auf einem bestimmten Reiter.
function WW:Oeffnen(schluessel)
  if not fenster then baueFenster() end
  fenster:Show()
  schluessel = schluessel or aktiv or WW.db.fenster.reiter or (reiter[1] and reiter[1].schluessel)
  local gibt = unter[schluessel] ~= nil and hauptReiter(unter[schluessel].eltern) ~= nil
  for _, r in ipairs(reiter) do if r.schluessel == schluessel then gibt = true end end
  if not gibt then schluessel = reiter[1] and reiter[1].schluessel end
  if schluessel then zeigeReiter(schluessel) end
end

-- Fenster auf einen Reiter öffnen und rechts neben einen anderen Rahmen legen (Knopf "Wegweiser" am
-- Auktionshaus). Daneben, nicht darüber: sonst verdeckt es Blizzards Reiter und den Knopf selbst.
-- Die gespeicherte Stelle bleibt; WW:Abdocken() oder Schließen legt das Fenster dorthin zurück.
function WW:OeffnenAn(schluessel, rahmen)
  if not fenster then baueFenster() end
  if rahmen then
    fenster:ClearAllPoints()
    fenster:SetPoint("TOPLEFT", rahmen, "TOPRIGHT", 4, 0)
    angedockt = rahmen
  end
  WW:Oeffnen(schluessel)
end

function WW:IstAngedockt(rahmen)
  return fenster ~= nil and fenster:IsShown() and angedockt ~= nil and (not rahmen or angedockt == rahmen)
end

function WW:Abdocken()
  if not (fenster and angedockt) then return end
  fenster:Hide()   -- OnHide setzt angedockt zurück und legt das Fenster an seine Stelle
  if angedockt then angedockt = nil; setzePosition() end
end

function WW:Umschalten()
  if fenster and fenster:IsShown() then fenster:Hide() else WW:Oeffnen() end
end

-- Schlüssel des sichtbaren Reiters (Unterreiter, wenn einer offen ist), oder nil
function WW:AktiverReiter()
  if fenster and fenster:IsShown() then return aktiv end
end

function WW:IstOffen(schluessel)
  return fenster and fenster:IsShown() and (not schluessel or aktiv == schluessel or aktivHaupt == schluessel)
end

-- Für Bindings.xml
function Wegweiser_Umschalten() WW:Umschalten() end

---------------------------------------------------------------------------
-- Minimap-Knopf. Links: Fenster. Rechts: Dungeon-Karte. Ziehen: verschieben.
---------------------------------------------------------------------------
local function minimapKnopf()
  local k = CreateFrame("Button", "WegweiserMinimapKnopf", Minimap)
  k:SetSize(31, 31)
  k:SetFrameStrata("MEDIUM")
  k:SetFrameLevel(8)
  k:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  k:RegisterForDrag("LeftButton")
  k:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  local icon = k:CreateTexture(nil, "BACKGROUND")
  icon:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
  icon:SetSize(20, 20)
  icon:SetPoint("TOPLEFT", 7, -5)
  icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
  local rand = k:CreateTexture(nil, "OVERLAY")
  rand:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  rand:SetSize(53, 53)
  rand:SetPoint("TOPLEFT")

  local function setzePosition()
    local w = math.rad(WW.db.minimap.winkel or 200)
    k:ClearAllPoints()
    k:SetPoint("CENTER", Minimap, "CENTER", math.cos(w) * 80, math.sin(w) * 80)
  end
  k:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local s = Minimap:GetEffectiveScale()
      WW.db.minimap.winkel = math.deg(math.atan2(cy / s - my, cx / s - mx))
      setzePosition()
    end)
  end)
  k:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  k:SetScript("OnClick", function(_, taste)
    if taste == "RightButton" then
      if WW.DungeonKarteUmschalten then WW:DungeonKarteUmschalten() end
    else
      WW:Umschalten()
    end
  end)
  k:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Wegweiser")
    GameTooltip:AddLine("Linksklick: Fenster", 1, 1, 1)
    GameTooltip:AddLine("Rechtsklick: Dungeon-Karte", 1, 1, 1)
    GameTooltip:AddLine("Ziehen: verschieben", 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end)
  k:SetScript("OnLeave", GameTooltip_Hide)
  setzePosition()
  WW.minimapKnopf = k
  if WW.db.minimap.aus then k:Hide() end
end

WW:BeimStart(minimapKnopf)
