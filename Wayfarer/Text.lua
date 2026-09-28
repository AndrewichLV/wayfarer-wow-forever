local _, ns = ...

-- Нормализация текста для сопоставления с пакетами озвучки.
-- ВАЖНО: логика обязана совпадать байт в байт с pipeline/vru/wowtext.py (tokens, fingerprint);
-- это проверяет тест pipeline/tests/test_lua_parity.py.
local Text = {}
ns.Text = Text

local FINGERPRINT_HEAD = 10
local FINGERPRINT_TAIL = 10

-- Кириллица в UTF-8: заглавные -> строчные, Ё/ё -> е (буква «ё» в текстах игры непостоянна).
local LOWER = {}
do
    local char = string.char
    for b = 0x90, 0x9F do -- А..П -> а..п
        LOWER["\208" .. char(b)] = "\208" .. char(b + 0x20)
    end
    for b = 0xA0, 0xAF do -- Р..Я -> р..я
        LOWER["\208" .. char(b)] = "\209" .. char(b - 0x20)
    end
    LOWER["\208\129"] = "\208\181" -- Ё -> е
    LOWER["\209\145"] = "\208\181" -- ё -> е
end

--- Убирает escape-последовательности интерфейса WoW: цвета, ссылки, иконки, |n.
function Text.StripMarkup(s)
    s = s:gsub("|c[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]", "")
    s = s:gsub("|cn[0-9A-Za-z_]+:", "")
    s = s:gsub("|r", "")
    s = s:gsub("|H.-|h(.-)|h", "%1")
    s = s:gsub("|T.-|t", "")
    s = s:gsub("|A.-|a", "")
    s = s:gsub("|n", "\n")
    return s
end

-- string.lower и %w зависят от локали C-библиотеки: в однобайтовой локали (например, cp1251)
-- они «опускают» байты UTF-8 и портят кириллицу. Поэтому только явные диапазоны байтов.
local function AsciiLower(c)
    return string.char(c:byte() + 32)
end

--- Список слов в нижнем регистре: латиница/цифры и кириллица, всё прочее — разделители.
function Text.Tokens(s)
    if type(s) ~= "string" or s == "" then
        return {}
    end
    s = Text.StripMarkup(s)
    s = s:gsub("[\208\209][\128-\191]", LOWER)
    s = s:gsub("[A-Z]", AsciiLower)

    local words, cur, n = {}, {}, 0
    for ch in s:gmatch("[\1-\127\192-\255][\128-\191]*") do
        local b = ch:byte(1)
        local isWord
        if b < 128 then
            isWord = ch:find("^[0-9A-Za-z]$") ~= nil
        else
            isWord = (b == 208 or b == 209) and #ch == 2
        end
        if isWord then
            n = n + 1
            cur[n] = ch
        elseif n > 0 then
            words[#words + 1] = table.concat(cur, "", 1, n)
            n = 0
        end
    end
    if n > 0 then
        words[#words + 1] = table.concat(cur, "", 1, n)
    end
    return words
end

--- Короткий «отпечаток» длинного текста: первые и последние слова.
function Text.Fingerprint(s)
    local t = Text.Tokens(s)
    if #t <= FINGERPRINT_HEAD + FINGERPRINT_TAIL then
        return t
    end
    local fp = {}
    for i = 1, FINGERPRINT_HEAD do
        fp[i] = t[i]
    end
    for i = #t - FINGERPRINT_TAIL + 1, #t do
        fp[#fp + 1] = t[i]
    end
    return fp
end

-- Кэшируются только ключи NPC, с которыми игрок реально говорил, так что кэш остаётся маленьким.
local keyCache = {}

--- Разбирает ключ из пакета (слова через пробел). Результат кэшируется по строке.
function Text.KeyTokens(key)
    local cached = keyCache[key]
    if cached then
        return cached
    end
    local t = {}
    for w in key:gmatch("[^ ]+") do -- не %S: в однобайтовой локали байт 0xA0 считается пробелом
        t[#t + 1] = w
    end
    keyCache[key] = t
    return t
end

--- Коэффициент Дайса по множествам слов: 1 — совпадение, 0 — ничего общего.
function Text.Similarity(a, b)
    if #a == 0 or #b == 0 then
        return 0
    end
    local setA, nA = {}, 0
    for i = 1, #a do
        local w = a[i]
        if not setA[w] then
            setA[w] = true
            nA = nA + 1
        end
    end
    local setB, nB, common = {}, 0, 0
    for i = 1, #b do
        local w = b[i]
        if not setB[w] then
            setB[w] = true
            nB = nB + 1
            if setA[w] then
                common = common + 1
            end
        end
    end
    return 2 * common / (nA + nB)
end
