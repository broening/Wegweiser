-- Wegweiser: Angel-Hilfe ("Angel-Modus").
-- Solange der Spieler angelt: Effekte laut, Musik und Umgebung aus, Ton auch im Hintergrund,
-- automatisch plündern an. Kurz nach dem letzten Wurf (oder bei Kampf) kommt alles zurück.
-- Dazu ein Warnton, wenn ein Wurf ohne Fang abläuft.
-- Den Biss selbst meldet das Spiel den Addons nicht. Darum macht der Modus nur das Platschen gut hörbar.
-- Angel-Taste: eine Taste wirft aus und holt während des Wurfs den Fisch ein (siehe unten).
local ADDON, WW = ...

local A = {}
WW.Angeln = A

WW.standardDB.angeln = {
  laut = true,        -- beim Angeln: Effekte laut, Musik und Umgebung aus, Ton auch im Hintergrund
  pluendern = true,   -- beim Angeln: automatisch plündern
  warnton = true,     -- Ton, wenn der Wurf ohne Fang abläuft
  taste = true,       -- Angel-Taste: während des Wurfs holt dieselbe Taste den Fisch ein
  -- gesichert = { [cvar] = { alt = "...", neu = "..." } }  nur solange der Angel-Modus läuft
}

local NACHLAUF = 15          -- Sekunden nach dem letzten Wurf, dann kommen die alten Werte zurück
local WARN_PAUSE = 0.7       -- so lange nach dem Ende auf Beute warten, bevor der Warnton kommt
local ABGELAUFEN = 0.5       -- Wurf gilt als abgelaufen, wenn weniger als das an der vollen Zeit fehlt
local WARN_TON = 8959        -- SOUNDKIT.RAID_WARNING

-- Zauber "Angeln" (alle Ränge)
local ANGEL_ZAUBER = { [7620] = true, [7731] = true, [7732] = true, [18248] = true, [33095] = true, [131474] = true }

local function jetzt() return GetTime() end
local function einst() return WW.db and WW.db.angeln end

---------------------------------------------------------------------------
-- Spiel-Einstellungen (CVars) lesen und setzen
---------------------------------------------------------------------------
local function cvarLesen(name)
  local f = WW.Neu("C_CVar", "GetCVar") or WW.Alt("GetCVar")
  if not f then return nil end
  local ok, wert = pcall(f, name)
  if ok and wert ~= nil then return tostring(wert) end
  return nil
end

local function cvarSetzen(name, wert)
  local f = WW.Neu("C_CVar", "SetCVar") or WW.Alt("SetCVar")
  if not f then return false end
  return (pcall(f, name, tostring(wert))) and true or false
end

local function gleich(a, b)
  local x, y = tonumber(a), tonumber(b)
  if x and y then return math.abs(x - y) < 0.001 end
  return tostring(a) == tostring(b)
end

