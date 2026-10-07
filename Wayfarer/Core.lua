local ADDON_NAME, ns = ...
local Util, Text, Identity = ns.Util, ns.Text, ns.Identity
local Packs, Queue, Collector, UI = ns.Packs, ns.Queue, ns.Collector, ns.UI
local Event = ns.Event

local Core = CreateFrame("Frame")
ns.Core = Core

local EVENTS = {
    "QUEST_DETAIL",
    "QUEST_PROGRESS",
    "QUEST_COMPLETE",
    "QUEST_GREETING",
    "QUEST_FINISHED",
    "GOSSIP_SHOW",
    "GOSSIP_CLOSED",
    "PLAYER_LOGIN",
    "PLAYER_LOGOUT",
}

-- Элементы очереди, запущенные текущим окном квеста/разговора (для «молчать после закрытия»).
local openQuestItem, openGossipItem

local function Portrait(target, speakerID)
    local p = {}
    if target and target.kind == "C" then
        p.unit = target.unit
        p.display = target.display
        p.creature = target.id
        if not p.display then
            -- Модель не прочиталась (ещё грузится) — displayID из модуля озвучки: портрет по нему
            -- получится, даже когда NPC уже далеко (реплика ждала в очереди).
            local info = Packs:NpcInfo(target.id)
            p.display = info and info.d
        end
    end
    if speakerID and not p.creature then
        local info = Packs:NpcInfo(speakerID)
        p.creature = speakerID
        p.display = info and info.d
    end
    return p
end

-- Приветствие собеседника («Приветствую!», «Чем могу помочь?»): игра играет его, когда открывается разговор.
-- Первую реплику разговора откладываем до конца приветствия, чтобы голоса не накладывались (настройка waitGreeting,
-- просьба пользователя 2026-10-04, как в CatQuest). Длина — по облику NPC (GreetData.lua: самая длинная фраза его
-- набора NPCSounds), не знаем — GREET_DEFAULT. Окна квеста и разговора одного NPC подряд — один разговор.
local GREET_GAP = 4       -- сек без окон разговора: следующее окно — новый разговор, NPC здоровается снова
local GREET_MAX = 4       -- редкие длинные приветствия (до 9 с) не держат озвучку дольше
local GREET_DEFAULT = 1.5
local GREET_TAIL = 0.25
local talk = { at = 0, last = -math.huge, key = nil, greet = 0 }

local function GreetLength(target)
    if not target or target.kind ~= "C" then
        return 0 -- предмет, объект, доска объявлений: не здороваются
    end
    local display = target.display
    if not display then
        local info = Packs:NpcInfo(target.id)
        display = info and info.d
    end
    local sound = display and ns.SoundByDisplay and ns.SoundByDisplay[display]
    local seconds = sound and ns.GreetBySound and ns.GreetBySound[sound]
    return math.min(seconds or GREET_DEFAULT, GREET_MAX)
end

--- Открылось окно квеста или разговора: если это новый разговор, NPC сейчас здоровается.
function Core:NoteTalk(target)
    local now = GetTime()
    local key = target and target.key
    if now - talk.last > GREET_GAP or key ~= talk.key then
        talk.at, talk.key, talk.greet = now, key, GreetLength(target)
    end
    talk.last = now
end

--- Пауза перед репликой: «Пауза перед чтением» или до конца приветствия собеседника, что дольше.
function Core:StartDelay()
    local delay = ns.db.startDelay or 0
    if ns.db.waitGreeting ~= false and talk.greet > 0 then
        delay = math.max(delay, talk.at + talk.greet + GREET_TAIL - GetTime())
    end
    return delay
end

--- Имя говорящего: собеседник, либо квестодатель из пакета (общий квест, квест из предмета).
local function SpeakerName(target, speakerID)
    if target and target.name and target.kind ~= "P" then
        return target.name
    end
    local info = Packs:NpcInfo(speakerID)
    return info and info.n or (target and target.name) or ""
