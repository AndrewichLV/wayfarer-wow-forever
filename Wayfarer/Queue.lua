local _, ns = ...
local Util = ns.Util

-- Очередь воспроизведения. Правила как в VoiceOver:
--  * квесты становятся в очередь и читаются по порядку, дубли не добавляются;
--  * реплика NPC (gossip) не встаёт в очередь к квестам и прерывается квестом;
--  * новая реплика заменяет старую;
--  * лор места (zone) — самый низкий приоритет: встаёт в конец, из ещё не начатых мест
--    остаётся только последнее; прерванный квестом лор дочитывается после квестов.
-- Конец звука определяем по длительности из пакета: API не даёт позицию проигрывания,
-- а пауза/продолжение начинают файл заново (перемотки в WoW нет).
local Queue = {
    items = {},
    paused = false,
    last = nil, -- последний запущенный элемент, для «повторить»
}
ns.Queue = Queue

local TICK = 0.1
local GAP_BETWEEN_ITEMS = 0.35
local END_MARGIN = 0.15

local function IsQuest(item)
    return item.questID ~= nil
end

local function IsZone(item)
    return item.zone ~= nil
end

function Queue:Current()
    return self.items[1]
end

function Queue:Size()
    return #self.items
end

---@param item table { sound, event, questID?, title?, name?, target?, speaker?, delay? }
---@return boolean added
function Queue:Add(item)
    for _, queued in ipairs(self.items) do
        if queued.sound.path == item.sound.path then
            return false
        end
    end

    local position
    if IsZone(item) then
        for i = #self.items, 2, -1 do
            if IsZone(self.items[i]) then
                self:Remove(self.items[i])
            end
        end
        position = #self.items + 1
    elseif IsQuest(item) then
        local current = self.items[1]
        if current and not IsQuest(current) then
            self:Remove(current)
            if IsZone(current) and not current.resumed then
                -- Лор прервал квест: перемотки нет, поэтому дочитаем его с начала после квестов.
                current.resumed = true
                table.insert(self.items, current)
            end
        end
        -- Квесты читаются раньше ждущего лора мест.
        position = #self.items + 1
        for i, queued in ipairs(self.items) do
            if IsZone(queued) then
                position = i
                break
            end
        end
    else
        for _, queued in ipairs(self.items) do
            if IsQuest(queued) then
                return false
            end
        end
        self:Clear()
        position = 1
    end

    table.insert(self.items, position, item)
    Util.Trace("add", (item.sound.uid or "?") .. " @" .. position)
    if position == 1 and not self.paused then
        self:Start(item, item.delay)
    end
    ns.UI:Refresh()
    return true
end

function Queue:Start(item, delay)
    if item.handle and item.startedAt and GetTime() - item.startedAt < (item.sound.duration or 0) then
        -- Реплика уже звучит: повторный запуск сыграл бы файл с начала поверх текущего.
        Util.Trace("start-skip", item.sound.uid)
        return
    end
    self:StopTimers()
    if delay and delay > 0 then
        item.waiting = true
        self.delayTimer = C_Timer.NewTimer(delay, function()
            self.delayTimer = nil
            item.waiting = nil
            if self.items[1] == item and not self.paused then
                self:Start(item)
            end
        end)
        ns.UI:Refresh()
        return
    end

    local ok, willPlay, handle = pcall(PlaySoundFile, item.sound.path, ns.db.channel)
    if (not ok or not willPlay) and ns.db.channel ~= "Master" then
        -- Канал выключен в настройках звука игры (например, «Диалоги») — играем через общий.
        ok, willPlay, handle = pcall(PlaySoundFile, item.sound.path, "Master")
    end
    if not ok or not willPlay then
        -- Файла нет (модуль установлен не полностью / клиент не перезапущен) или звук в игре выключен.
        Util.Debug("не воспроизводится: %s", item.sound.path)
        if not self.warned then
            self.warned = true
            Util.Print("звук не запускается (%s). Перезапустите игру полностью после установки или "
                .. "обновления и проверьте, что звук в игре включён. /wf packs — установленные модули.",
                item.sound.path)
        end
        item.failed = true
        self:Finish(item)
        return
    end

    item.handle = handle
    item.startedAt = GetTime()
    Util.Trace("start", item.sound.uid)
    ns.Duck:On() -- приглушить голоса NPC, пока звучит озвучка
    self.last = item
    local duration = item.sound.duration or 10
    self.ticker = C_Timer.NewTicker(TICK, function()
        if self.items[1] ~= item then
            self:StopTimers()
            return
        end
        local elapsed = GetTime() - item.startedAt
        if elapsed >= duration + END_MARGIN then
            self:Finish(item)
        else
            ns.UI:Progress(item, elapsed, duration)
        end
    end)
    ns.UI:OnStart(item)
