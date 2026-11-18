-- SZENE: Kern - fertige Quest ohne isComplete (Ersatz über C_QuestLog.IsComplete)
local altInfo, altIC = C_QuestLog.GetInfo, C_QuestLog.IsComplete
C_QuestLog.GetInfo = function(i)
  if i == 1 then return { title = "Testquest", level = 20, isHeader = false, questID = 777 } end
end
C_QuestLog.IsComplete = function(id) return id == 777 end
local e = __WW.QuestLogEintrag(1)
C_QuestLog.GetInfo, C_QuestLog.IsComplete = altInfo, altIC
assert(e and e.fertig == true, "fertige Quest wurde nicht erkannt")
