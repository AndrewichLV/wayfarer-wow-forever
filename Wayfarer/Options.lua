local _, ns = ...

-- Панель в «Настройки → Модификации». Значения пишутся прямо в Wayfarer_DB.
local Options = {}
ns.Options = Options

ns.DEFAULTS = {
    enabled = true,
    channel = "Master",   -- «Общая громкость»: звучит у всех, у кого включён звук (Диалоги бывают выключены)
    playAccept = true,
    playProgress = true,
    playComplete = true,
    gossipMode = "once",  -- "always" | "once" (каждую реплику один раз) | "never"
    zoneMode = "once",    -- лор мест: "once" (при первом посещении) | "always" | "never"
    zoneSubzones = true,  -- читать лор подзон, а не только зон
    stopOnClose = false,  -- замолкать при закрытии окна квеста/диалога
    startDelay = 0.6,     -- пауза перед чтением, чтобы не перебивать «Приветствую!» NPC
    showFrame = true,
    portraitMode = "icon", -- "icon" — 2D-портрет собеседника, "model" — говорящая 3D-голова
    subtitles = true,
    frameScale = 1.0,
    lockFrame = false,
    framePos = false,
    collect = true,
    debug = false,
}

local CHANNELS = {
    { "Master", "Общая громкость" },
    { "Dialog", "Диалоги" },
    { "SFX", "Эффекты" },
    { "Ambience", "Окружение" },
    { "Music", "Музыка" },
}

ns.CHANNELS = CHANNELS

local GOSSIP_MODES = {
    { "once", "Один раз для каждой реплики" },
    { "always", "Всегда" },
    { "never", "Никогда" },
}

local PORTRAIT_MODES = {
    { "icon", "Портрет-иконка" },
    { "model", "Говорящая 3D-голова" },
}

local ZONE_MODES = {
    { "once", "При первом посещении" },
    { "always", "При каждом входе (не чаще раза в 10 минут)" },
    { "never", "Никогда" },
}

function Options:Init()
    if not Settings or not Settings.RegisterVerticalLayoutCategory then
        return
    end
    local db = ns.db
    local category = Settings.RegisterVerticalLayoutCategory("Wayfarer")
    self.category = category

    local function Checkbox(key, label, tooltip, onChange)
        local setting = Settings.RegisterAddOnSetting(category, "WAYFARER_" .. key, key, db,
            Settings.VarType.Boolean, label, ns.DEFAULTS[key])
        if onChange then
            setting:SetValueChangedCallback(onChange)
        end
        Settings.CreateCheckbox(category, setting, tooltip)
    end

    local function Dropdown(key, label, choices, tooltip)
        local setting = Settings.RegisterAddOnSetting(category, "WAYFARER_" .. key, key, db,
            Settings.VarType.String, label, ns.DEFAULTS[key])
        local function GetOptions()
            local container = Settings.CreateControlTextContainer()
            for _, c in ipairs(choices) do
                container:Add(c[1], c[2])
            end
            return container:GetData()
        end
        Settings.CreateDropdown(category, setting, GetOptions, tooltip)
    end

    local function Slider(key, label, minValue, maxValue, step, tooltip, onChange)
        local setting = Settings.RegisterAddOnSetting(category, "WAYFARER_" .. key, key, db,
            Settings.VarType.Number, label, ns.DEFAULTS[key])
        if onChange then
            setting:SetValueChangedCallback(onChange)
        end
        local options = Settings.CreateSliderOptions(minValue, maxValue, step)
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
            return string.format("%.1f", value)
        end)
        Settings.CreateSlider(category, setting, options, tooltip)
    end

    local function RefreshUI()
        ns.UI:ApplySettings()
    end

    Checkbox("enabled", "Включить озвучку", "Главный выключатель.")
    Dropdown("channel", "Канал звука", CHANNELS,
        "Каким ползунком громкости регулируется озвучка. По умолчанию — «Общая громкость»: так звук есть у всех. Если выбранный канал выключен, озвучка всё равно пойдёт через общий.")
    Checkbox("playAccept", "Читать описание квеста", "При открытии квеста у NPC.")
    Checkbox("playProgress", "Читать «прогресс»", "Когда приходишь к NPC с незавершённым квестом.")
    Checkbox("playComplete", "Читать текст награды", "При сдаче квеста.")
    Dropdown("gossipMode", "Реплики NPC", GOSSIP_MODES, "Как часто озвучивать разговоры с NPC.")
    Dropdown("zoneMode", "Рассказчик мест", ZONE_MODES,
        "Лор зоны или подзоны, когда входишь в неё. Не перебивает квесты. /wf zone — прочитать ещё раз.")
    Checkbox("zoneSubzones", "Лор подзон", "Читать не только зоны (Элвиннский лес), но и подзоны (Рудник Горного Эха).")
    Checkbox("stopOnClose", "Молчать после закрытия окна",
        "Останавливать чтение, когда закрываешь окно квеста или разговора.")
    Slider("startDelay", "Пауза перед чтением, сек", 0, 3, 0.1,
        "Даёт NPC договорить своё приветствие.")
    Checkbox("showFrame", "Показывать окно с портретом", nil, RefreshUI)
    Dropdown("portraitMode", "Портрет собеседника", PORTRAIT_MODES,
        "Иконка — круглый портрет NPC (как в окне квеста); 3D — модель, которая «говорит».")
    Checkbox("lockFrame", "Закрепить окно", "Запретить перетаскивание окна мышью.")
    Slider("frameScale", "Масштаб окна", 0.5, 1.5, 0.05, nil, RefreshUI)
    Checkbox("collect", "Собирать тексты для озвучки",
        "Записывать тексты квестов и реплик в SavedVariables, чтобы потом сгенерировать для них озвучку.")
    Checkbox("debug", "Отладочные сообщения", "Писать в чат, почему что-то не озвучено.")

    Settings.RegisterAddOnCategory(category)
end

function Options:Open()
    if self.category then
        Settings.OpenToCategory(self.category:GetID())
    end
end
