local _, ns = ...
local Util = ns.Util

-- «Прослушать» в журнале квестов на карте мира (просьба пользователя 2026-10-03). Клиент Forever — тип игры
-- camelot на современном интерфейсе: список квестов — пул кнопок QuestScrollFrame.titleFramePool (у строки questID и
-- галочка отслеживания Checkbox справа), описание открывает QuestMapFrame_ShowQuestDetails (Blizzard_UIPanels_Game,
-- Mainline\QuestMapFrame.lua — достать из клиента: tools/casc_extract.py). Встраиваемся только hooksecurefunc:
-- чужой код не трогаем. Кнопка в описании видна всегда, в строке списка — при наведении (не закрывает названия).
-- Повторное нажатие на звучащий квест — остановить (Core:ReplayQuest).
-- Список заданий у края экрана (ObjectiveTracker, 2026-10-04): кнопка ▶ слева от значка квеста — прослушать, не
-- открывая журнал. Модули QuestObjectiveTracker и CampaignQuestObjectiveTracker (Blizzard_ObjectiveTracker): блок
-- квеста — block.id = questID, значок — block.poiButton (слева от HeaderText). Всё выключает настройка questButtons.
local QuestLog = CreateFrame("Frame")
ns.QuestLog = QuestLog

local MEDIA = "Interface\\AddOns\\Wayfarer\\Media\\Player\\"

local function Enabled()
    return not ns.db or ns.db.questButtons ~= false
end

-- Есть ли у квеста озвучка и показывать ли кнопку.
local function Voiced(questID)
    return Enabled() and type(questID) == "number" and ns.Core:QuestVoice(questID) ~= nil
end

local function LogIndex(questID)
    return C_QuestLog and C_QuestLog.GetLogIndexForQuestID and Util.Try(C_QuestLog.GetLogIndexForQuestID, questID)
end

local function Title(index)
    local info = index and C_QuestLog and C_QuestLog.GetInfo and Util.Try(C_QuestLog.GetInfo, index)
    return info and info.title
end

function QuestLog:Play(questID)
    local index = LogIndex(questID)
    local text = index and GetQuestLogQuestText and Util.Try(GetQuestLogQuestText, index)
    if not ns.Core:ReplayQuest(questID, nil, Title(index), text) then
        Util.Print("для этого квеста пока нет озвучки.")
    end
end

local function ShowTooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText("Прослушать квест")
    GameTooltip:AddLine("Wayfarer: описание голосом квестодателя. Нажмите ещё раз, чтобы остановить.", 1, 1, 1, true)
    GameTooltip:Show()
end

local function HideTooltip()
    GameTooltip:Hide()
end

-- Строки списка ------------------------------------------------------------------------------------

local function RowButton(row)
    local b = CreateFrame("Button", nil, row)
    b:SetSize(16, 16)
    b:SetNormalTexture(MEDIA .. "btn-play")
    b:SetHighlightTexture(MEDIA .. "btn-hl", "ADD")
    b:SetScript("OnClick", function(self) QuestLog:Play(self.questID) end)
    b:SetScript("OnEnter", ShowTooltip)
    b:SetScript("OnLeave", function(self)
        HideTooltip()
        if not (row.IsMouseOver and row:IsMouseOver()) then
            self:Hide()
        end
    end)
    b:Hide()
    row:HookScript("OnEnter", function(r)
        if b.questID then
            r.wayfarerPlay:Show()
        end
    end)
    row:HookScript("OnLeave", function(r)
        -- Мышь могла уйти на саму кнопку (она внутри строки) — тогда не прячем.
        C_Timer.After(0.05, function()
            if not (r.IsMouseOver and r:IsMouseOver()) then
                b:Hide()
            end
        end)
    end)
    row.wayfarerPlay = b
    return b
end

function QuestLog:DecorateRows()
    local pool = QuestScrollFrame and QuestScrollFrame.titleFramePool
    if not (pool and pool.EnumerateActive) then
        return
    end
    for row in pool:EnumerateActive() do
        -- Части строки — через rawget: у фрейма неизвестное поле может оказаться методом.
        local b = rawget(row, "wayfarerPlay") or RowButton(row)
        local questID = rawget(row, "questID")
        b.questID = Voiced(questID) and questID or nil
        -- Левее значков справа: сюжетной цепочки, типа квеста (если они есть) и галочки отслеживания.
        local anchor
        for _, key in ipairs({ "StorylineTexture", "TagTexture", "Checkbox" }) do
            local part = rawget(row, key)
            if part and (key == "Checkbox" or (part.IsShown and part:IsShown())) then
                anchor = part
                break
            end
        end
        b:ClearAllPoints()
        b:SetPoint("RIGHT", anchor or row, anchor and "LEFT" or "RIGHT", -6, 0)
        b:Hide()
    end
end

-- Описание квеста --------------------------------------------------------------------------------

