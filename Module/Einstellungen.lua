-- Wegweiser: Reiter "Einstellungen". Datenstand prüfen, neu laden, Minimap-Knopf, Quellen.
local ADDON, WW = ...
local UI = WW.UI

local GetMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
local QUELLEN = { "ForeverDB", "ForeverDB_Helper", "ForeverDungeonMap", "Gathercraft" }

-- Vergleicht die kopierten Daten mit den installierten Addons.
-- Gibt eine Liste { name, kopiert, installiert, neu } und ob etwas neu ist.
function WW.DatenPruefen()
  local stand = WW.datenStand and WW.datenStand.quellen or {}
  local liste, etwasNeu = {}, false
  for _, name in ipairs(QUELLEN) do
    local ok, installiert = pcall(GetMeta, name, "Version")
    if not ok then installiert = nil end
    local kopiert = stand[name]
    local neu = installiert ~= nil and kopiert ~= nil and installiert ~= kopiert
    if neu then etwasNeu = true end
    liste[#liste + 1] = { name = name, kopiert = kopiert, installiert = installiert, neu = neu }
  end
  return liste, etwasNeu
end

-- Prüf-Befehl: welche Spiel-Funktionen, die Wegweiser benutzt, fehlen auf diesem Client?
local API_LISTE = {
  "C_AddOns.GetAddOnMetadata", "C_AuctionHouse.ReplicateItems", "C_AuctionHouse.GetNumReplicateItems",
  "C_AuctionHouse.GetReplicateItemInfo", "C_Container.GetContainerItemInfo", "C_Container.GetContainerNumSlots",
  "C_Container.ContainerIDToInventoryID", "C_Item.GetItemInfo", "C_Item.GetItemInfoInstant", "C_Item.GetItemIconByID",
  "C_Item.GetItemNameByID", "C_Item.GetItemQualityByID", "C_Item.GetItemStats", "C_Item.RequestLoadItemDataByID",
  "C_Map.GetBestMapForUnit", "C_Map.GetMapInfo", "C_Map.GetPlayerMapPosition", "C_QuestLog.GetInfo",
  "C_QuestLog.GetNumQuestLogEntries", "C_QuestLog.GetQuestObjectives", "C_QuestLog.GetQuestsOnMap",
  "C_QuestLog.GetSelectedQuest", "C_QuestLog.SetSelectedQuest", "C_QuestLog.IsQuestFlaggedCompleted",
  "C_QuestLog.GetTitleForQuestID", "C_QuestLog.GetLogIndexForQuestID", "C_Spell.GetSpellName",
  "C_TaxiMap.GetAllTaxiNodes", "C_TaxiMap.GetTaxiNodesForMap", "C_Traits.GetNodeInfo", "C_ClassTalents.GetActiveConfigID",
  "GetQuestLogTitle", "GetNumQuestLogEntries", "SelectQuestLogEntry", "GetQuestLogSelection", "GetQuestLogLeaderBoard",
  "GetNumQuestLeaderBoards", "GetNumQuestLogRewards", "GetNumQuestLogChoices", "GetQuestLogItemLink",
  "GetQuestLogRewardInfo", "GetQuestLogChoiceInfo", "IsQuestFlaggedCompleted", "GetNumSkillLines", "GetSkillLineInfo",
  "GetNumTalentTabs", "GetTalentTabInfo", "GetSpellInfo", "IsSpellKnown", "IsPlayerSpell", "GetLootSlotLink",
  "GetNumLootItems", "GetLootSourceInfo", "GetInventoryItemLink", "GetInventoryItemID", "GetMoney", "GetInstanceInfo",
  "GetRealZoneText", "GetSubZoneText", "GetServerTime", "UnitPosition", "UnitOnTaxi", "IsSwimming", "IsMounted",
  "NumTaxiNodes", "TaxiNodeName", "TaxiNodeGetType", "TaxiNodePosition", "GetTaxiMapID", "TakeTaxiNode",
  "TaxiNodeOnButtonEnter", "QueryAuctionItems", "GetAuctionItemInfo", "GetNumAuctionItems", "GetCoinTextureString",
  "C_Container.UseContainerItem", "C_MerchantFrame.GetItemInfo", "GetMerchantNumItems", "GetMerchantItemInfo", "GetMerchantItemID", "GetMerchantItemLink",
  "OpenWorldMap", "FauxScrollFrame_Update", "FauxScrollFrame_GetOffset", "StaticPopup_Show", "GetItemInfo", "GetItemIcon",
  "UnitChannelInfo", "ChannelInfo", "C_CVar.GetCVar", "C_CVar.SetCVar", "GetCVar", "SetCVar", "PlaySound",
  "DeleteCursorItem", "GetCursorInfo", "CursorHasItem", "ClearCursor", "C_Container.PickupContainerItem",
  "ClickSendMailItemButton", "GetSendMailItem", "GetTradeSkillLine", "GetTradeSkillInfo", "GetCraftDisplaySkillLine",
}
WW:Befehl("api", "Zeigt Spiel-Funktionen, die dieser Client nicht hat (Fehlersuche)", function()
  local fehlt = {}
  for _, name in ipairs(API_LISTE) do
    local t = _G
    for teil in name:gmatch("[^%.]+") do
      t = type(t) == "table" and rawget(t, teil) or nil
    end
    if type(t) ~= "function" then fehlt[#fehlt + 1] = name end
  end
  WW:Print(("%d von %d Funktionen fehlen:"):format(#fehlt, #API_LISTE))
  -- in Stücken ausgeben, damit der Chat nichts abschneidet
  for i = 1, #fehlt, 6 do
    print("  " .. table.concat(fehlt, ", ", i, math.min(i + 5, #fehlt)))
  end
end)

-- Beim Einloggen einmal melden, wenn neue Daten bereitliegen.
WW:BeimStart(function()
  local _, neu = WW.DatenPruefen()
  if neu then
    WW:Print(WW.f("gelb", "Neue Daten verfügbar.") .. " Spiel schließen oder minimieren, "
      .. "Doppelklick auf Wegweiser\\Daten-aktualisieren.cmd, dann /reload.")
  end
end)

local LINKS_BREITE = 420   -- linke Spalte: Datenstand, Anzeige, Händler, Quellen
local RECHTS = 440         -- rechte Spalte: Tooltip-Zeilen

-- Schalter für jede Zeile, die Wegweiser in Tooltips schreibt. get/set lesen die Einstellung des Moduls.
local function ttTabelle(wurzel, modul, schluessel)
  local t = wurzel and wurzel[modul]
  if type(t) ~= "table" then return nil end
  if schluessel then
    if type(t[schluessel]) ~= "table" then t[schluessel] = {} end
    return t[schluessel]
  end
  return t
end
WW.TOOLTIP_SCHALTER = {
  { "Item: \"Wofür ist das?\"", function() return ttTabelle(WW.db, "items") end, "tooltip" },
  { "Item: \"Du hast\" (Bank, andere Charaktere)", function() return ttTabelle(WW.db, "inventarEinst") end, "tooltip" },
  { "Item: Upgrade und \"Gut für\" (Ausrüstung)", function() return ttTabelle(WW.db, "quests") end, "tooltip" },
  { "Item: Quest-Items", function() return ttTabelle(WW.db, "quests") end, "itemTipp" },
  { "Item: \"Behalten\" / \"Müll\" mit Grund", function() return ttTabelle(WW.db, "urteil") end, "tooltip" },
  { "Auktionshaus (alle Zeilen)", function() return ttTabelle(WW.db, "ah") end, "tooltip" },
  { "Preis und Preis nach Gebühren", function() return ttTabelle(WW.db, "ah", "tt") end, "preis", 16 },
  { "Menge im AH und Stand", function() return ttTabelle(WW.db, "ah", "tt") end, "menge", 16 },
  { "\"Verkaufen: AH lohnt / Händler\"", function() return ttTabelle(WW.db, "ah", "tt") end, "urteil", 16 },
  { "Einstellgebühr", function() return ttTabelle(WW.db, "ah", "tt") end, "kaution", 16 },
  { "Normalpreis, günstig / zu teuer", function() return ttTabelle(WW.db, "ah", "tt") end, "normal", 16 },
  { "Uhrzeit-Tipp", function() return ttTabelle(WW.db, "ah", "tt") end, "zeit", 16 },
  { "Flugkarte: Flugzeit (dieser Charakter)", function() return ttTabelle(WW.charDb, "fluege") end, "zeiten" },
}

-- Hauptreiter "Einstellungen": nur ein Behälter. Die Seiten sind Unterreiter
-- (Allgemein, Tooltip hier; Behalten in Urteil.lua, Sammeln in Sammeln.lua, Flüge in Fluege.lua).
WW:Reiter("einstellungen", "Einstellungen", 90)

WW:Reiter("allgemein", "Allgemein", 1, function(p)
  local titel = UI.Text(p, "gross")
  titel:SetPoint("TOPLEFT", 4, -4)
  titel:SetText("Datenstand")

  local text = UI.Text(p)
  text:SetPoint("TOPLEFT", titel, "BOTTOMLEFT", 0, -10)
  text:SetWidth(LINKS_BREITE)
  text:SetSpacing(3)

  local hinweis = UI.Text(p, "klein", 0.8, 0.8, 0.8)
  hinweis:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -12)
  hinweis:SetWidth(LINKS_BREITE)
  hinweis:SetSpacing(2)
  hinweis:SetText(
    "So holst du neue Daten:\n"
    .. "1. Die anderen Addons (ForeverDB, Helper, DungeonMap, Gathercraft) bleiben auf der Festplatte. "
    .. "Im Spiel kannst du sie ausschalten. Dein Addon-Programm hält sie aktuell.\n"
    .. "2. Doppelklick auf: World of Warcraft\\_forever_\\Interface\\AddOns\\Wegweiser\\Daten-aktualisieren.cmd\n"
    .. "3. Dann hier auf \"Neu laden\" klicken.")

  local pruefen = UI.Knopf(p, "Daten prüfen", 140)
  pruefen:SetPoint("TOPLEFT", hinweis, "BOTTOMLEFT", 0, -12)
  local neuLaden = UI.Knopf(p, "Neu laden", 140, function() ReloadUI() end)
  neuLaden:SetPoint("LEFT", pruefen, "RIGHT", 8, 0)

  local function zeige()
    local liste = WW.DatenPruefen()
    local zeilen = { "Kopiert am: " .. (WW.datenStand and WW.datenStand.erstellt or WW.f("rot", "noch nie")) }
    for _, q in ipairs(liste) do
      local status
      if not q.installiert then
        status = WW.f("grau", "nicht installiert")
      elseif not q.kopiert then
        status = WW.f("rot", "noch nicht kopiert")
      elseif q.neu then
        status = WW.f("gelb", "neue Version " .. q.installiert .. " - bitte Daten holen")
      else
        status = WW.f("gruen", "aktuell")
      end
      zeilen[#zeilen + 1] = string.format("%s: Kopie %s - %s", q.name, q.kopiert or "-", status)
    end
    text:SetText(table.concat(zeilen, "\n"))
  end
  pruefen:SetScript("OnClick", zeige)
  p.OnZeigen = zeige

  local t2 = UI.Text(p, "gross")
  t2:SetPoint("TOPLEFT", RECHTS, -4)
  t2:SetText("Anzeige")
  local mm = UI.Haken(p, "Minimap-Knopf zeigen",
    function() return not WW.db.minimap.aus end,
    function(an)
      WW.db.minimap.aus = not an
      if WW.minimapKnopf then WW.minimapKnopf:SetShown(an) end
    end)
  mm:SetPoint("TOPLEFT", t2, "BOTTOMLEFT", 0, -6)

  -- Händler-Hilfe (Module\Haendler.lua)
  local hk = UI.Haken(p, "Händler: Knopf \"Händlerware verkaufen\"",
    function() return WW.db.haendler.knopf end,
    function(an) WW.db.haendler.knopf = an end)
  hk:SetPoint("TOPLEFT", mm, "BOTTOMLEFT", 0, 2)
  local hg = UI.Haken(p, "graue Items verkaufen",
    function() return WW.db.haendler.graue end,
    function(an) WW.db.haendler.graue = an end)
  hg:SetPoint("TOPLEFT", hk, "BOTTOMLEFT", 16, 2)
  local hr = UI.Haken(p, "Items, für die das AH nicht lohnt",
    function() return WW.db.haendler.rote end,
    function(an) WW.db.haendler.rote = an end)
  hr:SetPoint("TOPLEFT", hg, "BOTTOMLEFT", 0, 2)

  -- Angel-Modus (Module\Angeln.lua)
  local ta = UI.Text(p, "gross")
  ta:SetPoint("TOPLEFT", hr, "BOTTOMLEFT", -16, -12)
  ta:SetText("Angeln")
  local function angelHaken(text, feld, anker, abstand)
    local h = UI.Haken(p, text,
      function() return WW.db.angeln[feld] end,
      function(an)
        WW.db.angeln[feld] = an
        WW.Angeln.einstellungNeu()
      end)
    h:SetPoint("TOPLEFT", anker, "BOTTOMLEFT", 0, abstand)
    return h
  end
  local a1 = angelHaken("Platschen laut, Musik und Umgebung aus", "laut", ta, -6)
  local a2 = angelHaken("Automatisch plündern", "pluendern", a1, 2)
  local a3 = angelHaken("Warnton, wenn der Wurf ohne Fang endet", "warnton", a2, 2)
  local a4 = angelHaken("Angel-Taste holt während des Wurfs den Fisch ein", "taste", a3, 2)
  local tasteText = UI.Text(p, "klein", 0.8, 0.8, 0.8)
  tasteText:SetPoint("TOPLEFT", a4, "BOTTOMLEFT", 4, -2)
  tasteText:SetWidth(WW.INHALT_BREITE - RECHTS - 10)
  local function zeigeTaste()
    local t = WW.Angeln and WW.Angeln.Tasten and WW.Angeln.Tasten() or {}
    tasteText:SetText(#t > 0 and ("Angel-Taste: " .. table.concat(t, ", "))
      or "Angel-Taste: keine. Esc > Optionen > Tastaturbelegung > Wegweiser > \"Angeln: auswerfen / Fisch einholen\".")
  end
  zeigeTaste()
  local altZeigen = p.OnZeigen
  p.OnZeigen = function(...) if altZeigen then altZeigen(...) end zeigeTaste() end

  local t3 = UI.Text(p, "gross")
  t3:SetPoint("TOPLEFT", pruefen, "BOTTOMLEFT", 0, -24)
  t3:SetText("Quellen")
  local q = UI.Text(p, "klein", 0.8, 0.8, 0.8)
  q:SetPoint("TOPLEFT", t3, "BOTTOMLEFT", 0, -6)
  q:SetWidth(LINKS_BREITE)
  q:SetSpacing(2)
  q:SetText(
    "Daten von ForeverDB.net (https://foreverdb.net), GPL-3.0.\n"
    .. "Dungeon-Quests: DungeonMaster von MalkDev (GPL-3.0, cMaNGOS classic-db), über Forever Dungeon Atlas.\n"
    .. "Dungeon-Karten: Wowhead, Icy Veins, Warcraft Tavern.\n"
    .. "Deutsche Namen der Sammelpunkte: QuestieDB über Gathercraft (GPL-3.0).\n"
    .. "Questziele im Dungeon: cMaNGOS classic-db (GPL-3.0).\n"
    .. "Kartennadeln: HereBeDragons.\n"
    .. "Wegweiser " .. WW.version)
end, "einstellungen")

-- Unterreiter "Tooltip": ein Schalter pro Zeile, die Wegweiser in Tooltips schreibt
WW:Reiter("tooltip", "Tooltip", 2, function(p)
  local tt = UI.Text(p, "gross")
  tt:SetPoint("TOPLEFT", 4, -4)
  tt:SetText("Tooltip")
  local ttHinweis = UI.Text(p, "klein", 0.8, 0.8, 0.8)
  ttHinweis:SetPoint("TOPLEFT", tt, "BOTTOMLEFT", 0, -4)
  ttHinweis:SetWidth(WW.INHALT_BREITE - 10)
  ttHinweis:SetText("Welche Zeilen Wegweiser in Tooltips schreibt.")
  local vorher, ersterAbstand = ttHinweis, -4
  local haken = {}
  for _, s in ipairs(WW.TOOLTIP_SCHALTER) do
    local text, tabelle, schluessel, einzug = s[1], s[2], s[3], s[4] or 0
    local h = UI.Haken(p, text,
      function() local t = tabelle() return t ~= nil and t[schluessel] ~= false end,
      function(an) local t = tabelle() if t then t[schluessel] = an end end)
    local x = einzug - ((vorher.einzug or 0))
    if vorher == ttHinweis then x = einzug end
    h:SetPoint("TOPLEFT", vorher, "BOTTOMLEFT", x, ersterAbstand)
    h.einzug = einzug
    haken[#haken + 1] = h
    vorher, ersterAbstand = h, 2
  end

end, "einstellungen")
