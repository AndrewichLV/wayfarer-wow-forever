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
-- NPC, чья модель не загрузилась: значок его расы по голосу (книга у NPC выглядела как рассказчик — баг
-- 2026-10-07), раса без значка (гоблины, элементали) — силуэт.
local NPC_ICON = "Interface\\CharacterFrame\\TempPortrait"
local RACE_ICONS = {
    human = { "Interface\\Icons\\Achievement_Character_Human_Male", "Interface\\Icons\\Achievement_Character_Human_Female" },
    child = { "Interface\\Icons\\Achievement_Character_Human_Male", "Interface\\Icons\\Achievement_Character_Human_Female" },
    dwarf = { "Interface\\Icons\\Achievement_Character_Dwarf_Male", "Interface\\Icons\\Achievement_Character_Dwarf_Female" },
    gnome = { "Interface\\Icons\\Achievement_Character_Gnome_Male", "Interface\\Icons\\Achievement_Character_Gnome_Female" },
    nightelf = { "Interface\\Icons\\Achievement_Character_Nightelf_Male",
        "Interface\\Icons\\Achievement_Character_Nightelf_Female" },
    orc = { "Interface\\Icons\\Achievement_Character_Orc_Male", "Interface\\Icons\\Achievement_Character_Orc_Female" },
    troll = { "Interface\\Icons\\Achievement_Character_Troll_Male", "Interface\\Icons\\Achievement_Character_Troll_Female" },
    tauren = { "Interface\\Icons\\Achievement_Character_Tauren_Male", "Interface\\Icons\\Achievement_Character_Tauren_Female" },
    scourge = { "Interface\\Icons\\Achievement_Character_Undead_Male", "Interface\\Icons\\Achievement_Character_Undead_Female" },
    bloodelf = { "Interface\\Icons\\Achievement_Character_Bloodelf_Male",
        "Interface\\Icons\\Achievement_Character_Bloodelf_Female" },
    skybourneelf = { "Interface\\Icons\\Achievement_Character_Bloodelf_Male",
        "Interface\\Icons\\Achievement_Character_Bloodelf_Female" },
}
-- Модель NPC, которого нет в кэше клиента (квест из журнала у NPC Forever без облика в модуле): запрос существа у
-- сервера и повторные попытки, пока модель не придёт.
local MODEL_RETRY, MODEL_TRIES, MODEL_RESET = 0.4, 30, 5

local GOLD_BORDER = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border"
local GOLD_RING = "Interface\\Common\\GoldRing"
local MAP_RING = "Interface\\Minimap\\MiniMap-TrackingBorder"
local FONT_FANCY = "Fonts\\MORPHEUS_CYR.TTF"   -- шрифт заголовков квестов, с кириллицей
local FONT_PLAIN = "Fonts\\FRIZQT___CYR.TTF"

