local _, ns = ...

-- Панель в «Настройки → Модификации». Значения пишутся прямо в Wayfarer_DB.
local Options = {}
ns.Options = Options

ns.DEFAULTS = {
    enabled = true,
    channel = "Master",   -- «Общая громкость»: звучит у всех, у кого включён звук (Диалоги бывают выключены)
    voiceModel = "v4",    -- версия голосов: модули v4 там, где они есть, остальное — v3 (Packs:Active)
    playAccept = true,
    playProgress = true,
    playComplete = true,
    gossipMode = "once",  -- "always" | "once" (каждую реплику один раз) | "never"
    zoneMode = "once",    -- лор мест: "once" (при первом посещении) | "always" | "never"
    zoneSubzones = true,  -- читать лор подзон, а не только зон
    stopOnClose = false,  -- замолкать при закрытии окна квеста/диалога
    questButtons = true,  -- кнопки ▶ у квестов в списке заданий и в журнале на карте (QuestLog.lua)
    playBooks = true,     -- книги, письма и таблички читает рассказчик (Books.lua)
    zoneButton = true,    -- кнопка ▶ рассказчика у мини-карты: лор места, где стоит игрок (ZoneMap.lua)
    muteNpcVoice = true,  -- на время озвучки опускать громкость «Диалогов» (приветствия NPC), Duck.lua
    playInBackground = true, -- на время озвучки звук игры не глохнет при Alt+Tab (CVar звука в фоне, Duck.lua)
    startDelay = 0.6,     -- пауза перед чтением, чтобы не перебивать «Приветствую!» NPC
    waitGreeting = true,  -- начинать после приветствия NPC (длина — по облику, GreetData.lua; Core:StartDelay)
    -- Окно плеера (UI.lua)
    showFrame = true,
    frameTheme = "head",  -- head («говорящая голова», как в retail) | parchment | marble | classic | clear (UI.THEMES)
    nameFont = "fancy",   -- fancy — шрифт заголовков квестов (Morpheus), plain — обычный
    frameAlpha = 1.0,     -- прозрачность фона и рамки
    portraitMode = "icon", -- "icon" — 2D-портрет собеседника, "model" — говорящая 3D-голова, "none" — без портрета
    headPortrait = "head", -- «говорящая голова»: "head" — крупно лицо, "bust" — по пояс
    showTitle = false,    -- название квеста (или «Рассказчик») под именем
    controlsMode = "always", -- кнопки управления: always | hover (при наведении) | hidden
    showTimer = true,
    showBar = true,
    showQueue = true,     -- «ещё N» рядом с кнопками
    showReport = true,    -- кнопка «!»
    animations = true,    -- плавное появление окна и мерцание кольца, пока NPC говорит
    subtitles = true,     -- текст реплики в окне «говорящей головы»
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

-- Модули озвучки помечены моделью ElevenLabs (model в Index.lua, без пометки — v3).
local VOICE_MODELS = {
    { "v4", "v4 — новые голоса (где уже есть)" },
    { "v3", "v3 — прежние голоса (отдельный модуль)" },
}

ns.VOICE_MODELS = VOICE_MODELS

local GOSSIP_MODES = {
    { "once", "Один раз для каждой реплики" },
    { "always", "Всегда" },
    { "never", "Никогда" },
}

local PORTRAIT_MODES = {
    { "icon", "Портрет в кольце" },
    { "model", "Говорящая 3D-голова" },
    { "none", "Без портрета" },
}

local HEAD_PORTRAITS = {
    { "head", "Голова — крупно" },
    { "bust", "По пояс" },
}

local ZONE_MODES = {
    { "once", "При первом посещении" },
    { "always", "При каждом входе (не чаще раза в 10 минут)" },
    { "never", "Никогда" },
}

local FRAME_THEMES = {
    { "head", "Говорящая голова (как в retail)" },
    { "parchment", "Пергамент" },
    { "marble", "Тёмный мрамор" },
    { "classic", "Классика" },
    { "clear", "Без фона" },
}

local NAME_FONTS = {
    { "fancy", "Сказочный (как названия квестов)" },
    { "plain", "Обычный" },
}

local CONTROLS_MODES = {
    { "always", "Всегда" },
    { "hover", "При наведении мыши" },
    { "hidden", "Скрыть" },
}

-- Проверка значений из SavedVariables: испорченное или старое — назад к умолчанию.
Options.CHOICES = {
    frameTheme = FRAME_THEMES, nameFont = NAME_FONTS, controlsMode = CONTROLS_MODES,
    portraitMode = PORTRAIT_MODES, gossipMode = GOSSIP_MODES, zoneMode = ZONE_MODES, headPortrait = HEAD_PORTRAITS,
}

function Options:Validate(db)
    for key, choices in pairs(self.CHOICES) do
        local ok = false
        for _, c in ipairs(choices) do
            ok = ok or c[1] == db[key]
        end
        if not ok then
            db[key] = ns.DEFAULTS[key]
        end
    end
    if type(db.frameAlpha) ~= "number" or db.frameAlpha < 0.2 or db.frameAlpha > 1 then
        db.frameAlpha = ns.DEFAULTS.frameAlpha
    end
    if type(db.frameScale) ~= "number" or db.frameScale < 0.5 or db.frameScale > 1.5 then
        db.frameScale = ns.DEFAULTS.frameScale
    end
end

function Options:Init()
    if not Settings or not Settings.RegisterVerticalLayoutCategory then
        return
    end
    local db = ns.db
    local category, layout = Settings.RegisterVerticalLayoutCategory("Wayfarer")
    self.category = category

    local function Header(text)
        if layout and CreateSettingsListSectionHeaderInitializer then
            layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
        end
    end

    local function Checkbox(key, label, tooltip, onChange)
        local setting = Settings.RegisterAddOnSetting(category, "WAYFARER_" .. key, key, db,
            Settings.VarType.Boolean, label, ns.DEFAULTS[key])
        if onChange then
            setting:SetValueChangedCallback(onChange)
        end
        Settings.CreateCheckbox(category, setting, tooltip)
    end

    local function Dropdown(key, label, choices, tooltip, onChange)
        local setting = Settings.RegisterAddOnSetting(category, "WAYFARER_" .. key, key, db,
            Settings.VarType.String, label, ns.DEFAULTS[key])
        if onChange then
            setting:SetValueChangedCallback(onChange)
        end
        local function GetOptions()
            local container = Settings.CreateControlTextContainer()
            for _, c in ipairs(choices) do
                container:Add(c[1], c[2])
            end
            return container:GetData()
        end
        Settings.CreateDropdown(category, setting, GetOptions, tooltip)
    end

    local function Slider(key, label, minValue, maxValue, step, tooltip, onChange, format)
        local setting = Settings.RegisterAddOnSetting(category, "WAYFARER_" .. key, key, db,
            Settings.VarType.Number, label, ns.DEFAULTS[key])
        if onChange then
            setting:SetValueChangedCallback(onChange)
        end
        local options = Settings.CreateSliderOptions(minValue, maxValue, step)
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, format or function(value)
            return string.format("%.1f", value)
        end)
        Settings.CreateSlider(category, setting, options, tooltip)
    end

    local function RefreshUI()
        ns.UI:ApplySettings()
    end

    Header("Озвучка")
    Checkbox("enabled", "Включить озвучку", "Главный выключатель.")
    Dropdown("channel", "Канал звука", CHANNELS,
        "Каким ползунком громкости регулируется озвучка. По умолчанию — «Общая громкость»: так звук есть у всех. Если выбранный канал выключен, озвучка всё равно пойдёт через общий.")
    Dropdown("voiceModel", "Версия голосов", VOICE_MODELS,
        "v4 — новые голоса (модуль Wayfarer_Voices_v4). v3 — прежние, нужен отдельный модуль Wayfarer_Voices. Где реплики нужной версии нет, звучит другая. Из чата: /wf v3, /wf v4.")
    Checkbox("playAccept", "Читать описание квеста", "При открытии квеста у NPC.")
    Checkbox("playProgress", "Читать «прогресс»", "Когда приходишь к NPC с незавершённым квестом.")
    Checkbox("playComplete", "Читать текст награды", "При сдаче квеста.")
    Checkbox("questButtons", "Кнопки ▶ у квестов",
        "В списке заданий у края экрана и в журнале квестов на карте: прослушать квест ещё раз, не открывая окно NPC. Повторное нажатие — остановить.",
        function() if ns.QuestLog then ns.QuestLog:Refresh() end end)
    Checkbox("playBooks", "Читать книги и таблички",
        "Письма, книги, таблички и надписи читает рассказчик, где есть озвучка. Перелистнули — звучит новая страница.")
    Dropdown("gossipMode", "Реплики NPC", GOSSIP_MODES, "Как часто озвучивать разговоры с NPC.")
    Dropdown("zoneMode", "Рассказчик мест", ZONE_MODES,
        "Лор зоны или подзоны, когда входишь в неё. Не перебивает квесты. /wf zone — прочитать ещё раз.")
    Checkbox("zoneSubzones", "Лор подзон", "Читать не только зоны (Элвиннский лес), но и подзоны (Рудник Горного Эха).")
    Checkbox("zoneButton", "Кнопка рассказчика у мини-карты",
        "Кнопка ▶ слева от названия места над мини-картой: рассказ о месте, где вы стоите, не открывая карту. Правый клик — о всей зоне. Повторное нажатие — остановить.",
        function() if ns.ZoneMap then ns.ZoneMap:Refresh() end end)
    Checkbox("muteNpcVoice", "Приглушать голоса NPC во время озвучки",
        "Пока звучит озвучка, громкость «Диалогов» опускается до нуля: приветствие NPC («Чем могу помочь?») не накладывается на реплику. Потом громкость возвращается. Не действует, если сама озвучка идёт через канал «Диалоги».",
        function() if not ns.db.muteNpcVoice then ns.Duck:Off() end end)
    Checkbox("playInBackground", "Не прерывать озвучку при сворачивании игры",
        "Если в настройках звука игры выключен «Звук в фоновом режиме», при Alt+Tab игра обрывает звук, и реплика пропадала. Пока звучит озвучка, звук в фоне включён; потом прежняя настройка возвращается. Выключено — оборванная реплика встаёт на паузу, ▶ — прослушать заново.",
        function() if not ns.db.playInBackground then ns.Duck:Background(false) end end)
    Checkbox("stopOnClose", "Молчать после закрытия окна",
        "Останавливать чтение, когда закрываешь окно квеста или разговора.")
    Checkbox("waitGreeting", "Ждать приветствие NPC",
        "Начинать чтение, когда NPC договорит приветствие («Приветствую!», «Чем могу помочь?»): длина приветствия известна по облику NPC. Ждём только в начале разговора и не дольше 4 секунд.")
    Slider("startDelay", "Пауза перед чтением, сек", 0, 3, 0.1,
        "Наименьшая пауза перед репликой. С «Ждать приветствие NPC» — пауза до конца приветствия, если оно дольше.")

    Header("Окно плеера")
    Checkbox("showFrame", "Показывать окно плеера", nil, RefreshUI)
    Dropdown("frameTheme", "Оформление", FRAME_THEMES,
        "Говорящая голова — большое окно, как в retail: звёздное небо, портрет в золотой рамке и текст реплики, который едет за голосом. Компактные: пергамент — состаренная бумага и золотая рамка; мрамор — тёмный камень с золотом; классика — прежний вид; без фона — только портрет, имя и полоса поверх игры.",
        RefreshUI)
    Slider("frameScale", "Размер окна плеера", 0.5, 1.5, 0.05,
        "Меньше или больше — окно меняется сразу, пока двигаете ползунок. Из чата: /wf size 80 (в процентах).",
        RefreshUI, function(value) return string.format("%d%%", math.floor(value * 100 + 0.5)) end)
    Dropdown("nameFont", "Шрифт имени", NAME_FONTS, "Сказочный — тот же, что у названий квестов.", RefreshUI)
    Checkbox("subtitles", "Текст реплики", "В окне «Говорящая голова»: текст квеста или разговора, прокручивается за голосом.",
        RefreshUI)
    Slider("frameAlpha", "Непрозрачность фона", 0.2, 1, 0.05, nil, RefreshUI,
        function(value) return string.format("%d%%", math.floor(value * 100 + 0.5)) end)
    Dropdown("portraitMode", "Портрет собеседника", PORTRAIT_MODES,
        "Портрет — круглый снимок NPC в кольце (как в окне квеста); 3D — модель, которая «говорит». В «говорящей голове» портрет всегда 3D (или его нет).", RefreshUI)
    Dropdown("headPortrait", "Собеседник в «говорящей голове»", HEAD_PORTRAITS,
        "Голова — лицо крупно, как в окне квеста. По пояс — видно и плечи, и одежду.", RefreshUI)
    Checkbox("showTitle", "Название квеста под именем", "У лора мест — «Рассказчик».", RefreshUI)
    Dropdown("controlsMode", "Кнопки управления", CONTROLS_MODES,
        "«Пауза», «Далее», «Стоп» и «!». При наведении — появляются, когда мышь над окном. Клавиши и /wf работают всегда.",
        RefreshUI)
    Checkbox("showTimer", "Время реплики", "«0:12 / 0:45» справа от имени.", RefreshUI)
    Checkbox("showBar", "Полоса прогресса", nil, RefreshUI)
    Checkbox("showQueue", "Сколько реплик в очереди", "«ещё 2» рядом с кнопками.", RefreshUI)
    Checkbox("showReport", "Кнопка «!» (сообщить о проблеме)", "Без кнопки — /wf report.", RefreshUI)
    Checkbox("animations", "Анимации", "Плавное появление окна и мерцание кольца портрета, пока NPC говорит.", RefreshUI)
    Checkbox("lockFrame", "Закрепить окно", "Запретить перетаскивание мышью. Передвинуть окно, когда ничего не звучит, — /wf move; вернуть на место — /wf reset frame.")

    Header("Сбор текстов")
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
