local _, ns = ...
local Util, Identity = ns.Util, ns.Identity

-- Компактный плеер: портрет собеседника (или иконка), имя — NPC или место — и кнопки
-- управления очередью, «!» (репорт), время реплики цифрами и полоса прогресса. Субтитров пока нет: окно не закрывает игру.
local UI = {}
ns.UI = UI

local ANIM_TALK = 60
local ANIM_IDLE = 0
local TALK_REFRESH = 2.5
local BOOK_ICON = "Interface\\Icons\\INV_Misc_Book_09"    -- рассказчик: книги, записки, предметы
local LORE_ICON = "Interface\\Icons\\INV_Misc_Book_07"     -- лор места: старая летопись (выбор пользователя)

local function Button(parent, label, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 18)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    return b
end

function UI:Init()
    local f = CreateFrame("Frame", "WayfarerFrame", UIParent, "BackdropTemplate")
    f:SetSize(300, 62)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0.05, 0.04, 0.03, 0.88)
    f:SetBackdropBorderColor(0.8, 0.65, 0.3, 1)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(frame)
        if not ns.db.lockFrame then
            frame:StartMoving()
        end
    end)
    f:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        local point, _, relPoint, x, y = frame:GetPoint()
        ns.db.framePos = { point, relPoint, x, y }
    end)
    f:Hide()
    self.frame = f

    local model = CreateFrame("PlayerModel", nil, f)
    model:SetSize(46, 46)
    model:SetPoint("LEFT", 7, 0)
    self.model = model

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(38, 38)
    icon:SetPoint("CENTER", model, "CENTER")
    icon:SetTexture(BOOK_ICON)
    icon:Hide()
    self.icon = icon

    -- Портрет-иконка собеседника (круглый снимок модели, как в окне квеста).
    local portrait = f:CreateTexture(nil, "ARTWORK")
    portrait:SetSize(40, 40)
    portrait:SetPoint("CENTER", model, "CENTER")
    portrait:Hide()
    self.portrait = portrait
    local ring = f:CreateTexture(nil, "OVERLAY")
    ring:SetSize(52, 52)
    ring:SetPoint("CENTER", portrait, "CENTER", 0, 0)
    ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    ring:SetTexCoord(0, 0.6, 0, 0.6)
    ring:Hide()
    self.ring = ring

    local LEFT, RIGHT = 60, -10

    -- Время реплики цифрами: «0:12 / 0:45» — в строке имени справа.
    local timer = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    timer:SetPoint("TOPRIGHT", RIGHT, -11)
    timer:SetJustifyH("RIGHT")
    self.timer = timer

    local name = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    name:SetPoint("TOPLEFT", LEFT, -10)
    name:SetPoint("RIGHT", timer, "LEFT", -6, 0)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    self.name = name

    self.pauseButton = Button(f, "Пауза", 62, function() ns.Queue:TogglePause() end)
    self.pauseButton:SetPoint("BOTTOMLEFT", LEFT - 2, 14)
    self.skipButton = Button(f, "Далее", 58, function() ns.Queue:Skip() end)
    self.skipButton:SetPoint("LEFT", self.pauseButton, "RIGHT", 3, 0)
    self.stopButton = Button(f, "Стоп", 50, function() ns.Queue:Clear() end)
    self.stopButton:SetPoint("LEFT", self.skipButton, "RIGHT", 3, 0)

    -- «!» — сообщить о проблеме с репликой (ударение, голос, обрезка...).
    self.reportButton = Button(f, "!", 22, function() ns.Report:Open() end)
    self.reportButton:SetPoint("BOTTOMRIGHT", RIGHT + 2, 14)
    self.reportButton:SetScript("OnEnter", function(button)
        GameTooltip:SetOwner(button, "ANCHOR_TOP")
        GameTooltip:SetText("Сообщить о проблеме")
        GameTooltip:AddLine("Ударение, голос, обрезка, подача. Список — /wf reports.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    self.reportButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local queued = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    queued:SetPoint("LEFT", self.stopButton, "RIGHT", 6, 0)
    self.queued = queued

    -- Сколько осталось до конца — тонкая полоса без цифр.
    local bar = CreateFrame("StatusBar", nil, f)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(0.85, 0.7, 0.3)
    bar:SetHeight(3)
    bar:SetPoint("BOTTOMLEFT", LEFT, 8)
    bar:SetPoint("RIGHT", RIGHT, 0)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    self.bar = bar

    self:ApplySettings()
end

function UI:ApplySettings()
    local f = self.frame
    if not f then
        return
    end
    f:SetScale(ns.db.frameScale or 1)
    f:ClearAllPoints()
    local pos = ns.db.framePos
    if pos then
        f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        f:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 220)
    end
    self:Refresh()
end

local function Clock(seconds)
    seconds = math.max(0, math.floor((seconds or 0) + 0.5))
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- Иконка вместо портрета: лор места — летопись, рассказчик и предметы — книга.
local function FallbackIcon(item)
    return item.zone and LORE_ICON or BOOK_ICON
end

--- 2D-портрет: снимок собеседника, если он рядом, иначе по модели NPC из пакета.
function UI:SetIconPortrait(item)
    local p = item.portrait or {}
    local tex = self.portrait
    local shown = false
    if p.unit and Identity.IsStillPresent(item.target) and SetPortraitTexture then
        shown = pcall(SetPortraitTexture, tex, p.unit)
    end
    if not shown and p.display and SetPortraitTextureFromCreatureDisplayID then
        shown = pcall(SetPortraitTextureFromCreatureDisplayID, tex, p.display)
    end
    self.model:Hide()
    if shown then
        self.icon:Hide()
        tex:Show()
        self.ring:Show()
    else
        tex:Hide()
        self.ring:Hide()
        self.icon:SetTexture(FallbackIcon(item))
        self.icon:Show()
    end
end

function UI:SetPortrait(item)
    if ns.db.portraitMode ~= "model" then
        self:SetIconPortrait(item)
        return
    end
    local model, icon = self.model, self.icon
    local p = item.portrait or {}
    local shown = false
    self.portrait:Hide()
    self.ring:Hide()

    if p.unit and Identity.IsStillPresent(item.target) then
        shown = pcall(model.SetUnit, model, p.unit)
    end
    if not shown and p.display then
        shown = pcall(model.SetDisplayInfo, model, p.display)
    end
    if not shown and p.creature then
        shown = pcall(model.SetCreature, model, p.creature)
    end

    if shown then
        icon:Hide()
        model:Show()
        pcall(model.SetPortraitZoom, model, 0.9)
        pcall(model.SetAnimation, model, ANIM_TALK)
        self.lastTalk = GetTime()
    else
        model:Hide()
        icon:SetTexture(FallbackIcon(item))
        icon:Show()
    end
end

function UI:OnStart(item)
    if not self.frame then
        return
    end
    self.name:SetText(item.name or item.title or "")
    self.bar:SetMinMaxValues(0, item.sound.duration or 1)
    self.bar:SetValue(0)
    self.timer:SetText(Clock(0) .. " / " .. Clock(item.sound.duration))
    self.shownSecond = 0
    self:SetPortrait(item)
    self:Refresh()
end

function UI:Progress(item, elapsed, duration)
    if not self.frame or not self.frame:IsShown() then
        return
    end
    self.bar:SetValue(math.min(elapsed, duration))
    local second = math.floor(math.min(elapsed, duration))
    if second ~= self.shownSecond then
        self.shownSecond = second
        self.timer:SetText(Clock(second) .. " / " .. Clock(duration))
    end
    if self.model:IsShown() and GetTime() - (self.lastTalk or 0) > TALK_REFRESH then
        pcall(self.model.SetAnimation, self.model, ANIM_TALK)
        self.lastTalk = GetTime()
    end
end

function UI:Refresh()
    if ns.ZoneMap then
        ns.ZoneMap:Refresh() -- «Послушать / Стоп» на карте мира следует за очередью
    end
    local f = self.frame
    if not f then
        return
    end
    local queue = ns.Queue
    local current = queue:Current()
    if not ns.db.showFrame or not current then
        f:Hide()
        return
    end
    f:Show()
    if current.waiting then
        self.timer:SetText("")
    end
    self.pauseButton:SetText(queue.paused and "Играть" or "Пауза")
    local rest = queue:Size() - 1
    self.queued:SetText(rest > 0 and ("ещё " .. rest) or "")
    if queue.paused or current.waiting then
        pcall(self.model.SetAnimation, self.model, ANIM_IDLE)
    end
end
