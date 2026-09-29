local _, ns = ...
local Util, Identity = ns.Util, ns.Identity

-- Плеер: портрет собеседника (или иконка) в кольце, имя — NPC или место, по желанию название квеста,
-- время реплики, полоса прогресса и кнопки управления. Стили и что показывать — в настройках
-- (Options.lua); все текстуры и шрифты проверены в клиенте Forever (tools/casc_paths.py): путь к
-- несуществующей текстуре клиент рисует зелёным квадратом.
local UI = {}
ns.UI = UI

local ANIM_TALK = 60
local ANIM_IDLE = 0
local TALK_REFRESH = 2.5
local BOOK_ICON = "Interface\\Icons\\INV_Misc_Book_09"    -- рассказчик: книги, записки, предметы
local LORE_ICON = "Interface\\Icons\\INV_Misc_Book_07"     -- лор места: старая летопись (выбор пользователя)

local GOLD_BORDER = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border"
local GOLD_RING = "Interface\\Common\\GoldRing"
local MAP_RING = "Interface\\Minimap\\MiniMap-TrackingBorder"
local FONT_FANCY = "Fonts\\MORPHEUS_CYR.TTF"   -- шрифт заголовков квестов, с кириллицей
local FONT_PLAIN = "Fonts\\FRIZQT___CYR.TTF"

-- Стили окна. bg — фон (tile — плиткой), edge — рамка; цвета текста и полосы подобраны под фон.
local THEMES = {
    parchment = {   -- состаренный пергамент (окно достижений), золотая рамка
        bg = "Interface\\ACHIEVEMENTFRAME\\UI-Achievement-Parchment-Horizontal", tile = false,
        edge = GOLD_BORDER, edgeSize = 16, inset = 4, tint = { 1, 1, 1 },
        name = { 0.29, 0.12, 0.03 }, sub = { 0.33, 0.22, 0.12 }, timer = { 0.33, 0.22, 0.12 },
        bar = { 0.52, 0.30, 0.06 }, track = { 0.18, 0.10, 0.03, 0.35 }, ring = GOLD_RING, shadow = false,
        queued = { 0.36, 0.26, 0.16 },
    },
    marble = {      -- тёмный мрамор, золотая рамка
        bg = "Interface\\FrameGeneral\\UI-Background-Marble", tile = true, tileSize = 128,
        edge = GOLD_BORDER, edgeSize = 16, inset = 4, tint = { 1, 1, 1 },
        name = { 1.0, 0.82, 0.38 }, sub = { 0.82, 0.77, 0.66 }, timer = { 0.86, 0.81, 0.70 },
        bar = { 0.88, 0.70, 0.28 }, track = { 0, 0, 0, 0.55 }, ring = GOLD_RING, shadow = true,
        queued = { 0.62, 0.58, 0.50 },
    },
    classic = {     -- прежний вид: тёмная подложка подсказки
        bg = "Interface\\Tooltips\\UI-Tooltip-Background", tile = true, tileSize = 16,
        edge = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14, inset = 3, tint = { 0.05, 0.04, 0.03 },
        border = { 0.8, 0.65, 0.3 },
        name = { 1.0, 0.82, 0.0 }, sub = { 0.80, 0.80, 0.80 }, timer = { 1, 1, 1 },
        bar = { 0.85, 0.70, 0.30 }, track = { 0, 0, 0, 0.4 }, ring = MAP_RING, shadow = true,
        queued = { 0.5, 0.5, 0.5 },
    },
    clear = {       -- без фона: только портрет, имя и полоса поверх игры
        name = { 1.0, 0.84, 0.45 }, sub = { 0.92, 0.88, 0.80 }, timer = { 0.95, 0.92, 0.85 },
        bar = { 0.95, 0.76, 0.30 }, track = { 0, 0, 0, 0.45 }, ring = GOLD_RING, shadow = true, outline = true,
        queued = { 0.85, 0.82, 0.75 },
    },
}
UI.THEMES = THEMES