end

function Queue:StopTimers()
    if self.ticker then
        self.ticker:Cancel()
        self.ticker = nil
    end
    if self.delayTimer then
        self.delayTimer:Cancel()
        self.delayTimer = nil
    end
end

local function StopHandle(item)
    if item.handle then
        StopSound(item.handle, 200)
        item.handle = nil
    end
end

--- Очередь замолчала (пусто или пауза) — вернуть громкость голосов NPC. Между репликами не
--- возвращаем, чтобы приветствие NPC не пробивалось в паузе.
function Queue:CheckIdle()
    if not self.items[1] or self.paused then
        ns.Duck:Off()
    end
end

--- Элемент доиграл (или его пропустили): убираем и запускаем следующий.
function Queue:Finish(item)
    local wasCurrent = self.items[1] == item
    Util.Trace("finish", (item.sound.uid or "?") .. (wasCurrent and "" or " (не текущая)"))
    self:Remove(item)
    if wasCurrent and not self.paused and self.items[1] then
        self:Start(self.items[1], GAP_BETWEEN_ITEMS)
    end
    self:CheckIdle()
end

function Queue:Remove(item)
    for i, queued in ipairs(self.items) do
        if queued == item then
            if i == 1 then
                self:StopTimers()
                StopHandle(item)
            end
            table.remove(self.items, i)
            if item.onRemoved then
                item.onRemoved(item)
            end
            ns.UI:Refresh()
            return true
        end
    end
    return false
end

function Queue:RemoveWhere(predicate)
    for i = #self.items, 1, -1 do
        local item = self.items[i]
        if predicate(item) then
            if i == 1 then
                self:Finish(item)
            else
                self:Remove(item)
            end
        end
    end
end

function Queue:Skip()
    local current = self.items[1]
    if current then
        self:Finish(current)
    end
end

function Queue:Clear()
    Util.Trace("clear", #self.items)
    self:StopTimers()
    local current = self.items[1]
    if current then
        StopHandle(current)
    end
    wipe(self.items)
    self:CheckIdle()
    ns.UI:Refresh()
end

function Queue:SetPaused(paused)
    if self.paused == paused then
        return
    end
    self.paused = paused
    Util.Trace(paused and "pause" or "resume")
    local current = self.items[1]
    if paused then
        self:StopTimers()
        if current then
            StopHandle(current)
            current.waiting = nil
        end
    elseif current then
        self:Start(current)
    end
    self:CheckIdle()
    ns.UI:Refresh()
end

function Queue:TogglePause()
    self:SetPaused(not self.paused)
end

function Queue:IsPlaying()
    local current = self.items[1]
    return current ~= nil and current.handle ~= nil
end

--- Повторить последнюю озвучку.
function Queue:Replay()
    local last = self.last
    if not last then
        return false
    end
    local copy = {}
    for k, v in pairs(last) do
        copy[k] = v
    end
    copy.handle, copy.startedAt, copy.delay, copy.failed = nil, nil, nil, nil
    self:Clear()
    self.paused = false
    return self:Add(copy)
end
