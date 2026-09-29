local _, ns = ...

-- Приглушение голосов NPC на время озвучки: приветствие NPC («Чем могу помочь?») звучит в канале
-- «Диалоги» и накладывается на реплику. Пока идёт озвучка, громкость «Диалогов» опускается до нуля,
-- потом возвращается. Прежнее значение хранится в Wayfarer_DB.duckRestore, чтобы вернуть его и после
-- вылета или /reload посреди реплики (Core:ADDON_LOADED).
local Duck = {}
ns.Duck = Duck

local CVAR = "Sound_DialogVolume"

local function Get(name)
    local getter = C_CVar and C_CVar.GetCVar or GetCVar
    return getter and getter(name)
end

local function Set(name, value)
    local setter = C_CVar and C_CVar.SetCVar or SetCVar
    if setter then
        pcall(setter, name, value)
    end
end

--- Можно ли приглушать: включено в настройках и сама озвучка идёт не через «Диалоги».
function Duck:Allowed()
    return ns.db.muteNpcVoice and ns.db.channel ~= "Dialog"
end

function Duck:On()
    if self.active or not self:Allowed() then
        return
    end
    local current = tonumber(Get(CVAR))
    if not current or current <= 0 then
        return -- «Диалоги» и так молчат
    end
    self.active = true
    ns.db.duckRestore = current
    Set(CVAR, 0)
end

function Duck:Off()
    if not self.active then
        return
    end
    self.active = false
    local restore = ns.db.duckRestore
    ns.db.duckRestore = nil
    if restore then
        Set(CVAR, restore)
    end
end

--- При загрузке: если прошлый сеанс оборвался посреди реплики — вернуть громкость «Диалогов».
function Duck:RestoreAfterCrash()
    local restore = ns.db.duckRestore
    if restore then
        ns.db.duckRestore = nil
        if tonumber(Get(CVAR)) == 0 then
            Set(CVAR, restore)
        end
    end
end
