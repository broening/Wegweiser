-- SZENE: Angeln - Vorbereitung (CVars, Zeit, Kanal, Ton)
__AN = { t = 1000, toene = 0, kanal = nil }
__AN.cvar = { Sound_EnableAllSound = "1", Sound_EnableSFX = "1", Sound_SFXVolume = "0.4", Sound_MusicVolume = "0.6",
  Sound_AmbienceVolume = "0.5", Sound_EnableSoundWhenGameIsInBG = "0", autoLootDefault = "0" }
__AN.altZeit, __AN.altTon = GetTime, PlaySound
GetTime = function() return __AN.t end
GetCVar = function(n) return __AN.cvar[n] end
SetCVar = function(n, w) __AN.cvar[n] = tostring(w) end
PlaySound = function() __AN.toene = __AN.toene + 1 end
UnitChannelInfo = function() local k = __AN.kanal if k then return k.name, "", 136245, k.start, k.ende, false, false, k.id end end
-- Wurf beginnen (20 s Kanal) / beenden; Zeit vergehen lassen
function __WURF(id, name)
  __AN.kanal = { name = name or "Angeln", id = id or 7620, start = __AN.t * 1000, ende = (__AN.t + 20) * 1000 }
  __FEUER("UNIT_SPELLCAST_CHANNEL_START", "player", "Cast-4-1", id or 7620)
end
function __WURF_ENDE()
  __AN.kanal = nil
  __FEUER("UNIT_SPELLCAST_CHANNEL_STOP", "player", "Cast-4-1", 7620)
end
function __WARTE(sek) __AN.t = __AN.t + sek __UPDATE(2) end
function __CV(n) return __AN.cvar[n] end
local e = __WW.db.angeln
if not (e and e.laut and e.pluendern and e.warnton) then error("Standardwerte fehlen") end
if __WW.Angeln.aktiv then error("Angel-Modus schon vor dem ersten Wurf an") end

-- SZENE: Angeln - Wurf: Effekte laut, Musik und Umgebung aus, Hintergrund-Ton an, automatisch plündern
__WURF()
if not __WW.Angeln.aktiv then error("Angel-Modus nicht an") end
if __CV("Sound_SFXVolume") ~= "1" then error("Effekte nicht laut: " .. __CV("Sound_SFXVolume")) end
if __CV("Sound_MusicVolume") ~= "0" then error("Musik nicht aus") end
if __CV("Sound_AmbienceVolume") ~= "0" then error("Umgebung nicht aus") end
if __CV("Sound_EnableSoundWhenGameIsInBG") ~= "1" then error("Ton im Hintergrund nicht an") end
if __CV("autoLootDefault") ~= "1" then error("Automatisch plündern nicht an") end
local g = __WW.db.angeln.gesichert
if not (g and g.Sound_MusicVolume and g.Sound_MusicVolume.alt == "0.6") then error("Alter Wert nicht gemerkt") end
if g.Sound_EnableSFX then error("Wert gemerkt, der schon passte") end

-- SZENE: Angeln - Fang nach 8 s: kein Warnton; neuer Wurf: Modus bleibt, alte Werte bleiben gemerkt
__WARTE(8)
__WURF_ENDE()
__FEUER("LOOT_READY", true)
__WARTE(2)
if __AN.toene ~= 0 then error("Warnton trotz Fang") end
__WURF()
if __WW.db.angeln.gesichert.Sound_MusicVolume.alt ~= "0.6" then error("Gemerkter Wert überschrieben") end

-- SZENE: Angeln - neuer Wurf mitten im alten (Abbruch): kein Warnton
__WARTE(5)
__WURF_ENDE()
__WURF()
__WARTE(2)
if __AN.toene ~= 0 then error("Warnton bei Abbruch") end

-- SZENE: Angeln - Wurf läuft ab ohne Fang: genau ein Warnton
__WARTE(18)
__WURF_ENDE()
__WARTE(1)
if __AN.toene ~= 1 then error("Warntöne: " .. __AN.toene .. " statt 1") end
__WARTE(3)
if __AN.toene ~= 1 then error("Warnton doppelt") end
if not __WW.Angeln.aktiv then error("Modus zu früh aus") end

-- SZENE: Angeln - 15 s nach dem letzten Wurf: alles zurück
__WARTE(13)
if __WW.Angeln.aktiv then error("Modus nach Nachlauf noch an") end
if __CV("Sound_SFXVolume") ~= "0.4" or __CV("Sound_MusicVolume") ~= "0.6" or __CV("Sound_AmbienceVolume") ~= "0.5" then error("Lautstärken nicht zurück") end
if __CV("Sound_EnableSoundWhenGameIsInBG") ~= "0" or __CV("autoLootDefault") ~= "0" then error("Schalter nicht zurück") end
if __WW.db.angeln.gesichert then error("gesichert nicht geleert") end

-- SZENE: Angeln - anderer Kanal (kein Angeln): nichts passiert
__WURF(5143, "Arkane Geschosse")
if __WW.Angeln.aktiv or __CV("Sound_MusicVolume") ~= "0.6" then error("Fremder Kanal schaltet Angel-Modus") end
__WURF_ENDE()

