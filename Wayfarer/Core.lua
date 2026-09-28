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
}

-- Элементы очереди, запущенные текущим окном квеста/разговора (для «молчать после закрытия»).
local openQuestItem, openGossipItem

local function Portrait(target, speakerID)
    local p = {}
    if target and target.kind == "C" then
        p.unit = target.unit
        p.display = target.display
        p.creature = target.id
    end
    if speakerID and not p.creature then
        local info = Packs:NpcInfo(speakerID)
        p.creature = speakerID
        p.display = info and info.d
    end
    return p
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
        name = SpeakerName(target, speakerID),
        target = target,
        portrait = Portrait(target, speakerID),
        delay = ns.db.startDelay,
    }
    if Queue:Add(item) then
        openQuestItem = item
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
        name = SpeakerName(target, sound.speaker),
        target = target,
        portrait = Portrait(target, sound.speaker),
        delay = ns.db.startDelay,
    }
    if Queue:Add(item) then
        ns.charDB.seen[seenKey] = true
        openGossipItem = item
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
    Collector:Quest(Event.QuestComplete, questID, title, text, nil, target)
    if ns.db.playComplete then
        self:PlayQuest(Event.QuestComplete, questID, title, text, target)
    end
end

function Core:QUEST_GREETING()
    local text = GetGreetingText()
    local target = Identity.Current(true)
    Collector:Gossip("greeting", target, text)
    self:PlayGossip(target, text)
end

function Core:GOSSIP_SHOW()
    local text = C_GossipInfo.GetText()
    local target = Identity.Current(false)
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
    if Packs:Count() == 0 then
        Util.Print("пакеты озвучки не найдены. Аддон собирает тексты квестов; озвучка появится после установки модуля Wayfarer_Voices.")
    else
        Util.Debug("загружено пакетов: %d", Packs:Count())
    end
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
    Wayfarer_CharDB = Util.ApplyDefaults(Wayfarer_CharDB or {}, { seen = {}, zones = {} })
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
    if type(ns.db.startDelay) ~= "number" or ns.db.startDelay < 0 or ns.db.startDelay > 3 then
        ns.db.startDelay = ns.DEFAULTS.startDelay
    end

    Collector:Init()
    UI:Init()
    ns.Options:Init()
    ns.Zones:Init()
    ns.ZoneMap:Init()
    HookAbandon()

    for _, event in ipairs(EVENTS) do
        self:RegisterEvent(event)
    end
end

Core:SetScript("OnEvent", function(self, event, ...)
    local handler = self[event]
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
    print("  /wf stop — остановить и очистить очередь")
    print("  /wf skip — следующая озвучка")
    print("  /wf pause — пауза / продолжить")
    print("  /wf replay — повторить последнюю")
    print("  /wf report [комментарий] — сообщить о проблеме с текущей или последней репликой")
    print("  /wf reports — список репортов, чтобы скопировать в Discord (/wf reports clear — очистить)")
    print("  /wf quest <id> [a|p|c] — прослушать квест из пакета")
    print("  /wf packs — установленные пакеты")
    print("  /wf stats — сколько текстов собрано")
    print("  /wf mine [скорость] — запросить у сервера тексты всех квестов (потом выйти из игры)")
    print("  /wf npc — что аддон знает о текущем собеседнике")
    print("  /wf zone — прочитать лор места, где стоишь")
    print("  /wf reset seen — снова озвучивать уже слышанные реплики")
    print("  /wf reset zones — снова читать лор уже посещённых мест")
    print("  /wf options — настройки")
end

local commands = {}

function commands.stop() Queue:Clear() end
function commands.skip() Queue:Skip() end
function commands.pause() Queue:TogglePause() end
function commands.options() ns.Options:Open() end

function commands.replay()
    if not Queue:Replay() then
        Util.Print("ещё ничего не звучало.")
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

function commands.quest(args)
    local id, event = args:match("^(%d+)%s*([apc]?)")
    id = tonumber(id)
    if not id then
        Util.Print("использование: /wf quest <id> [a|p|c]")
        return
    end
    event = event ~= "" and event or Event.QuestAccept
    local sound = Packs:FindQuest(id, event)
    if not sound then
        Util.Print("в пакетах нет озвучки для квеста %d (%s).", id, event)
        return
    end
    local giver = sound.speaker or Packs:QuestGiver(id)
    Queue:Add({
        sound = sound,
        event = event,
        questID = id,
        title = "Квест " .. id,
        name = SpeakerName(nil, giver),
        portrait = Portrait(nil, giver),
    })
end

function commands.packs()
    if Packs:Count() == 0 then
        Util.Print("пакеты не установлены.")
        return
    end
    for _, pack in ipairs(Packs.list) do
        local quests = 0
        for _ in pairs(pack.q) do
            quests = quests + 1
        end
        Util.Print("%s (версия %s, приоритет %d): квестов %d", pack.name, tostring(pack.version or "?"), pack.priority, quests)
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
    else
        ns.Miner:Start(args)
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

function commands.reset(args)
    if args == "seen" then
        wipe(ns.charDB.seen)
        Util.Print("реплики снова будут озвучиваться.")
    elseif args == "zones" then
        ns.Zones:Forget()
        Util.Print("лор мест снова будет читаться при входе.")
    else
        Util.Print("использование: /wf reset seen | zones")
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
BINDING_NAME_WAYFARER_REPORT = "Сообщить о проблеме с репликой"
