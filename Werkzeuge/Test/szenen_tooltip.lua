-- Szenen fuer die Tooltip-Schalter (Reiter "Einstellungen", WW.TOOLTIP_SCHALTER, AH-Zeilen einzeln).
-- SZENE: Tooltip - jeder Schalter findet seine Einstellung und ist am Anfang an
for _, s in ipairs(__WW.TOOLTIP_SCHALTER) do
  local t = s[2]()
  if type(t) ~= "table" then error("Schalter ohne Einstellung: " .. s[1]) end
  if t[s[3]] == false then error("Schalter am Anfang aus: " .. s[1]) end
end

-- SZENE: Tooltip - AH-Zeilen einzeln abschalten
__TT_ALT = GameTooltip.AddLine
local zeilen = {}
GameTooltip.AddLine = function(self, text) zeilen[#zeilen + 1] = text end
local db = __WW.db
db.ah["Forever|Alliance"] = { r = "Forever", f = "Alliance", t = time(), n = 3, z = 3, m = "test", i = {
  [7001] = "1000,1200,9", [7002] = "1000,1200,9", [7003] = "1000,1200,9", [7004] = "1000,1200,9" } }
local function tip(id)
  zeilen = {}
  local f = GameTooltip.__scripts.OnTooltipCleared
  if f then f(GameTooltip) end
  GameTooltip.__owner = nil
  __WW.AH.TooltipZeilen(GameTooltip, { id = id, type = 0 })
  return table.concat(zeilen, "\n")
end
local alle = tip(7001)
if not alle:find("AH:", 1, true) then error("Preiszeile fehlt: " .. alle) end
if not alle:find("Stück im AH", 1, true) then error("Mengenzeile fehlt: " .. alle) end
db.ah.tt.preis = false
local ohnePreis = tip(7002)
if ohnePreis:find("AH:", 1, true) then error("Preiszeile trotz Schalter aus") end
if not ohnePreis:find("Stück im AH", 1, true) then error("Mengenzeile fehlt ohne Preis") end
db.ah.tt.menge = false
local ohneMenge = tip(7003)
if ohneMenge:find("Stück im AH", 1, true) then error("Mengenzeile trotz Schalter aus") end
db.ah.tt.preis, db.ah.tt.menge = true, true
db.ah.tooltip = false
local nichts = tip(7004)
if nichts ~= "" then error("AH aus, aber Zeilen: " .. nichts) end
db.ah.tooltip = true
GameTooltip.AddLine = __TT_ALT
db.ah["Forever|Alliance"] = nil

-- SZENE: Tooltip - Haken im Reiter Einstellungen schalten die Einstellung
__WW:Oeffnen("tooltip")   -- Unterreiter in den Einstellungen
if not __WW:IstOffen("tooltip") then error("Unterreiter Tooltip nicht offen") end
local function haken(text)
  for _, f in ipairs(__FRAMES) do
    if f.__typ == "CheckButton" then
      for _, g in ipairs(__FRAMES) do
        if g.__parent == f and g.__text == text then return f end
      end
      local t = f.text or f.Text
      if t and t.__text == text then return f end
    end
  end
end
local h = haken("Einstellgebühr")
if not h then error("Haken Einstellgebuehr fehlt") end
h.GetChecked = function() return false end
h.__scripts.OnClick(h)
if __WW.db.ah.tt.kaution ~= false then error("Haken hat Einstellgebuehr nicht abgeschaltet") end
h.GetChecked = function() return true end
h.__scripts.OnClick(h)
if __WW.db.ah.tt.kaution ~= true then error("Haken hat Einstellgebuehr nicht angeschaltet") end
local f = haken("Flugkarte: Flugzeit (dieser Charakter)")
if not f then error("Haken Flugzeit fehlt") end
