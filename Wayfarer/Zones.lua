local _, ns = ...
local Util, Packs, Queue, Collector, Text = ns.Util, ns.Packs, ns.Queue, ns.Collector, ns.Text

-- Рассказчик мест: входишь в зону или подзону (Элвиннский лес, Рудник Горного Эха) — звучит её
-- лор. По умолчанию один раз на персонажа. Лор не перебивает квесты и реплики: встаёт в конец
-- очереди, а если его прервал квест — дочитывается после.
local Zones = CreateFrame("Frame")
ns.Zones = Zones

local EVENTS = {
    "PLAYER_ENTERING_WORLD",
    "ZONE_CHANGED_NEW_AREA",
    "ZONE_CHANGED",
    "ZONE_CHANGED_INDOORS",
    "PLAYER_REGEN_ENABLED",
    "CINEMATIC_START",
    "CINEMATIC_STOP",
    "PLAY_MOVIE",
    "STOP_MOVIE",
}

local REPEAT_COOLDOWN = 600 -- режим «всегда»: одно и то же место не чаще раза в 10 минут
local LOGIN_DELAY = 3       -- после входа в игру: дать начаться вступительному ролику
-- Двойники лора: одноимённые подзоны разных карт, пересказанные почти теми же словами. У пересказов
-- одного места (Руины Лордерона, реки, моря, пограничные мосты) совпадает 45–95% слов, у разных мест
-- с одним названием (Каналы и Торговый квартал Штормграда и Подгорода) — 13–20%.
local TWIN_SIMILARITY = 0.45

local recent = {}           -- [ключ места] = GetTime() последнего чтения
local twinCache = {}        -- [ключ подзоны] = { [ключ] = true } — она сама и её двойники
local missingLogged = {}    -- места без лора, уже записанные в этой сессии
local inCinematic = false
local pending = nil         -- отложенная проверка (бой, ролик): nil | "sub" | "zone"

local function PlaceKey(mapID, subzone)
    return subzone and (mapID .. ":" .. subzone) or tostring(mapID)
end

--- Где игрок: звук зоны, звук подзоны, uiMapID зоны с лором, название подзоны.
function Zones:Current()
    local mapID = Util.Try(C_Map.GetBestMapForUnit, "player")
    local subzone = Util.Try(GetSubZoneText)
    if subzone == "" then
        subzone = nil
    end
    local zoneSound, subSound, zoneMap
    if mapID then
        zoneSound, subSound, zoneMap = Packs:FindZone(mapID, subzone)
    end
    if not zoneMap then
        -- У места нет карты с лором (Подземный поезд, подземелье): ищем по названию из клиента.
        local place = subzone or Util.Try(GetRealZoneText) or Util.Try(GetZoneText)
        if place == "" then
            place = nil
        end
        subSound, zoneMap = Packs:FindPlaceByName(place)
        if subSound then
            subzone = place
        end
    end
    if not mapID and not zoneMap then
        return nil
    end
    if not zoneMap or (subzone and not subSound) then
        local key = "z:" .. PlaceKey(zoneMap or mapID, subzone)
        if not missingLogged[key] then
            missingLogged[key] = true
            Collector:Missing(key)
        end
    end
    return zoneSound, subSound, zoneMap, subzone
end