end

function Core:PlayQuest(event, questID, title, text, target)
    if not ns.db.enabled then
        return
    end
    local sound = Packs:FindQuest(questID, event, text)
    if not sound then
        Collector:Missing(("q:%d:%s"):format(questID, event))
        Util.Debug("нет озвучки: квест %d (%s)", questID, event)
        return
    end
    if sound.stale then
        Collector:Stale(("q:%d:%s"):format(questID, event), sound.score)
        Util.Debug("текст квеста %d (%s) изменился, озвучка может не совпадать (%.2f)", questID, event, sound.score)
    end

    -- Если говорит не NPC (игрок поделился квестом, квест из предмета) — берём квестодателя из пакета.
    local speakerID = sound.speaker
    if (not target or target.kind ~= "C") and event == Event.QuestAccept then
        speakerID = speakerID or Packs:QuestGiver(questID)
    end

    local item = {
        sound = sound,
        event = event,
        questID = questID,
        title = title,
        text = text, -- текст окна квеста: его показывает плеер («говорящая голова»)
        name = SpeakerName(target, speakerID),
        target = target,
        portrait = Portrait(target, speakerID),
        delay = self:StartDelay(),
    }
    if Queue:Add(item) then
        openQuestItem = item
        UI:Snapshot(item)
    end
end

-- Реплики, которые уже звучали у этого персонажа (режим «один раз»).
local function SeenKey(target, text)
    local who = target and (target.key or target.name) or "?"
    return who .. "|" .. table.concat(Text.Fingerprint(text), " ")
end

function Core:PlayGossip(target, text)
    if not ns.db.enabled or ns.db.gossipMode == "never" then
        return
    end
    local seenKey = SeenKey(target, text)
    if ns.db.gossipMode == "once" and ns.charDB.seen[seenKey] then
        return
    end
    local sound = Packs:FindGossip(target, text)
    if not sound then
        Collector:Missing("g:" .. seenKey)
        Util.Debug("нет озвучки реплики: %s", seenKey)
        return
    end
    local item = {
        sound = sound,
        event = Event.Gossip,
        text = text,
        name = SpeakerName(target, sound.speaker),
        target = target,
        portrait = Portrait(target, sound.speaker),
        delay = self:StartDelay(),
    }
    if Queue:Add(item) then
        ns.charDB.seen[seenKey] = true
        openGossipItem = item
        UI:Snapshot(item)
    end
end

-- События игры ---------------------------------------------------------------

function Core:QUEST_DETAIL()
    local questID = GetQuestID()
    if not questID or questID == 0 then
        return
    end
    local title, text = GetTitleText(), GetQuestText()
    local target = Identity.Current(true)
    self:NoteTalk(target)
    Collector:Quest(Event.QuestAccept, questID, title, text, GetObjectiveText(), target)
    if ns.db.playAccept then
        self:PlayQuest(Event.QuestAccept, questID, title, text, target)
    end
end

function Core:QUEST_PROGRESS()
    local questID = GetQuestID()
    if not questID or questID == 0 then
        return
    end
    local title, text = GetTitleText(), GetProgressText()
    local target = Identity.Current(true)
    self:NoteTalk(target)
    Collector:Quest(Event.QuestProgress, questID, title, text, nil, target)
    if ns.db.playProgress then
        self:PlayQuest(Event.QuestProgress, questID, title, text, target)
    end
end

function Core:QUEST_COMPLETE()
    local questID = GetQuestID()
    if not questID or questID == 0 then
        return
    end
    local title, text = GetTitleText(), GetRewardText()
    local target = Identity.Current(true)
    self:NoteTalk(target)
    Collector:Quest(Event.QuestComplete, questID, title, text, nil, target)
    if ns.db.playComplete then
        self:PlayQuest(Event.QuestComplete, questID, title, text, target)
    end