function QuestLog:DecorateDetails(questID)
    local details = QuestMapFrame and rawget(QuestMapFrame, "DetailsFrame")
    local back = details and rawget(details, "BackFrame")
    if not back then
        return
    end
    local b = rawget(self, "detailsButton")
    if not b then
        b = CreateFrame("Button", nil, back, "UIPanelButtonTemplate")
        b:SetSize(124, 22)
        b:SetText("Прослушать")
        local label = b.GetFontString and b:GetFontString()
        if label then
            label:ClearAllPoints()
            label:SetPoint("CENTER", 9, 0) -- место под значок слева
        end
        local icon = b:CreateTexture(nil, "OVERLAY")
        icon:SetSize(14, 14)
        icon:SetPoint("LEFT", 10, 0)
        icon:SetTexture(MEDIA .. "btn-play")
        b:SetScript("OnClick", function(self) QuestLog:Play(self.questID) end)
        b:SetScript("OnEnter", ShowTooltip)
        b:SetScript("OnLeave", HideTooltip)
        self.detailsButton = b
    end
    -- На одной линии с «Назад» слева; справа бывает отметка «выполнено на другом персонаже» — тогда левее неё.
    local notice = rawget(back, "AccountCompletedNotice")
    notice = notice and notice.IsShown and notice:IsShown() and notice or nil
    b:ClearAllPoints()
    if notice then
        b:SetPoint("RIGHT", notice, "LEFT", -6, 0)
    else
        b:SetPoint("RIGHT", back, "RIGHT", -12, 4)
    end
    b.questID = questID
    b:SetShown(Voiced(questID))
end

-- Список заданий у края экрана --------------------------------------------------------------------

local TRACKER_MODULES = { "QuestObjectiveTracker", "CampaignQuestObjectiveTracker" }

local function TrackerButton(block)
    local b = CreateFrame("Button", nil, block)
    b:SetSize(16, 16)
    b:SetNormalTexture(MEDIA .. "btn-play")
    b:SetHighlightTexture(MEDIA .. "btn-hl", "ADD")
    b:SetScript("OnClick", function(self) QuestLog:Play(self.questID) end)
    b:SetScript("OnEnter", ShowTooltip)
    b:SetScript("OnLeave", HideTooltip)
    block.wayfarerPlay = b
    return b
end

function QuestLog:DecorateTracker(module)
    if not (module and module.EnumerateActiveBlocks) then
        return
    end
    module:EnumerateActiveBlocks(function(block)
        local questID = rawget(block, "id")
        local b = rawget(block, "wayfarerPlay")
        if not Voiced(questID) then
            if b then
                b:Hide()
            end
            return
        end
        b = b or TrackerButton(block)
        b.questID = questID
        -- Левее значка квеста (его кладёт OnLayout блока); без значков — левее названия.
        local poi = rawget(block, "poiButton")
        local header = rawget(block, "HeaderText")
        b:ClearAllPoints()
        if poi and poi.IsShown and poi:IsShown() then
            b:SetPoint("RIGHT", poi, "LEFT", -5, 0) -- зазор, чтобы кнопка не прижималась к значку
        else
            b:SetPoint("TOPRIGHT", header or block, "TOPLEFT", -6, 1)
        end
        b:Show()
    end)
end

-- Настройка «Кнопки ▶ у квестов» поменялась — перерисовать то, что уже на экране.
function QuestLog:Refresh()
    for _, name in ipairs(TRACKER_MODULES) do
        pcall(self.DecorateTracker, self, _G[name])
    end
    pcall(self.DecorateRows, self)
    local b = rawget(self, "detailsButton")
    if b then
        b:SetShown(Voiced(b.questID))
    end
end

-- Подключение: функции журнала и модули списка заданий есть после загрузки интерфейса игры (список — отдельный
-- аддон Blizzard_ObjectiveTracker); пробуем при входе и при загрузке каждого аддона, пока не подключим всё.
local function Safe(fn)
    return function(...)
        local ok, err = pcall(fn, QuestLog, ...)
        if not ok then
            Util.Debug("журнал квестов: %s", tostring(err))
        end
    end
end

local mapHooked = false
local trackerHooked = {}

function QuestLog:Hook()
    if not hooksecurefunc then
        return true
    end
    if not mapHooked and QuestLogQuests_Update and QuestMapFrame_ShowQuestDetails then
        hooksecurefunc("QuestLogQuests_Update", Safe(QuestLog.DecorateRows))
        hooksecurefunc("QuestMapFrame_ShowQuestDetails", Safe(QuestLog.DecorateDetails))
        mapHooked = true
    end
    local done = mapHooked
    for _, name in ipairs(TRACKER_MODULES) do
        local module = _G[name]
        if not trackerHooked[name] and type(module) == "table" and module.Update then
            hooksecurefunc(module, "Update", Safe(QuestLog.DecorateTracker))
            trackerHooked[name] = true
            Safe(QuestLog.DecorateTracker)(module)
        end
        done = done and trackerHooked[name] == true
    end
    return done
end

QuestLog:RegisterEvent("PLAYER_LOGIN")
QuestLog:RegisterEvent("ADDON_LOADED")
QuestLog:SetScript("OnEvent", function(self)
    if self:Hook() then
        self:UnregisterAllEvents()
    end
end)
