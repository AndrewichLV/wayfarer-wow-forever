local _, ns = ...
local Util = ns.Util

-- /wf mine: просит у сервера данные всех квестов из ns.QUEST_IDS (QuestIDs.lua).
-- Клиент складывает ответы в Cache/WDB/ruRU/questcache.wdb и пишет файл на диск при выходе
-- из игры. Оттуда пайплайн (vru questcache) берёт официальные тексты с шаблонами $N/$g.
local Miner = {}
ns.Miner = Miner

local DEFAULT_RATE = 8 -- запросов в секунду
local GAPS_RATE = 2
local MAX_RATE = 20
local REPORT_EVERY = 500
local ANSWER_WAIT = 10 -- сколько ждать последних ответов, сек

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, _, questID, success)
    Miner:OnResult(questID, success)
end)

function Miner:IsRunning()
    return self.run ~= nil
end

--- gaps — только квесты, которых нет в текстах озвучки (QuestGaps.lua): медленнее по умолчанию —
--- на 8 запросов в секунду сервер отвечал «нет данных» на две трети квестов.
function Miner:Start(rateArg, gaps)
    if self.run then
        Util.Print("сбор уже идёт. /wf mine stop — остановить.")
        return
    end
    local ids = gaps and ns.QUEST_GAPS or ns.QUEST_IDS
    if not ids or #ids == 0 then
        Util.Print("нет списка квестов (%s). Обновите аддон и перезапустите игру.",
            gaps and "QuestGaps.lua" or "QuestIDs.lua")
        return
    end
    if gaps and not rateArg then
        rateArg = GAPS_RATE
    end
    if not (C_QuestLog and C_QuestLog.RequestLoadQuestByID) then
        Util.Print("клиент не поддерживает запрос данных квестов.")
        return
    end

    local rate = math.max(1, math.min(tonumber(rateArg) or DEFAULT_RATE, MAX_RATE))
    -- Квесты, которые уже есть в кеше клиента, повторно не запрашиваем.
    local todo = {}
    for _, id in ipairs(ids) do
        if not Util.Try(C_QuestLog.GetTitleForQuestID, id) then
            todo[#todo + 1] = id
        end
    end

    self.run = {
        ids = todo, total = #ids, sent = 0, answered = 0, loaded = 0,
        pending = {}, rate = rate, startedAt = time(),
    }
    events:RegisterEvent("QUEST_DATA_LOAD_RESULT")
    self.run.ticker = C_Timer.NewTicker(1 / rate, function() self:Tick() end)
    Util.Print("запрашиваю данные %d квестов (%d уже в кеше) по %d в секунду — примерно %d мин.",
        #todo, #ids - #todo, rate, math.ceil(#todo / rate / 60))
    Util.Print("Можно просто стоять в городе. /wf mine stop — остановить.")
end

function Miner:Tick()
    local run = self.run
    local id = run.ids[run.sent + 1]
    if not id then
        run.ticker:Cancel()
        run.ticker = nil
        run.finishTimer = C_Timer.NewTimer(ANSWER_WAIT, function() self:Finish() end)
        return
    end
    run.sent = run.sent + 1
    run.pending[id] = true
    C_QuestLog.RequestLoadQuestByID(id)
    if run.sent % REPORT_EVERY == 0 then
        Util.Print("запрошено %d из %d, получено данных: %d", run.sent, #run.ids, run.loaded)
    end
end

function Miner:OnResult(questID, success)
    local run = self.run
    if not run or not run.pending[questID] then
        return -- ответы на чужие запросы (интерфейс игры тоже грузит квесты)
    end
    run.pending[questID] = nil
    run.answered = run.answered + 1
    if success then
        run.loaded = run.loaded + 1
    end
end

function Miner:Finish()
    local run = self.run
    if not run then
        return
    end
    if run.ticker then
        run.ticker:Cancel()
    end
    if run.finishTimer then
        run.finishTimer:Cancel()
    end
    events:UnregisterEvent("QUEST_DATA_LOAD_RESULT")
    self.run = nil

    if ns.Collector.db then
        ns.Collector.db.mine = {
            t = time(), rate = run.rate, total = run.total, sent = run.sent,
            answered = run.answered, loaded = run.loaded,
        }
    end
    Util.Print("готово: запрошено %d, ответов %d, с данными %d.", run.sent, run.answered, run.loaded)
    Util.Print("|cffff8000Теперь полностью выйдите из игры (не /reload)|r — только тогда клиент запишет кеш квестов на диск.")
end

function Miner:Stop()
    if not self.run then
        Util.Print("сбор не запущен.")
        return
    end
    self:Finish()
end