-- Стили окна. bg — фон (tile — плиткой), edge — рамка; цвета текста и полосы подобраны под фон.
local THEMES = {
    -- «Говорящая голова», как окно TalkingHead в retail (просьба пользователя 2026-10-02): звёздное небо,
    -- 3D-портрет в золотой рамке, имя, текст реплики с прокруткой за голосом, «X», тонкая золотая полоса.
    -- В клиенте Forever такого окна и его текстур нет — свои, Media/Player (tools/make_player_assets.py).
    head = {
        layout = "head", tint = { 1, 1, 1 },
        name = { 1.0, 0.82, 0.0 }, sub = { 0.72, 0.72, 0.80 }, timer = { 0.66, 0.66, 0.74 },
        text = { 0.93, 0.93, 0.93 }, bar = { 0.95, 0.75, 0.25 }, track = { 1, 1, 1, 0.05 }, shadow = true,
        queued = { 0.66, 0.66, 0.74 },
    },
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

-- Размеры «говорящей головы»: окно 480×128 (фон 1024×256 — почти те же пропорции), портрет 108 с моделью 94,
-- текст справа от портрета, кнопки столбиком под «X».
local MEDIA = "Interface\\AddOns\\Wayfarer\\Media\\Player\\"
local HEAD_W, HEAD_H = 480, 128
local HEAD_FRAME, HEAD_MODEL, HEAD_PAD = 108, 94, 10
local HEAD_TEXT = HEAD_PAD + HEAD_FRAME + 12
local TEXT_SIZE, TEXT_SPACING = 12, 2
-- «Говорящая голова» при «Размере окна» 100% — ещё чуть меньше базовых размеров (пользователь 2026-10-02:
-- «сделать ещё чуть меньше»); дальше — ползунок в настройках.
local HEAD_K = 0.88
-- Рассказчик: книга в своей рамке с камнями (картинка пользователя, 2026-10-02; tools/make_player_assets.py) —
-- вместо золотой рамки портрета.
local NARRATOR_ICON = MEDIA .. "narrator"

-- Фон по расе говорящего (просьба пользователя 2026-10-02: «для каждой расы свой фон»). Раса — по голосу из пакета
-- (слот вида «orc-male-…»); у элементалей — по стихии; кого нет в таблице — нейтральный.
local KITS = {
    human = "human", dwarf = "dwarf", gnome = "gnome", nightelf = "nightelf", orc = "orc", troll = "troll",
    tauren = "tauren", scourge = "forsaken", goblin = "goblin", bloodelf = "bloodelf", skybourneelf = "skyelf",
    satyr = "fel", myzrael = "earth", child = "human", narrator = "narrator",
}
local SLOT_KITS = { ["elemental-water"] = "water", ["elemental-earth"] = "earth" }

local function Voice(item)
    return tostring(item.sound and item.sound.voice or "")
end

--- Говорит рассказчик: лор места или текст голосом рассказчика (книги, записки, описания).
local function IsNarrator(item)
    return item.zone ~= nil or Voice(item):match("^narrator") ~= nil
end
UI.IsNarrator = IsNarrator

local function Kit(item)
    if item.zone then
        return "narrator"
    end
    local voice = Voice(item)
    for slot, kit in pairs(SLOT_KITS) do
        if voice:sub(1, #slot) == slot then
            return kit
        end
    end
    return KITS[voice:match("^(%a+)") or ""] or "neutral"
end
UI.Kit = Kit

local function Button(parent, label, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 18)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    return b
end

local function Theme()
    return THEMES[ns.db.frameTheme] or THEMES.head
end

local function Tooltip(owner, title, text)
    UI:SetHover(true)
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    GameTooltip:SetText(title)
    if text then
        GameTooltip:AddLine(text, 1, 1, 1, true)
    end
    GameTooltip:Show()
end

local function TooltipOff()
    GameTooltip:Hide()
    UI:CheckHover()
end

-- Кнопка «говорящей головы»: тёмный квадрат в золотом ободке (Media/Player/btn-*), подсветка при наведении.
local function IconButton(parent, texture, title, text, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(17, 17)
    b:SetNormalTexture(MEDIA .. texture)
    b:SetPushedTexture(MEDIA .. texture)
    local pushed = b.GetPushedTexture and b:GetPushedTexture()
    if pushed then
        pushed:SetVertexColor(0.65, 0.65, 0.65)
    end
    b:SetHighlightTexture(MEDIA .. "btn-hl", "ADD")
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(button) Tooltip(button, title, text) end)
    b:SetScript("OnLeave", TooltipOff)
    return b
end

--- Части «говорящей головы»: фон, рамка портрета, «X», текст с прокруткой, кнопки столбиком.
--- Имя, время, «ещё N», полоса и сам портрет — общие с компактным видом (их расставляет ApplySettings).
function UI:CreateHead(f)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    bg:SetTexture(MEDIA .. "bg-neutral")
    bg:Hide()
    self.headBg = bg

    -- Тёмная подложка под 3D-моделью (модель — отдельный фрейм и рисуется поверх неё).
    local shade = f:CreateTexture(nil, "BORDER")
    shade:SetSize(HEAD_MODEL, HEAD_MODEL)
    shade:SetPoint("TOPLEFT", HEAD_PAD + (HEAD_FRAME - HEAD_MODEL) / 2, -(HEAD_PAD + (HEAD_FRAME - HEAD_MODEL) / 2))
    shade:SetTexture("Interface\\Buttons\\WHITE8X8")
    shade:SetVertexColor(0.02, 0.02, 0.035, 0.92)
    shade:Hide()
    self.headShade = shade

    -- Золотая рамка — на своём фрейме выше модели (дочерний фрейм рисуется поверх слоёв родителя).
    local border = CreateFrame("Frame", nil, f)
    border:SetSize(HEAD_FRAME, HEAD_FRAME)
    border:SetPoint("TOPLEFT", HEAD_PAD, -HEAD_PAD)
    border:SetFrameLevel((f:GetFrameLevel() or 1) + 6)
    local art = border:CreateTexture(nil, "ARTWORK")
    art:SetAllPoints(border)
    art:SetTexture(MEDIA .. "portrait")
    border:Hide()
    self.headBorder = border

    local close = CreateFrame("Button", nil, f)
    close:SetSize(22, 22)
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetFrameLevel((f:GetFrameLevel() or 1) + 7)
    -- «X» — жёлтый крест на красном из клиента, как в образце.
    close:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    close:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
    close:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
    close:SetScript("OnClick", function() ns.Queue:Clear() end)
    close:SetScript("OnEnter", function(button)
        Tooltip(button, "Стоп", "Замолчать и очистить очередь. Клавиша — в «Назначении клавиш», /wf stop.")
    end)
    close:SetScript("OnLeave", TooltipOff)
    close:Hide()
    self.headClose = close

    -- Текст реплики: вся реплика, окно показывает несколько строк и едет за голосом (Progress).
    local scroll = CreateFrame("ScrollFrame", nil, f)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(HEAD_W - HEAD_TEXT - 32, 1)
    scroll:SetScrollChild(child)
    local text = child:CreateFontString(nil, "OVERLAY")
    text:SetFont(FONT_PLAIN, TEXT_SIZE, "")
    text:SetPoint("TOPLEFT", 0, 0)
    text:SetWidth(HEAD_W - HEAD_TEXT - 32)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    text:SetSpacing(TEXT_SPACING)
    scroll:SetScript("OnUpdate", function(frame, elapsed)
        local target = UI.scrollTarget or 0
        local current = frame:GetVerticalScroll() or 0
        if math.abs(target - current) < 0.5 then
            if current ~= target then
                frame:SetVerticalScroll(target)
            end
            return
        end
        frame:SetVerticalScroll(current + (target - current) * math.min(1, (elapsed or 0) * 6))
    end)
    scroll:Hide()
    self.textScroll, self.textChild, self.text = scroll, child, text

    -- Новый текст проявляется (новая реплика в том же окне).
    local fade = child:CreateAnimationGroup()
    local alpha = fade and fade:CreateAnimation("Alpha")
    if alpha then
        alpha:SetFromAlpha(0)
        alpha:SetToAlpha(1)
        alpha:SetDuration(0.35)
        alpha:SetSmoothing("OUT")
    end
    self.textFade = fade

    local column = CreateFrame("Frame", nil, f)
    column:SetSize(17, 80)
    column:SetPoint("TOPRIGHT", -7, -30)
    column:SetFrameLevel((f:GetFrameLevel() or 1) + 7)
    self.headControls = column
    self.headPause = IconButton(column, "btn-pause", "Пауза", "Пауза и продолжение (реплика начнётся заново). /wf pause",
        function() ns.Queue:TogglePause() end)
    self.headSkip = IconButton(column, "btn-next", "Далее", "Следующая реплика в очереди. /wf skip",
        function() ns.Queue:Skip() end)
    self.headReport = IconButton(column, "btn-report", "Сообщить о проблеме",
        "Ударение, голос, обрезка, подача. Список — /wf reports.", function() ns.Report:Open() end)
    -- Дневник путника (Journal.lua; в выпусках для игроков его нет — кнопки тоже).
    if ns.Journal then
        self.headJournal = IconButton(column, "btn-journal", "Дневник путника",
            "Открытые места, встреченные противники и всё, что вы услышали. /wf journal",
            function() ns.Journal:Toggle() end)
    end
end

--- Кнопки столбиком сверху вниз: только видимые, без пропусков.
function UI:LayoutColumn()
    local y = 0
    for _, b in ipairs({ self.headPause, self.headSkip, self.headReport, self.headJournal }) do
        if b and b:IsShown() then
            b:ClearAllPoints()
            b:SetPoint("TOP", 0, -y)
            y = y + 20
        end
    end
end

-- Портрет (модель; снимки, иконка и кольцо — по её центру): квадрат size у точки point окна.
function UI:PlacePortrait(size, point, x, y, round)
    self.model:ClearAllPoints()
    self.model:SetSize(size, size)
    self.model:SetPoint(point, self.frame, point, x, y)
    local inner = round and size - 4 or size - 14
    self.icon:SetSize(round and size - 8 or inner, round and size - 8 or inner)
    self.portrait:SetSize(round and size - 4 or inner, round and size - 4 or inner)
    for _, snap in ipairs(self.snaps) do
        snap:SetSize(round and size - 4 or inner, round and size - 4 or inner)
    end
    if round then
        self.icon:SetTexCoord(0, 1, 0, 1)
    else
        self.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) -- без тёмной каймы иконки: рамка своя
    end
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
        -- Сдвиг — в единицах окна при его масштабе: масштаб запоминаем, чтобы при смене размера окно не уезжало.
        ns.db.framePos = { point, relPoint, x, y, frame:GetScale() }
    end)
    f:SetScript("OnEnter", function() UI:SetHover(true) end)
    f:SetScript("OnLeave", function() UI:CheckHover() end)
    f:Hide()
    self.frame = f
    -- Модель, заданную скрытому окну, клиент не загружает (особенность PlayerModel). Реплика из журнала или списка
    -- заданий при пустой очереди звучит сразу: портрет задавался до показа окна (OnStart раньше Refresh), и первая
    -- реплика оставалась без головы, а следующая в очереди — с головой (баг 2026-10-07). Окно показалось — портрет
    -- задаётся заново.
    f:HookScript("OnShow", function()
        if self.current then
            self:SetPortrait(self.current)
        end
    end)

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
    model:SetScript("OnModelLoaded", function()
        -- Модель существа пришла позже (см. SetPortrait): показываем, если окно всё ещё про ту же реплику.
        self:ModelArrived(self.modelPending)
    end)
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
    -- Дневник путника: атлас мест, бестиарий, летопись (Journal.lua; в выпусках для игроков его нет — кнопки тоже).
    local journal = ns.Journal and CreateFrame("Button", nil, controls)
    if journal then
        journal:SetSize(18, 18)
        journal:SetPoint("RIGHT", self.reportButton, "LEFT", -4, 0)
        journal:SetNormalTexture("Interface\\Icons\\INV_Misc_Book_09")
        journal:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        journal:SetScript("OnClick", function() ns.Journal:Toggle() end)
        journal:SetScript("OnEnter", function(button)
            UI:SetHover(true)
            GameTooltip:SetOwner(button, "ANCHOR_TOP")
            GameTooltip:SetText("Дневник путника")
            GameTooltip:AddLine("Открытые места, встреченные противники и всё, что вы услышали. /wf journal", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        journal:SetScript("OnLeave", function()
            GameTooltip:Hide()
            UI:CheckHover()
        end)
        self.journalButton = journal
    end

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

    self:CreateHead(f)
    self:ApplySettings()
end

--- Стиль, шрифты, видимость частей и размер — по настройкам. Вызывается при любой их смене.
function UI:ApplySettings()
    local f = self.frame
    if not f then
        return
    end
    local db, t = ns.db, Theme()
    self.layout = t.layout or "compact"
    if self.layout == "head" then
        self:LayoutHead(t)
    else
        self:LayoutCompact(t)
    end

    local scale = (db.frameScale or 1) * (self.layout == "head" and HEAD_K or 1)
    f:SetScale(scale)
    f:ClearAllPoints()
    local pos = db.framePos
    if pos then
        local k = (pos[5] or scale) / scale
        f:SetPoint(pos[1], UIParent, pos[2], pos[3] * k, pos[4] * k)
    else
        f:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 220)
    end
    if self.current then
        self:SetPortrait(self.current)
        self:ShowText(self.current, true)
    end
    self:Refresh()
end

--- Цвета и тени надписей стиля (общие для обоих видов).
function UI:ColorTexts(t)
    for fs, color in pairs({ [self.name] = t.name, [self.sub] = t.sub, [self.timer] = t.timer, [self.queued] = t.queued,
        [self.text] = t.text or t.sub }) do
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
end

--- «Говорящая голова»: окно 600×160, портрет слева, имя и текст справа, «X» и кнопки — у правого края.
function UI:LayoutHead(t)
    local f, db = self.frame, ns.db
    f:SetBackdrop(nil)
    f:SetSize(HEAD_W, HEAD_H)
    local alpha = db.frameAlpha or 1
    self.headBg:Show()
    self.headBg:SetAlpha(alpha)

    local portrait = db.portraitMode ~= "none"
    self.headShade:SetShown(portrait)
    self.headBorder:SetShown(portrait)
    self.ring:Hide()
    self:PlacePortrait(HEAD_MODEL, "TOPLEFT", HEAD_PAD + (HEAD_FRAME - HEAD_MODEL) / 2,
        -(HEAD_PAD + (HEAD_FRAME - HEAD_MODEL) / 2), false)
    local left = portrait and HEAD_TEXT or 14

    self.name:SetFont(db.nameFont == "fancy" and FONT_FANCY or FONT_PLAIN, db.nameFont == "fancy" and 18 or 14, "")
    self.sub:SetFont(FONT_PLAIN, 11, "")
    self.timer:SetFont(FONT_PLAIN, 10, "")
    self.queued:SetFont(FONT_PLAIN, 10, "")
    self.text:SetFont(FONT_PLAIN, TEXT_SIZE, "")
    self:ColorTexts(t)

    local controls = db.controlsMode ~= "hidden"
    self.timer:ClearAllPoints()
    self.timer:SetPoint("TOPRIGHT", controls and -30 or -10, -16)
    self.timer:SetShown(db.showTimer)
    self.name:ClearAllPoints()
    self.name:SetPoint("TOPLEFT", left, -12)
    self.name:SetPoint("RIGHT", self.timer, "LEFT", -8, 0)
    self.sub:ClearAllPoints()
    self.sub:SetPoint("TOPLEFT", self.name, "BOTTOMLEFT", 0, -2)
    self.sub:SetPoint("RIGHT", self.timer, "LEFT", -8, 0)
    self.sub:SetShown(db.showTitle)

    local top = 36 + (db.showTitle and 12 or 0)
    local scroll = self.textScroll
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", left, -top)
    scroll:SetPoint("BOTTOMRIGHT", controls and -32 or -12, 10)
    local width = HEAD_W - left - (controls and 32 or 12)
    self.textChild:SetWidth(width)
    self.text:SetWidth(width)
    scroll:SetShown(db.subtitles ~= false)

    self.bar:ClearAllPoints()
    self.bar:SetPoint("BOTTOMLEFT", 10, 5)
    self.bar:SetPoint("BOTTOMRIGHT", -10, 5)
    self.bar:SetHeight(2)
    self.bar:SetShown(db.showBar)
    self.spark:SetSize(8, 10)

    self.queued:ClearAllPoints()
    self.queued:SetPoint("BOTTOMRIGHT", -8, 6)
    self.controls:Hide()
    self.headClose:SetShown(controls)
    self.headControls:SetShown(controls)
    self.headReport:SetShown(db.showReport)
    self:LayoutColumn()
    self:SetHover(false)
end

--- Компактный вид (пергамент, мрамор, классика, без фона): окно 320 в высоту по содержимому.
function UI:LayoutCompact(t)
    local f, db = self.frame, ns.db
    for _, part in ipairs({ self.headBg, self.headShade, self.headBorder, self.headClose, self.headControls,
        self.textScroll }) do
        part:Hide()
    end
    self:PlacePortrait(46, "LEFT", 9, 0, true)
    self.bar:SetHeight(4)
    self.spark:SetSize(12, 16)
    self.timer:ClearAllPoints()
    self.timer:SetPoint("TOPRIGHT", RIGHT, -12)
    self.sub:ClearAllPoints()
    self.sub:SetPoint("TOPLEFT", self.name, "BOTTOMLEFT", 0, -2)
    self.sub:SetPoint("RIGHT", RIGHT, 0)
    self.queued:ClearAllPoints()
    self.queued:SetPoint("LEFT", self.stopButton, "RIGHT", 6, 0)
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
    self.queued:SetFont(FONT_PLAIN, 10, t.outline and "OUTLINE" or "")
    self:ColorTexts(t)
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
end

--- Кнопки «при наведении»: видны, пока мышь над окном.
function UI:SetHover(over)
    local alpha = (ns.db.controlsMode ~= "hover" or over) and 1 or 0
    self.controls:SetAlpha(alpha)
    if self.headControls then
        self.headControls:SetAlpha(alpha)
        self.headClose:SetAlpha(alpha)
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

-- Иконка вместо портрета: лор места — летопись, рассказчик и предметы — книга, NPC — значок расы по голосу.
local function FallbackIcon(item)
    if item.zone then
        return LORE_ICON
    end
    local voice = Voice(item)
    if voice == "" then
        return (item.portrait and item.portrait.creature) and NPC_ICON or BOOK_ICON
    end
    if voice:match("^narrator") then
        return BOOK_ICON
    end
    local race = RACE_ICONS[voice:match("^(%a+)") or ""]
    if race then
        return voice:match("%-female") and race[2] or race[1]
    end
    return NPC_ICON
end
UI.FallbackIcon = FallbackIcon

-- Запросить существо у сервера (как тултип по ссылке unit:Creature): после ответа оно в кэше клиента, и модель
-- по SetCreature загружается.
local function RequestCreature(id)
    if id and C_TooltipInfo and C_TooltipInfo.GetHyperlink then
        pcall(C_TooltipInfo.GetHyperlink, ("unit:Creature-0-0-0-0-%d-0000000000"):format(id))
    end
end

--- Модель собеседника пришла: показать вместо значка, если окно всё ещё про ту же реплику.
function UI:ModelArrived(item)
    if not item or item ~= self.modelPending or item ~= self.current then
        return
    end
    self.modelPending = nil
    self.icon:Hide()
    if item.portrait and item.portrait.snap then
        item.portrait.snap:Hide()
    end
    self:ShowModel()
end

--- Существа нет в кэше клиента (облик 0): спросить его у сервера и задать снова, когда клиент узнает (облик > 0).
--- Задавать заново — не чаще раза в 2 с: SetCreature/SetDisplayInfo начинает загрузку модели сначала, и частый повтор
--- обрывал долгую загрузку с диска (регрессия 2026-10-07).
local function Known(model)
    return (tonumber(Util.Try(model.GetDisplayInfo, model)) or 0) > 0 or Util.Try(model.GetModelFileID, model) ~= nil
end

function UI:WatchModel(item)
    if self.modelTicker then
        self.modelTicker:Cancel()
        self.modelTicker = nil
    end
    local p = item.portrait or {}
    RequestCreature(p.creature)
    if not (C_Timer and C_Timer.NewTicker) then
        return
    end
    local tries = 0
    local ticker
    ticker = C_Timer.NewTicker(MODEL_RETRY, function()
        tries = tries + 1
        local model = self.model
        if self.modelPending ~= item or self.current ~= item or tries > MODEL_TRIES then
            ticker:Cancel()
            if self.modelTicker == ticker then
                self.modelTicker = nil
            end
            return
        end
        if not Known(model) and tries % MODEL_RESET == 1 then
            pcall(model.SetCreature, model, p.creature)
        end
        if Known(model) then
            self:ModelArrived(item)
        end
    end)
    self.modelTicker = ticker
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

--- Показать загруженную 3D-модель собеседника: «говорящая голова» — крупно лицо (headPortrait = "head") или по пояс.
function UI:ShowModel()
    local model = self.model
    model:SetAlpha(1)
    model:Show()
    local zoom = self.layout ~= "head" and 0.9 or ns.db.headPortrait == "bust" and 0.75 or 1
    pcall(model.SetPortraitZoom, model, zoom)
    pcall(model.SetAnimation, model, ANIM_TALK)
    self.lastTalk = GetTime()
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
    -- В «говорящей голове» портрет квадратный — только 3D-модель (круглый снимок — запасной путь).
    if ns.db.portraitMode ~= "model" and self.layout ~= "head" then
        self:SetIconPortrait(item)
        return
    end
    local model, icon = self.model, self.icon
    local p = item.portrait or {}
    local shown = false
    self.portrait:Hide()
    self.ring:Hide()

    -- Рассказчик в «говорящей голове»: книга в своей рамке с камнями, без золотой рамки и подложки портрета.
    local narrator = self.layout == "head" and IsNarrator(item)
    if self.layout == "head" then
        self.headBorder:SetShown(not narrator)
        self.headShade:SetShown(not narrator)
    end
    if narrator then
        model:Hide()
        icon:SetTexture(NARRATOR_ICON)
        icon:SetTexCoord(0, 1, 0, 1)
        icon:SetSize(HEAD_FRAME, HEAD_FRAME)
        icon:Show()
        return
    end

    -- Прежняя модель очищается: иначе неудачная смена оставляла в рамке прошлого собеседника (баг 2026-10-04:
    -- после квеста Дугхана квест из журнала у NPC Forever без облика в модуле показывал Дугхана).
    pcall(model.ClearModel, model)
    self.modelPending = nil
    if p.unit and Identity.IsStillPresent(item.target) then
        shown = pcall(model.SetUnit, model, p.unit)
    end
    if not shown and p.display then
        shown = pcall(model.SetDisplayInfo, model, p.display)
    end
    if not shown and p.creature then
        shown = pcall(model.SetCreature, model, p.creature)
        if shown and (tonumber(Util.Try(model.GetDisplayInfo, model)) or 0) == 0 then
            -- Существа нет в кэше клиента (NPC Forever без облика в модуле, не рядом): облик 0, модель сама не придёт.
            -- Пока — значок; WatchModel спросит существо у сервера. Облик известен — модель показываем сразу (догрузится
            -- с диска на глазах, как в окне TalkingHead retail): проверка GetModelFileID держала значок у всех NPC,
            -- чья модель грузилась не мгновенно (баг 2026-10-07).
            shown = false
            self.modelPending = item
        end
    end

    if shown then
        icon:Hide()
        self:ShowModel()
    else
        if self.modelPending then
            model:Show()
            model:SetAlpha(0) -- невидимая модель грузится; пока — снимок или значок
            self:WatchModel(item)
        else
            model:Hide()
        end
        if p.snap then
            icon:Hide()
            p.snap:Show()
            return
        end
        icon:SetTexture(FallbackIcon(item))
        if self.layout == "head" then
            -- Иконки клиента — внутри золотой рамки, без своей тёмной каймы.
            icon:SetSize(HEAD_MODEL - 14, HEAD_MODEL - 14)
            icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        end
        icon:Show()
    end
end

local function Subtitle(item)
    if item.zone then
        return "Рассказчик"
    end
    return item.title or ""
end

--- Текст реплики: из окна квеста или разговора (с абзацами, именем персонажа), иначе — субтитры пакета.
function UI.ItemText(item)
    local text = item.text
    if type(text) ~= "string" or text == "" then
        local parts = {}
        for _, cue in ipairs(item.sound and item.sound.subtitles or {}) do
            parts[#parts + 1] = cue[2]
        end
        text = table.concat(parts, " ")
    end
    text = text:gsub("\r", ""):gsub("\n\n\n+", "\n\n"):gsub("^%s+", ""):gsub("%s+$", "")
    return text
end

--- Какая доля текста уже прочитана: по субтитрам (время начала каждой фразы), внутри фразы — по времени;
--- без субтитров — по времени всей реплики.
function UI.SpokenFraction(item, elapsed, duration)
    local cues = item.sound and item.sound.subtitles
    local total = 0
    for _, cue in ipairs(cues or {}) do
        total = total + #tostring(cue[2] or "")
    end
    if total == 0 then
        return duration > 0 and math.max(0, math.min(1, elapsed / duration)) or 0
    end
    local before = 0
    for i, cue in ipairs(cues) do
        local start = cue[1] or 0
        local finish = cues[i + 1] and cues[i + 1][1] or duration
        local len = #tostring(cue[2] or "")
        if elapsed < finish or i == #cues then
            local part = finish > start and math.max(0, math.min(1, (elapsed - start) / (finish - start))) or 1
            return (before + len * part) / total
        end
        before = before + len
    end
    return 1
end

--- Текст и фон «говорящей головы»; keepScroll — та же реплика (смена настроек), прокрутку не сбрасывать.
function UI:ShowText(item, keepScroll)
    if not self.text then
        return
    end
    self.headBg:SetTexture(MEDIA .. "bg-" .. Kit(item))
    self.text:SetText(UI.ItemText(item))
    self.textMax = nil -- высота текста известна не сразу: считаем в Progress
    if not keepScroll then
        self.scrollTarget = 0
        self.textScroll:SetVerticalScroll(0)
        if self.layout == "head" and ns.db.animations and self.textFade then
            self.textFade:Play()
        end
    end
end

--- Сколько можно прокрутить текст (и высота содержимого для прокрутки).
function UI:TextMaxScroll()
    local height = self.text:GetStringHeight() or 0
    local visible = self.textScroll:GetHeight() or 0
    if height <= 0 or visible <= 0 then
        return 0
    end
    self.textChild:SetHeight(height)
    return math.max(0, height - visible)
end

--- Показать элемент очереди в окне (имя, портрет, текст, время с нуля), не запуская его.
function UI:ShowItem(item)
    self.current = item
    self.name:SetText(item.name or item.title or "")
    self.sub:SetText(Subtitle(item))
    self.bar:SetMinMaxValues(0, item.sound.duration or 1)
    self.bar:SetValue(0)
    self.timer:SetText(Clock(0) .. " / " .. Clock(item.sound.duration))
    self.shownSecond = 0
    self:SetPortrait(item)
    self:ShowText(item)
end

function UI:OnStart(item)
    if not self.frame then
        return
    end
    self:ShowItem(item)
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
    -- Текст едет за голосом: читаемая строка спускается по окну сверху вниз, прокрутка — по целым строкам.
    if self.layout == "head" and self.textScroll:IsShown() then
        local maxScroll = self:TextMaxScroll()
        local line = TEXT_SIZE + TEXT_SPACING
        local target = UI.SpokenFraction(item, value, duration) * maxScroll
        self.scrollTarget = math.min(maxScroll, math.floor(target / line + 0.5) * line)
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

-- Режим «передвинуть окно» (/wf move): окно видно и без озвучки, с подсказкой; место запоминает OnDragStop.
local MOVE_ITEM = {
    sound = { path = "", uid = "move", duration = 0, voice = "narrator" },
    name = "Окно Wayfarer",
    text = "Перетащите окно мышью — место запомнится. Готово — /wf move ещё раз.",
    moving = true,
}

function UI:ToggleMove()
    self.moving = not self.moving
    if self.moving and ns.db.lockFrame then
        ns.db.lockFrame = false
        Util.Print("окно откреплено (настройка «Закрепить окно»).")
    end
    self:Refresh()
    return self.moving
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
    if not current and self.moving then
        current = MOVE_ITEM
    elseif current and self.current == MOVE_ITEM then
        self.current = nil -- зазвучала реплика: окно показывает её
    end
    if not (ns.db.showFrame or current == MOVE_ITEM) or not current then
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
    if current ~= self.current then
        -- На паузе новый элемент не запускается, но окно должно показывать его, а не прежний.
        self:ShowItem(current)
    end
    if current.waiting then
        self.timer:SetText("")
        self.spark:Hide()
    end
    self.pauseButton:SetText(queue.paused and "Играть" or "Пауза")
    if self.headPause then
        self.headPause:SetNormalTexture(MEDIA .. (queue.paused and "btn-play" or "btn-pause"))
        self.headPause:SetPushedTexture(MEDIA .. (queue.paused and "btn-play" or "btn-pause"))
    end
    local rest = queue:Size() - 1
    self.queued:SetText((ns.db.showQueue and rest > 0) and ("ещё " .. rest) or "")
    if current == MOVE_ITEM then
        self.timer:SetText("")
        self:SetTalking(false)
        return
    end
    if queue.paused or current.waiting then
        pcall(self.model.SetAnimation, self.model, ANIM_IDLE)
    end
    if queue.paused and current.cut then
        self.timer:SetText("звук прерван") -- игра оборвала звук (Alt+Tab): «Играть» — заново
        self.spark:Hide()
    end
    self:SetTalking(not queue.paused and not current.waiting)
end