end

function Core:QUEST_GREETING()
    local text = GetGreetingText()
    local target = Identity.Current(true)
    self:NoteTalk(target)
    Collector:Gossip("greeting", target, text)
    self:PlayGossip(target, text)
end

function Core:GOSSIP_SHOW()
    local text = C_GossipInfo.GetText()
    local target = Identity.Current(false)
    self:NoteTalk(target)
    Collector:Gossip("gossip", target, text)
    self:PlayGossip(target, text)
end

function Core:QUEST_FINISHED()
    if ns.db.stopOnClose and openQuestItem then
        Queue:RemoveWhere(function(item) return item == openQuestItem end)
    end
    openQuestItem = nil
end

function Core:GOSSIP_CLOSED()
    if ns.db.stopOnClose and openGossipItem then
        Queue:RemoveWhere(function(item) return item == openGossipItem end)
    end
    openGossipItem = nil
end

function Core:PLAYER_LOGIN()
    -- Прежнее имя аддона: если его не удалили, каждая реплика прозвучит дважды.
    if C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("VoiceOverRU") then
        Util.Print("включён старый аддон VoiceOverRU — озвучка будет звучать дважды. Удалите папки "
            .. "VoiceOverRU и VoiceOverRU_Data* из Interface\\AddOns (Wayfarer его полностью заменяет).")
    end
    local missing = Packs:Missing(Util.Try(UnitFactionGroup, "player"))
    if #missing > 0 then
        local names, projects = {}, {}
        for _, m in ipairs(missing) do
            names[#names + 1] = string.format("«%s» (%s)", m.info.title, m.state)
            projects[#projects + 1] = m.info.project
        end
        Util.Print("с версии 0.6.0 озвучка — отдельными паками, и не хватает: %s. В приложении CurseForge они ставятся "
            .. "сами вместе с аддоном; если нет — найдите %s или возьмите архивы на GitHub. /wf packs — что установлено.",
            table.concat(names, ", "), table.concat(projects, ", "))
    elseif Packs:HasLegacyAndSplit() then
        Util.Print("установлены и прежний модуль Wayfarer_Voices, и новые паки озвучки — папку Wayfarer_Voices "
            .. "в Interface\\AddOns можно удалить.")
    else
        Util.Debug("загружено пакетов: %d", Packs:Count())
    end
end

-- Выход из игры или /reload посреди реплики: вернуть громкость «Диалогов» до записи настроек клиента.
function Core:PLAYER_LOGOUT()
    ns.Duck:Off()
end

-- При отказе от квеста убираем его из очереди.
local function HookAbandon()
    if C_QuestLog and C_QuestLog.AbandonQuest and C_QuestLog.GetAbandonQuest then
        hooksecurefunc(C_QuestLog, "AbandonQuest", function()
            local questID = Util.Try(C_QuestLog.GetAbandonQuest)
            if questID then
                Queue:RemoveWhere(function(item) return item.questID == questID end)
            end
        end)
    end
end

function Core:ADDON_LOADED(name)
    if name ~= ADDON_NAME then
        return
    end
    self:UnregisterEvent("ADDON_LOADED")

    Wayfarer_DB = Util.ApplyDefaults(Wayfarer_DB or {}, ns.DEFAULTS)
    Wayfarer_CharDB = Util.ApplyDefaults(Wayfarer_CharDB or {},
        { seen = {}, zones = {}, visits = {}, chronicle = {}, bestiary = {} }) -- три последних — дневник путника
    ns.db = Wayfarer_DB
    ns.charDB = Wayfarer_CharDB
    -- Испорченное значение канала (старые версии, ручная правка) — назад к рабочему по умолчанию.
    local validChannel = false
    for _, c in ipairs(ns.CHANNELS) do
        validChannel = validChannel or c[1] == ns.db.channel
    end
    if not validChannel then
        ns.db.channel = ns.DEFAULTS.channel
    end
    local validModel = false
    for _, m in ipairs(ns.VOICE_MODELS) do
        validModel = validModel or m[1] == ns.db.voiceModel
    end
    if not validModel then
        ns.db.voiceModel = ns.DEFAULTS.voiceModel
    end
    ns.Duck:RestoreAfterCrash()
    -- 0.6.0: плеер «говорящая голова» стал видом по умолчанию — переводим тех, у кого стоял прежний
    -- вид по умолчанию (пергамент); выбранные вручную мрамор, классика и «без фона» не трогаем. Один раз.
    if not ns.db.headStyle then
        if ns.db.frameTheme == "parchment" then
            ns.db.frameTheme = "head"
        end
        ns.db.headStyle = true
    end
    ns.Options:Validate(ns.db)
    if type(ns.db.startDelay) ~= "number" or ns.db.startDelay < 0 or ns.db.startDelay > 3 then
        ns.db.startDelay = ns.DEFAULTS.startDelay
    end

    Collector:Init()
    UI:Init()
    ns.Options:Init()
    ns.Zones:Init()
    ns.ZoneMap:Init()
    if ns.Diary then -- дневника нет в выпусках для игроков (vru export: RELEASE_EXCLUDE)
        ns.Diary:Init()
    end
    HookAbandon()

    for _, event in ipairs(EVENTS) do
        self:RegisterEvent(event)
    end
end

Core:SetScript("OnEvent", function(self, event, ...)
    local handler = self[event]
    if handler and event ~= "ADDON_LOADED" then
        Util.Trace("ev", event)
    end
    if handler then
        -- Ошибка в одном событии не должна ломать остальные; показываем её штатным обработчиком.
        local ok, err = pcall(handler, self, ...)
        if not ok then
            geterrorhandler()(err)
        end
    end
end)
Core:RegisterEvent("ADDON_LOADED")

-- Команды ------------------------------------------------------------------

local function PrintHelp()
    Util.Print("команды:")
    if ns.Journal then
        print("  /wf journal (/wf j) — дневник путника: атлас мест, бестиарий, летопись")
    end
    print("  /wf stop — остановить и очистить очередь")
    print("  /wf skip — следующая озвучка")
    print("  /wf pause — пауза / продолжить")
    print("  /wf replay — повторить последнюю")
    print("  /wf report [комментарий] — сообщить о проблеме с текущей или последней репликой")
    print("  /wf reports — список репортов, чтобы скопировать в Discord (/wf reports clear — очистить)")
    print("  /wf v4, /wf v3 — версия голосов: новые (где есть) или прежние")
    print("  /wf quest <id> [a|p|c] — прослушать квест из пакета")
    print("  /wf packs — установленные пакеты")
    print("  /wf stats — сколько текстов собрано")
    print("  /wf mine [скорость] — запросить у сервера тексты всех квестов (потом выйти из игры)")
    print("  /wf mine gaps [скорость] — только квесты, которых ещё нет в озвучке (по 2 в секунду)")
    print("  /wf npc — что аддон знает о текущем собеседнике")
    print("  /wf zone — прочитать лор места, где стоишь")
    print("  /wf reset seen — снова озвучивать уже слышанные реплики")
    print("  /wf reset zones — снова читать лор уже посещённых мест")
    print("  /wf move — показать окно плеера, чтобы перетащить его мышью (ещё раз — готово)")
    print("  /wf reset frame — вернуть окно плеера на место")
    print("  /wf size 80 — размер окна плеера в процентах")
    print("  /wf options — настройки")
end

local commands = {}

function commands.stop() Queue:Clear() end
function commands.skip() Queue:Skip() end
function commands.pause() Queue:TogglePause() end
function commands.options() ns.Options:Open() end
function commands.journal()
    if ns.Journal then
        ns.Journal:Toggle()
    end
end
commands.j = commands.journal
commands["дневник"] = commands.journal

function commands.replay()
    if not Queue:Replay() then
        Util.Print("ещё ничего не звучало.")
    end
end

local function SetVoiceModel(model)
    ns.db.voiceModel = model
    if Settings and Settings.SetValue then
        pcall(Settings.SetValue, "WAYFARER_voiceModel", model) -- чтобы панель настроек показала то же
    end
    local has = false
    for _, pack in ipairs(Packs.list) do
        has = has or pack.model == model
    end
    if not has then
        Util.Print("голоса: %s, но модуль с ними не установлен — звучат голоса из установленных модулей.", model)
    elseif model == "v3" then
        Util.Print("голоса: v3 (прежние); где их нет — v4.")
    else
        Util.Print("голоса: %s; где их нет — прежние.", model)
    end
end

function commands.v3() SetVoiceModel("v3") end
function commands.v4() SetVoiceModel("v4") end

function commands.log()
    local trace = Wayfarer_Collected and Wayfarer_Collected.trace or {}
    Util.Print("последние события очереди (время, событие, реплика | подзона):")
    for i = math.max(1, #trace - 24), #trace do
        print("  " .. trace[i])
    end
end

function commands.report(args)
    ns.Report:Open(args)
end

function commands.reports(args)
    if args == "clear" then
        ns.Report:Clear()
    else
        ns.Report:ShowAll()
    end
end

--- Озвучка квеста в пакетах: описание (взятие), а если его нет — сдача или «прогресс». event — только это событие.
---@return table|nil sound, string|nil event
function Core:QuestVoice(questID, event)
    for _, e in ipairs(event and { event } or { Event.QuestAccept, Event.QuestComplete, Event.QuestProgress }) do
        local sound = Packs:FindQuest(questID, e)
        if sound then
            return sound, e
        end
    end
end

--- Прослушать квест заново (журнал квестов, /wf quest). Нажали на квест, который звучит сейчас, — остановить.
---@param text string|nil текст описания из журнала (его показывает плеер «говорящая голова»)
---@return boolean есть озвучка
function Core:ReplayQuest(questID, event, title, text)
    local sound, e = self:QuestVoice(questID, event)
    if not sound then
        return false
    end
    local current = Queue:Current()
    if current and current.sound.path == sound.path then
        Queue:Skip()
        return true
    end
    local giver = sound.speaker or Packs:QuestGiver(questID)
    Queue:Add({
        sound = sound,
        event = e,
        questID = questID,
        title = title or ("Квест " .. questID),
        text = e == Event.QuestAccept and text or nil,
        name = SpeakerName(nil, giver),
        portrait = Portrait(nil, giver),
    })
    return true
end

function commands.quest(args)
    local id, event = args:match("^(%d+)%s*([apc]?)")
    id = tonumber(id)
    if not id then
        Util.Print("использование: /wf quest <id> [a|p|c]")
        return
    end
    event = event ~= "" and event or Event.QuestAccept
    if not Core:ReplayQuest(id, event) then
        Util.Print("в пакетах нет озвучки для квеста %d (%s).", id, event)
    end
end

function commands.packs()
    for _, m in ipairs(Packs:Missing(Util.Try(UnitFactionGroup, "player"))) do
        Util.Print("нет пака «%s» (%s) — CurseForge: %s", m.info.title, m.state, m.info.project)
    end
    if Packs:Count() == 0 then
        Util.Print("пакеты не установлены.")
        return
    end
    for _, pack in ipairs(Packs.list) do
        local quests = 0
        for _ in pairs(pack.q) do
            quests = quests + 1
        end
        Util.Print("%s (голоса %s, версия %s, приоритет %d): квестов %d", pack.name, pack.model,
            tostring(pack.version or "?"), pack.priority, quests)
    end
end

function commands.stats()
    local s = Collector:Stats()
    Util.Print("собрано: квестов %d, реплик %d, NPC %d; без озвучки встречено %d, устаревших %d.",
        s.quests, s.gossip, s.npcs, s.missing, s.stale)
    Util.Print("данные сохраняются при выходе из игры или /reload в WTF\\Account\\<аккаунт>\\SavedVariables\\Wayfarer.lua")
end

function commands.npc()
    local t = Identity.Current(false) or Identity.Current(true)
    if not t then
        Util.Print("нет собеседника: откройте диалог с NPC.")
        return
    end
    Util.Print("unit=%s kind=%s id=%s display=%s sex=%s secret=%s name=%s",
        tostring(t.unit), tostring(t.kind), tostring(t.id), tostring(t.display), tostring(t.sex),
        tostring(t.secret), tostring(t.name))
end

function commands.mine(args)
    if args == "stop" then
        ns.Miner:Stop()
        return
    end
    local gaps, rate = args:match("^(gaps)%s*(%d*)$")
    if gaps then
        ns.Miner:Start(tonumber(rate), true)
    else
        ns.Miner:Start(tonumber(args))
    end
end

function commands.zone()
    local zoneSound, subSound, _, subzone = ns.Zones:Current()
    if not zoneSound and not subSound then
        Util.Print("для этого места (%s) лора в пакетах нет.", subzone or GetZoneText() or "?")
        return
    end
    ns.Zones:Check(true, true)
end

--- Размер окна плеера в процентах: /wf size 80 (то же, что ползунок «Размер окна плеера»).
function commands.size(args)
    local pct = tonumber((args or ""):match("%d+"))
    if not pct then
        Util.Print("размер окна плеера: %d%%. Изменить: /wf size 80 (от 50 до 150).",
            math.floor((ns.db.frameScale or 1) * 100 + 0.5))
        return
    end
    ns.db.frameScale = math.max(0.5, math.min(1.5, pct / 100))
    UI:ApplySettings()
    Util.Print("размер окна плеера: %d%%.", math.floor(ns.db.frameScale * 100 + 0.5))
end
commands["размер"] = commands.size

function commands.move()
    if UI:ToggleMove() then
        Util.Print("перетащите окно мышью — место запомнится. Готово — /wf move ещё раз.")
    else
        Util.Print("окно на месте.")
    end
end

function commands.reset(args)
    if args == "seen" then
        wipe(ns.charDB.seen)
        Util.Print("реплики снова будут озвучиваться.")
    elseif args == "zones" then
        ns.Zones:Forget()
        Util.Print("лор мест снова будет читаться при входе.")
    elseif args == "frame" then
        ns.db.framePos = false
        ns.db.frameScale = ns.DEFAULTS.frameScale
        UI:ApplySettings()
        Util.Print("окно плеера возвращено на место.")
    else
        Util.Print("использование: /wf reset seen | zones | frame")
    end
end

SLASH_WAYFARER1 = "/wf"
SLASH_WAYFARER2 = "/wayfarer"
SLASH_WAYFARER3 = "/vru"   -- прежняя команда VoiceOverRU
SlashCmdList.WAYFARER = function(msg)
    local cmd, args = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    local fn = commands[(cmd or ""):lower()]
    if fn then
        fn(args or "")
    else
        PrintHelp()
    end
end

-- Назначение клавиш (Bindings.xml)
BINDING_HEADER_WAYFARER = "Wayfarer"
BINDING_NAME_WAYFARER_PAUSE = "Пауза / продолжить"
BINDING_NAME_WAYFARER_SKIP = "Следующая озвучка"
BINDING_NAME_WAYFARER_STOP = "Остановить и очистить очередь"
BINDING_NAME_WAYFARER_REPLAY = "Повторить последнюю"
BINDING_NAME_WAYFARER_JOURNAL = "Дневник путника"
BINDING_NAME_WAYFARER_REPORT = "Сообщить о проблеме с репликой"
