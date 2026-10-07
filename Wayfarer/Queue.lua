local _, ns = ...
local Util = ns.Util

-- Очередь воспроизведения. Ограничения на длину нет (просьба пользователя 2026-09-30: раньше из реплик
-- NPC и из лора мест в очереди оставалась одна — новая вытесняла прежние):
--  * всё встаёт в очередь и читается по порядку, дубли (тот же звук) не добавляются;
--  * квесты — первыми: звучащую реплику NPC квест прерывает, звучащий лор места — тоже;
--  * реплика NPC (страница диалога) — после квестов и прежних реплик, раньше лора мест;
--    звучащий лор прерывает (иначе ответ NPC ждал бы конца долгого рассказа);
--  * лор места (zone) — самый низкий приоритет, в конец; прерванный лор дочитывается с начала потом.
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
-- Звук оборвался раньше конца (игра заглушила его: Alt+Tab без звука в фоне): не раньше, чем через CUT_START после
-- запуска (звук ещё мог не начаться), и не позже, чем за CUT_TAIL до конца (длительность в пакете округлена).
local CUT_START, CUT_TAIL = 0.5, 1.0

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
        position = #self.items + 1
    else
        local current = self.items[1]
        if current and (IsZone(current) or (IsQuest(item) and not IsQuest(current))) then
            self:Interrupt(current)
        end
        -- Квесты и реплики NPC читаются раньше ждущего лора мест.
        position = #self.items + 1
        for i, queued in ipairs(self.items) do
            if IsZone(queued) then
                position = i
                break
            end
        end
        if IsQuest(item) then
            -- Квест — сразу за квестами: ждущие реплики NPC пропускают его вперёд.
            for i, queued in ipairs(self.items) do
                if i >= position then
                    break
                end
                if not IsQuest(queued) then
                    position = i
                    break
                end
            end
        end
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
    item.cut, item.audible = nil, nil
    Util.Trace("start", item.sound.uid)
    if item.onStart then
        item.onStart(item)
    end
    if ns.Diary then
        ns.Diary:Heard(item) -- летопись дневника: что звучало, чтобы переслушать
    end
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
        elseif self:SoundCut(item, elapsed, duration) then
            self:OnCut(item, elapsed)
        else
            ns.UI:Progress(item, elapsed, duration)
        end
    end)
    ns.UI:OnStart(item)
end

--- Игра оборвала звук реплики раньше конца (C_Sound.IsPlaying: звука уже нет). Перемотки нет — продолжить с того же
--- места нельзя, а молча «доигрывать» по таймеру — обман (баг 2026-10-07: после Alt+Tab звука нет, полоса идёт).
function Queue:SoundCut(item, elapsed, duration)
    if not (item.handle and C_Sound and C_Sound.IsPlaying) then
        return false
    end
    local ok, playing = pcall(C_Sound.IsPlaying, item.handle)
    if not ok then
        return false
    end
    if playing then
        item.audible = true -- обрыв — только у звука, который уже звучал (файл с диска мог грузиться дольше)
        return false
    end
    return item.audible == true and elapsed >= CUT_START and elapsed <= duration - CUT_TAIL
end

--- Реплика оборвалась: пауза — окно показывает «Играть», реплика начнётся заново по нажатию.
function Queue:OnCut(item, elapsed)
    if self.items[1] ~= item or item.cut then
        return
    end
    Util.Trace("cut", string.format("%s %.1f/%.1f", item.sound.uid or "?", elapsed, item.sound.duration or 0))
    item.cut = true
    item.handle = nil -- звука уже нет: StopSound не нужен
    self:SetPaused(true)
end

-- Клиент сообщает, что звук доиграл (SOUNDKIT_FINISHED, по номеру звука): в журнал — когда и через сколько от
-- начала. Если реплика оборвалась или прозвучала заново, а очередь её не запускала, это будет видно по журналу.
local soundWatch = CreateFrame("Frame")
if pcall(soundWatch.RegisterEvent, soundWatch, "SOUNDKIT_FINISHED") then
    soundWatch:SetScript("OnEvent", function(_, _, handle)
        for i, item in ipairs(Queue.items) do
            if item.handle and item.handle == handle then
                local elapsed = GetTime() - (item.startedAt or GetTime())
                local duration = item.sound.duration or 0
                Util.Trace("sound-end", string.format("%s %.1f/%.1f", item.sound.uid or "?", elapsed, duration))
                if i == 1 and elapsed >= CUT_START and elapsed < duration - CUT_TAIL then
                    Queue:OnCut(item, elapsed)
                end
                return
            end
        end
        if Queue.last and Queue.last.lastHandle == handle then
            Util.Trace("sound-end", (Queue.last.sound.uid or "?") .. " (уже снята)")
        end
    end)
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
        item.lastHandle = item.handle
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
            if not self.items[1] then
                self.paused = false -- пауза относится к очереди: опустела — следующая озвучка играет сразу
            end
            if item.onRemoved then
                item.onRemoved(item)
            end
            ns.UI:Refresh()
            return true
        end
    end
    return false
end

--- Прервать звучащий элемент ради более важного: реплика NPC снимается, лор места встаёт в конец
--- (перемотки нет — дочитаем с начала, но один раз).
function Queue:Interrupt(item)
    self:Remove(item)
    if IsZone(item) and not item.resumed then
        item.resumed = true
        item.handle, item.startedAt = nil, nil
        table.insert(self.items, item)
    end
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
    -- «Стоп» снимает и паузу: иначе следующие реплики вставали в очередь и молчали, а окно показывало
    -- последнюю звучавшую (баг 2026-09-30: «Волок» на паузе, «Стоп», в Аллее Чести — тишина).
    self.paused = false
    self:CheckIdle()
    ns.UI:Refresh()
end

function Queue:SetPaused(paused)
    if self.paused == paused or (paused and not self.items[1]) then
        return -- ставить на паузу нечего: пустая «пауза» глушила бы следующую озвучку
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
