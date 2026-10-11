local _, ns = ...
local Util, Packs, Queue, Diary = ns.Util, ns.Packs, ns.Queue, ns.Diary

-- Дневник путника v4 — раскрытая книга (2026-10-10, по макету dist/journal-v4-mock и картинкам пользователя из
-- Nano Banana: разворот, ленты, чернильные украшения — pipeline/data/ui_ref/journal-v4). Пользователь: прежнее окно
-- «перегружено, глаза разбегаются, лишние вкладки». Теперь две закладки-ленты:
--   «Азерот»  — обзор и атлас вместе: слева герой, открытые земли материка (закрытые свёрнуты), справа земля — карта,
--               места (открытые — с ▶, закрытые — счётчиком) и рассказ выбранного места;
--   «Истории» — библиотека путевых историй (модуль Wayfarer_Radio): рубрики, выпуски, части, текст, эфир.
-- Бестиарий и летопись убраны (решение пользователя): переслушать — в библиотеке, квесты — ▶ в журнале квестов.
-- Правила вида: одна рамка (сама книга), чернила на пергаменте, строки в одну линию без рамок, золото — только выбор
-- и главная кнопка, два шрифта клиента (Morpheus — заголовки, Friz Quadrata — текст). Текстуры — Media/Journal
-- (tools/make_journal_assets.py, размеры — JournalArt.lua); без нарезанной картинки — простая заливка.
local Journal = {}
ns.Journal = Journal

local ART = ns.JournalArt or {}
local JTEX = "Interface\\AddOns\\Wayfarer\\Media\\Journal\\"
local CIRCLE = "Interface\\AddOns\\Wayfarer\\Media\\UI\\circle"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local FONT_TITLE = "Fonts\\MORPHEUS_CYR.TTF"
local FONT_TEXT = "Fonts\\FRIZQT___CYR.TTF"

-- Геометрия: окно — разворот книги в пропорциях картинки; поле письма на листах (внутри двойной рамки страницы) —
-- доли окна: { слева, справа, сверху, снизу } (ART.book.pages, если инструмент их измерил).
local BOOK = ART.book
local W = 1000
local H = BOOK and math.floor(W * BOOK.h / BOOK.w + 0.5) or 636
local PAGES = (BOOK and BOOK.pages) or { left = { 0.085, 0.470, 0.085, 0.900 }, right = { 0.535, 0.920, 0.085, 0.900 } }
local ROW_H = 28
local RIBBON_DIP = 10 -- насколько лента уходит в верхний край книги

-- Палитра: чернила на пергаменте, золото — акцент.
local C = {
    ink = { 0.23, 0.145, 0.06 }, inkSoft = { 0.42, 0.31, 0.19 }, inkFaint = { 0.60, 0.51, 0.38 },
    gold = { 0.70, 0.48, 0.12 }, goldHi = { 0.90, 0.70, 0.30 }, light = { 0.97, 0.90, 0.75 },
    sel = { 1, 0.97, 0.88 }, track = { 0.78, 0.67, 0.49 },
}
local CONTINENTS = { { 1415, "Восточные королевства" }, { 1414, "Калимдор" }, { false, "Другие земли" } }
local ORDINALS = { "первая", "вторая", "третья", "четвёртая", "пятая", "шестая", "седьмая", "восьмая", "девятая",
    "десятая" }

-- Мелочи ------------------------------------------------------------------------------------------

local function Now()
    return time and time() or 0
end

local function Day(t)
    if t == 0 then
        return "раньше" -- открыто до появления дневника: дата неизвестна
    end
    local fmt = date or (os and os.date)
    return t and fmt and fmt("%d.%m.%Y", t) or ""
end

--- 1 земля, 2 земли, 5 земель.
local function Plural(n, one, few, many)
    local m10, m100 = n % 10, n % 100
    if m10 == 1 and m100 ~= 11 then
        return one
    elseif m10 >= 2 and m10 <= 4 and (m100 < 12 or m100 > 14) then
        return few
    end
    return many
end

local function Duration(seconds)
    seconds = math.floor((seconds or 0) + 0.5)
    if seconds < 60 then
        return seconds .. " с"
    end
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- Строчные и прописные: string.lower/upper в клиенте кириллицу не понимают.
local LOWER = {}
do
    local up = { "А", "Б", "В", "Г", "Д", "Е", "Ё", "Ж", "З", "И", "Й", "К", "Л", "М", "Н", "О", "П", "Р", "С", "Т",
        "У", "Ф", "Х", "Ц", "Ч", "Ш", "Щ", "Ъ", "Ы", "Ь", "Э", "Ю", "Я" }
    local low = { "а", "б", "в", "г", "д", "е", "е", "ж", "з", "и", "й", "к", "л", "м", "н", "о", "п", "р", "с", "т",
        "у", "ф", "х", "ц", "ч", "ш", "щ", "ъ", "ы", "ь", "э", "ю", "я" }
    for i, u in ipairs(up) do
        LOWER[u] = low[i]
    end
    LOWER["ё"] = "е"
end
local UPPER = {}
for up, low in pairs(LOWER) do
    if up ~= "ё" and up ~= "Ё" then
        UPPER[low] = up
    end
end
UPPER["ё"] = "Ё"
-- Латиница — только байтами A–Z / a–z: string.upper/lower зависят от локали C и могут задеть байты UTF-8.
local function Lower(s)
    return ((((s or ""):gsub("[\208\209][\128-\191]", LOWER)):gsub("[A-Z]", string.lower)))
end
local function Upper(s)
    return ((((s or ""):gsub("[\208\209][\128-\191]", UPPER)):gsub("[a-z]", string.upper)))
end

--- Первая буква прописной (кириллица — своей таблицей).
local function Capital(s)
    local first, rest = (s or ""):match("^([\208\209][\128-\191])(.*)$")
    if first then
        return Upper(first) .. rest
    end
    return ((s or ""):gsub("^%l", string.upper))
end

local function Matches(query, ...)
    if not query or query == "" then
        return true
    end
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if v and Lower(v):find(query, 1, true) then
            return true
        end
    end
    return false
end

local function Paint(obj, c, a)
    obj:SetVertexColor(c[1], c[2], c[3], a or 1)
end

local function Color(fs, c, a)
    fs:SetTextColor(c[1], c[2], c[3], a or 1)
end

-- Движение: один фрейм-мотор на все «твины»; твин всегда доходит до конца (ничего не остаётся полупрозрачным).
local tweens = {}
local animator = CreateFrame("Frame")
animator:Hide()
animator:SetScript("OnUpdate", function(self, elapsed)
    local busy = false
    for key, tw in pairs(tweens) do
        tw.t = tw.t + (elapsed or 0)
        if tw.t >= 0 then
            local p = math.min(1, tw.t / tw.dur)
            tw.set(tw.from + (tw.to - tw.from) * (1 - (1 - p) ^ 3))
            if p >= 1 then
                tweens[key] = nil
            end
        end
        busy = busy or tweens[key] ~= nil
    end
    if not busy then
        self:Hide()
    end
end)

local function Tween(key, from, to, dur, set, delay)
    if from == nil or from == to then
        tweens[key] = nil
        set(to)
        return
    end
    tweens[key] = { from = from, to = to, t = -(delay or 0), dur = dur or 0.3, set = set }
    set(from)
    animator:Show()
end

local function FadeIn(frame, dur, delay)
    Tween(frame, 0, 1, dur or 0.2, function(v) frame:SetAlpha(v) end, delay)
end

-- Строительные блоки ------------------------------------------------------------------------------

