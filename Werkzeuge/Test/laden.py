import os, sys
from lupa.luajit21 import LuaRuntime
ROOT = sys.argv[1]
S = os.path.dirname(os.path.abspath(__file__))
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(open(os.path.join(S, "mockwow.lua"), encoding="utf-8").read())
run = lua.eval("""function(src, name, ww)
  local f, err = loadstring(src, name)
  if not f then return "SYNTAX " .. err end
  local ok, e = xpcall(function() f("Wegweiser", ww) end, debug.traceback)
  if not ok then return e end
end""")
schritt = lua.eval("""function(code, name)
  local f, err = loadstring(code, name)
  if not f then return "SYNTAX " .. err end
  local ok, e = xpcall(f, debug.traceback)
  if not ok then return e end
end""")
WW = lua.eval("{}")
lua.globals().__WW = WW
fehler = []
for zeile in open(os.path.join(ROOT, "Wegweiser.toc"), encoding="utf-8"):
    zeile = zeile.strip()
    if not zeile or zeile.startswith("#") or zeile.startswith("Libs"):
        continue
    pfad = os.path.join(ROOT, zeile.replace("\\", os.sep))
    e = run(open(pfad, "rb").read(), "@" + zeile, WW)
    if e:
        fehler.append(("LADEN " + zeile, e))