local WIDTH, LEFT, RIGHT = 320, 66, -12

local function Button(parent, label, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 18)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    return b
end

local function Theme()
    return THEMES[ns.db.frameTheme] or THEMES.parchment
end

function UI:Init()
    local f = CreateFrame("Frame", "WayfarerFrame", UIParent, "BackdropTemplate")
    f:SetSize(WIDTH, 64)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
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
    f:SetScript("OnEnter", function() UI:SetHover(true) end)
    f:SetScript("OnLeave", function() UI:CheckHover() end)
    f:Hide()
    self.frame = f

    -- Плавное появление окна.
    local fade = f:CreateAnimationGroup()
    local alpha = fade and fade:CreateAnimation("Alpha")
    if alpha then
        alpha:SetFromAlpha(0)
        alpha:SetToAlpha(1)
        alpha:SetDuration(0.3)
        alpha:SetSmoothing("OUT")
    end
    self.fadeIn = fade

    -- Портрет: 3D-модель или круглый снимок / иконка, поверх — кольцо; «говорит» — кольцо мерцает.
    local model = CreateFrame("PlayerModel", nil, f)
    model:SetSize(46, 46)
    model:SetPoint("LEFT", 9, 0)
    self.model = model

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(38, 38)
    icon:SetPoint("CENTER", model, "CENTER")
    icon:SetTexture(BOOK_ICON)
    icon:Hide()
    self.icon = icon

    local portrait = f:CreateTexture(nil, "ARTWORK")
    portrait:SetSize(42, 42)
    portrait:SetPoint("CENTER", model, "CENTER")
    portrait:Hide()
    self.portrait = portrait

    -- Снимки портретов реплик в очереди: делаются, пока NPC рядом (окно разговора открыто), и
    -- показываются, когда до реплики дошла очередь, а NPC уже далеко.
    self.snaps = {}
    for i = 1, 6 do
        local snap = f:CreateTexture(nil, "ARTWORK")
        snap:SetSize(42, 42)
        snap:SetPoint("CENTER", model, "CENTER")
        snap:Hide()
        self.snaps[i] = snap
    end

    local ring = f:CreateTexture(nil, "OVERLAY")
    ring:SetSize(54, 54)
    ring:SetPoint("CENTER", model, "CENTER")
    ring:Hide()
    self.ring = ring

    local glow = f:CreateTexture(nil, "OVERLAY", nil, 2)
    glow:SetSize(54, 54)
    glow:SetPoint("CENTER", model, "CENTER")
    glow:SetTexture(GOLD_RING)
    glow:SetBlendMode("ADD")
    glow:SetAlpha(0)
    self.glow = glow
    local pulse = glow:CreateAnimationGroup()
    local shine = pulse and pulse:CreateAnimation("Alpha")
    if shine then
        pulse:SetLooping("BOUNCE")
        shine:SetFromAlpha(0.05)
        shine:SetToAlpha(0.55)
        shine:SetDuration(0.9)
        shine:SetSmoothing("IN_OUT")
    end
    self.pulse = pulse

    -- Время реплики цифрами: «0:12 / 0:45» — справа в строке имени.
    local timer = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    timer:SetPoint("TOPRIGHT", RIGHT, -12)
    timer:SetJustifyH("RIGHT")
    self.timer = timer

    local name = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    name:SetPoint("TOPLEFT", LEFT, -10)
    name:SetPoint("RIGHT", timer, "LEFT", -6, 0)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    self.name = name

    -- Название квеста или «Рассказчик» под именем (по желанию).
    local sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -2)
    sub:SetPoint("RIGHT", RIGHT, 0)
    sub:SetJustifyH("LEFT")
    sub:SetWordWrap(false)
    self.sub = sub

    -- Кнопки управления — отдельной группой: их можно скрыть или показывать при наведении.
    local controls = CreateFrame("Frame", nil, f)
    controls:SetPoint("BOTTOMLEFT", LEFT - 2, 12)
    controls:SetPoint("BOTTOMRIGHT", RIGHT + 2, 12)
    controls:SetHeight(18)
    self.controls = controls

    self.pauseButton = Button(controls, "Пауза", 62, function() ns.Queue:TogglePause() end)
    self.pauseButton:SetPoint("LEFT", 0, 0)
    self.skipButton = Button(controls, "Далее", 58, function() ns.Queue:Skip() end)
    self.skipButton:SetPoint("LEFT", self.pauseButton, "RIGHT", 3, 0)
    self.stopButton = Button(controls, "Стоп", 50, function() ns.Queue:Clear() end)
    self.stopButton:SetPoint("LEFT", self.skipButton, "RIGHT", 3, 0)

    -- «!» — сообщить о проблеме с репликой (ударение, голос, обрезка...).
    self.reportButton = Button(controls, "!", 22, function() ns.Report:Open() end)
    self.reportButton:SetPoint("RIGHT", 0, 0)
    self.reportButton:SetScript("OnEnter", function(button)
        UI:SetHover(true)
        GameTooltip:SetOwner(button, "ANCHOR_TOP")
        GameTooltip:SetText("Сообщить о проблеме")
        GameTooltip:AddLine("Ударение, голос, обрезка, подача. Список — /wf reports.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    self.reportButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
        UI:CheckHover()
    end)
    for _, b in ipairs({ self.pauseButton, self.skipButton, self.stopButton }) do
        b:HookScript("OnEnter", function() UI:SetHover(true) end)
        b:HookScript("OnLeave", function() UI:CheckHover() end)
    end

    local queued = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    queued:SetPoint("LEFT", self.stopButton, "RIGHT", 6, 0)
    self.queued = queued

    -- Сколько осталось до конца — тонкая полоса с «искрой» на конце.
    local bar = CreateFrame("StatusBar", nil, f)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetHeight(4)
    bar:SetPoint("BOTTOMLEFT", LEFT, 6)
    bar:SetPoint("RIGHT", RIGHT, 0)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    self.bar = bar
    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints(bar)
    track:SetTexture("Interface\\Buttons\\WHITE8X8")
    self.track = track
    local spark = bar:CreateTexture(nil, "OVERLAY")
    spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    spark:SetBlendMode("ADD")
    spark:SetSize(12, 16)
    spark:Hide()
    self.spark = spark

    self:ApplySettings()
end

--- Стиль, шрифты, видимость частей и размер — по настройкам. Вызывается при любой их смене.
function UI:ApplySettings()
    local f = self.frame
    if not f then
        return
    end
    local db, t = ns.db, Theme()
    if t.bg or t.edge then
        f:SetBackdrop({
            bgFile = t.bg, edgeFile = t.edge, tile = t.tile, tileSize = t.tileSize or 0, edgeSize = t.edgeSize,
            insets = { left = t.inset, right = t.inset, top = t.inset, bottom = t.inset },
        })
        local alpha = db.frameAlpha or 1
        f:SetBackdropColor(t.tint[1], t.tint[2], t.tint[3], (t == THEMES.classic and 0.88 or 1) * alpha)
        local b = t.border or { 1, 1, 1 }
        f:SetBackdropBorderColor(b[1], b[2], b[3], alpha)
    else
        f:SetBackdrop(nil)
    end

    local flags = t.outline and "OUTLINE" or ""
    if db.nameFont == "fancy" then
        self.name:SetFont(FONT_FANCY, 17, flags)
    else
        self.name:SetFont(FONT_PLAIN, 13, flags)
    end
    self.sub:SetFont(FONT_PLAIN, 10, t.outline and "OUTLINE" or "")
    self.timer:SetFont(FONT_PLAIN, 10, t.outline and "OUTLINE" or "")
    for fs, color in pairs({ [self.name] = t.name, [self.sub] = t.sub, [self.timer] = t.timer, [self.queued] = t.queued }) do
        fs:SetTextColor(color[1], color[2], color[3])
        if t.shadow then
            fs:SetShadowColor(0, 0, 0, 0.9)
            fs:SetShadowOffset(1, -1)
        else
            fs:SetShadowOffset(0, 0)
        end
    end
    self.bar:SetStatusBarColor(t.bar[1], t.bar[2], t.bar[3])
    self.track:SetVertexColor(t.track[1], t.track[2], t.track[3], t.track[4])
    self.ring:SetTexture(t.ring)
    if t.ring == MAP_RING then
        self.ring:SetTexCoord(0, 0.6, 0, 0.6)
    else
        self.ring:SetTexCoord(0, 1, 0, 1)
    end

    -- Что показывать.
    local portrait = db.portraitMode ~= "none"
    local left = portrait and LEFT or 14
    self.name:ClearAllPoints()
    self.name:SetPoint("TOPLEFT", left, -10)
    self.name:SetPoint("RIGHT", self.timer, "LEFT", -6, 0)
    self.bar:ClearAllPoints()
    self.bar:SetPoint("BOTTOMLEFT", left, 6)
    self.bar:SetPoint("RIGHT", RIGHT, 0)
    self.controls:ClearAllPoints()
    self.controls:SetPoint("BOTTOMLEFT", left - 2, 12)
    self.controls:SetPoint("BOTTOMRIGHT", RIGHT + 2, 12)
    self.timer:SetShown(db.showTimer)
    self.bar:SetShown(db.showBar)
    self.sub:SetShown(db.showTitle)
    self.reportButton:SetShown(db.showReport)
    local controls = db.controlsMode ~= "hidden"
    self.controls:SetShown(controls)
    local height = 40 + (db.showTitle and 12 or 0) + (controls and 22 or 0)
    f:SetSize(WIDTH, math.max(height, portrait and 58 or 0))
    self:SetHover(false)

    f:SetScale(db.frameScale or 1)
    f:ClearAllPoints()
    local pos = db.framePos
    if pos then
        f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        f:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 220)
    end
    if self.current then
        self:SetPortrait(self.current)
    end
    self:Refresh()