--- Текст шрифтом клиента: title — Morpheus (заголовки), иначе Friz Quadrata.
local function Label(parent, size, color, justify, title, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFont(title and FONT_TITLE or FONT_TEXT, size, "")
    fs:SetJustifyH(justify or "LEFT")
    Color(fs, color or C.ink)
    fs:SetWordWrap(false)
    return fs
end

--- Длинное название сначала уменьшается шрифтом (size → minSize), потом обрезается многоточием.
local function FitTitle(fs, text, size, minSize)
    text = text or ""
    local width = fs:GetWidth() or 0
    for s = size, minSize or size, -2 do
        fs:SetFont(FONT_TITLE, s, "")
        fs:SetText(text)
        if width <= 0 or (fs:GetStringWidth() or 0) <= width then
            return
        end
    end
end

local function Shadow(fs)
    fs:SetShadowColor(0, 0, 0, 0.9)
    fs:SetShadowOffset(1, -1)
    return fs
end

--- Кусок из набора, нарезанный на 9 частей (или 3 — если у поля 0): края постоянного размера (масштаб scale),
--- середина растягивается. Возвращает объект с SetShown/SetColor/SetAlpha.
local function Slice(parent, name, scale, layer, sublevel, blend, anchor)
    anchor = anchor or parent
    local a = ART[name] or { w = 8, h = 8, tw = 8, th = 8 }
    local s = a.slice or { 0, 0, 0, 0 }
    local l, r, t, b = s[1] * scale, s[2] * scale, s[3] * scale, s[4] * scale
    local xs = { 0, s[1], a.w - s[2], a.w }
    local ys = { 0, s[3], a.h - s[4], a.h }
    local hl = { { "LEFT", 0 }, { "LEFT", l }, { "RIGHT", -r } }
    local hr = { { "LEFT", l }, { "RIGHT", -r }, { "RIGHT", 0 } }
    local vt = { { "TOP", 0 }, { "TOP", -t }, { "BOTTOM", b } }
    local vb = { { "TOP", -t }, { "BOTTOM", b }, { "BOTTOM", 0 } }
    local shape = { parts = {} }
    for row = 1, 3 do
        for col = 1, 3 do
            if xs[col + 1] > xs[col] and ys[row + 1] > ys[row] then
                local tex = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel or 0)
                tex:SetTexture(JTEX .. name)
                tex:SetTexCoord(xs[col] / a.tw, xs[col + 1] / a.tw, ys[row] / a.th, ys[row + 1] / a.th)
                if blend then
                    tex:SetBlendMode(blend)
                end
                tex:SetPoint("TOPLEFT", anchor, vt[row][1] .. hl[col][1], hl[col][2], vt[row][2])
                tex:SetPoint("BOTTOMRIGHT", anchor, vb[row][1] .. hr[col][1], hr[col][2], vb[row][2])
                shape.parts[#shape.parts + 1] = tex
            end
        end
    end
    function shape:SetShown(v)
        for _, tex in ipairs(self.parts) do
            tex:SetShown(v)
        end
    end
    function shape:SetColor(c, alpha)
        for _, tex in ipairs(self.parts) do
            tex:SetVertexColor(c[1], c[2], c[3], alpha or 1)
        end
    end
    return shape
end

--- Целая текстура из набора (иконка, украшение) с обрезкой по холсту; SetArt — сменить картинку.
local function Art(parent, name, w, h, layer, sublevel)
    local tex = parent:CreateTexture(nil, layer or "ARTWORK", nil, sublevel or 0)
    tex:SetSize(w, h or w)
    function tex:SetArt(n)
        local info = ART[n] or { w = 8, h = 8, tw = 8, th = 8 }
        self:SetTexture(JTEX .. n)
        self:SetTexCoord(0, info.w / info.tw, 0, info.h / info.th)
    end
    tex:SetArt(name)
    return tex
end

--- Чернильное украшение листа (завиток, уголок, компас) — если нарезано; иначе nil.
local function Ink(parent, name, w, layer)
    local a = ART[name]
    if not a then
        return nil
    end
    local tex = Art(parent, name, w, w * a.h / a.w, layer or "ARTWORK")
    tex:SetVertexColor(1, 1, 1, 0.9) -- цвет чернил — в самой картинке
    return tex
end

--- Тонкая черта: чернильный завиток, если есть, иначе линия.
local function Rule(parent, width)
    local ink = Ink(parent, "ink_rule", width)
    if ink then
        return ink
    end
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetTexture(WHITE)
    t:SetSize(width, 1)
    Paint(t, C.inkSoft, 0.4)
    return t
end

--- Главная кнопка — бронзовая пилюля из набора (на листе она одна), по желанию со значком слева.
local function Pill(parent, text, icon, onClick, width, height)
    local b = CreateFrame("Button", nil, parent)
    height = height or 28
    b:SetSize(width or 150, height)
    local scale = height / ((ART.pill1 and ART.pill1.h) or height)
    b.normal = Slice(b, "pill1", scale, "BACKGROUND", 1)
    b.hover = Slice(b, "pill2", scale, "BACKGROUND", 2)
    b.hover:SetShown(false)
    b.label = Shadow(Label(b, 13, C.light, "CENTER"))
    b.label:SetPoint("CENTER", icon and 8 or 0, 0)
    if icon then
        b.icon = Art(b, "round-" .. icon, height - 12, nil, "OVERLAY")
        b.icon:SetPoint("RIGHT", b.label, "LEFT", -6, 0)
    end
    function b:SetLabel(t)
        self.label:SetText(t)
    end
    b:SetScript("OnEnter", function(self) self.hover:SetShown(true) end)
    b:SetScript("OnLeave", function(self) self.hover:SetShown(false) end)
    b:SetScript("OnClick", onClick)
    b:SetLabel(text)
    return b
end

--- Ссылка чернилами с тонким подчёркиванием (второстепенные действия); tab — вид переключателя (золотая черта
--- у выбранного, у остальных — ничего).
local function Link(parent, text, onClick, size, tab)
    local b = CreateFrame("Button", nil, parent)
    b.label = Label(b, size or 12, C.inkSoft)
    b.label:SetPoint("LEFT")
    b.line = b:CreateTexture(nil, "ARTWORK")
    b.line:SetTexture(WHITE)
    b.line:SetPoint("TOPLEFT", b.label, "BOTTOMLEFT", 0, -2)
    b.line:SetPoint("TOPRIGHT", b.label, "BOTTOMRIGHT", 0, -2)
    b.line:SetHeight(tab and 2 or 1)
    Paint(b.line, tab and C.gold or C.inkSoft, tab and 1 or 0.45)
    b.line:SetShown(not tab)
    function b:SetLabel(t)
        self.label:SetText(t)
        self:SetSize((self.label:GetStringWidth() or 60) + 2, 20)
    end
    function b:SetActive(on)
        self.active = on
        Color(self.label, on and C.ink or C.inkFaint)
        self.line:SetShown(on and true or false)
    end
    b:SetScript("OnEnter", function(self) Color(self.label, C.gold) end)
    b:SetScript("OnLeave", function(self)
        Color(self.label, tab and (self.active and C.ink or C.inkFaint) or C.inkSoft)
    end)
    b:SetScript("OnClick", onClick)
    b:SetLabel(text)
    return b
end

--- Тонкая полоса прогресса: светлая дорожка и золото.
local function Bar(parent, width)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width, 4)
    local track = f:CreateTexture(nil, "ARTWORK")
    track:SetAllPoints(f)
    track:SetTexture(WHITE)
    Paint(track, C.track, 0.75)
    local fill = f:CreateTexture(nil, "ARTWORK", nil, 1)
    fill:SetPoint("TOPLEFT")
    fill:SetPoint("BOTTOMLEFT")
    fill:SetTexture(WHITE)
    Paint(fill, C.goldHi)
    function f:Set(part)
        part = math.max(0, math.min(1, part or 0))
        fill:SetShown(part > 0)
        Tween(fill, 1, math.max(1, width * part), 0.6, function(v) fill:SetWidth(v) end)
    end
    return f
end

