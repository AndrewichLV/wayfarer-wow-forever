local _, ns = ...
local Util = ns.Util

-- Кто с нами говорит: NPC, игровой объект (доска объявлений), предмет или игрок (общий квест).
local Identity = {}
ns.Identity = Identity

local KIND_BY_GUID_TYPE = {
    Creature = "C",
    Vehicle = "C",
    Pet = "C",
    GameObject = "O",
    Item = "I",
    Player = "P",
}

--- Разбирает GUID вида "Creature-0-1-2-3-<npcID>-<spawn>".
---@return string|nil kind "C" | "O" | "I" | "P"
---@return number|nil id ID существа или объекта (у предметов и игроков в GUID его нет)
function Identity.ParseGUID(guid)
    if type(guid) ~= "string" then
        return nil
    end
    local unitType, _, _, _, _, id = strsplit("-", guid)
    local kind = KIND_BY_GUID_TYPE[unitType]
    if kind == "C" or kind == "O" then
        return kind, tonumber(id)
    end
    return kind, nil
end

function Identity.Key(kind, id)
    if kind and id then
        return kind .. ":" .. id
    end
end

-- Невидимая модель для чтения displayID собеседника (по нему пайплайн определяет расу и пол).
local probe

function Identity.DisplayID(unit)
    if Util.IsIdentitySecret(unit) then
        return nil
    end
    probe = probe or CreateFrame("PlayerModel")
    if not pcall(probe.SetUnit, probe, unit) then
        return nil
    end
    local id = Util.Try(probe.GetDisplayInfo, probe)
    if id and id > 0 then
        return id
    end
end

--- Описание текущего собеседника.
---@param preferQuestUnit boolean для окна квеста сначала смотрим "questnpc", для диалога — "npc"
---@return table|nil { unit, kind, id, key, name, sex, display, secret }
function Identity.Current(preferQuestUnit)
    local first, second = "npc", "questnpc"
    if preferQuestUnit then
        first, second = "questnpc", "npc"
    end
    for _, unit in ipairs({ first, second }) do
        if Util.Try(UnitExists, unit) then
            local info = { unit = unit }
            info.secret = Util.IsIdentitySecret(unit)
            info.kind, info.id = Identity.ParseGUID(Util.Try(UnitGUID, unit))
            if not info.id and (info.kind == nil or info.kind == "C") then
                info.id = Util.Try(UnitCreatureID, unit)
                if info.id then
                    info.kind = "C"
                end
            end
            info.key = Identity.Key(info.kind, info.id)
            info.name = Util.Try(UnitName, unit)
            info.sex = Util.Try(UnitSex, unit)
            if info.kind == "C" then
                info.display = Identity.DisplayID(unit)
            end
            return info
        end
    end
    return nil
end

--- true, если target всё ещё тот, с кем игрок разговаривает прямо сейчас (для живого портрета).
function Identity.IsStillPresent(target)
    if not target or not target.unit or target.secret or not target.key then
        return false
    end
    local kind, id = Identity.ParseGUID(Util.Try(UnitGUID, target.unit))
    return Identity.Key(kind, id) == target.key
end
