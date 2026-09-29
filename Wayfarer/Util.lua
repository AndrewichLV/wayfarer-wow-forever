local _, ns = ...

local Util = {}
ns.Util = Util

-- В клиенте на API 12.x часть значений (GUID, имена, ID существ в подземельях) может
-- приходить «секретной»: её нельзя сравнивать, использовать как ключ таблицы и т.п.
-- Любое значение из Unit*-функций пропускаем через Plain/Try, прежде чем что-то с ним делать.
local issecretvalue = issecretvalue or function() return false end

--- Возвращает v, если это обычное значение, и nil, если секретное.
function Util.Plain(v)
    if issecretvalue(v) then
        return nil
    end
    return v
end

--- Безопасный вызов API: ошибки и секретные результаты превращаются в nil.
function Util.Try(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, a, b, c, d = pcall(fn, ...)
    if not ok then
        return nil
    end
    return Util.Plain(a), Util.Plain(b), Util.Plain(c), Util.Plain(d)
end

--- true, если личность юнита (имя, GUID, ID) сейчас скрыта клиентом.
function Util.IsIdentitySecret(unit)
    if C_Secrets and C_Secrets.ShouldUnitIdentityBeSecret then
        return Util.Try(C_Secrets.ShouldUnitIdentityBeSecret, unit) == true
    end
    return false
end

--- "m" или "f" по полу персонажа игрока: от него зависят варианты фраз ($g в шаблонах).
function Util.PlayerSexKey()
    return Util.Try(UnitSex, "player") == 3 and "f" or "m"
end

function Util.Print(msg, ...)
    if select("#", ...) > 0 then
        msg = msg:format(...)
    end
    print("|cffd4af37Wayfarer:|r " .. msg)
end

function Util.Debug(msg, ...)
    if ns.db and ns.db.debug then
        Util.Print("|cff808080" .. msg .. "|r", ...)
    end
end

--- Копирует отсутствующие ключи из defaults в tbl (неглубоко для не-таблиц, рекурсивно для таблиц).
--- Журнал очереди для диагностики (/wf log): последние события с временем и местом.
--- Хранится в Wayfarer_Collected.trace, чтобы пережить /reload и попасть в SavedVariables.
local TRACE_MAX = 40
function Util.Trace(event, detail)
    if not Wayfarer_Collected then
        return
    end
    local trace = Wayfarer_Collected.trace or {}
    Wayfarer_Collected.trace = trace
    local sub = GetSubZoneText and GetSubZoneText() or ""
    table.insert(trace, string.format("%.1f %s %s | %s", GetTime(), event, tostring(detail or ""), sub))
    while #trace > TRACE_MAX do
        table.remove(trace, 1)
    end
end

function Util.ApplyDefaults(tbl, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(tbl[k]) ~= "table" then
                tbl[k] = {}
            end
            Util.ApplyDefaults(tbl[k], v)
        elseif tbl[k] == nil then
            tbl[k] = v
        end
    end
    return tbl
end
