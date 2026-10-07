local _, ns = ...
local Util, Text = ns.Util, ns.Text

-- Реестр пакетов озвучки и поиск звука под текущий текст.
-- Формат пакета описан в docs/PACK_FORMAT.md; генерирует его pipeline/vru/build.py.
local Packs = {
    list = {},   -- пакеты по убыванию приоритета
    byName = {},
}
ns.Packs = Packs

-- Минимальная похожесть реплики NPC на ключ из пакета. Ниже — считаем, что озвучки нет:
-- лучше промолчать, чем прочитать чужой текст.
local GOSSIP_MIN_SCORE = 0.6
-- Если текст квеста в игре заметно отличается от озвученного — помечаем как устаревший.
local QUEST_STALE_SCORE = 0.5

--- Вызывается из Index.lua каждого пакета.
function ns.RegisterPack(pack)
    if type(pack) ~= "table" or type(pack.name) ~= "string" then
        Util.Print("пакет без имени пропущен")
        return nil
    end
    if pack.format ~= ns.PACK_FORMAT then
        Util.Print("пакет %s: формат %s, нужен %d — пропущен. Обновите аддон и пакет до одной версии.",
            pack.name, tostring(pack.format), ns.PACK_FORMAT)
        return nil
    end
    if Packs.byName[pack.name] then
        return Packs.byName[pack.name]
    end

    pack.root = "Interface\\AddOns\\" .. pack.name .. "\\"
    pack.priority = pack.priority or 0
    pack.model = pack.model or "v3" -- модель голосов: v3 — основа, остальные — по настройке voiceModel
    pack.ext = pack.ext or "ogg"
    pack.q = pack.q or {}     -- [questID] = { a = entry, p = entry, c = entry }
    pack.g = pack.g or {}     -- [npcID] = { entry, ... } реплики существ
    pack.o = pack.o or {}     -- [objectID] = { entry, ... } тексты объектов
    pack.gn = pack.gn or {}   -- [имя] = { entry, ... } запасной поиск, когда ID скрыт
    pack.qg = pack.qg or {}   -- [questID] = npcID квестодателя (для общих квестов и предметов)
    pack.npc = pack.npc or {} -- [npcID] = { n = имя, d = displayID } для портрета
    pack.z = pack.z or {}     -- [uiMapID] = { h, d, t, n, s = { [название подзоны] = { h, d, t, n } } }
    pack.b = pack.b or {}     -- [название книги] = { { h = страница, p = номер, k, d, t }, ... } книги и таблички

    Packs.byName[pack.name] = pack
    table.insert(Packs.list, pack)
    table.sort(Packs.list, function(x, y)
        if x.priority ~= y.priority then
            return x.priority > y.priority
        end
        return x.name < y.name
    end)
    return pack
end

function Packs:Count()
    return #self.list
end

-- С 0.6.0 озвучка раздаётся четырьмя паками (на CurseForge — отдельными проектами «Wayfarer Voices - …»):
-- один архив больше 1 ГБ сайт не принимает. Прежний единый модуль Wayfarer_Voices содержит всё сразу.
Packs.FULL = "Wayfarer_Voices"
Packs.SPLIT = {
    { name = "Wayfarer_Voices_Alliance", title = "Альянс", project = "Wayfarer Voices - Alliance", faction = "Alliance" },
    { name = "Wayfarer_Voices_Horde", title = "Орда", project = "Wayfarer Voices - Horde", faction = "Horde" },
    { name = "Wayfarer_Voices_Shared", title = "Общие квесты", project = "Wayfarer Voices - Shared Quests" },
    { name = "Wayfarer_Voices_Narrator", title = "Рассказчик", project = "Wayfarer Voices - Narrator" },
}

--- Состояние пака по списку модификаций: нет в папке AddOns или выключен.
local function AddOnState(name)
    if not (C_AddOns and C_AddOns.GetAddOnInfo) then
        return "не установлен"
    end
    local _, _, _, _, reason = C_AddOns.GetAddOnInfo(name)
    if reason == "DISABLED" then
        return "выключен в списке модификаций"
    elseif reason and reason ~= "MISSING" then
        return "не загрузился: " .. tostring(reason)
    end
    return "не установлен"
end