-- Welche Werte der Angel-Modus haben will (je nach Einstellung)
local function wunsch()
  local e, w = einst(), {}
  if not e then return w end
  if e.laut then
    w[#w + 1] = { "Sound_EnableAllSound", "1" }
    w[#w + 1] = { "Sound_EnableSFX", "1" }
    w[#w + 1] = { "Sound_SFXVolume", "1" }
    w[#w + 1] = { "Sound_MusicVolume", "0" }
    w[#w + 1] = { "Sound_AmbienceVolume", "0" }
    w[#w + 1] = { "Sound_EnableSoundWhenGameIsInBG", "1" }
  end
  if e.pluendern then
    w[#w + 1] = { "autoLootDefault", "1" }
  end
  -- Angel-Taste: weiche Zielwahl, damit die Interaktionstaste den Schwimmer findet (nur wenn der Client sie kennt)
  if e.taste and A.einholenMoeglich and A.einholenMoeglich() and #A.Tasten() > 0 then
    w[#w + 1] = { "SoftTargetInteract", "3" }
    -- Der Schwimmer landet bis etwa 20 Meter weit: Reichweite der weichen Zielwahl dafür groß genug
    if cvarLesen("SoftTargetInteractRange") ~= nil then w[#w + 1] = { "SoftTargetInteractRange", "30" } end
  end
  return w
end

-- Angel-Modus an: alte Werte merken (in WW.db, damit sie einen Absturz des Addons überleben), neue setzen.
function A.ein()
  local e = einst()
  if not e then return end
  e.gesichert = e.gesichert or {}
  for _, paar in ipairs(wunsch()) do
    local name, neu = paar[1], paar[2]
    if not e.gesichert[name] then
      local alt = cvarLesen(name)
      if alt ~= nil and not gleich(alt, neu) and cvarSetzen(name, neu) then
        e.gesichert[name] = { alt = alt, neu = neu }
      end
    end
  end
  A.aktiv = true
end

-- Angel-Modus aus: alte Werte zurück. Hat der Spieler einen Wert inzwischen selbst geändert, bleibt seiner.
function A.aus()
  A.aktiv = false
  local e = einst()
  local g = e and e.gesichert
  if not g then return end
  for name, w in pairs(g) do
    local ist = cvarLesen(name)
    if ist == nil or gleich(ist, w.neu) then cvarSetzen(name, w.alt) end
  end
  e.gesichert = nil
end

-- Nach einer Änderung im Reiter "Einstellungen": laufenden Modus mit den neuen Werten neu aufsetzen.
function A.einstellungNeu()
  local e = einst()
  if A.einholenAus and not (e and e.taste) then A.einholenAus() end
  if A.aktiv then
    A.aus()
    A.ein()
  end
end

---------------------------------------------------------------------------
-- Angel-Taste: eine Taste zum Auswerfen und zum Einholen.
-- Tastenbelegung "Angeln: auswerfen / Fisch einholen" (Esc > Optionen > Tastaturbelegung > Wegweiser).
--   Kein Wurf: die Taste klickt den sicheren Knopf WegweiserAngelKnopf (Zauber "Angeln").
--   Während des Wurfs: dieselbe Taste ist kurz die Interaktionstaste des Spiels (INTERACTTARGET). Mit der
--   Spiel-Einstellung SoftTargetInteract = 3 zielt sie auf den Schwimmer, ein Druck holt den Fisch ein.
-- Tasten werden nur außerhalb des Kampfs umgelegt (SetOverrideBinding ist im Kampf gesperrt) und beim Ende des
-- Wurfs zurückgesetzt. Kennt der Client die weiche Zielwahl nicht, bleibt die Taste beim Auswerfen.
---------------------------------------------------------------------------
local KNOPF = "WegweiserAngelKnopf"
local BINDUNG = "CLICK " .. KNOPF .. ":LeftButton"
_G["BINDING_NAME_" .. BINDUNG] = "Angeln: auswerfen / Fisch einholen"
A.BINDUNG = BINDUNG

local function imKampf() return InCombatLockdown and InCombatLockdown() and true or false end

-- Der sichere Knopf (beim Laden gebaut: im Kampf darf ein Addon keine sicheren Knöpfe anlegen)
local knopf = CreateFrame("Button", KNOPF, UIParent, "SecureActionButtonTemplate")
knopf:SetSize(1, 1)
knopf:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -10, -10)
knopf:SetAttribute("type", "spell")
knopf:SetAttribute("spell", "Angeln")
A.knopf = knopf

-- Eine Tastenbindung schickt einen Klick beim Drücken und einen beim Loslassen. Nur einer davon soll auswerfen:
-- der, den die Spiel-Einstellung ActionButtonUseKeyDown vorgibt (sonst startet der zweite den Wurf neu).
-- Der Knopf nimmt darum nur diese Hälfte an. Umstellen geht nur außerhalb des Kampfs.
local klickArt
function A.klicksSetzen()
  if imKampf() or not knopf.RegisterForClicks then return end
  local art = (cvarLesen("ActionButtonUseKeyDown") == "0") and "AnyUp" or "AnyDown"
  if art ~= klickArt then
    knopf:RegisterForClicks(art)
    klickArt = art
  end
end
A.klicksSetzen()
WW:Event("CVAR_UPDATE", function() A.klicksSetzen() end)

-- Zaubername in der Sprache des Clients (höchster Rang wird von selbst genommen)
WW:BeimStart(function()
  if imKampf() then return end
  knopf:SetAttribute("spell", WW.SpellName(7620) or "Angeln")
  A.klicksSetzen()
end)

-- Kann der Client den Schwimmer per Taste anvisieren? (weiche Zielwahl, ab Classic 1.14.4)
function A.einholenMoeglich()
  return cvarLesen("SoftTargetInteract") ~= nil and type(rawget(_G, "SetOverrideBinding")) == "function"
end

local besitzer = CreateFrame("Frame")
A.einholen = false
local hinweisEinholen = false

-- Tasten der Angel-Bindung (bis zu zwei)
local function tasten()
  local f = WW.Alt("GetBindingKey")
  if not f then return {} end
  local ok, a, b = pcall(f, BINDUNG)
  local t = {}
  if ok and type(a) == "string" and a ~= "" then t[#t + 1] = a end
  if ok and type(b) == "string" and b ~= "" then t[#t + 1] = b end
  return t
end
A.Tasten = tasten

function A.einholenAn()
  local e = einst()
  if not (e and e.taste) or A.einholen or imKampf() then return end
  local liste = tasten()
  if #liste == 0 then return end
  if not A.einholenMoeglich() then
    if not hinweisEinholen then
      hinweisEinholen = true
      WW:Print("Dieser Client kann den Schwimmer nicht per Taste anvisieren. Hol den Fisch mit Rechtsklick auf den Schwimmer.")
    end
    return
  end
  local setzen = rawget(_G, "SetOverrideBinding")
  for _, t in ipairs(liste) do pcall(setzen, besitzer, true, t, "INTERACTTARGET") end
  A.einholen = true
end

function A.einholenAus()
  if not A.einholen or imKampf() then return end
  local leeren = rawget(_G, "ClearOverrideBindings")
  if leeren then pcall(leeren, besitzer) end
  A.einholen = false
end

---------------------------------------------------------------------------
-- Angeln erkennen
---------------------------------------------------------------------------
-- Laufender Kanal des Spielers: name, startMS, endeMS, spellID
local function kanal()
  local f = WW.Alt("UnitChannelInfo")
  local r
  if f then
    r = { pcall(f, "player") }
  else
    f = WW.Alt("ChannelInfo")
    if not f then return nil end
    r = { pcall(f) }
  end
  if not r[1] or type(r[2]) ~= "string" then return nil end
  return r[2], tonumber(r[5]), tonumber(r[6]), tonumber(r[9])
end

local angelNamen
local function namen()
  if not angelNamen then
    angelNamen = { ["Angeln"] = true, ["Fishing"] = true }
    for id in pairs(ANGEL_ZAUBER) do
      local n = WW.SpellName(id)
      if n then angelNamen[n] = true end
    end
  end
  return angelNamen
end

local function wurfBeginnt(spellID)
  local name, start, ende, kanalID = kanal()
  if not (ANGEL_ZAUBER[spellID or 0] or ANGEL_ZAUBER[kanalID or 0] or (name and namen()[name])) then return end
  local t = jetzt()
  A.wurf = { beginn = t, dauer = (start and ende and ende > start) and (ende - start) / 1000 or nil }
  A.letzter = t
  A.warnUm = nil
  local e = einst()
  -- Modus nur, wenn er etwas umstellen soll (Laut, Plündern, weiche Zielwahl für die Taste)
  if not e or A.aktiv or #wunsch() == 0 then
    A.einholenAn()
    return
  end
  if InCombatLockdown and InCombatLockdown() then return end
  A.ein()
  A.einholenAn()
  if not A.hinweisGezeigt then
    A.hinweisGezeigt = true
    WW:Print("Angel-Modus an. " .. (e.laut and "Musik und Umgebung sind beim Angeln aus, das Platschen ist laut. " or "")
      .. "Schalter: Reiter \"Einstellungen\" oder /ww angeln.")
  end
end

local function wurfEndet()
  A.einholenAus()   -- Taste wirft wieder aus
  local w = A.wurf
  if not w then return end
  A.wurf = nil
  local t = jetzt()
  A.letzter = t
  -- Nur ein Wurf, der bis zum Ende lief, ist "ohne Fang abgelaufen" (kein Abbruch, kein neuer Wurf).
  if w.dauer and t - w.beginn >= w.dauer - ABGELAUFEN then
    A.warnUm = t + WARN_PAUSE
  end
end

function A.warne()
  local e = einst()
  if not (e and e.warnton) then return end
  local kit = rawget(_G, "SOUNDKIT")
  local ton = type(kit) == "table" and tonumber(rawget(kit, "RAID_WARNING")) or WARN_TON
  local spiele = WW.Alt("PlaySound")
  if spiele then pcall(spiele, ton, "Master") end
  local meldung = rawget(_G, "UIErrorsFrame")
  if type(meldung) == "table" and type(meldung.AddMessage) == "function" then
    pcall(meldung.AddMessage, meldung, "Wurf vorbei - neu auswerfen", 1, 0.82, 0)
  end
end

local function spellID(a3, a5) return tonumber(a3) or tonumber(a5) end

WW:Event("UNIT_SPELLCAST_CHANNEL_START", function(unit, a2, a3, a4, a5)
  if unit == "player" then wurfBeginnt(spellID(a3, a5)) end
end)
WW:Event("UNIT_SPELLCAST_CHANNEL_STOP", function(unit)
  if unit == "player" then wurfEndet() end
end)

-- Beute: der Wurf hatte einen Fang, also kein Warnton
local function beute() A.warnUm = nil end
WW:Event("LOOT_READY", beute)
WW:Event("LOOT_OPENED", beute)

-- Kampf: sofort alles zurück, damit man den Kampf normal hört
WW:Event("PLAYER_REGEN_DISABLED", function()
  A.wurf, A.warnUm = nil, nil
  A.einholenAus()   -- geht hier noch: das Ereignis kommt, bevor der Kampf Tasten sperrt
  if A.aktiv then A.aus() end
end)
-- Falls die Taste im Kampf umgelegt blieb: nach dem Kampf zurück
WW:Event("PLAYER_REGEN_ENABLED", function()
  A.klicksSetzen()
  -- Wurf läuft nach dem Kampf noch: Zustand neu aufbauen, die Taste holt wieder ein
  local name, start, ende, id = kanal()
  if name and (ANGEL_ZAUBER[id or 0] or namen()[name]) then
    local t = jetzt()
    A.wurf = A.wurf or { beginn = (start and start / 1000) or t, dauer = (start and ende and ende > start) and (ende - start) / 1000 or nil }
    A.letzter = t
    A.einholenAn()
  else
    A.einholenAus()
  end
end)

WW:Event("PLAYER_LOGOUT", function() A.aus() end)

-- Reste vom letzten Mal (Spiel hart beendet, während der Modus lief): alte Werte zurück
function A.beimStart()
  local e = einst()
  if e and e.gesichert then A.aus() end
end
WW:BeimStart(A.beimStart)

function A.takt()
  local t = jetzt()
  if A.warnUm and t >= A.warnUm then
    A.warnUm = nil
    A.warne()
  end
  -- Ende des Wurfs verpasst (z. B. Ladebildschirm): Wurf vergessen
  local w = A.wurf
  if w and t - w.beginn > (w.dauer or 30) + 5 then
    A.wurf = nil
    A.letzter = t
    A.einholenAus()
  end
  if A.aktiv and not A.wurf and t - (A.letzter or 0) >= NACHLAUF then A.aus() end
end

local uhrwerk = CreateFrame("Frame")
local takt = 0
uhrwerk:SetScript("OnUpdate", function(_, vergangen)
  takt = takt + (vergangen or 0)
  if takt < 0.2 then return end
  takt = 0
  local ok, err = pcall(A.takt)
  if not ok and geterrorhandler then geterrorhandler()(err) end
end)

WW:Befehl("angeln", "Laut-Modus beim Angeln an/aus", function()
  local e = einst()
  if not e then return end
  e.laut = not e.laut
  A.einstellungNeu()
  WW:Print("Laut-Modus beim Angeln: " .. (e.laut and WW.f("gruen", "an") or WW.f("rot", "aus")))
end)
