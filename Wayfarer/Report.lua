local _, ns = ...
local Util = ns.Util

-- Репорт реплики прямо из игры: кнопка «!» в плеере или /wf report.
-- Репорты копятся в Wayfarer_Collected.reports (SavedVariables). /wf reports — окно с текстом,
-- который можно скопировать в Discord; пайплайн (vru ingest) переносит их в проводник.
local Report = {}
ns.Report = Report

-- Те же категории, что в проводнике (pipeline/vru/explore.py, REPORT_CATEGORIES).
Report.CATEGORIES = {
    "ударение", "не тот голос", "обрезано или склейка", "подача и эмоции", "текст или опечатка", "другое",
}

local function List()
    Wayfarer_Collected = Wayfarer_Collected or {}
    Wayfarer_Collected.reports = Wayfarer_Collected.reports or {}
    return Wayfarer_Collected.reports
end

local function Trim(s)
    return ((s or ""):match("^%s*(.-)%s*$"))
end

local function Backdrop(f)
    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.05, 0.04, 0.03, 0.96)
    f:SetBackdropBorderColor(0.8, 0.65, 0.3, 1)
end

local function Movable(f, name)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if UISpecialFrames then
        table.insert(UISpecialFrames, name) -- закрывается по Esc
    end
end

local function Button(parent, label, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    return b
end

--- Что репортим: то, что звучит сейчас, иначе последнее прозвучавшее.
function Report:Target()
    return ns.Queue:Current() or ns.Queue.last
end

function Report:Add(item, category, comment)
    if not item or not item.sound or not item.sound.uid then
        Util.Print("нечего репортить: ещё ничего не звучало.")
        return nil
    end
    comment = Trim(comment):gsub("[\r\n]+", " ")
    local row = {
        uid = item.sound.uid,
        cat = category,
        comment = comment ~= "" and comment or nil,
        name = item.name ~= "" and item.name or nil,
        title = not item.zone and item.title ~= "" and item.title or nil, -- у лора места это «Рассказчик»
        char = ns.Collector.db and ns.Collector:CharKey() or nil,
        v = ns.VERSION,
        t = time(),
    }
    local list = List()
    table.insert(list, row)
    Util.Print("спасибо! Репорт сохранён (%s, всего %d). /wf reports — скопировать для отправки.", row.uid, #list)
    return row
end

--- Строка для Discord (её же разбирает vru reports import):
--- [Wayfarer 0.3.0] q/783-a (Маршал Макбрайд, «Внутренняя угроза») — ударение: комментарий
function Report:Line(row)
    local context = {}
    if row.name then
        table.insert(context, row.name)
    end
    if row.title then
        table.insert(context, "«" .. row.title .. "»")
    end
    local line = ("[Wayfarer %s] %s"):format(tostring(row.v or "?"), row.uid)
    if #context > 0 then
        line = line .. " (" .. table.concat(context, ", ") .. ")"
    end
    line = line .. " — " .. row.cat
    if row.comment then
        line = line .. ": " .. row.comment
    end
    return line
end

-- Окно «Что не так с репликой?» -------------------------------------------------

function Report:CreateDialog()
    local f = CreateFrame("Frame", "WayfarerReportFrame", UIParent, "BackdropTemplate")
    f:SetSize(340, 312)
    f:SetPoint("CENTER", 0, 80)
    Backdrop(f)
    Movable(f, "WayfarerReportFrame")
    f:Hide()

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -14)
    title:SetText("Что не так с репликой?")

    local what = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    what:SetPoint("TOP", 0, -36)
    what:SetWidth(300)
    what:SetWordWrap(false)
    f.what = what

    f.checks = {}
    for i, category in ipairs(self.CATEGORIES) do
        local check = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        check:SetSize(24, 24)
        check:SetPoint("TOPLEFT", 20, -54 - (i - 1) * 24)
        check:SetScript("OnClick", function() Report:Select(i) end)
        local label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("LEFT", check, "RIGHT", 2, 0)
        label:SetText(category)
        f.checks[i] = check
    end

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("TOPLEFT", 24, -204)
    hint:SetText("Комментарий, если нужно. Например: «Арати» — ударение на второй слог.")
    hint:SetWidth(296)
    hint:SetJustifyH("LEFT")

    local edit = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    edit:SetSize(290, 20)
    edit:SetPoint("TOPLEFT", 30, -236)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(200)
    edit:SetScript("OnEnterPressed", function() Report:Save() end)
    edit:SetScript("OnEscapePressed", function() f:Hide() end)
    f.comment = edit

    local save = Button(f, "Сохранить", 110, function() Report:Save() end)
    save:SetPoint("BOTTOMRIGHT", -16, 12)
    local cancel = Button(f, "Отмена", 90, function() f:Hide() end)
    cancel:SetPoint("RIGHT", save, "LEFT", -6, 0)

    self.dialog = f
    return f
end

function Report:Select(index)
    self.category = index
    for n, check in ipairs(self.dialog.checks) do
        check:SetChecked(n == index)
    end
end

function Report:Open(comment)
    local item = self:Target()
    if not item then
        Util.Print("нечего репортить: ещё ничего не звучало.")
        return
    end
    local f = self.dialog or self:CreateDialog()
    f.item = item
    local who = item.name or ""
    if item.title and item.title ~= "" then
        who = who .. (who ~= "" and " — " or "") .. item.title
    end
    f.what:SetText(who ~= "" and who or item.sound.uid)
    self:Select(1)
    f.comment:SetText(comment or "")
    f:Show()
    f.comment:SetFocus()
end

function Report:Save()
    local f = self.dialog
    if f and f.item then
        self:Add(f.item, self.CATEGORIES[self.category or #self.CATEGORIES], f.comment:GetText())
    end
    if f then
        f:Hide()
    end
end

-- Окно «скопировать всё» ---------------------------------------------------------

function Report:CreateCopy()
    local f = CreateFrame("Frame", "WayfarerReportsFrame", UIParent, "BackdropTemplate")
    f:SetSize(480, 320)
    f:SetPoint("CENTER")
    Backdrop(f)
    Movable(f, "WayfarerReportsFrame")
    f:Hide()

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -14)
    title:SetText("Репорты Wayfarer")

    local count = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    count:SetPoint("TOP", 0, -36)
    f.count = count

    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 16, -56)
    scroll:SetPoint("BOTTOMRIGHT", -36, 44)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetWidth(420)
    if ChatFontNormal then
        edit:SetFontObject(ChatFontNormal)
    end
    edit:SetScript("OnEscapePressed", function() f:Hide() end)
    scroll:SetScrollChild(edit)
    f.edit = edit

    local close = Button(f, "Закрыть", 90, function() f:Hide() end)
    close:SetPoint("BOTTOMRIGHT", -16, 12)
    local clear = Button(f, "Очистить список", 130, function() Report:Clear() end)
    clear:SetPoint("RIGHT", close, "LEFT", -6, 0)

    self.copy = f
    return f
end

function Report:ShowAll()
    local list = List()
    if #list == 0 then
        Util.Print("репортов пока нет. Кнопка «!» в окне плеера или /wf report.")
        return
    end
    local lines = {}
    for _, row in ipairs(list) do
        table.insert(lines, self:Line(row))
    end
    local f = self.copy or self:CreateCopy()
    f.count:SetText(("Репортов: %d. Нажмите Ctrl+C и вставьте в Discord; потом — «Очистить список»."):format(#list))
    f.edit:SetText(table.concat(lines, "\n"))
    f:Show()
    f.edit:SetFocus()
    f.edit:HighlightText()
end

function Report:Clear()
    wipe(List())
    Util.Print("список репортов очищен.")
    if self.copy then
        self.copy:Hide()
    end
end
