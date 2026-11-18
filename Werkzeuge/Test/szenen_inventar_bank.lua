-- Szenen fuer die Bank wie im Forever-Client (Stand 17.11., aus "/ww bank"):
-- Enum.BagIndex hat kein "Bank" und kein "BankBag_n", aber CharacterBankTab_1..9 = 6..14 und AccountBankTab_n.
-- Behaelter -1 hat 32 Plaetze, ist aber leer. Die Sachen liegen in den Reitern 6, 7, 8.
-- Ereignisse beim Oeffnen: BANKFRAME_OPENED, dann PLAYER_INTERACTION_MANAGER_FRAME_SHOW mit 67.
-- SZENE: Inventar - Bank wie im Forever-Client wird gespeichert
__BANK_ALT = { num = C_Container.GetContainerNumSlots, info = C_Container.GetContainerItemInfo,
  name = UnitName, enum = rawget(_G, "Enum"), n = rawget(_G, "NUM_TOTAL_EQUIPPED_BAG_SLOTS"), nb = rawget(_G, "NUM_BANKBAGSLOTS") }
local bi = { Backpack = 0, Bag_1 = 1, Bag_2 = 2, Bag_3 = 3, Bag_4 = 4, ReagentBag = 5 }
for i = 1, 9 do bi["CharacterBankTab_" .. i] = 5 + i end
for i = 1, 9 do bi["AccountBankTab_" .. i] = 14 + i end
Enum = { BagIndex = bi, PlayerInteractionType = { Banker = 8, Auctioneer = 21, CharacterBanker = 67, AccountBanker = 68, GuildBanker = 10 } }
NUM_TOTAL_EQUIPPED_BAG_SLOTS, NUM_BANKBAGSLOTS = 5, 7
local plaetze = { [0] = 16, [5] = 8, [-1] = 32, [6] = 48, [7] = 8, [8] = 8 }
local inhalt = { [0] = { 4001 }, [6] = { 4006 }, [7] = { 4007 }, [8] = { 4008 } }
C_Container.GetContainerNumSlots = function(b) return plaetze[b] or 0 end
C_Container.GetContainerItemInfo = function(b, s)
  local id = inhalt[b] and inhalt[b][s]
  if id then return { itemID = id, stackCount = 1, isBound = false } end
end
UnitName = function() return "Forever" end
__WW.db.inventar = {}
__FEUER("BANKFRAME_OPENED")
__FEUER("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 67)
__UPDATE(5)
local r = __WW.db.inventar["Forever"]
local e = r and r["Forever"]
if not e then error("kein Eintrag") end
if not e.bankT then error("Bank nicht gespeichert (bankT fehlt)") end
for _, id in ipairs({ 4006, 4007, 4008 }) do
  if not (e.bank or ""):find(id .. ":1:0", 1, true) then error("Bank ohne " .. id .. ": " .. tostring(e.bank)) end
end
SlashCmdList.WEGWEISER("bank")

-- SZENE: Inventar - Bank-Reiter 9 (Behaelter 14) wird mitgelesen
plaetze = nil
C_Container.GetContainerNumSlots = function(b) return ({ [0] = 16, [-1] = 32, [6] = 48, [14] = 8 })[b] or 0 end
C_Container.GetContainerItemInfo = function(b, s)
  if b == 14 and s == 1 then return { itemID = 4014, stackCount = 2, isBound = false } end
end
__FEUER("BANKFRAME_OPENED")
__UPDATE(5)
local e = __WW.db.inventar["Forever"]["Forever"]
if not (e.bank or ""):find("4014:2:0", 1, true) then error("Reiter 9 fehlt: " .. tostring(e.bank)) end

-- SZENE: Inventar - Bank nur ueber PLAYER_INTERACTION_MANAGER_FRAME_SHOW 67 (CharacterBanker)
__FEUER("BANKFRAME_CLOSED")
local e = __WW.db.inventar["Forever"]["Forever"]
e.bank, e.bankT = nil, nil
__FEUER("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 67)
__UPDATE(5)
if not e.bankT then error("Bank ueber Interaktion 67 nicht gespeichert") end
__FEUER("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 67)
-- Gildenbank zaehlt nicht als Bank
e.bank, e.bankT = nil, nil
__FEUER("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 10)
__UPDATE(5)
if e.bankT then error("Gildenbank darf nicht als Bank gelten") end
__FEUER("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 10)

-- SZENE: Inventar - Bank im Auktionshaus (Ansicht Taschen mit Bank)
__FEUER("BANKFRAME_OPENED")
__UPDATE(5)
__FEUER("BANKFRAME_CLOSED")
__WW.db.ah.taschenBank = true
__WW:Oeffnen("ah")
__UPDATE(5)
local gefunden
for _, f in ipairs(__FRAMES) do
  if f.eintraege then for _, x in ipairs(f.eintraege) do if x.id == 4014 and x.bank then gefunden = x end end end
end
if not gefunden then error("Bank-Item fehlt in der Auktionshaus-Ansicht") end

-- SZENE: Inventar - Fehler bei der Aufnahme wird gemeldet und gemerkt
local altLevel = UnitLevel
UnitLevel = function() error("Testfehler Stufe") end
__WW.db.inventarFehler = nil
__FEUER("BAG_UPDATE_DELAYED")
__UPDATE(5)
UnitLevel = altLevel
local f = __WW.db.inventarFehler
if not (f and f.text and f.text:find("Testfehler Stufe", 1, true)) then error("Fehler nicht gemerkt: " .. tostring(f and f.text)) end
__WW.db.inventarFehler = nil

-- SZENE: Inventar - Bank-Pruefung Aufraeumen
__WW.db.ah.taschenBank = false
__FEUER("BANKFRAME_CLOSED")
C_Container.GetContainerNumSlots, C_Container.GetContainerItemInfo = __BANK_ALT.num, __BANK_ALT.info
UnitName, Enum = __BANK_ALT.name, __BANK_ALT.enum
NUM_TOTAL_EQUIPPED_BAG_SLOTS, NUM_BANKBAGSLOTS = __BANK_ALT.n, __BANK_ALT.nb
__WW.db.inventar = {}