local function LoreTokens(sound)
    local parts = {}
    for _, cue in ipairs(sound.subtitles or {}) do
        parts[#parts + 1] = cue[2]
    end
    return Text.Tokens(table.concat(parts, " "))
end

--- Одна подзона бывает записана под двумя картами (Руины Лордерона — в Тирисфале и в Подгороде,
--- реки и моря — у каждой прибрежной зоны). На границе карт игра сообщает о «новом» месте, и тот же
--- рассказ звучал второй раз подряд. Двойники слушаются один раз на всех.
---@return table places { [ключ места] = true } — сама подзона и её двойники
function Zones:Twins(sound, mapID, subzone)
    local key = PlaceKey(mapID, subzone)
    if twinCache[key] then
        return twinCache[key]
    end
    local places, mine = { [key] = true }, LoreTokens(sound)
    for _, found in ipairs(Packs:SubzoneEverywhere(subzone)) do
        local other = PlaceKey(found.mapID, subzone)
        if not places[other] and (found.sound.path == sound.path
                or Text.Similarity(mine, LoreTokens(found.sound)) >= TWIN_SIMILARITY) then
            places[other] = true
        end
    end
    twinCache[key] = places
    return places
end

--- opts: places — ключи места и его двойников; batch — метка лора, добавленного вместе; zoneLevel — лор
--- зоны (для журнала; очередь с 2026-09-30 лор не вытесняет — звучат все места по порядку). Место
--- считается прочитанным, когда лор действительно зазвучал: снятый «Стопом» прозвучит при следующем посещении.
function Zones:Play(sound, key, force, opts)
    opts = opts or {}
    local places = opts.places or { [key] = true }
    local mode = ns.db.zoneMode
    if not force then
        if mode == "never" then
            return false
        end
        for place in pairs(places) do
            if (mode == "once" and ns.charDB.zones[place])
                or (recent[place] and GetTime() - recent[place] < REPEAT_COOLDOWN) then
                return false
            end
        end
        for _, queued in ipairs(Queue.items) do
            if queued.places and queued.places[key] then
                return false -- тот же рассказ уже звучит или ждёт в очереди (под другой картой)
            end
        end
    end
    local item = {
        sound = sound, zone = key, places = places, batch = opts.batch, zoneLevel = opts.zoneLevel,
        name = sound.name, title = "Рассказчик", portrait = {},
    }
    item.onStart = function()
        local now = GetTime()
        for place in pairs(places) do
            ns.charDB.zones[place] = true
            recent[place] = now
        end
    end
    return Queue:Add(item)
end

--- Прочитать лор места, где стоит игрок. withZone — и самой зоны (игрок вошёл в новую зону).
function Zones:Check(withZone, force)
    if not ns.db or not ns.db.enabled then
        return
    end
    local zoneSound, subSound, zoneMap, subzone = self:Current()
    if zoneMap and ns.Diary then
        ns.Diary:Visit(zoneMap, subzone) -- атлас дневника: место открыто, даже если лор не звучит
    end
    if ns.db.zoneMode == "never" and not force then
        return
    end
    if not force then
        if (UnitOnTaxi and UnitOnTaxi("player")) then
            return -- в полёте места мелькают одно за другим
        end
        if inCinematic or (InCombatLockdown and InCombatLockdown()) then
            pending = (withZone or pending == "zone") and "zone" or "sub"
            return
        end
    end
    if not zoneMap then
        return
    end
    local batch = {}
    if withZone and zoneSound then
        self:Play(zoneSound, PlaceKey(zoneMap), force, { batch = batch, zoneLevel = true })
    end
    if subSound and (ns.db.zoneSubzones or force) then
        self:Play(subSound, PlaceKey(zoneMap, subzone), force,
            { batch = batch, places = self:Twins(subSound, zoneMap, subzone) })
    end
end

function Zones:RunPending()
    if pending and not inCinematic and not (InCombatLockdown and InCombatLockdown()) then
        local withZone = pending == "zone"
        pending = nil
        self:Check(withZone)
    end
end

function Zones:PLAYER_ENTERING_WORLD(isInitialLogin, isReloadingUi)
    if isReloadingUi then
        return
    end
    -- Новый персонаж сначала смотрит ролик своей расы: проверяем чуть позже, ролик отложит чтение.
    pending = "zone"
    C_Timer.After(LOGIN_DELAY, function() self:RunPending() end)
end

function Zones:ZONE_CHANGED_NEW_AREA() self:Check(true) end
function Zones:ZONE_CHANGED() self:Check(false) end
function Zones:ZONE_CHANGED_INDOORS() self:Check(false) end
function Zones:PLAYER_REGEN_ENABLED() self:RunPending() end

function Zones:CINEMATIC_START() inCinematic = true end
function Zones:PLAY_MOVIE() inCinematic = true end
function Zones:CINEMATIC_STOP()
    inCinematic = false
    C_Timer.After(1, function() self:RunPending() end)
end
Zones.STOP_MOVIE = Zones.CINEMATIC_STOP

function Zones:Init()
    for _, event in ipairs(EVENTS) do
        self:RegisterEvent(event)
    end
    self:SetScript("OnEvent", function(frame, event, ...)
        local handler = frame[event]
        ns.Util.Trace("ev", event)
        if handler then
            local ok, err = pcall(handler, frame, ...)
            if not ok then
                geterrorhandler()(err)
            end
        end
    end)
end

--- Для /wf reset zones.
function Zones:Forget()
    wipe(ns.charDB.zones)
    wipe(recent)
end