--- Каких паков не хватает игроку этой фракции: свой фракционный, общие квесты, рассказчик.
--- Пак чужой фракции не нужен; с прежним единым модулем не нужен ни один.
function Packs:Missing(faction)
    local missing = {}
    if self.byName[self.FULL] then
        return missing
    end
    for _, info in ipairs(self.SPLIT) do
        if not self.byName[info.name] and (not info.faction or info.faction == faction) then
            missing[#missing + 1] = { info = info, state = AddOnState(info.name) }
        end
    end
    return missing
end

--- Прежний единый модуль рядом с новыми паками: реплики продублированы (звучит одна, но папка лишняя).
function Packs:HasLegacyAndSplit()
    if not self.byName[self.FULL] then
        return false
    end
    for _, info in ipairs(self.SPLIT) do
        if self.byName[info.name] then
            return true
        end
    end
    return false
end

--- Пакеты для поиска звука: сначала выбранной в настройках версии голосов, потом остальные — где
--- реплики нужной версии нет (или её модуль не установлен), звучит другая, а не тишина.
function Packs:Active()
    local wanted = ns.db and ns.db.voiceModel or "v4"
    local active, rest = {}, {}
    for _, pack in ipairs(self.list) do
        table.insert(pack.model == wanted and active or rest, pack)
    end
    for _, pack in ipairs(rest) do
        table.insert(active, pack)
    end
    return active
end

-- Превращает запись пакета в описание звука с учётом пола игрока.
-- Запись: { d = длительность } или { m = длит., f = длит. } для вариантов по полу;
-- s = ID говорящего NPC, v = голос (для отладки), k = ключ текста, t/tm/tf = субтитры,
-- h = имя файла реплики NPC (g\<h>.ogg).
local function Resolve(pack, entry, relPath)
    local suffix, duration, subtitles = "", entry.d, entry.t
    if entry.m or entry.f then
        local sex = Util.PlayerSexKey()
        if not entry[sex] then
            sex = entry.m and "m" or "f"
        end
        suffix = "-" .. sex
        duration = entry[sex]
        subtitles = entry["t" .. sex]
    end
    return {
        path = pack.root .. relPath .. suffix .. "." .. pack.ext,
        uid = relPath:gsub("\\", "/") .. suffix, -- ID реплики в пайплайне (q/783-a-m): для репортов
        duration = duration,
        subtitles = subtitles,
        speaker = entry.s,
        voice = entry.v,
        pack = pack,
    }
end

---@param event string ns.Event.QuestAccept | QuestProgress | QuestComplete
---@param text string|nil текст из окна квеста — для проверки, что озвучка не устарела
function Packs:FindQuest(questID, event, text)
    for _, pack in ipairs(self:Active()) do
        local quest = pack.q[questID]
        local entry = quest and quest[event]
        if entry then
            local sound = Resolve(pack, entry, "q\\" .. questID .. "-" .. event)
            if entry.k and text then
                sound.score = Text.Similarity(Text.KeyTokens(entry.k), Text.Fingerprint(text))
                sound.stale = sound.score < QUEST_STALE_SCORE
            end
            return sound
        end
    end
end

--- Ищет реплику NPC: сначала по ID существа/объекта, если ID скрыт — по имени.
---@param target table|nil результат Identity.Current()
function Packs:FindGossip(target, text)
    if not target then
        return nil
    end
    local tokens = Text.Tokens(text)
    if #tokens == 0 then
        return nil
    end

    local best, bestScore, bestPack = nil, 0, nil
    for _, pack in ipairs(self:Active()) do
        local list
        if target.id then
            list = (target.kind == "O" and pack.o or pack.g)[target.id]
        elseif target.name then
            list = pack.gn[target.name]
        end
        if list then
            for _, entry in ipairs(list) do
                local score = Text.Similarity(Text.KeyTokens(entry.k), tokens)
                -- Строго больше: при равенстве выигрывает пакет с большим приоритетом.
                if score > bestScore then
                    best, bestScore, bestPack = entry, score, pack
                end
            end
        end
    end

    if best and bestScore >= GOSSIP_MIN_SCORE then
        local sound = Resolve(bestPack, best, "g\\" .. best.h)
        sound.score = bestScore
        return sound
    end
end

--- Страница книги, письма, таблички: по названию (предмет или объект) и тексту; номер страницы — подсказка
--- при равной похожести. Не нашлось под этим названием (Forever переименовал предмет) — по всем книгам.
---@param title string|nil ItemTextGetItem()
---@param page number|nil ItemTextGetPage()
---@param text string текст страницы без HTML (Books.PlainText)
function Packs:FindBook(title, page, text)
    local tokens = Text.Tokens(text)
    if #tokens == 0 then
        return nil
    end
    local best, bestScore, bestPack = nil, 0, nil
    local function Consider(pack, entry)
        local score = Text.Similarity(Text.KeyTokens(entry.k), tokens)
        if score > bestScore or (score == bestScore and best and entry.p == page and best.p ~= page) then
            best, bestScore, bestPack = entry, score, pack
        end
    end
    for _, pack in ipairs(self:Active()) do
        for _, entry in ipairs(title and pack.b[title] or {}) do
            Consider(pack, entry)
        end
    end
    if bestScore < GOSSIP_MIN_SCORE then
        for _, pack in ipairs(self:Active()) do
            for _, entries in pairs(pack.b) do
                for _, entry in ipairs(entries) do
                    Consider(pack, entry)
                end
            end
        end
    end
    if best and bestScore >= GOSSIP_MIN_SCORE then
        local sound = Resolve(bestPack, best, "b\\" .. best.h)
        sound.score = bestScore
        return sound
    end
end

local function ZoneSound(pack, entry)
    local sound = Resolve(pack, entry, "z\\" .. entry.h)
    sound.name = entry.n
    return sound
end

local UIMAP_ZONE = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3

--- Лор места: зона — по uiMapID игрока или ближайшей родительской карте, у которой он есть
--- (пещера, отдельная карта деревни), но не выше зоны: лор материка сам не читается.
--- Подзона — по названию, которое показывает клиент (GetSubZoneText).
---@return table|nil zoneSound, table|nil subzoneSound, number|nil zoneMapID
function Packs:FindZone(mapID, subzone)
    for _ = 1, 10 do
        if not mapID then
            return nil
        end
        local info = C_Map.GetMapInfo and Util.Try(C_Map.GetMapInfo, mapID)
        if info and info.mapType and info.mapType < UIMAP_ZONE then
            return nil
        end
        local zoneSound, subSound, found
        for _, pack in ipairs(self:Active()) do
            local zone = pack.z[mapID]
            if zone then
                found = true
                if not zoneSound and zone.h then
                    zoneSound = ZoneSound(pack, zone)
                end
                local sub = subzone and zone.s and zone.s[subzone]
                if not subSound and sub then
                    subSound = ZoneSound(pack, sub)
                end
            end
        end
        if found then
            return zoneSound, subSound, mapID
        end
        mapID = info and info.parentMapID
    end
end

--- Звук записи лора (зоны или подзоны) — для дневника, который перебирает все места модуля.
function Packs:ZoneEntrySound(pack, entry)
    return entry and entry.h and ZoneSound(pack, entry) or nil
end

--- Лор места по его названию в клиенте — для мест без своей карты мира (Подземный поезд — отдельная
--- карта-инстанс, а лор у него записан подзоной Штормграда и Стальгорна; подземелья).
---@return table|nil sound, number|nil zoneMapID
function Packs:FindPlaceByName(name)
    if not name or name == "" then
        return nil
    end
    for _, pack in ipairs(self:Active()) do
        for mapID, zone in pairs(pack.z) do
            local sub = zone.s and zone.s[name]
            if sub then
                return ZoneSound(pack, sub), mapID
            end
        end
    end
end

--- Все записи подзоны с этим названием на всех картах — для поиска двойников лора (Zones:Twins).
---@return table list of { mapID, sound }
function Packs:SubzoneEverywhere(name)
    local out = {}
    for _, pack in ipairs(self:Active()) do
        for mapID, zone in pairs(pack.z) do
            local sub = zone.s and zone.s[name]
            if sub then
                out[#out + 1] = { mapID = mapID, sound = ZoneSound(pack, sub) }
            end
        end
    end
    return out
end

--- Квестодатель из данных пакетов (когда квест пришёл от игрока или из предмета).
function Packs:QuestGiver(questID)
    for _, pack in ipairs(self.list) do
        local npcID = pack.qg[questID]
        if npcID then
            return npcID
        end
    end
end

--- { n = имя, d = displayID } для портрета, если NPC уже не рядом.
function Packs:NpcInfo(npcID)
    if not npcID then
        return nil
    end
    for _, pack in ipairs(self.list) do
        local info = pack.npc[npcID]
        if info then
            return info
        end
    end
end