-- SZENE: Angeln - Erkennung über den Namen, wenn die Zauber-ID unbekannt ist
__WURF(999999, "Angeln")
if not __WW.Angeln.aktiv then error("Angeln über den Namen nicht erkannt") end

-- SZENE: Angeln - Spieler ändert die Musik selbst: sein Wert bleibt
SetCVar("Sound_MusicVolume", "0.3")
__WURF_ENDE()
__WARTE(16)
if __CV("Sound_MusicVolume") ~= "0.3" then error("Wert des Spielers überschrieben: " .. __CV("Sound_MusicVolume")) end
if __CV("Sound_SFXVolume") ~= "0.4" then error("Effekte nicht zurück") end
SetCVar("Sound_MusicVolume", "0.6")

-- SZENE: Angeln - Kampf: sofort zurück, kein Warnton
__WURF()
__WARTE(19.8)
__WURF_ENDE()
__FEUER("PLAYER_REGEN_DISABLED")
if __WW.Angeln.aktiv or __CV("Sound_MusicVolume") ~= "0.6" then error("Im Kampf nicht zurück") end
__WARTE(2)
if __AN.toene ~= 1 then error("Warnton im Kampf") end

-- SZENE: Angeln - Laut-Modus aus (/ww angeln): nur automatisch plündern ändert sich
SlashCmdList.WEGWEISER("angeln")
if __WW.db.angeln.laut then error("/ww angeln schaltet nicht um") end
__WURF()
if __CV("Sound_MusicVolume") ~= "0.6" or __CV("Sound_SFXVolume") ~= "0.4" then error("Ton geändert trotz Laut-Modus aus") end
if __CV("autoLootDefault") ~= "1" then error("Automatisch plündern fehlt") end

-- SZENE: Angeln - Schalter während des Angelns: Laut-Modus an wirkt sofort
SlashCmdList.WEGWEISER("angeln")
if __CV("Sound_MusicVolume") ~= "0" then error("Laut-Modus wirkt nicht sofort") end
__WURF_ENDE()
__WARTE(16)
if __CV("Sound_MusicVolume") ~= "0.6" or __CV("autoLootDefault") ~= "0" then error("Nach Umschalten nicht zurück") end

-- SZENE: Angeln - alles aus: kein Modus, kein Warnton
local e = __WW.db.angeln
e.laut, e.pluendern, e.warnton = false, false, false
__WURF()
if __WW.Angeln.aktiv then error("Modus an, obwohl alles aus ist") end
__WARTE(20)
__WURF_ENDE()
__WARTE(1)
if __AN.toene ~= 1 then error("Warnton trotz Einstellung aus") end
e.laut, e.pluendern, e.warnton = true, true, true

-- SZENE: Angeln - Reste nach hartem Ende: beim Start zurück
__WURF()
__WW.Angeln.aktiv, __WW.Angeln.wurf = false, nil
if __CV("Sound_MusicVolume") ~= "0" then error("Vorbereitung falsch") end
__WW.Angeln.beimStart()
if __CV("Sound_MusicVolume") ~= "0.6" or __WW.db.angeln.gesichert then error("Reste beim Start nicht zurückgestellt") end

-- SZENE: Angeln - Ausloggen im Angel-Modus: zurück
__WURF()
__FEUER("PLAYER_LOGOUT")
if __CV("Sound_MusicVolume") ~= "0.6" or __WW.db.angeln.gesichert then error("Beim Ausloggen nicht zurück") end
__WW.Angeln.wurf = nil

-- SZENE: Angeln - Schalter im Reiter Einstellungen
__WW:Oeffnen("einstellungen")
local n = 0
for _, f in ipairs(__FRAMES) do
  if f.__typ == "CheckButton" and f.Text and tostring(f.Text.__text):find("Platschen laut") then
    n = n + 1
    f:SetChecked(false) f:Click()
    if __WW.db.angeln.laut then error("Haken schaltet nicht aus") end
    f:SetChecked(true) f:Click()
    if not __WW.db.angeln.laut then error("Haken schaltet nicht an") end
  end
end
if n ~= 1 then error("Haken 'Platschen laut': " .. n .. " statt 1") end

