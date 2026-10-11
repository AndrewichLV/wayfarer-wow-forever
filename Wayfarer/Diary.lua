local _, ns = ...

-- Дневник путника — данные: открытые места («Азерот»). Хранится у персонажа (Wayfarer_CharDB); окно — Journal.lua.
--   visits [ключ места] = время первого визита (ключ как у лора: "1429" — зона, "1429:Златоземье" — подзона)
-- Бестиарий и летопись убраны 2026-10-10 (решение пользователя: дневник перегружен; переслушать — в библиотеке
-- историй, квесты — ▶ в журнале квестов): их записи в сохранениях персонажа удаляются при входе.
local Diary = {}
ns.Diary = Diary

local function Now()
    return time and time() or 0
end

--- Место открыто: игрок в нём побывал (независимо от того, звучал ли лор).
function Diary:Visit(zoneMap, subzone)
    local visits = ns.charDB and ns.charDB.visits
    if not visits or not zoneMap then
        return
    end
    local now = Now()
    local zoneKey = tostring(zoneMap)
    visits[zoneKey] = visits[zoneKey] or now
    if subzone then
        local key = zoneMap .. ":" .. subzone
        visits[key] = visits[key] or now
    end
end

function Diary:Visited(key)
    return ns.charDB and ns.charDB.visits and ns.charDB.visits[key]
end

function Diary:Init()
    local db = ns.charDB
    if not db then
        return
    end
    -- Места, чей лор звучал до появления дневника, открыты «раньше» (время 0 — дата неизвестна).
    db.visits = db.visits or {}
    for key in pairs(db.zones or {}) do
        if not db.visits[key] then
            db.visits[key] = 0
        end
    end
    db.chronicle, db.bestiary = nil, nil -- прежние разделы дневника
end