SZENEN = [
 ("ADDON_LOADED", '__FEUER("ADDON_LOADED", "Wegweiser")'),
 ("PLAYER_LOGIN", '__FEUER("PLAYER_LOGIN")'),
 ("PLAYER_ENTERING_WORLD", '__FEUER("PLAYER_ENTERING_WORLD", true, false)'),
 ("Zeit vergeht", '__UPDATE(20)'),
 ("Slash leer", 'SlashCmdList.WEGWEISER("")'),
 ("Slash hilfe", 'SlashCmdList.WEGWEISER("hilfe")'),
 ("Reiter rueckwaerts", 'local function sichtbar() local t = {} for _, f in ipairs(__FRAMES) do if f.__parent == WegweiserFenster and f.__typ == "Frame" and f.__shown and not f.__name then t[#t+1] = f end end return #t end for _, k in ipairs({"einstellungen","sammeln","dungeon","ah","items","sammeln","ah"}) do __WW:Oeffnen(k) local n = sichtbar() if n ~= 1 then error("Nach Reiter " .. k .. " sind " .. n .. " Reiter-Seiten sichtbar") end end'),
 ("Reiter mit Fehler", 'local function seiten() local t = {} for _, f in ipairs(__FRAMES) do if f.__parent == WegweiserFenster and f.__typ == "Frame" and f.__shown and not f.__name then t[#t+1] = f end end return t end __WW:Oeffnen("ah") local ah = seiten()[1] local alt = ah.OnZeigen ah.OnZeigen = function() error("Testfehler") end __WW:Oeffnen("sammeln") __WW:Oeffnen("ah") local n = #seiten() ah.OnZeigen = alt if n ~= 1 then error("Bei Fehler im Reiter sind " .. n .. " Seiten sichtbar") end'),
 ("Reiter items", '__WW:Oeffnen("items")'),
 ("Reiter ah", '__WW:Oeffnen("ah")'),
 ("Reiter dungeon", '__WW:Oeffnen("dungeon")'),
 ("Reiter sammeln", '__WW:Oeffnen("sammeln")'),
 ("Reiter einstellungen", '__WW:Oeffnen("einstellungen")'),
 ("Suche Text", 'SlashCmdList.WEGWEISER("suche Friedens")  __UPDATE(5)'),
 ("Suche Zahl", 'SlashCmdList.WEGWEISER("suche 2447")  __UPDATE(5)'),
 ("Suche englisch", 'SlashCmdList.WEGWEISER("suche peace")  __UPDATE(5)'),
 ("Bewertung", 'for _, id in ipairs({2447, 2449, 118, 999999}) do local a,b,c,d = __WW.AH.Bewertung(id, 5) __LOG[#__LOG+1] = "Bewertung " .. id .. " " .. tostring(a) .. " " .. tostring(b) end'),
 ("AH oeffnen", '__FEUER("AUCTION_HOUSE_SHOW") __FEUER("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 21)'),
 ("AH scan", 'SlashCmdList.WEGWEISER("scan") __FEUER("REPLICATE_ITEM_LIST_UPDATE") __UPDATE(60)'),
 ("Bewertung nach Scan", 'for _, id in ipairs({2448, 2449, 2450}) do local a,b,c,d = __WW.AH.Bewertung(id, 5) __LOG[#__LOG+1] = "Nach Scan " .. id .. " " .. tostring(a) .. " " .. tostring(b) .. " AH=" .. tostring(c) .. " H=" .. tostring(d) end'),
 ("AH schliessen", '__FEUER("AUCTION_HOUSE_CLOSED")'),
 ("Tasche", '__FEUER("BAG_UPDATE_DELAYED") __UPDATE(3)'),
 ("Tooltip Post", 'if __TTPOST then GameTooltip.__owner = ContainerFrame1Item1 __TTPOST(GameTooltip, { id = 2448, type = 0 }) end'),
 ("Tooltip Script", 'local f = GameTooltip:GetScript("OnTooltipSetItem") if f then GameTooltip.GetItem = function() return "Item", "|Hitem:2448|h" end f(GameTooltip) end'),
 ("Dungeon Karte", 'SlashCmdList.WEGWEISER("karte")'),
 ("Dungeon Karte 47", 'SlashCmdList.WEGWEISER("karte 47") __UPDATE(3)'),
 ("Dungeon in Instanz", '__INSTANZ_ID, __INSTANZ_TYP, __INSTANZ_NAME = 36, "party", "Die Todesminen" __FEUER("PLAYER_ENTERING_WORLD", false, false) __WW:DungeonKarteZeigen() __UPDATE(3)'),
 ("Alle Dungeons zeigen", 'for id in pairs(__WW.quelle.fdm.dungeons) do __WW:DungeonKarteZeigen(id) end for id in pairs(__WW.quelle.helper.dungeons) do __WW:DungeonKarteZeigen(id) end'),
 ("Quest-Updates", '__FEUER("QUEST_LOG_UPDATE") __FEUER("QUEST_TURNED_IN", 1101) __UPDATE(5)'),
 ("Dungeon umschalten", '__WW:DungeonKarteUmschalten() __WW:DungeonKarteUmschalten()'),
 ("Sammeln Weltkarte", 'WorldMapFrame.__shown = true WorldMapFrame.OnMapChanged(WorldMapFrame) __UPDATE(4)'),
 ("Sammeln Zonen", 'for _, m in ipairs({1411, 1412, 1429, 1436, 1440, 1446, 1448, 1452, 1423}) do __KARTE = m WorldMapFrame.GetMapID = function() return m end __FEUER("ZONE_CHANGED_NEW_AREA") WorldMapFrame.OnMapChanged(WorldMapFrame) __UPDATE(2) __LOG[#__LOG+1] = "Zone " .. m .. " Welt " .. tostring(__PINS_WELT) .. " Mini " .. tostring(__PINS_MINI) end __LOG[#__LOG+1] = "Pins Welt " .. tostring(__PINS_WELT) .. " Mini " .. tostring(__PINS_MINI)'),
 ("Sammeln Skill", '__FEUER("SKILL_LINES_CHANGED") __UPDATE(2)'),
 ("Sammeln an/aus", 'SlashCmdList.WEGWEISER("sammeln") SlashCmdList.WEGWEISER("sammeln")'),
 ("Alle Reiter nochmal", 'for _, k in ipairs({"items","ah","dungeon","sammeln","einstellungen"}) do __WW:Oeffnen(k) end __UPDATE(3)'),
 ("Klick auf alle Knoepfe", 'for _, f in ipairs(__FRAMES) do if f.__scripts.OnClick and f.__typ ~= "GameTooltip" then local ok, e = xpcall(function() f.__scripts.OnClick(f, "LeftButton") end, debug.traceback) if not ok then __LOG[#__LOG+1] = "KLICKFEHLER " .. e end end end __UPDATE(3)'),
 ("Hover auf alles", 'for _, f in ipairs(__FRAMES) do if f.__scripts.OnEnter then local ok, e = xpcall(function() f.__scripts.OnEnter(f) end, debug.traceback) if not ok then __LOG[#__LOG+1] = "HOVERFEHLER " .. e end end end'),
 ("Namen sammeln", '__UPDATE(200) local n = 0 for _ in pairs(__WW.db.namen) do n = n + 1 end __LOG[#__LOG+1] = "Namen im Speicher: " .. n'),
]
# Zusaetzliche Szenen: Dateien szenen_*.lua, je Szene ein Block "-- SZENE: Name" gefolgt von Lua-Code
import glob as _g
for _p in sorted(_g.glob(os.path.join(os.path.dirname(os.path.abspath(__file__)), "szenen_*.lua"))):
    _name, _code = None, []
    for _z in open(_p, encoding="utf-8").read().split(chr(10)) + ["-- SZENE: __ende"]:
        if _z.startswith("-- SZENE:"):
            if _name: SZENEN.append((os.path.basename(_p) + ": " + _name, chr(10).join(_code)))
            _name, _code = _z[9:].strip(), []
        else:
            _code.append(_z)
for name, code in SZENEN:
    e = schritt(code, "=" + name)
    if e:
        fehler.append((name, e))

for z in lua.globals().__LOG.values():
    print("LOG", z)
    # Fehler beim Bauen eines Reiters, bei Klicks und beim Zeigen von Tooltips landen nur im LOG.
    # Sie zaehlen als Fehler, ausser den absichtlichen ("Testfehler").
    t = str(z)
    if t.startswith(("SPIELFEHLER", "KLICKFEHLER", "HOVERFEHLER")) and "Testfehler" not in t:
        fehler.append(("LOG " + t.split(" ", 1)[0], t))
print()
if fehler:
    for n, e in fehler:
        print("=== FEHLER bei:", n)
        print(e)
        print()
else:
    print("KEINE FEHLER")
unb = sorted(lua.globals().__UNBEKANNT.keys())
print("Unbekannte API (Magie):", ", ".join(unb))