--- Переключатель-капсула (эфир вкл/выкл).
local function Toggle(parent, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(34, 18)
    local parts = {}
    for i, spec in ipairs({ { "LEFT", 18 }, { "RIGHT", 18 } }) do
        local t = b:CreateTexture(nil, "ARTWORK")
        t:SetTexture(CIRCLE)
        t:SetSize(spec[2], 18)
        t:SetPoint(spec[1])
        parts[i] = t
    end
    local mid = b:CreateTexture(nil, "ARTWORK")
    mid:SetTexture(WHITE)
    mid:SetPoint("TOPLEFT", 9, 0)
    mid:SetPoint("BOTTOMRIGHT", -9, 0)
    parts[3] = mid
    local knob = b:CreateTexture(nil, "OVERLAY")
    knob:SetTexture(CIRCLE)
    knob:SetSize(14, 14)
    function b:Set(on)
        self.on = on
        for _, t in ipairs(parts) do
            Paint(t, on and C.gold or C.inkFaint) -- выключен — тёмная дорожка: светлую на пергаменте не видно
        end
        knob:ClearAllPoints()
        knob:SetPoint(on and "RIGHT" or "LEFT", on and -2 or 2, 0)
        Paint(knob, C.sel)
    end
    b:SetScript("OnClick", onClick)
    b:Set(false)
    return b
end

--- Тонкая полоса прокрутки у края списка (колесо мыши).
local function Scroller(parent, height)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetSize(3, height)
    bar.len = height
    local track = bar:CreateTexture(nil, "ARTWORK")
    track:SetAllPoints(bar)
    track:SetTexture(WHITE)
    Paint(track, C.inkSoft, 0.15)
    local thumb = bar:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture(WHITE)
    thumb:SetWidth(3)
    Paint(thumb, C.inkSoft, 0.55)
    function bar:SetLength(h)
        self.len = h
        self:SetHeight(h)
    end
    function bar:Update(first, visible, total)
        if total <= visible then
            self:Hide()
            return
        end
        self:Show()
        local size = math.max(16, self.len * visible / total)
        thumb:SetHeight(size)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", self, "TOP", 0, -(self.len - size) * first / math.max(1, total - visible))
    end
    return bar
end

--- Список строк без рамок: заголовки групп ({ header = "ТЕКСТ" }), выбор — светлая подложка и золотая черта слева.
--- fill(row, item) заполняет row.icon, row.title, row.meta и по желанию row.dot (новое).
local function RowList(parent, width, height, iconSize, fill, onSelect)
    local list = CreateFrame("Frame", nil, parent)
    list:SetSize(width, height)
    local count = math.max(1, math.floor(height / ROW_H))
    list.rows, list.offset, list.data = {}, 0, {}
    for i = 1, count do
        local b = CreateFrame("Button", nil, list)
        b:SetSize(width - 8, ROW_H - 1)
        b:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        b.bg = b:CreateTexture(nil, "BACKGROUND")
        b.bg:SetAllPoints(b)
        b.bg:SetTexture(WHITE)
        b.mark = b:CreateTexture(nil, "ARTWORK")
        b.mark:SetTexture(WHITE)
        b.mark:SetWidth(3)
        b.mark:SetPoint("TOPLEFT", 0, -4)
        b.mark:SetPoint("BOTTOMLEFT", 0, 4)
        Paint(b.mark, C.gold)
        b.icon = Art(b, "icon-map", iconSize)
        b.icon:SetPoint("LEFT", 9, 0)
        b.meta = Label(b, 11, C.inkSoft, "RIGHT")
        b.meta:SetPoint("RIGHT", -8, 0)
        b.dot = b:CreateTexture(nil, "OVERLAY")
        b.dot:SetTexture(CIRCLE)
        b.dot:SetSize(7, 7)
        b.dot:SetPoint("RIGHT", b.meta, "LEFT", -6, 0)
        Paint(b.dot, C.goldHi)
        b.title = Label(b, 13, C.ink)
        b.title:SetPoint("LEFT", b.icon, "RIGHT", 8, 0)
        b.title:SetPoint("RIGHT", b.dot, "LEFT", -6, 0)
        b.header = Label(b, 10, C.inkSoft)
        b.header:SetPoint("BOTTOMLEFT", 2, 5)
        b:SetScript("OnEnter", function(self)
            local item = rawget(self, "item")
            if item and not item.header and item ~= list.selected then
                self.bg:SetVertexColor(C.sel[1], C.sel[2], C.sel[3], 0.35)
            end
        end)
        b:SetScript("OnLeave", function(self) list:Paint(self) end)
        b:SetScript("OnClick", function(self)
            local item = rawget(self, "item")
            if item and not item.header then
                if not item.action then
                    list.selected = item
                end
                list:Refresh()
                onSelect(item)
            end
        end)
        list.rows[i] = b
    end
    list.bar = Scroller(list, height)
    list.bar:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, 0)
    list.empty = Label(list, 12, C.inkFaint, "CENTER")
    list.empty:SetPoint("TOP", list, "TOP", -4, -24)
    list.empty:SetWidth(width - 30)
    list.empty:SetWordWrap(true)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta) list:Scroll(-delta * 2) end)

    function list:Paint(b)
        local item = rawget(b, "item")
        local selected = item ~= nil and not item.header and item == self.selected
        b.bg:SetVertexColor(C.sel[1], C.sel[2], C.sel[3], selected and 0.75 or 0)
        b.mark:SetShown(selected)
    end
    function list:Scroll(n)
        self.offset = math.max(0, math.min(self.offset + n, math.max(0, #self.data - count)))
        self:Refresh()
    end
    function list:SetData(data, emptyText, animate)
        self.data = data
        self.offset = math.max(0, math.min(self.offset, #data - count))
        self.empty:SetText(#data == 0 and emptyText or "")
        self:Refresh()
        if animate then
            for i, b in ipairs(self.rows) do
                if rawget(b, "item") then
                    FadeIn(b, 0.2, (i - 1) * 0.02)
                end
            end
        end
    end
    function list:First()
        for _, item in ipairs(self.data) do
            if not item.header and not item.action then
                return item
            end
        end
    end
    function list:Refresh()
        for i, b in ipairs(self.rows) do
            local item = self.data[self.offset + i]
            b.item = item
            if item then
                local header = item.header ~= nil
                b.icon:SetShown(not header)
                b.title:SetShown(not header)
                b.meta:SetShown(not header)
                b.header:SetShown(header)
                b.dot:Hide()
                b.meta:SetText("")
                b:EnableMouse(not header)
                if header then
                    b.header:SetText(item.header)
                    -- Подзаголовок (сезон «Хроник») — золотом и с отступом, под заголовком рубрики.
                    b.header:ClearAllPoints()
                    b.header:SetPoint("BOTTOMLEFT", item.sub and 12 or 2, 5)
                    Color(b.header, item.faint and C.inkFaint or item.sub and C.gold or C.inkSoft)
                else
                    b.icon:SetDesaturated(false)
                    b.icon:SetAlpha(1)
                    fill(b, item)
                end
                self:Paint(b)
                b:Show()
            else
                b:Hide()
            end
        end
        self.bar:Update(self.offset, count, #self.data)
    end
    return list
end

--- Длинный текст на листе с прокруткой колесом.
local function Reader(parent, width, height, size)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    scroll:SetSize(width, height)
    scroll.viewH = height
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(width - 10, height)
    scroll:SetScrollChild(child)
    local fs = Label(child, size or 12.5, C.ink)
    fs:SetPoint("TOPLEFT", 0, 0)
    fs:SetWidth(width - 10)
    fs:SetWordWrap(true)
    fs:SetSpacing(3)
    fs:SetJustifyV("TOP")
    scroll.text = fs
    scroll.bar = Scroller(scroll, height)
    scroll.bar:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 0, 0)
    scroll.pos = 0
    local function Range()
        return math.max(0, ((fs:GetStringHeight() or 0) + 6) - scroll.viewH)
    end
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        self.pos = math.max(0, math.min(self.pos - delta * 36, Range()))
        self:SetVerticalScroll(self.pos)
        self.bar:Update(self.pos, self.viewH, self.viewH + Range())
    end)
    function scroll:SetViewHeight(h)
        self.viewH = h
        self:SetHeight(h)
        self.bar:SetLength(h)
    end
    function scroll:SetBody(body)
        if body == rawget(self, "body") then
            return
        end
        self.body = body
        fs:SetText(body or "")
        child:SetHeight(math.max(self.viewH, (fs:GetStringHeight() or 0) + 6))
        self.pos = 0
        self:SetVerticalScroll(0)
        self.bar:Update(0, self.viewH, self.viewH + Range())
        FadeIn(self, 0.25)
    end
    return scroll
end

--- Карта зоны из клиента (слои карты мира); dim — «туман» неоткрытой земли.
local function MapArt(parent, width, height)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(width, height)
    if holder.SetClipsChildren then
        holder:SetClipsChildren(true)
    end
    holder.tiles = {}
    local back = holder:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints(holder)
    back:SetTexture(WHITE)
    Paint(back, { 0.55, 0.45, 0.30 }, 0.35)
    function holder:ShowMap(mapID, dim)
        for _, tile in ipairs(self.tiles) do
            tile:Hide()
        end
        local layers = mapID and C_Map and C_Map.GetMapArtLayers and Util.Try(C_Map.GetMapArtLayers, mapID)
        local files = mapID and C_Map and C_Map.GetMapArtLayerTextures and Util.Try(C_Map.GetMapArtLayerTextures, mapID, 1)
        local layer = type(layers) == "table" and layers[1]
        if not (layer and layer.layerWidth and layer.tileWidth and type(files) == "table" and files[1]) then
            return false
        end
        local scale = width / layer.layerWidth
        local shift = (layer.layerHeight * scale - height) / 2
        local cols = math.ceil(layer.layerWidth / layer.tileWidth)
        for i, file in ipairs(files) do
            local tile = self.tiles[i] or holder:CreateTexture(nil, "BACKGROUND", nil, 3)
            self.tiles[i] = tile
            local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
            tile:ClearAllPoints()
            tile:SetSize(layer.tileWidth * scale, layer.tileHeight * scale)
            tile:SetPoint("TOPLEFT", col * layer.tileWidth * scale, -row * layer.tileHeight * scale + shift)
            tile:SetTexture(file)
            tile:SetDesaturated(dim and true or false)
            local v = dim and 0.55 or 0.92
            tile:SetVertexColor(v, v * 0.95, v * 0.85) -- в тон пергамента
            tile:Show()
        end
        return true
    end
    -- Тонкая чернильная рамка и уголки-завитки поверх карты.
    for _, p in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 },
        { "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil } }) do
        local t = holder:CreateTexture(nil, "OVERLAY", nil, 6)
        t:SetTexture(WHITE)
        t:SetPoint(p[1])
        t:SetPoint(p[2])
        if p[3] then
            t:SetWidth(p[3])
        else
            t:SetHeight(p[4])
        end
        Paint(t, C.inkSoft, 0.7)
    end
    return holder
end

--- Кнопка-значок ▶/■ (послушать рассказ места).
local function PlayButton(parent, size, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b.icon = Art(b, "round-play", size)
    b.icon:SetAllPoints(b)
    function b:SetPlaying(on)
        self.icon:SetArt(on and "round-stop" or "round-play")
    end
    b:SetScript("OnEnter", function(self) self.icon:SetAlpha(0.8) end)
    b:SetScript("OnLeave", function(self) self.icon:SetAlpha(1) end)
    b:SetScript("OnClick", onClick)
    return b
end

-- Данные ------------------------------------------------------------------------------------------

--- Своя иконка земли: icon-zone-<uiMapID> (листы zones-N в make_journal_assets.py), если нарезана.
local function ZoneIcon(z)
    local key = "icon-zone-" .. tostring(z.mapID)
    return ART[key] and key or nil
end

--- Неоткрытая земля: свиток в тумане (zone-unknown), без него — замок.
local function LockedLandIcon()
    return ART["icon-zone-unknown"] and "icon-zone-unknown" or "icon-lock"
end

--- Материк карты (uiMapType 2) — для переключателя материков.
local continentCache = {}
local function Continent(mapID)
    if continentCache[mapID] ~= nil then
        return continentCache[mapID] or nil
    end
    local id = mapID
    for _ = 1, 6 do
        local info = id and C_Map and C_Map.GetMapInfo and Util.Try(C_Map.GetMapInfo, id)
        if not info then
            break
        end
        if info.mapType == 2 then
            continentCache[mapID] = id
            return id
        end
        id = info.parentMapID
    end
    continentCache[mapID] = false
end

local function ContinentKey(z)
    local c = z.continent
    return (c == 1415 or c == 1414) and c or false
end

--- Зоны из модулей: { mapID, name, sound, continent, subs = { {name, names, sound, first}, ... }, open, first }.
function Journal:Zones()
    local byMap = {}
    for _, pack in ipairs(Packs:Active()) do
        for mapID, zone in pairs(pack.z or {}) do
            local info = C_Map and C_Map.GetMapInfo and Util.Try(C_Map.GetMapInfo, mapID)
            if not (info and info.mapType and info.mapType < 3) then -- материки и мир — не место
                local z = byMap[mapID]
                if not z then
                    z = { mapID = mapID, subs = {}, seen = {}, info = info }
                    byMap[mapID] = z
                end
                if zone.h and not z.sound then
                    z.name = zone.n
                    z.sound = Packs:ZoneEntrySound(pack, zone)
                end
                for subName, entry in pairs(zone.s or {}) do
                    local sub = z.seen[entry.h]
                    if not sub then
                        sub = { name = entry.n or subName, names = {}, sound = Packs:ZoneEntrySound(pack, entry), zone = z }
                        z.seen[entry.h] = sub
                        z.subs[#z.subs + 1] = sub
                    end
                    sub.names[#sub.names + 1] = subName
                end
            end
        end
    end
    local out = {}
    for mapID, z in pairs(byMap) do
        z.name = z.name or (z.info and z.info.name) or tostring(mapID)
        z.continent = Continent(mapID)
        z.first = Diary:Visited(tostring(mapID))
        z.open = 0
        for _, sub in ipairs(z.subs) do
            for _, name in ipairs(sub.names) do
                local at = Diary:Visited(mapID .. ":" .. name)
                if at then
                    sub.first = math.min(sub.first or at, at)
                end
            end
            if sub.first then
                z.open = z.open + 1
                z.first = z.first and math.min(z.first, sub.first) or sub.first
            end
        end
        table.sort(z.subs, function(a, b) return a.name < b.name end)
        out[#out + 1] = z
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

--- Сколько мест открыто: зона со своим рассказом считается местом, плюс её подзоны.
local function Count(zones)
    local open, total = 0, 0
    for _, z in ipairs(zones) do
        local own = z.sound and 1 or 0
        total = total + own + #z.subs
        open = open + (z.first and own or 0) + z.open
    end
    return open, total
end

--- Закреплённые земли — группа сверху списка.
function Journal:Pins()
    ns.charDB.pins = ns.charDB.pins or {}
    return ns.charDB.pins
end

local function SubtitleText(sound)
    local parts = {}
    for _, cue in ipairs(sound and sound.subtitles or {}) do
        parts[#parts + 1] = cue[2]
    end
    return table.concat(parts, " ")
end

--- Земля, где стоит игрок (зона или её родитель с лором).
function Journal:CurrentZone(zones)
    local mapID = C_Map and C_Map.GetBestMapForUnit and Util.Try(C_Map.GetBestMapForUnit, "player")
    for _ = 1, 4 do
        for _, z in ipairs(zones) do
            if z.mapID == mapID then
                return z
            end
        end
        local info = mapID and C_Map and C_Map.GetMapInfo and Util.Try(C_Map.GetMapInfo, mapID)
        mapID = info and info.parentMapID
        if not mapID then
            break
        end
    end
end

--- Карта мира на нужной земле (дневник закрывается, чтобы не загораживать карту).
local function OpenWorldMap(mapID)
    if not WorldMapFrame then
        return
    end
    Journal.frame:Hide()
    if not WorldMapFrame:IsShown() then
        if ToggleWorldMap then
            pcall(ToggleWorldMap)
        elseif ShowUIPanel then
            pcall(ShowUIPanel, WorldMapFrame)
        end
    end
    if mapID and WorldMapFrame.SetMapID then
        pcall(WorldMapFrame.SetMapID, WorldMapFrame, mapID)
    end
end

--- Звучит ли этот звук сейчас.
local function Playing(sound)
    local current = Queue:Current()
    return sound ~= nil and current ~= nil and current.sound ~= nil and current.sound.path == sound.path
end

--- Сыграть рассказ из дневника (или остановить, если он уже звучит).
function Journal:PlaySound(sound, name, title)
    if not sound or not sound.path then
        return false
    end
    if Playing(sound) then
        Queue:Skip()
        return false
    end
    return Queue:Add({
        sound = sound, event = ns.Event.Gossip, name = name or "", title = title or "Рассказчик",
        portrait = {}, fromJournal = true,
    })
end

-- Окно-книга --------------------------------------------------------------------------------------

--- Поле письма листа: левый верхний угол (от окна) и размер.
local function PageRect(side)
    local p = PAGES[side]
    return p[1] * W, -p[3] * H, (p[2] - p[1]) * W, (p[4] - p[3]) * H
end

--- Лист: фрейм на поле письма (всё содержимое листа — в нём).
local function Page(f, side)
    local x, y, w, h = PageRect(side)
    local page = CreateFrame("Frame", nil, f)
    page:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
    page:SetSize(w, h)
    page.w, page.h = w, h
    return page
end

--- Лента-закладка (вкладка): торчит из верхнего края книги вырезом вверх; выбранная — выше и ярче.
local function Ribbon(parent, color, text, onClick)
    local b = CreateFrame("Button", nil, parent)
    local on, off = "ribbon_" .. color, "ribbon_" .. color .. "_dim"
    local a = ART[on]
    local width = 92
    local scale = a and width / a.w or 1
    b:SetWidth(width)
    if a then
        b.on = Slice(b, on, scale, "ARTWORK", 0)
        b.off = Slice(b, ART[off] and off or on, scale, "ARTWORK", 0)
        b.notch = ((a.slice and a.slice[3]) or 0) * scale -- вырез — сверху (лента перевёрнута)
    else
        local tint = color == "red" and { 0.55, 0.15, 0.11 } or { 0.36, 0.20, 0.52 }
        local t = b:CreateTexture(nil, "ARTWORK")
        t:SetAllPoints(b)
        t:SetTexture(WHITE)
        Paint(t, tint)
        b.on = { SetShown = function(_, v) t:SetAlpha(v and 1 or 0.7) end }
        b.off = { SetShown = function() end }
        b.notch = 0
    end
    b.label = Shadow(Label(b, 11, C.light, "CENTER"))
    b.label:SetText(text)
    function b:SetActive(active)
        self.active = active
        self.on:SetShown(active)
        self.off:SetShown(not active)
        -- Низ ленты уходит в книгу на RIBBON_DIP; надпись — на прямом куске над краем книги, под вырезом.
        self:SetHeight((active and 36 or 27) + self.notch)
        self.label:ClearAllPoints()
        self.label:SetPoint("BOTTOM", self, "BOTTOM", 0, RIBBON_DIP + 5)
        Color(self.label, active and C.light or { 0.80, 0.72, 0.58 })
    end
    b:SetScript("OnClick", onClick)
    b:SetActive(false)
    return b
end

function Journal:Create()
    local f = CreateFrame("Frame", "WayfarerJournal", UIParent)
    f:SetSize(W, H)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(frame) frame:StartMoving() end)
    f:SetScript("OnDragStop", function(frame) frame:StopMovingOrSizing() end)
    f:Hide()
    if UISpecialFrames then
        table.insert(UISpecialFrames, "WayfarerJournal") -- Esc закрывает
    end
    self.frame = f

    local open = f.CreateAnimationGroup and f:CreateAnimationGroup()
    if open then
        local alpha = open:CreateAnimation("Alpha")
        alpha:SetFromAlpha(0)
        alpha:SetToAlpha(1)
        alpha:SetDuration(0.18)
        alpha:SetSmoothing("OUT")
        self.openAnim = open
    end

    -- Разворот книги — одна картинка на всё окно; без неё — кожа и два листа заливкой.
    if BOOK then
        Art(f, "book", W, H, "BACKGROUND", 0):SetPoint("TOPLEFT")
    else
        local cover = f:CreateTexture(nil, "BACKGROUND", nil, 0)
        cover:SetAllPoints(f)
        cover:SetTexture(WHITE)
        Paint(cover, { 0.24, 0.14, 0.08 })
        for _, side in ipairs({ "left", "right" }) do
            local x, y, w, h = PageRect(side)
            local paper = f:CreateTexture(nil, "BACKGROUND", nil, 1)
            paper:SetPoint("TOPLEFT", f, "TOPLEFT", x - 14, y + 14)
            paper:SetSize(w + 28, h + 28)
            paper:SetTexture(WHITE)
            Paint(paper, { 0.93, 0.86, 0.69 })
        end
    end

    local close = CreateFrame("Button", nil, f)
    close:SetSize(30, 30)
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", 8, 8)
    close:SetFrameLevel((f:GetFrameLevel() or 1) + 20)
    close.icon = Art(close, "icon-close", 30)
    close.icon:SetAllPoints(close)
    close:SetScript("OnClick", function() f:Hide() end)

    -- Ленты-закладки свисают с верхнего края книги над левым листом.
    self.ribbons = {}
    local tabs = { { "azeroth", "red", "АЗЕРОТ" } }
    if rawget(ns, "Radio") then
        tabs[#tabs + 1] = { "stories", "purple", "ИСТОРИИ" }
    end
    for i, tab in ipairs(tabs) do
        local r = Ribbon(f, tab[2], tab[3], function() Journal:Show(tab[1]) end)
        r:SetFrameLevel((f:GetFrameLevel() or 1) + 15)
        r:SetPoint("BOTTOMLEFT", f, "TOPLEFT", PAGES.left[1] * W + 6 + (i - 1) * 100, -RIBBON_DIP)
        self.ribbons[tab[1]] = r
    end

    self.pages = {}
    self:CreateAzeroth(f)
    if rawget(ns, "Radio") then
        self:CreateStories(f)
    end
end

-- Азерот ------------------------------------------------------------------------------------------

function Journal:CreateAzeroth(f)
    local left, right = Page(f, "left"), Page(f, "right")
    local view = { left = left, right = right }
    self.pages.azeroth = view
    local lw, rw = left.w, right.w

    -- Слева: герой и общий прогресс.
    view.hero = Label(left, 22, C.ink, "LEFT", true)
    view.hero:SetPoint("TOPLEFT", 0, 0)
    view.heroLine = Label(left, 11.5, C.inkSoft)
    view.heroLine:SetPoint("TOPLEFT", view.hero, "BOTTOMLEFT", 0, -3)
    local openLabel = Label(left, 12, C.inkSoft)
    openLabel:SetPoint("TOPLEFT", 0, -52)
    openLabel:SetText("Открыто мест")
    view.openCount = Label(left, 12, C.inkSoft, "RIGHT")
    view.openCount:SetPoint("TOPRIGHT", 0, -52)
    view.bar = Bar(left, lw)
    view.bar:SetPoint("TOPLEFT", 0, -70)

    -- Материки — ссылки-вкладки.
    view.continents = {}
    local x = 0
    for _, spec in ipairs(CONTINENTS) do
        local l = Link(left, spec[2], function()
            Journal.continent = spec[1]
            Journal.zoneId = nil
            Journal:Refresh(true)
        end, 12, true)
        l:SetPoint("TOPLEFT", x, -84)
        l.value = spec[1]
        view.continents[#view.continents + 1] = l
        x = x + (l:GetWidth() or 120) + 16
    end

    -- Поиск — строка с подчёркиванием.
    local search = CreateFrame("Frame", nil, left)
    search:SetSize(lw, 22)
    search:SetPoint("TOPLEFT", 0, -112)
    local line = search:CreateTexture(nil, "ARTWORK")
    line:SetTexture(WHITE)
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    Paint(line, C.inkSoft, 0.45)
    local glass = Art(search, "round-search", 14)
    glass:SetPoint("LEFT", 2, 0)
    glass:SetAlpha(0.7)
    local edit = CreateFrame("EditBox", nil, search)
    edit:SetPoint("LEFT", glass, "RIGHT", 6, 0)
    edit:SetPoint("RIGHT", -4, 0)
    edit:SetHeight(20)
    edit:SetAutoFocus(false)
    edit:SetFont(FONT_TEXT, 12, "")
    edit:SetTextColor(C.ink[1], C.ink[2], C.ink[3])
    local hint = Label(search, 12, C.inkFaint)
    hint:SetPoint("LEFT", edit, "LEFT", 0, 0)
    hint:SetText("Найти землю или место...")
    edit:SetScript("OnEscapePressed", function(e) e:ClearFocus() end)
    edit:SetScript("OnEnterPressed", function(e) e:ClearFocus() end)
    edit:SetScript("OnTextChanged", function(e)
        local text = e:GetText() or ""
        hint:SetShown(text == "")
        Journal.query = text ~= "" and Lower(text) or nil
        Journal:Refresh()
    end)
    search:EnableMouse(true)
    search:SetScript("OnMouseDown", function() edit:SetFocus() end)
    view.search = edit

    view.list = RowList(left, lw, left.h - 144, 22, function(row, item)
        if item.action == "locked" then
            row.icon:SetArt(LockedLandIcon())
            row.icon:SetAlpha(0.55)
            row.title:SetText(item.title)
            Color(row.title, C.inkFaint)
            row.meta:SetText(Journal.showLocked and "скрыть" or "показать")
            return
        end
        local z = item.zone
        local open = z.first ~= nil
        row.icon:SetArt(not open and LockedLandIcon() or ZoneIcon(z) or item.here and "icon-place" or "icon-map")
        row.icon:SetDesaturated(not open)
        row.icon:SetAlpha(open and 1 or 0.55)
        row.title:SetText(z.name)
        Color(row.title, open and C.ink or C.inkFaint)
        row.meta:SetText(#z.subs > 0 and string.format("%d / %d", z.open, #z.subs) or "")
    end, function(item)
        if item.action == "locked" then
            Journal.showLocked = not Journal.showLocked
            Journal:Refresh()
        else
            Journal:SelectZone(item.zone)
        end
    end)
    view.list:SetPoint("TOPLEFT", 0, -144)

    -- Справа: земля. Иконка земли (если нарезана) — слева от названия, как у выпусков «Историй».
    view.zoneIcon = Art(right, "icon-map", 56)
    view.zoneIcon:SetPoint("TOPLEFT", 0, 0)
    view.name = Label(right, 30, C.ink, "LEFT", true)
    view.info = Label(right, 12, C.inkSoft)
    function view:PlaceTitle(iconShown)
        local x = iconShown and 66 or 0
        self.name:ClearAllPoints()
        self.name:SetPoint("RIGHT", self.right, "RIGHT", 0, 0)
        self.name:SetPoint("TOPLEFT", x, 0)
        self.info:ClearAllPoints()
        self.info:SetPoint("RIGHT", self.right, "RIGHT", 0, 0)
        self.info:SetPoint("TOPLEFT", x, -38)
    end
    view:PlaceTitle(false)
    view.map = MapArt(right, rw, 118)
    view.map:SetPoint("TOPLEFT", 0, -60)
    view.listen = Pill(right, "Рассказ о земле", "play", function()
        local z = Journal.zone
        if z and z.sound then
            Journal:PlaySound(z.sound, z.name)
            Journal:Refresh()
        end
    end, 170, 28)
    view.listen:SetPoint("TOPLEFT", 0, -188)
    view.openMap = Link(right, "Открыть карту", function() OpenWorldMap(Journal.zone and Journal.zone.mapID) end)
    view.pin = Link(right, "Закрепить", function()
        local z = Journal.zone
        if z then
            local pins = Journal:Pins()
            pins[z.mapID] = not pins[z.mapID] or nil
            Journal:Refresh()
        end
    end)
    local rule = Rule(right, rw)
    rule:SetPoint("TOPLEFT", 0, -226)

    local places = Label(right, 10, C.inkSoft)
    places:SetPoint("TOPLEFT", 0, -244)
    places:SetText("МЕСТА")
    view.placeCount = Label(right, 10, C.inkSoft, "RIGHT")
    view.placeCount:SetPoint("TOPRIGHT", 0, -244)

    -- Места — в две колонки; открытые с ▶, закрытые — одной строкой «ещё N не открыто».
    local gridTop, cellH, rows = 258, 24, 4
    local cellW = (rw - 14) / 2
    local grid = CreateFrame("Frame", nil, right)
    grid:SetPoint("TOPLEFT", 0, -gridTop)
    grid:SetSize(rw, rows * cellH)
    grid.cells, grid.offset, grid.data = {}, 0, {}
    for i = 1, rows * 2 do
        local c = CreateFrame("Button", nil, grid)
        c:SetSize(cellW, cellH - 2)
        c:SetPoint("TOPLEFT", ((i - 1) % 2) * (cellW + 14), -math.floor((i - 1) / 2) * cellH)
        c.bg = c:CreateTexture(nil, "BACKGROUND")
        c.bg:SetAllPoints(c)
        c.bg:SetTexture(WHITE)
        c.mark = c:CreateTexture(nil, "ARTWORK")
        c.mark:SetTexture(WHITE)
        c.mark:SetWidth(3)
        c.mark:SetPoint("TOPLEFT", 0, -3)
        c.mark:SetPoint("BOTTOMLEFT", 0, 3)
        Paint(c.mark, C.gold)
        c.icon = Art(c, "round-play", 16)
        c.icon:SetPoint("LEFT", 8, 0)
        c.title = Label(c, 12, C.ink)
        c.title:SetPoint("LEFT", c.icon, "RIGHT", 7, 0)
        c.title:SetPoint("RIGHT", c, "RIGHT", -4, 0)
        c:SetScript("OnEnter", function(b)
            if rawget(b, "place") and b.place ~= Journal.place then
                b.bg:SetVertexColor(C.sel[1], C.sel[2], C.sel[3], 0.35)
            end
        end)
        c:SetScript("OnLeave", function() grid:Refresh() end)
        c:SetScript("OnClick", function(b)
            if rawget(b, "place") then
                Journal:SelectPlace(b.place)
            end
        end)
        grid.cells[i] = c
    end
    grid.bar = Scroller(grid, rows * cellH)
    grid.bar:SetPoint("TOPRIGHT", grid, "TOPRIGHT", 4, 0)
    grid:EnableMouseWheel(true)
    grid:SetScript("OnMouseWheel", function(_, delta)
        local maxRow = math.max(0, math.ceil(#grid.data / 2) - rows)
        grid.offset = math.max(0, math.min(grid.offset - delta, maxRow))
        grid:Refresh()
    end)
    function grid:SetData(data)
        self.data, self.offset = data, 0
        self:Refresh()
    end
    function grid:Refresh()
        for i, c in ipairs(self.cells) do
            local item = self.data[self.offset * 2 + i]
            c.place = item and not item.locked and item or nil
            if item then
                local selected = item == Journal.place
                c.bg:SetVertexColor(C.sel[1], C.sel[2], C.sel[3], selected and 0.75 or 0)
                c.mark:SetShown(selected)
                if item.locked then
                    c.icon:SetArt("icon-lock")
                    c.icon:SetAlpha(0.5)
                    c.title:SetText(item.locked)
                    Color(c.title, C.inkFaint)
                else
                    c.icon:SetArt(Playing(item.sound) and "round-stop" or "round-play")
                    c.icon:SetAlpha(1)
                    c.title:SetText(item.name)
                    Color(c.title, C.ink)
                end
                c:Show()
            else
                c:Hide()
            end
        end
        self.bar:Update(self.offset, rows, math.ceil(#self.data / 2))
    end
    view.grid = grid

    -- Рассказ выбранного места (или самой земли): золотая черта слева, название с ▶, текст.
    local loreTop = gridTop + rows * cellH + 12
    local lore = CreateFrame("Frame", nil, right)
    lore:SetPoint("TOPLEFT", 0, -loreTop)
    lore:SetSize(rw, right.h - loreTop)
    view.loreFrame = lore
    --- Мест мало — рассказ поднимается к ним, а не оставляет пустую полосу (снимок пользователя 2026-10-10).
    function view:PlaceLore(placeRows)
        local top = gridTop + math.max(1, math.min(rows, placeRows)) * cellH + 12
        lore:ClearAllPoints()
        lore:SetPoint("TOPLEFT", right, "TOPLEFT", 0, -top)
        lore:SetSize(rw, right.h - top)
        self.lore:SetViewHeight(right.h - top - 44)
    end
    local tint = lore:CreateTexture(nil, "BACKGROUND")
    tint:SetAllPoints(lore)
    tint:SetTexture(WHITE)
    Paint(tint, C.sel, 0.32)
    local edge = lore:CreateTexture(nil, "ARTWORK")
    edge:SetTexture(WHITE)
    edge:SetWidth(3)
    edge:SetPoint("TOPLEFT")
    edge:SetPoint("BOTTOMLEFT")
    Paint(edge, C.gold)
    view.loreTitle = Label(lore, 16, C.ink, "LEFT", true)
    view.loreTitle:SetPoint("TOPLEFT", 14, -10)
    view.lorePlay = PlayButton(lore, 18, function()
        if view.loreSound then
            Journal:PlaySound(view.loreSound, view.loreTitle:GetText())
            Journal:Refresh()
        end
    end)
    view.lorePlay:SetPoint("LEFT", view.loreTitle, "RIGHT", 8, 0)
    view.lore = Reader(lore, rw - 26, right.h - loreTop - 44)
    view.lore:SetPoint("TOPLEFT", 14, -34)
end

--- Строка героя: имя и «11 уровень, человек, паладин».
local function Hero()
    local parts = {}
    local level = Util.Try(UnitLevel, "player")
    if level then
        parts[#parts + 1] = level .. " уровень"
    end
    for _, v in ipairs({ Util.Try(UnitRace, "player") or false, Util.Try(UnitClass, "player") or false }) do
        if v then
            parts[#parts + 1] = Lower(v) -- «человек, паладин»
        end
    end
    return Util.Try(UnitName, "player") or "Путник", table.concat(parts, ", ")
end

function Journal:FillAzeroth(animate)
    local view = self.pages.azeroth
    local zones = self:Zones()
    local name, line = Hero()
    view.hero:SetText(name)
    view.heroLine:SetText(line)
    local open, total = Count(zones)
    view.openCount:SetText(string.format("%d из %d", open, total))
    view.bar:Set(total > 0 and open / total or 0)

    local here = self:CurrentZone(zones)
    if self.continent == nil then
        self.continent = here and ContinentKey(here) or 1415
    end
    local present = {}
    for _, z in ipairs(zones) do
        present[ContinentKey(z)] = true
    end
    local x = 0
    for _, l in ipairs(view.continents) do
        l:SetShown(present[l.value] == true or l.value == self.continent)
        if l:IsShown() then
            l:ClearAllPoints()
            l:SetPoint("TOPLEFT", view.left, "TOPLEFT", x, -84)
            x = x + (l:GetWidth() or 120) + 16
        end
        l:SetActive(l.value == self.continent)
    end

    -- Список: «Вы здесь», закреплённые, открытые; закрытые — свёрнуты в одну строку.
    local pins = self:Pins()
    local data, openRows, locked = {}, {}, {}
    local function hit(z)
        if Matches(self.query, z.name) then
            return true
        end
        for _, sub in ipairs(z.subs) do
            if sub.first and Matches(self.query, sub.name) then
                return true
            end
        end
    end
    local pinned = {}
    for _, z in ipairs(zones) do
        local inContinent = ContinentKey(z) == self.continent or self.query ~= nil
        if inContinent and hit(z) then
            if z == here and not self.query then
                -- отдельной группой ниже
            elseif pins[z.mapID] and not self.query then
                pinned[#pinned + 1] = { zone = z }
            elseif z.first then
                openRows[#openRows + 1] = { zone = z }
            else
                locked[#locked + 1] = { zone = z }
            end
        end
    end
    local hereItem
    if here and not self.query and ContinentKey(here) == self.continent then
        hereItem = { zone = here, here = true }
        data[#data + 1] = { header = "ВЫ ЗДЕСЬ" }
        data[#data + 1] = hereItem
    end
    if #pinned > 0 then
        data[#data + 1] = { header = "ЗАКРЕПЛЕНО" }
        for _, item in ipairs(pinned) do
            data[#data + 1] = item
        end
    end
    if #openRows > 0 then
        data[#data + 1] = { header = self.query and "НАЙДЕНО" or "ОТКРЫТЫЕ ЗЕМЛИ" }
        for _, item in ipairs(openRows) do
            data[#data + 1] = item
        end
    end
    if #locked > 0 then
        if self.query then
            for _, item in ipairs(locked) do
                data[#data + 1] = item
            end
        else
            data[#data + 1] = { header = "ЕЩЁ НЕ ОТКРЫТЫ" }
            data[#data + 1] = { action = "locked", title = self.showLocked and "Скрыть закрытые земли"
                or string.format("%d %s путника", #locked, Plural(#locked, "земля ждёт", "земли ждут", "земель ждут")) }
            if self.showLocked then
                for _, item in ipairs(locked) do
                    data[#data + 1] = item
                end
            end
        end
    end
    view.list:SetData(data, "Ничего не найдено.", animate)

    local keep
    for _, item in ipairs(data) do
        if item.zone and self.zoneId and item.zone.mapID == self.zoneId then
            keep = item
        end
    end
    keep = keep or hereItem or view.list:First()
    if keep then
        view.list.selected = keep
        view.list:Refresh()
    end
    self:SelectZone(keep and keep.zone)
end

function Journal:SelectZone(z)
    local view = self.pages.azeroth
    local changed = (self.zone and self.zone.mapID) ~= (z and z.mapID)
    self.zone = z
    self.zoneId = z and z.mapID or nil
    for _, item in ipairs(view.list.data) do
        if item.zone and item.zone == z then
            view.list.selected = item
        end
    end
    view.list:Refresh()
    if changed then
        self.place = nil
    end
    local icon = z and (z.first and ZoneIcon(z) or not z.first and LockedLandIcon()) or nil
    view.zoneIcon:SetShown(icon ~= nil)
    if icon then
        view.zoneIcon:SetArt(icon)
        view.zoneIcon:SetDesaturated(not z.first)
        view.zoneIcon:SetAlpha(z.first and 1 or 0.6)
    end
    view:PlaceTitle(icon ~= nil)
    if not z then
        view.name:SetText("")
        view.info:SetText("Здесь появятся земли, в которых вы побываете.")
        view.map:ShowMap(nil)
        view.listen:Hide()
        view.openMap:Hide()
        view.pin:Hide()
        view.placeCount:SetText("")
        view.grid:SetData({})
        self:ShowLore(nil, "", "")
        return
    end
    FitTitle(view.name, z.name, 30, 20)
    if z.first then
        view.info:SetText(string.format("Исследовано %d из %d %s — впервые: %s", z.open, #z.subs,
            Plural(#z.subs, "места", "мест", "мест"), Day(z.first)))
    else
        view.info:SetText("Земля ещё не открыта — побывайте в ней.")
    end
    view.map:ShowMap(z.mapID, not z.first)
    view.listen:SetShown(z.first ~= nil and z.sound ~= nil)
    view.listen:SetLabel(Playing(z.sound) and "Стоп" or "Рассказ о земле")
    view.openMap:ClearAllPoints()
    if view.listen:IsShown() then
        view.openMap:SetPoint("LEFT", view.listen, "RIGHT", 16, 0)
    else
        view.openMap:SetPoint("TOPLEFT", view.right, "TOPLEFT", 0, -192)
    end
    view.openMap:Show()
    view.pin:Show()
    view.pin:SetLabel(self:Pins()[z.mapID] and "Открепить" or "Закрепить")
    view.pin:ClearAllPoints()
    view.pin:SetPoint("LEFT", view.openMap, "RIGHT", 14, 0)

    view.placeCount:SetText(string.format("%d ИЗ %d", z.open, #z.subs))
    local items, closed = {}, 0
    for _, sub in ipairs(z.subs) do
        if sub.first then
            items[#items + 1] = sub
        else
            closed = closed + 1
        end
    end
    if closed > 0 then
        items[#items + 1] = { locked = string.format("ещё %d не открыто", closed) }
    end
    if changed then
        view.grid:SetData(items)
        view:PlaceLore(math.ceil(#items / 2))
    else
        view.grid.data = items
        view.grid:Refresh()
        view:PlaceLore(math.ceil(#items / 2))
    end

    local place = self.place
    if place then
        self:ShowLore(place.sound, place.name, SubtitleText(place.sound))
    elseif z.first and z.sound then
        self:ShowLore(z.sound, z.name, SubtitleText(z.sound))
    elseif z.first then
        self:ShowLore(nil, z.name, "У этой земли нет общего рассказа — выберите место выше.")
    else
        self:ShowLore(nil, z.name, "Рассказ откроется, когда вы побываете здесь.")
    end
    if changed then
        FadeIn(view.right, 0.2)
    end
end

--- Клик по месту: показать его рассказ и послушать (у места значок ▶); звучит — второй клик останавливает.
function Journal:SelectPlace(place)
    self.place = place
    if place and place.sound then
        self:PlaySound(place.sound, place.name)
    end
    self:SelectZone(self.zone)
end

function Journal:ShowLore(sound, title, body)
    local view = self.pages.azeroth
    view.loreSound = sound
    view.loreTitle:SetText(title or "")
    view.lorePlay:SetShown(sound ~= nil)
    view.lorePlay:SetPlaying(Playing(sound))
    view.lore:SetBody(body or "")
end

-- Истории (модуль Wayfarer_Radio) ------------------------------------------------------------------

local RUBRIC_ICONS = {
    chronicles = "chronicles", bestiary = "bestiary", faces = "faces", places = "mysteries", facts = "facts",
    tales = "tales",
}

local function Radio()
    return rawget(ns, "Radio")
end

--- Иконка выпуска: своя (icon в каталоге, если текстура нарезана — листы radio-icons), иначе — рубрики.
local function StoryIcon(s)
    local own = s.icon and ART["icon-" .. s.icon] and ("icon-" .. s.icon)
    return own or ("icon-" .. (RUBRIC_ICONS[s.rubric] or "book"))
end

--- Коротко справа в строке: звучит / закрыт / прослушано / часть N из M / длительность.
local function StoryMeta(s)
    if s.locked then
        return "закрыт"
    elseif s.playing then
        return "звучит"
    elseif s.heard then
        return "прослушано"
    elseif s.mark and s.mark > 1 then
        return string.format("часть %d из %d", s.mark, s.parts)
    end
    return Duration(s.duration)
end

--- Подробно для карточки.
local function StoryStatus(s)
    local size = s.parts > 1 and string.format("%d %s, %s", s.parts, Plural(s.parts, "часть", "части", "частей"),
        Duration(s.duration)) or Duration(s.duration)
    if s.locked then
        return Capital(s.locked)
    elseif s.playing then
        return size .. (s.parts > 1 and string.format(" — звучит часть %d", s.part or 1) or " — звучит")
    elseif s.heard then
        return size .. " — прослушано"
    elseif s.mark and s.mark > 1 then
        return size .. string.format(" — остановились на части %d", s.mark)
    end
    return size .. " — новое"
end

function Journal:CreateStories(f)
    local left, right = Page(f, "left"), Page(f, "right")
    local view = { left = left, right = right }
    self.pages.stories = view
    local lw, rw = left.w, right.w
    local radio = Radio()

    local title = Label(left, 22, C.ink, "LEFT", true)
    title:SetPoint("TOPLEFT", 0, 0)
    title:SetText("Путевые истории")
    local heardLabel = Label(left, 12, C.inkSoft)
    heardLabel:SetPoint("TOPLEFT", 0, -34)
    heardLabel:SetText("Прослушано")
    view.heard = Label(left, 12, C.inkSoft, "RIGHT")
    view.heard:SetPoint("TOPRIGHT", 0, -34)
    view.bar = Bar(left, lw)
    view.bar:SetPoint("TOPLEFT", 0, -52)

    -- Рубрики — круглые иконки (только те, где есть выпуски); выбранная — в бронзовом кольце. «Все» — ссылкой.
    local present = {}
    for _, s in ipairs(radio and radio:Library() or {}) do
        present[s.rubric] = true
    end
    view.rubrics = {}
    local all = Link(left, "Все", function()
        Journal.rubric = nil
        Journal:Refresh(true)
    end, 12, true)
    all:SetPoint("TOPLEFT", 0, -74)
    all.value = false
    view.rubrics[1] = all
    local x = (all:GetWidth() or 30) + 14
    for _, key in ipairs(radio and radio.RUBRIC_ORDER or {}) do
        if present[key] then
            local b = CreateFrame("Button", nil, left)
            b:SetSize(32, 32)
            b:SetPoint("TOPLEFT", x, -66)
            b.icon = Art(b, "round-" .. (RUBRIC_ICONS[key] or "book"), 32)
            b.icon:SetAllPoints(b)
            b.ring = Art(b, "medal_ring", 42, nil, "OVERLAY")
            b.ring:SetPoint("CENTER")
            b.value = key
            function b:SetActive(on)
                self.ring:SetShown(on)
                self.icon:SetAlpha(on and 1 or 0.75)
            end
            b:SetScript("OnClick", function()
                Journal.rubric = Journal.rubric ~= key and key or nil
                Journal:Refresh(true)
            end)
            b:SetScript("OnEnter", function(self)
                if GameTooltip then
                    GameTooltip:SetOwner(self, "ANCHOR_TOP")
                    GameTooltip:SetText(radio.RUBRICS[key] or key)
                    GameTooltip:Show()
                end
            end)
            b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
            view.rubrics[#view.rubrics + 1] = b
            x = x + 40
        end
    end

    local airTop = left.h - 44
    view.list = RowList(left, lw, airTop - 112, 22, function(row, s)
        row.icon:SetArt(s.locked and "icon-lock" or StoryIcon(s))
        row.icon:SetDesaturated(s.locked ~= nil)
        row.icon:SetAlpha(s.locked and 0.55 or 1)
        row.title:SetText(s.name or "?")
        Color(row.title, s.locked and C.inkFaint or s.playing and C.gold or C.ink)
        row.meta:SetText(StoryMeta(s))
        Color(row.meta, s.playing and C.gold or C.inkSoft)
        row.dot:SetShown(not s.locked and not s.heard and not s.mark and not s.playing)
    end, function(s) Journal:SelectStory(s) end)
    view.list:SetPoint("TOPLEFT", 0, -112)

    -- Эфир — внизу листа: значок, состояние, режим и переключатель.
    local rule = Rule(left, lw)
    rule:SetPoint("TOPLEFT", 0, -(airTop - 6))
    local air = Art(left, "icon-air", 26)
    air:SetPoint("TOPLEFT", 0, -(airTop + 6))
    view.airState = Label(left, 12.5, C.ink)
    view.airState:SetPoint("TOPLEFT", air, "TOPRIGHT", 10, -1)
    view.airMode = Link(left, "режим", function(b)
        if MenuUtil and MenuUtil.CreateContextMenu and Radio() then
            MenuUtil.CreateContextMenu(b, function(_, root) Radio():BuildMenu(root) end)
        end
    end, 11)
    view.airMode:SetPoint("TOPLEFT", view.airState, "BOTTOMLEFT", 0, -3)
    view.airToggle = Toggle(left, function()
        local r = Radio()
        if r and r.session and r.session.kind ~= "library" then
            r:Stop()
        elseif r then
            r:Start("radio")
        end
        Journal:Refresh()
    end)
    view.airToggle:SetPoint("TOPRIGHT", 0, -(airTop + 10))

    -- Справа: выпуск.
    view.art = Art(right, "icon-book", 84)
    view.art:SetPoint("TOPLEFT", 0, 0)
    view.rubric = Label(right, 10, C.inkSoft)
    view.rubric:SetPoint("TOPLEFT", 98, -6)
    view.name = Label(right, 30, C.ink, "LEFT", true)
    view.name:SetPoint("TOPLEFT", 98, -22)
    view.name:SetPoint("RIGHT", right, "RIGHT", 0, 0)
    view.meta = Label(right, 12, C.inkSoft)
    view.meta:SetPoint("TOPLEFT", 98, -60)
    view.meta:SetPoint("RIGHT", right, "RIGHT", 0, 0)

    view.listen = Pill(right, "Слушать", "play", function()
        local s = view.story
        if s and s.playing then
            Radio():Stop()
        elseif s then
            Radio():PlayEpisode(s.id)
        end
        Journal:Refresh()
    end, 150, 28)
    view.listen:SetPoint("TOPLEFT", 0, -100)
    view.restart = Link(right, "С начала", function()
        if view.story then
            Radio():PlayEpisode(view.story.id, 1)
            Journal:Refresh()
        end
    end)
    view.recap = Link(right, "Краткий пересказ", function()
        if view.story then
            Radio():PlayEpisode(view.story.id, nil, true)
            Journal:Refresh()
        end
    end)
    view.rule = Rule(right, rw)
    view.rule:SetPoint("TOPLEFT", 0, -140)

    view.partsLabel = Label(right, 10, C.inkSoft)
    view.partsLabel:SetPoint("TOPLEFT", 0, -156)
    view.partsLabel:SetText("ЧАСТИ")
    view.parts = {}
    for i = 1, 8 do
        local b = CreateFrame("Button", nil, right)
        b:SetSize(rw, 26)
        b:SetPoint("TOPLEFT", 0, -172 - (i - 1) * 26)
        b.bg = b:CreateTexture(nil, "BACKGROUND")
        b.bg:SetAllPoints(b)
        b.bg:SetTexture(WHITE)
        b.line = b:CreateTexture(nil, "ARTWORK")
        b.line:SetTexture(WHITE)
        b.line:SetHeight(1)
        b.line:SetPoint("BOTTOMLEFT")
        b.line:SetPoint("BOTTOMRIGHT")
        Paint(b.line, C.inkSoft, 0.2)
        b.num = Label(b, 15, C.gold, "CENTER", true)
        b.num:SetPoint("LEFT", 2, 0)
        b.num:SetWidth(18)
        b.title = Label(b, 12.5, C.ink)
        b.title:SetPoint("LEFT", 28, 0)
        b.icon = Art(b, "round-play", 18)
        b.icon:SetPoint("RIGHT", -4, 0)
        b.time = Label(b, 11, C.inkSoft, "RIGHT")
        b.time:SetPoint("RIGHT", b.icon, "LEFT", -10, 0)
        b:SetScript("OnEnter", function(self) self.bg:SetVertexColor(C.sel[1], C.sel[2], C.sel[3], 0.35) end)
        b:SetScript("OnLeave", function(self) self.bg:SetVertexColor(C.sel[1], C.sel[2], C.sel[3], self.now and 0.6 or 0) end)
        b:SetScript("OnClick", function(self)
            local s = view.story
            if s and rawget(self, "part") and not s.locked then
                if self.part.recap then
                    Radio():PlayEpisode(s.id, nil, true)
                else
                    Radio():PlayEpisode(s.id, self.part.index)
                end
                Journal:Refresh()
            end
        end)
        view.parts[i] = b
    end
    view.flourish = Ink(right, "ink_flourish", 120)
    view.text = Reader(right, rw, 100)
end

function Journal:FillStories(animate)
    local view = self.pages.stories
    local radio = Radio()
    local library = radio and radio:Library() or {}
    local heard, shown = 0, {}
    for _, s in ipairs(library) do
        heard = heard + (s.heard and 1 or 0)
        if not self.rubric or s.rubric == self.rubric then
            shown[#shown + 1] = s
        end
    end
    view.heard:SetText(string.format("%d из %d", heard, #library))
    view.bar:Set(#library > 0 and heard / #library or 0)
    for _, b in ipairs(view.rubrics) do
        b:SetActive(b.value == (self.rubric or false))
    end
    local data, last, season = {}, nil, nil
    for _, s in ipairs(shown) do
        if s.rubricName ~= last then
            data[#data + 1] = { header = Upper(s.rubricName) }
            last, season = s.rubricName, nil
        end
        -- «Хроники»: каждый сезон — своим подзаголовком, иначе три сезона читаются одним списком (2026-10-11).
        local name = s.series and s.series:match("сезон%s+(.+)$")
        if name and name ~= season then
            -- Закрытый сезон (не дослушан прошлый и не тот уровень) — блёклым, с пометкой; причина — в карточке серии.
            data[#data + 1] = { header = "Сезон " .. name .. (s.seasonLocked and " — пока закрыт" or ""), sub = true,
                                faint = s.seasonLocked }
            season = name
        end
        data[#data + 1] = s
    end
    view.list:SetData(data, "Выпусков нет — установите модуль «Путевые истории».", animate)
    local keep
    for _, s in ipairs(shown) do
        keep = keep or (s.id == self.story and s)
    end
    self:SelectStory(keep or view.list:First())

    local session = radio and radio.session
    local on = session ~= nil and session.kind ~= "library"
    view.airToggle:Set(on)
    view.airState:SetText(on and "Эфир включён" or "Эфир выключен")
    local modes = { button = "по кнопке", auto = "сам, когда я в пути", off = "выключен" }
    local db = rawget(_G, "Wayfarer_RadioDB")
    view.airMode:SetLabel("режим: " .. (modes[db and db.mode or "button"] or "по кнопке"))
end

function Journal:SelectStory(s)
    local view = self.pages.stories
    local changed = self.story ~= (s and s.id)
    self.story = s and s.id or nil
    view.story = s
    view.list.selected = s
    view.list:Refresh()
    if not s then
        view.art:Hide()
        view.rubric:SetText("")
        view.name:SetText("")
        view.meta:SetText("")
        for _, w in ipairs({ view.listen, view.restart, view.recap, view.partsLabel }) do
            w:Hide()
        end
        for _, b in ipairs(view.parts) do
            b:Hide()
        end
        view.text:SetBody("")
        return
    end
    view.art:Show()
    view.art:SetArt(s.locked and "icon-lock" or StoryIcon(s))
    view.art:SetDesaturated(s.locked ~= nil)
    view.rubric:SetText(Upper(s.rubricName))
    FitTitle(view.name, s.name or "?", 30, 18)
    view.meta:SetText(StoryStatus(s))

    view.listen:SetShown(not s.locked)
    view.listen:SetLabel(s.playing and "Стоп" or (s.mark and not s.heard and s.mark > 1) and "Продолжить" or "Слушать")
    if view.listen.icon then
        view.listen.icon:SetArt(s.playing and "round-stop" or "round-play")
    end
    local anchor = view.listen
    view.restart:SetShown(not s.locked and s.parts > 1 and (s.heard ~= nil or (s.mark or 1) > 1))
    if view.restart:IsShown() then
        view.restart:ClearAllPoints()
        view.restart:SetPoint("LEFT", anchor, "RIGHT", 16, 0)
        anchor = view.restart
    end
    view.recap:SetShown(not s.locked and s.recap)
    view.recap:ClearAllPoints()
    view.recap:SetPoint("LEFT", anchor, "RIGHT", anchor == view.listen and 16 or 14, 0)

    -- Части: у многосерийных — список (любую можно включить); у одиночных — сразу текст.
    local parts = Radio():Parts(s.id)
    local playingId, playingPart, playingRecap = Radio():NowPlaying()
    local multi = s.parts > 1 or s.recap
    view.partsLabel:SetShown(multi and not s.locked)
    local shownParts = 0
    for i, b in ipairs(view.parts) do
        local part = multi and not s.locked and parts[i]
        b.part = part or nil
        if part then
            shownParts = i
            local now = playingId == s.id and ((part.recap and playingRecap) or (not part.recap and not playingRecap
                and playingPart == part.index))
            b.now = now
            b.num:SetText(part.recap and "" or tostring(part.index))
            b.title:SetText(part.recap and "Краткий пересказ" or ("Часть " .. (ORDINALS[part.index] or part.index)))
            Color(b.title, now and C.gold or C.ink)
            b.time:SetText(now and "звучит" or Duration(part.duration))
            Color(b.time, now and C.gold or C.inkSoft)
            b.icon:SetArt(now and "round-stop" or part.heard and "round-heard" or part.recap and "round-recap"
                or "round-play")
            b.bg:SetVertexColor(C.sel[1], C.sel[2], C.sel[3], now and 0.6 or 0)
            b:Show()
        else
            b:Hide()
        end
    end

    local top = multi and not s.locked and (172 + shownParts * 26 + 12) or 152
    if view.flourish then
        view.flourish:ClearAllPoints()
        view.flourish:SetPoint("TOP", view.right, "TOP", 0, -top)
        top = top + 22
    end
    view.text:ClearAllPoints()
    view.text:SetPoint("TOPLEFT", view.right, "TOPLEFT", 0, -top)
    view.text:SetViewHeight(math.max(60, view.right.h - top))
    if s.locked then
        view.text:SetBody("Этот рассказ пока закрыт: " .. s.locked .. ". Так он не расскажет того, до чего вы ещё не дошли.")
    else
        local body = {}
        for _, part in ipairs(parts) do
            if not part.recap then
                body[#body + 1] = part.text or ""
            end
        end
        view.text:SetBody(table.concat(body, "\n\n"))
    end
    if changed then
        FadeIn(view.right, 0.2)
    end
end

-- Показ -------------------------------------------------------------------------------------------

--- Прежние имена вкладок (обзор, атлас, бестиарий, летопись) ведут в «Азерот».
local ALIASES = { overview = "azeroth", atlas = "azeroth", bestiary = "azeroth", chronicle = "azeroth" }

function Journal:Show(tab)
    if not self.frame then
        self:Create()
    end
    local was = self.tab
    local opening = not self.frame:IsShown()
    tab = ALIASES[tab] or tab or self.tab or "azeroth"
    if not self.pages[tab] then
        tab = "azeroth" -- «Историй» нет без модуля путевых историй
    end
    self.tab = tab
    for key, view in pairs(self.pages) do
        view.left:SetShown(key == tab)
        view.right:SetShown(key == tab)
    end
    for key, ribbon in pairs(self.ribbons) do
        ribbon:SetActive(key == tab)
    end
    self.frame:Show()
    if opening and self.openAnim then
        self.openAnim:Stop()
        self.openAnim:Play()
    end
    if opening or was ~= tab then
        FadeIn(self.pages[tab].left, 0.2)
        FadeIn(self.pages[tab].right, 0.2)
    end
    self:Refresh(true)
end

function Journal:Toggle()
    if self.frame and self.frame:IsShown() then
        self.frame:Hide()
    else
        self:Show()
    end
end

function Journal:Refresh(animate)
    if not self.frame then
        return
    end
    if self.tab == "stories" then
        self:FillStories(animate)
    else
        self:FillAzeroth(animate)
    end
end

--- Очередь изменилась (UI:Refresh): ▶/■ и «звучит» на листах следуют за тем, что играет. Не чаще раза за кадр.
function Journal:OnQueue()
    if not (self.frame and self.frame:IsShown()) or self.queued then
        return
    end
    self.queued = true
    C_Timer.After(0, function()
        self.queued = nil
        if self.frame:IsShown() then
            self:Refresh(false)
        end
    end)
end

-- Ошибки внутри дневника клиент молча прячет: пишем первую в чат, чтобы её можно было прислать.
for _, name in ipairs({ "Show", "Toggle", "Refresh", "FillAzeroth", "SelectZone", "SelectPlace", "FillStories",
    "SelectStory", "OnQueue" }) do
    local fn = Journal[name]
    Journal[name] = function(...)
        local ok, err = pcall(fn, ...)
        if not ok then
            Util.Trace("journal", tostring(err))
            if not Journal.warned then
                Journal.warned = true
                Util.Print("дневник: ошибка — %s. Пришлите, пожалуйста, это сообщение.", tostring(err))
            end
            local handler = geterrorhandler and geterrorhandler()
            if handler then
                handler(err)
            end
        end
    end
end
