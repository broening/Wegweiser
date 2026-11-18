-- Grobe Nachbildung der WoW-API, um Wegweiser zu laden und Laufzeitfehler zu finden.
-- Unbekannte globale Namen liefern ein "Magie"-Objekt (aufrufbar, indizierbar), das nil zurückgibt.
local LOG = {}
local function log(...) local t = {} for i = 1, select("#", ...) do t[#t+1] = tostring((select(i, ...))) end LOG[#LOG+1] = table.concat(t, " ") end
_G.__LOG = LOG
local unbekannt = {}
_G.__UNBEKANNT = unbekannt

local magic
local magicMT = {
  __index = function(t, k) return magic(rawget(t, "__name") .. "." .. tostring(k)) end,
  __call = function(t, ...) return nil end,
}
function magic(name)
  unbekannt[name] = true
  return setmetatable({ __name = name }, magicMT)
end

-- Frames ---------------------------------------------------------------
local frameMT = {}
local alleFrames = {}
_G.__FRAMES = alleFrames
local function neuesObjekt(typ, name, parent)
  local o = { __typ = typ, __name = name, __scripts = {}, __shown = true, __parent = parent, __w = 100, __h = 20, __text = "", __points = {}, __events = {} }
  setmetatable(o, frameMT)
  alleFrames[#alleFrames + 1] = o
  return o
end
local methoden = {}
function methoden:SetScript(n, f) self.__scripts[n] = f end
function methoden:GetScript(n) return self.__scripts[n] end
function methoden:HookScript(n, f)
  local alt = self.__scripts[n]
  self.__scripts[n] = function(...) if alt then alt(...) end return f(...) end
end
function methoden:Show() local war = self.__shown self.__shown = true if not war and self.__scripts.OnShow then self.__scripts.OnShow(self) end end
function methoden:Hide() local war = self.__shown self.__shown = false if war and self.__scripts.OnHide then self.__scripts.OnHide(self) end end
function methoden:SetShown(s) if s then self:Show() else self:Hide() end end
function methoden:IsShown() return self.__shown end
function methoden:IsVisible() return self.__shown end
function methoden:GetWidth() return self.__w end
function methoden:GetHeight() return self.__h end
function methoden:SetWidth(w) self.__w = w end
function methoden:SetHeight(h) self.__h = h end
function methoden:SetSize(w, h) self.__w, self.__h = w, h end
function methoden:GetSize() return self.__w, self.__h end
function methoden:GetScale() return 1 end
function methoden:GetEffectiveScale() return 1 end
function methoden:GetCenter() return 500, 400 end
function methoden:GetLeft() return 100 end
function methoden:GetRight() return 200 end
function methoden:GetTop() return 500 end
function methoden:GetBottom() return 100 end
function methoden:GetRect() return 100, 100, self.__w, self.__h end
function methoden:GetName() return self.__name end
function methoden:GetParent() return self.__parent end
function methoden:GetID() return self.__id or 0 end
function methoden:SetID(i) self.__id = i end
function methoden:SetText(t) self.__text = t end
function methoden:GetText() return self.__text end
function methoden:SetFormattedText(f, ...) self.__text = string.format(f, ...) end
function methoden:GetStringWidth() return #tostring(self.__text) * 6 end
function methoden:GetStringHeight() return 12 end
function methoden:GetNumLines() return 1 end
function methoden:SetChecked(c) self.__checked = c end
function methoden:GetChecked() return self.__checked end
function methoden:GetNumPoints() return #self.__points end
function methoden:SetPoint(...) self.__points[#self.__points + 1] = { ... } end
function methoden:ClearAllPoints() self.__points = {} end
function methoden:GetPoint(i) local p = self.__points[i or 1] if p then return p[1], UIParent, p[3] or p[1], p[4] or 0, p[5] or 0 end end
-- Wie im Spiel: ein Ereignis, das der Client nicht kennt, wirft einen Fehler (Liste: Ereignisse, die es in Forever vielleicht nicht gibt)
__UNBEKANNTE_EVENTS = { NEW_RECIPE_LEARNED = true, TRADE_SKILL_LIST_UPDATE = true }
function methoden:RegisterEvent(e)
  if __UNBEKANNTE_EVENTS[e] then error('Attempt to register unknown event "' .. tostring(e) .. '"') end
  self.__events[e] = true
end
function methoden:UnregisterEvent(e) self.__events[e] = nil end
function methoden:IsEventRegistered(e) return self.__events[e] end
function methoden:CreateTexture(name) return neuesObjekt("Texture", name, self) end
function methoden:CreateLine(name) local l = neuesObjekt("Line", name, self) __LINIEN = (__LINIEN or 0) + 1 return l end
function methoden:SetStartPoint(_, _, x, y) self.__start = { x, y } end
function methoden:SetEndPoint(_, _, x, y) self.__ende = { x, y } end
function methoden:CreateFontString(name) return neuesObjekt("FontString", name, self) end
function methoden:CreateAnimationGroup() return neuesObjekt("AnimationGroup", nil, self) end
function methoden:CreateAnimation() return neuesObjekt("Animation", nil, self) end
function methoden:GetFrameLevel() return 1 end
function methoden:GetVerticalScroll() return self.__vs or 0 end
function methoden:SetVerticalScroll(v) self.__vs = v end
function methoden:GetHorizontalScroll() return 0 end
function methoden:GetVerticalScrollRange() return 0 end
function methoden:GetObjectType() return self.__typ end
function methoden:IsObjectType(t) return self.__typ == t end
function methoden:GetChildren() return end
function methoden:GetRegions() return end
function methoden:GetValue() return self.__value or 0 end
function methoden:SetValue(v) self.__value = v end
function methoden:GetMinMaxValues() return 0, 100 end
function methoden:IsMouseOver() return false end
function methoden:GetAlpha() return 1 end
function methoden:GetTexture() return self.__tex end
function methoden:SetTexture(t) self.__tex = t end
function methoden:GetMapID() return 1429 end
function methoden:GetCursorPosition() return 0, 0 end
function methoden:NumLines() return 0 end
function methoden:GetOwner() return self.__owner end
function methoden:SetOwner(o) self.__owner = o end
function methoden:GetItem() return nil end
function methoden:IsForbidden() return false end
function methoden:HasFocus() return false end
function methoden:GetCursorPosition() return 0 end
function methoden:GetFontObject() return nil end
function methoden:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "" end
function methoden:GetTextColor() return 1, 1, 1, 1 end
function methoden:IsDragging() return false end
function methoden:CanChangeAttribute() return true end
function methoden:GetAttribute() return nil end
function methoden:Click() if self.__scripts.OnClick then self.__scripts.OnClick(self, "LeftButton") end end
frameMT.__index = function(t, k)
  local m = methoden[k]
  if m then return m end
  if type(k) == "string" and k:match("^[A-Z]") then
    return function() return nil end   -- unbekannte Methode: nichts tun
  end
  return nil
end

function CreateFrame(typ, name, parent, vorlage)
  local f = neuesObjekt(typ, name, parent)
  if vorlage and vorlage:find("ScrollFrame") then
    f.ScrollBar = neuesObjekt("Slider", nil, f)
  end
  if vorlage and vorlage:find("CheckButton") then f.Text = neuesObjekt("FontString", nil, f); f.text = f.Text end
  if vorlage and vorlage:find("BasicFrameTemplate") then f.TitleText = neuesObjekt("FontString", nil, f) f.CloseButton = neuesObjekt("Button", nil, f) end
  if name then _G[name] = f end
  return f
end

UIParent = neuesObjekt("Frame", "UIParent")
Minimap = neuesObjekt("Frame", "Minimap")
WorldFrame = neuesObjekt("Frame", "WorldFrame")
GameTooltip = CreateFrame("GameTooltip", "GameTooltip", UIParent)
ItemRefTooltip = CreateFrame("GameTooltip", "ItemRefTooltip", UIParent)
WorldMapFrame = CreateFrame("Frame", "WorldMapFrame", UIParent)
WorldMapFrame.ScrollContainer = CreateFrame("Frame", nil, WorldMapFrame)
WorldMapFrame.ScrollContainer.Child = CreateFrame("Frame", nil, WorldMapFrame.ScrollContainer)
WorldMapFrame.OnMapChanged = function() end
WorldMapFrame.__shown = false
UISpecialFrames = {}

-- Lua/WoW-Grundfunktionen ---------------------------------------------
tinsert, tremove, wipe = table.insert, table.remove, function(t) for k in pairs(t) do t[k] = nil end return t end
strsplit = function(sep, s) local t = {} for p in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do t[#t+1] = p end return unpack(t) end
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
strlower, strupper, strfind, strsub, format, gsub, strlen, strmatch = string.lower, string.upper, string.find, string.sub, string.format, string.gsub, string.len, string.match
floor, ceil, abs, min, max = math.floor, math.ceil, math.abs, math.min, math.max
date = os.date
time = os.time
debugprofilestop = function() return os.clock() * 1000 end
GetTime = function() return os.clock() end
GetServerTime = os.time
geterrorhandler = function() return function(e) __LOG[#__LOG+1] = "SPIELFEHLER " .. tostring(e) .. " " .. debug.traceback() end end
securecall = function(f, ...) return f(...) end
hooksecurefunc = function(a, b, c)
  if type(a) == "table" then local alt = a[b]; a[b] = function(...) local r = { alt(...) } c(...) return unpack(r) end
  else local alt = _G[a]; _G[a] = function(...) local r = { alt(...) } b(...) return unpack(r) end end
end
issecurevariable = function() return true end
InCombatLockdown = function() return false end
UnitAffectingCombat = function() return false end
UnitFactionGroup = function() return "Alliance", "Allianz" end
UnitRace = function() return "Mensch", "Human", 1 end
UnitClass = function() return "Krieger", "WARRIOR", 1 end
UnitLevel = function() return 30 end
UnitName = function() return "Dan" end
GetRealmName = function() return "Forever" end
GetNormalizedRealmName = function() return "Forever" end
GetLocale = function() return "deDE" end
GetCursorPosition = function() return 0, 0 end
IsShiftKeyDown = function() return false end
IsControlKeyDown = function() return false end
IsAltKeyDown = function() return false end
ReloadUI = function() end
PlaySound = function() end
GetCoinTextureString = function(c) return tostring(c) .. "c" end
GetItemInfo = function(id)
  id = tonumber(tostring(id):match("%d+"))
  if not id then return nil end
  return "Item" .. id, "|Hitem:" .. id .. "|h[Item" .. id .. "]|h", 2, 10, 5, "Gegenstand", "Zeug", 20, "", 134400, 150, 7, 0, 0
end
GetItemIcon = function() return 134400 end
GetItemQualityColor = function() return 1, 1, 1, "ffffffff" end
ITEM_QUALITY_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1, hex = "|cffffffff", color = { GenerateHexColor = function() return "ffffffff" end } } end })
GetRealZoneText = function(id) return id and ("Zone" .. id) or "Zone" end
GetZoneText = function() return "Wald von Elwynn" end
GetSubZoneText = function() return "" end
GetInstanceInfo = function() return __INSTANZ_NAME or "Wald", __INSTANZ_TYP or "none", 0, "", 5, 0, false, __INSTANZ_ID or 0 end
IsInInstance = function() return __INSTANZ_TYP ~= nil and __INSTANZ_TYP ~= "none", __INSTANZ_TYP or "none" end
GetNumSkillLines = function() return 4 end
local skills = { { "Berufe", true }, { "Kräuterkunde", false, nil, 120, nil, nil, 150 }, { "Kräuterkunde", false, nil, 125, nil, nil, 150 }, { "Bergbau", false, nil, 80, nil, nil, 150 } }
GetSkillLineInfo = function(i) local s = skills[i] return s[1], s[2], false, s[4] or 0, 0, 0, s[7] or 0 end
IsSpellKnown = function() return true end
IsPlayerSpell = function() return true end
GetSpellInfo = function(id) return "Zauber" .. tostring(id), nil, 136000 end
GetNumQuestLogEntries = function() return 2, 1 end
GetQuestLogTitle = function(i)
  if i == 1 then return "Kral der Klingenhauer", 30, nil, true, false, nil, nil, 0 end
  return "Willix der Importeur", 30, nil, false, false, nil, nil, 1144
end
GetQuestLogLeaderBoard = function(n, i) if n == 1 then return "Willix befreit: 0/1", "event", false end end
GetNumQuestLeaderBoards = function() return 1 end
SelectQuestLogEntry = function() end
GetQuestLogSelection = function() return 0 end
IsQuestFlaggedCompleted = function(id) return id == 1101 end
GetQuestsCompleted = function() return { [1101] = true } end
C_QuestLog = { IsQuestFlaggedCompleted = IsQuestFlaggedCompleted, GetNumQuestLogEntries = GetNumQuestLogEntries }
C_Item = { GetItemIconByID2 = nil, GetItemNameByID = function(id) if id % 3 == 0 then return "Deutsch" .. id end end, RequestLoadItemDataByID = function() end, GetItemIconByID = function() return 134400 end, IsItemDataCachedByID = function() return true end, GetItemInfo = GetItemInfo }
C_Container = {
  GetContainerNumSlots = function(b) return b == 0 and 4 or 0 end,
  GetContainerItemInfo = function(b, s) if b == 0 and s <= 3 then return { itemID = 2447 + s, stackCount = 5, hyperlink = "|Hitem:" .. (2447 + s) .. "|h", isBound = false, iconFileID = 134400, quality = 1 } end end,
  GetContainerItemID = function(b, s) if b == 0 and s <= 3 then return 2447 + s end end,
  GetContainerItemLink = function(b, s) if b == 0 and s <= 3 then return "|Hitem:" .. (2447 + s) .. "|h" end end,
}
NUM_BAG_SLOTS = 4
NUM_CONTAINER_FRAMES = 13
C_Map = {
  GetBestMapForUnit = function() return __KARTE or 1429 end,
  GetMapInfo = function(id) return { mapID = id, name = "Karte" .. tostring(id), mapType = 3, parentMapID = 1415 } end,
  GetPlayerMapPosition = function() return { x = 0.4, y = 0.6, GetXY = function(s) return 0.4, 0.6 end } end,
  GetWorldPosFromMapPos = function() return 0, { x = 0, y = 0 } end,
}
C_Timer = {
  After = function(t, f) __TIMER[#__TIMER + 1] = f end,
  NewTicker = function(t, f, n) local tk = { f = f, aktiv = true } tk.Cancel = function(s) s.aktiv = false end __TICKER[#__TICKER + 1] = tk return tk end,
  NewTimer = function(t, f) __TIMER[#__TIMER + 1] = f return { Cancel = function() end } end,
}
__TIMER, __TICKER = {}, {}
C_AddOns = { GetAddOnMetadata = function(name, f) if name == "Wegweiser" then return "0.1.0" end if name == "ForeverDB" then return "0.62.2" end if name == "Gathercraft" then error("unbekanntes Addon") end return "1.0" end,
  IsAddOnLoaded = function() return false end }
C_AuctionHouse = { ReplicateItems = function() end, GetNumReplicateItems = function() return 3 end,
  GetReplicateItemInfo = function(i) return "Item", 0, 5, 1, true, 1, "", 0, 0, 1000 * (i + 1), 0, false, nil, nil, nil, 0, 2448 + i end }
FauxScrollFrame_Update = function(f, n, sicht, h) f.__n = n end
FauxScrollFrame_GetOffset = function(f) return 0 end
FauxScrollFrame_SetOffset = function() end
FauxScrollFrame_OnVerticalScroll = function(self, v, h, fn) fn(self) end
GameTooltip_Hide = function() end
SlashCmdList = {}
StaticPopupDialogs = {}
BackdropTemplateMixin = {}
Enum = setmetatable({ ItemQuality = { Poor = 0, Common = 1 }, TooltipDataType = { Item = 0 } }, { __index = function(t, k) return magic("Enum." .. k) end })
__TTPOSTS = {}
TooltipDataProcessor = { AddTooltipPostCall = function(typ, fn) __TTPOSTS[#__TTPOSTS + 1] = fn end }
-- ruft alle angemeldeten Tooltip-Funktionen auf (wie das echte Spiel)
__TTPOST = function(tt, daten) for _, fn in ipairs(__TTPOSTS) do fn(tt, daten) end end
__TTZEILEN = {}
function methoden:AddLine(t) __TTZEILEN[#__TTZEILEN + 1] = tostring(t) end
function methoden:AddDoubleLine(a, b) __TTZEILEN[#__TTZEILEN + 1] = tostring(a) .. " | " .. tostring(b) end
OpenWorldMap = function(id) WorldMapFrame.__shown = true end
ShowUIPanel = function(f) f:Show() end
HideUIPanel = function(f) f:Hide() end
ToggleWorldMap = function() end
CloseDropDownMenus = function() end
ContainerFrame1 = CreateFrame("Frame", "ContainerFrame1", UIParent)
ContainerFrame1.__id = 0
for s = 1, 4 do local b = CreateFrame("Button", "ContainerFrame1Item" .. s, ContainerFrame1) b.__id = 5 - s end

-- LibStub-Ersatz für HereBeDragons (echte Lib braucht viele Karten-APIs)
local pins = {}
function pins:AddWorldMapIconMap(ref, icon, map, x, y, flag) assert(type(x) == "number" and x >= 0 and x <= 1, "x ausserhalb 0..1: " .. tostring(x)) assert(type(y) == "number" and y >= 0 and y <= 1, "y ausserhalb: " .. tostring(y)) __PINS_WELT = (__PINS_WELT or 0) + 1 end
function pins:AddMinimapIconMap(ref, icon, map, x, y) assert(type(x) == "number" and x >= 0 and x <= 1) __PINS_MINI = (__PINS_MINI or 0) + 1 end
function pins:AddMinimapIconWorld(ref, icon, inst, x, y) __PINS_MINI = (__PINS_MINI or 0) + 1 end
function pins:RemoveAllWorldMapIcons() __PINS_WELT = 0 end
function pins:RemoveAllMinimapIcons() __PINS_MINI = 0 end
function pins:RemoveWorldMapIcon() end
function pins:RemoveMinimapIcon() end
function pins:SetMinimapObject() end
local hbd = { GetWorldCoordinatesFromZone = function(s, x, y, m) return x * 1000, y * 1000, 0 end, GetPlayerZone = function() return 1429 end, GetPlayerZonePosition = function() return 0.4, 0.6, 1429 end, RegisterCallback = function() end }
LibStub = setmetatable({ libs = {} }, { __call = function(s, name, leise) if name == "HereBeDragons-Pins-2.0" then return pins end if name == "HereBeDragons-2.0" then return hbd end if not leise then error("Lib fehlt: " .. name) end end })
function LibStub:GetLibrary(n, l) return LibStub(n, l) end

-- Unbekannte Globale -> Magie
setmetatable(_G, { __index = function(t, k)
  if type(k) == "string" and not k:match("^Wegweiser") and not k:match("^__") and (k:match("^[A-Z]") or k:match("^C_")) then return magic(k) end
end })

-- Ereignisse an alle Frames schicken
function __FEUER(e, ...)
  for _, f in ipairs(alleFrames) do
    if f.__events[e] and f.__scripts.OnEvent then f.__scripts.OnEvent(f, e, ...) end
  end
end
function __UPDATE(n, dt)
  for i = 1, n do
    for _, f in ipairs(alleFrames) do
      if f.__scripts.OnUpdate and f.__shown then f.__scripts.OnUpdate(f, dt or 0.25) end
    end
    local t = __TIMER; __TIMER = {}
    for _, fn in ipairs(t) do fn() end
    for _, tk in ipairs(__TICKER) do if tk.aktiv then tk.f(tk) end end
  end
end

-- Wie der Forever-Client: alte Item-Funktionen gibt es nicht mehr, nur C_Item.*
C_Item.GetItemInfo = GetItemInfo
C_Item.GetItemIconByID = C_Item.GetItemIconByID or GetItemIcon
GetItemInfo = nil
GetItemIcon = nil
-- Diese Namen gibt es im Client nicht: Aufruf muss wie im Spiel scheitern (nicht die stille Magie)
-- Neue Funktionen wie im Forever-Client (aus den alten Nachbildungen gebaut)
local altTitel, altAnzahl, altFertig, altSkillN, altSkill = GetQuestLogTitle, GetNumQuestLogEntries, IsQuestFlaggedCompleted, GetNumSkillLines, GetSkillLineInfo
C_QuestLog.GetNumQuestLogEntries = function() return altAnzahl() end
C_QuestLog.GetInfo = function(i)
  local titel, stufe, _, kopf, _, fertig, _, id = altTitel(i)
  if not titel then return nil end
  return { title = titel, level = stufe, isHeader = kopf, isComplete = fertig, questID = id, isHidden = false, isCollapsed = false }
end
C_QuestLog.IsQuestFlaggedCompleted = function(id) return altFertig(id) end
C_QuestLog.GetLogIndexForQuestID = function(id) for i = 1, altAnzahl() do local _, _, _, _, _, _, _, q = altTitel(i) if q == id then return i end end end
C_QuestLog.GetTitleForQuestID = function(id) local i = C_QuestLog.GetLogIndexForQuestID(id) if i then return (altTitel(i)) end end
__AUSGEWAEHLT = 0
C_QuestLog.SetSelectedQuest = function(id) __AUSGEWAEHLT = id end
C_QuestLog.GetSelectedQuest = function() return __AUSGEWAEHLT end
C_QuestLog.GetQuestObjectives = function(id) return {} end
C_SkillInfo = {
  GetNumSkillLines = function() return altSkillN() end,
  GetSkillLineInfo = function(i)
    local name, kopf, _, rang, _, _, maxi = altSkill(i)
    if not name then return nil end
    return { name = name, isHeader = kopf, rank = rang, maxRank = maxi, skillID = 100 + i, skillLineCategoryID = kopf and 0 or 11 }
  end,
}
C_Spell = C_Spell or {}
C_Spell.GetSpellName = function(id) return "Zauber" .. tostring(id) end
C_Spell.GetSpellInfo = function(id) return { name = "Zauber" .. tostring(id), iconID = 136000, spellID = id } end
C_CurrencyInfo = { GetCoinTextureString = GetCoinTextureString }
for _, k in ipairs({ "GetQuestLogTitle", "GetNumQuestLogEntries", "SelectQuestLogEntry", "GetQuestLogSelection",
  "IsQuestFlaggedCompleted", "GetNumSkillLines", "GetSkillLineInfo", "GetNumTalentTabs", "GetTalentTabInfo",
  "GetSpellInfo", "QueryAuctionItems", "GetAuctionItemInfo", "GetNumAuctionItems", "GetCoinTextureString" }) do _G[k] = nil end
__FEHLT = { GetItemInfo = true, GetItemIcon = true, GetQuestLogTitle = true, GetNumQuestLogEntries = true,
  SelectQuestLogEntry = true, GetQuestLogSelection = true, IsQuestFlaggedCompleted = true, GetNumSkillLines = true,
  GetSkillLineInfo = true, GetNumTalentTabs = true, GetTalentTabInfo = true, GetSpellInfo = true, QueryAuctionItems = true,
  GetAuctionItemInfo = true, GetNumAuctionItems = true, GetCoinTextureString = true }
do
  local mt = getmetatable(_G)
  local alt = mt.__index
  mt.__index = function(t, k)
    if __FEHLT[k] then return nil end
    return alt(t, k)
  end
end