end

--- Кнопки «при наведении»: видны, пока мышь над окном.
function UI:SetHover(over)
    if ns.db.controlsMode == "hover" then
        self.controls:SetAlpha(over and 1 or 0)
    else
        self.controls:SetAlpha(1)
    end
end

function UI:CheckHover()
    C_Timer.After(0.05, function()
        local f = self.frame
        UI:SetHover(f and f.IsMouseOver and f:IsMouseOver() or false)
    end)
end

local function Clock(seconds)
    seconds = math.max(0, math.floor((seconds or 0) + 0.5))
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- Иконка вместо портрета: лор места — летопись, рассказчик и предметы — книга.
local function FallbackIcon(item)
    return item.zone and LORE_ICON or BOOK_ICON
end

--- Снимок портрета собеседника для реплики, которая ещё ждёт в очереди (вызывается при добавлении).
function UI:Snapshot(item)
    local p = item.portrait
    if not (self.snaps and p and p.unit and not p.snap and SetPortraitTexture) then
        return
    end
    if not Identity.IsStillPresent(item.target) then
        return
    end
    self.snapOwners = self.snapOwners or {}
    for i, snap in ipairs(self.snaps) do
        if not self.snapOwners[i] then
            if pcall(SetPortraitTexture, snap, p.unit) then
                self.snapOwners[i] = item
                p.snap, p.snapIndex = snap, i
                item.onRemoved = function(removed) UI:ReleaseSnapshot(removed) end
            end
            return
        end
    end