-- SZENE: Angeln - Angel-Taste: auswerfen per Knopf, waehrend des Wurfs einholen, Kampf, alter Client
do
  local function gleich(ist, soll, was) if ist ~= soll then error(was .. ": erwartet " .. tostring(soll) .. ", war " .. tostring(ist), 2) end end
  local A = __WW.Angeln
  local e = __WW.db.angeln
  local log = {}
  local altBK, altSO, altCO, altKampf = rawget(_G, "GetBindingKey"), rawget(_G, "SetOverrideBinding"), rawget(_G, "ClearOverrideBindings"), InCombatLockdown
  GetBindingKey = function(b) if b == A.BINDUNG then return "F" end end
  SetOverrideBinding = function(_, _, taste, aktion) log[#log + 1] = "setze " .. taste .. " " .. aktion end
  ClearOverrideBindings = function() log[#log + 1] = "leere" end
  local kampf = false
  InCombatLockdown = function() return kampf end
  __AN.cvar.SoftTargetInteract = "0"
  local function hat(t) for _, x in ipairs(log) do if x == t then return true end end return false end
  -- 1. Wurf: Taste F wird Interaktionstaste, weiche Zielwahl an; Ende: zurueck
  A.aus()
  __WARTE(30)
  __WURF()
  if not hat("setze F INTERACTTARGET") then error("Taste beim Wurf nicht umgelegt: " .. table.concat(log, "; ")) end
  gleich(__CV("SoftTargetInteract"), "3", "weiche Zielwahl beim Angeln")
  __WARTE(5)
  __WURF_ENDE()
  if not hat("leere") then error("Taste nach dem Wurf nicht zurueck") end
  gleich(A.einholen, false, "einholen aus nach dem Wurf")
  __WARTE(20)
  gleich(__CV("SoftTargetInteract"), "0", "weiche Zielwahl nach dem Angeln zurueck")
  -- 2. Kampf beginnt waehrend des Wurfs: Taste sofort zurueck
  log = {}
  __WURF()
  __FEUER("PLAYER_REGEN_DISABLED")
  if not hat("leere") then error("Taste bei Kampfbeginn nicht zurueck") end
  __WURF_ENDE()
  -- 3. im Kampf (Wurf erkannt): nichts umlegen
  log = {}
  kampf = true
  __WURF()
  kampf = false
  if hat("setze F INTERACTTARGET") then error("Taste im Kampf umgelegt") end
  __WURF_ENDE()
  -- 4. Haken aus: nichts umlegen
  log = {}
  e.taste = false
  __WARTE(30)
  __WURF()
  if hat("setze F INTERACTTARGET") then error("Taste umgelegt, obwohl der Haken aus ist") end
  __WURF_ENDE()
  e.taste = true
  -- 5. alter Client ohne weiche Zielwahl: nichts umlegen, ein Hinweis
  log = {}
  __AN.cvar.SoftTargetInteract = nil
  __WARTE(30)
  __WURF()
  if hat("setze F INTERACTTARGET") then error("Taste umgelegt ohne weiche Zielwahl") end
  __WURF_ENDE()
  -- 6. Knopf: nimmt nur die Klick-Haelfte an, die ActionButtonUseKeyDown vorgibt; im Kampf wird nichts umgestellt
  local k = A.knopf
  local klicks
  k.RegisterForClicks = function(_, art) klicks = art end
  __AN.cvar.ActionButtonUseKeyDown = "0"
  A.klicksSetzen()
  gleich(klicks, "AnyUp", "KeyDown aus: nur Loslassen")
  __AN.cvar.ActionButtonUseKeyDown = "1"
  A.klicksSetzen()
  gleich(klicks, "AnyDown", "KeyDown an: nur Druecken")
  __AN.cvar.ActionButtonUseKeyDown = "0"
  kampf = true
  __FEUER("CVAR_UPDATE", "ActionButtonUseKeyDown")
  gleich(klicks, "AnyDown", "im Kampf nicht umgestellt")
  kampf = false
  __FEUER("PLAYER_REGEN_ENABLED")
  gleich(klicks, "AnyUp", "nach dem Kampf: nur Loslassen")
  if k.__scripts.PreClick then error("PreClick schaltet noch den Zauber um") end
  -- 7. Kampf mitten im Wurf, danach laeuft der Wurf weiter: Taste holt wieder ein
  log = {}
  __AN.cvar.SoftTargetInteract = "0"
  __WARTE(30)
  __WURF()
  __FEUER("PLAYER_REGEN_DISABLED")
  log = {}
  __FEUER("PLAYER_REGEN_ENABLED")
  if not hat("setze F INTERACTTARGET") then error("nach dem Kampf holt die Taste nicht mehr ein") end
  if not A.wurf then error("Wurf nach dem Kampf vergessen") end
  -- 8. Haken mitten im Wurf aus: Taste sofort zurueck
  log = {}
  e.taste = false
  A.einstellungNeu()
  if not hat("leere") then error("Haken aus: Taste bleibt Interaktionstaste") end
  e.taste = true
  __WURF_ENDE()
  -- 9. keine Taste belegt: weiche Zielwahl bleibt unveraendert
  GetBindingKey = function() return nil end
  __WARTE(30)
  __WURF()
  gleich(__CV("SoftTargetInteract"), "0", "ohne Taste keine weiche Zielwahl")
  __WURF_ENDE()
  GetBindingKey = function(b) if b == A.BINDUNG then return "F" end end
  -- aufraeumen
  k.RegisterForClicks = nil
  __AN.cvar.ActionButtonUseKeyDown = nil
  GetBindingKey, SetOverrideBinding, ClearOverrideBindings, InCombatLockdown = altBK, altSO, altCO, altKampf
  A.aus()
  __WARTE(30)
end

-- SZENE: Angeln - Aufraeumen
GetTime, PlaySound = __AN.altZeit, __AN.altTon
GetCVar, SetCVar, UnitChannelInfo = nil, nil, nil
__AN.kanal = nil
