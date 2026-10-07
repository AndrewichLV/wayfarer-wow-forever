local _, ns = ...

-- Приглушение голосов NPC на время озвучки: приветствие NPC («Чем могу помочь?») звучит в канале
-- «Диалоги» и накладывается на реплику. Пока идёт озвучка, громкость «Диалогов» опускается до нуля,
-- потом возвращается. Прежнее значение хранится в Wayfarer_DB.duckRestore, чтобы вернуть его и после
-- вылета или /reload посреди реплики (Core:ADDON_LOADED).
-- Звук в фоне (баг 2026-10-07): с выключенным «Звуком в фоновом режиме» игра при Alt+Tab обрывает звук, и
-- реплика пропадала, а окно плеера шло дальше. Пока звучит озвучка, звук в фоне включён (настройка
-- playInBackground), потом прежнее значение возвращается — так же через Wayfarer_DB.bgRestore.
local Duck = {}
ns.Duck = Duck

local CVAR = "Sound_DialogVolume"
local BG_CVAR = "Sound_EnableSoundWhenGameIsInBG"

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

--- Звук в фоне на время озвучки: on — включить (если выключен), иначе вернуть прежнее значение.
function Duck:Background(on)
    if on then
        if self.bgActive or ns.db.playInBackground == false then
            return
        end
        local current = Get(BG_CVAR)
        if current == nil or tostring(current) ~= "0" then
            return -- звук в фоне и так есть (или настройки нет в клиенте)
        end
        self.bgActive = true
        ns.db.bgRestore = tostring(current)
        Set(BG_CVAR, "1")
    elseif self.bgActive then
        self.bgActive = false
        local restore = ns.db.bgRestore
        ns.db.bgRestore = nil
        if restore then
            Set(BG_CVAR, restore)
        end
    end
end

function Duck:On()
    self:Background(true)
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
    self:Background(false)
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

--- При загрузке: если прошлый сеанс оборвался посреди реплики — вернуть громкость «Диалогов» и звук в фоне.
function Duck:RestoreAfterCrash()
    local restore = ns.db.duckRestore
    if restore then
        ns.db.duckRestore = nil
        if tonumber(Get(CVAR)) == 0 then
            Set(CVAR, restore)
        end
    end
    local bg = ns.db.bgRestore
    if bg then
        ns.db.bgRestore = nil
        if tostring(Get(BG_CVAR)) == "1" then
            Set(BG_CVAR, bg)
        end
    end
end