end

function UI:ReleaseSnapshot(item)
    local p = item.portrait
    local i = p and p.snapIndex
    if i and self.snapOwners and self.snapOwners[i] == item then
        self.snapOwners[i] = nil
        self.snaps[i]:Hide()
        p.snap, p.snapIndex = nil, nil
    end
end

local function HideSnapshots(self)
    for _, snap in ipairs(self.snaps or {}) do
        snap:Hide()
    end
end

--- 2D-портрет: собеседник, если он рядом; иначе снимок, сделанный при взятии квеста; иначе по модели
--- NPC (displayID); иначе иконка.
function UI:SetIconPortrait(item)
    local p = item.portrait or {}
    local tex = self.portrait
    local shown = false
    HideSnapshots(self)
    if p.unit and Identity.IsStillPresent(item.target) and SetPortraitTexture then
        shown = pcall(SetPortraitTexture, tex, p.unit)
    end
    if not shown and p.snap then
        tex:Hide()
        self.model:Hide()
        self.icon:Hide()
        p.snap:Show()
        self.ring:Show()
        return
    end
    if not shown and p.display and SetPortraitTextureFromCreatureDisplayID then
        shown = pcall(SetPortraitTextureFromCreatureDisplayID, tex, p.display)
    end
    self.model:Hide()
    self.ring:Show()
    if shown then
        self.icon:Hide()
        tex:Show()
    else
        tex:Hide()
        self.icon:SetTexture(FallbackIcon(item))
        self.icon:Show()
    end
end

function UI:SetPortrait(item)
    HideSnapshots(self)
    if ns.db.portraitMode == "none" then
        self.model:Hide()
        self.icon:Hide()
        self.portrait:Hide()
        self.ring:Hide()
        return
    end
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

local function Subtitle(item)
    if item.zone then
        return "Рассказчик"
    end
    return item.title or ""
end

function UI:OnStart(item)
    if not self.frame then
        return
    end
    self.current = item
    self.name:SetText(item.name or item.title or "")
    self.sub:SetText(Subtitle(item))
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
    local value = math.min(elapsed, duration)
    self.bar:SetValue(value)
    if ns.db.showBar and duration > 0 then
        local width = self.bar:GetWidth() or 0
        self.spark:ClearAllPoints()
        self.spark:SetPoint("CENTER", self.bar, "LEFT", width * value / duration, 0)
        self.spark:Show()
    end
    local second = math.floor(value)
    if second ~= self.shownSecond then
        self.shownSecond = second
        self.timer:SetText(Clock(second) .. " / " .. Clock(duration))
    end
    if self.model:IsShown() and GetTime() - (self.lastTalk or 0) > TALK_REFRESH then
        pcall(self.model.SetAnimation, self.model, ANIM_TALK)
        self.lastTalk = GetTime()
    end
end

--- Мерцание кольца, пока реплика звучит (не на паузе и не в ожидании).
function UI:SetTalking(talking)
    local pulse = self.pulse
    if not pulse then
        return
    end
    talking = talking and ns.db.animations and ns.db.portraitMode ~= "none" and self.ring:IsShown()
    if talking and not self.talking then
        pulse:Play()
    elseif not talking and self.talking then
        pulse:Stop()
        self.glow:SetAlpha(0)
    end
    self.talking = talking
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
        if f:IsShown() then
            f:Hide()
        end
        self.spark:Hide()
        self:SetTalking(false)
        self.current = nil
        return
    end
    if not f:IsShown() then
        f:Show()
        if ns.db.animations and self.fadeIn then
            self.fadeIn:Play()
        end
    end
    if current.waiting then
        self.timer:SetText("")
        self.spark:Hide()
    end
    self.pauseButton:SetText(queue.paused and "Играть" or "Пауза")
    local rest = queue:Size() - 1
    self.queued:SetText((ns.db.showQueue and rest > 0) and ("ещё " .. rest) or "")
    if queue.paused or current.waiting then
        pcall(self.model.SetAnimation, self.model, ANIM_IDLE)
    end
    self:SetTalking(not queue.paused and not current.waiting)
end
