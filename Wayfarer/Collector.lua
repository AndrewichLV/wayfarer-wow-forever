local _, ns = ...
local Util, Text = ns.Util, ns.Text

-- Сборщик текстов. Для 1000+ новых квестов Forever нет открытой базы текстов, поэтому
-- аддон сам записывает всё, что показывает клиент, в SavedVariables (Wayfarer_Collected).
-- Пайплайн (pipeline: vru ingest) превращает эти записи в сценарий для озвучки.
-- Данные остаются на вашем компьютере; делиться ими или нет — решаете вы.
local Collector = {}
ns.Collector = Collector

local FORMAT = 1

function Collector:Init()
    Wayfarer_Collected = Wayfarer_Collected or {}
    local db = Wayfarer_Collected
    if db.format ~= FORMAT then
        wipe(db)
        db.format = FORMAT
    end
    db.chars = db.chars or {}
    db.npcs = db.npcs or {}
    db.quests = db.quests or {}
    db.gossip = db.gossip or {}
    db.missing = db.missing or {}
    db.books = db.books or {}   -- страницы книг и табличек без озвучки: [название|страница] = { title, page, text, ... }
    db.stale = db.stale or {}

    local version, build = GetBuildInfo()
    db.client = version .. "." .. build
    db.locale = GetLocale()
    self.db = db
end

function Collector:Enabled()
    return self.db ~= nil and ns.db.collect
end

-- Контекст персонажа: пайплайн по нему заменяет имя/класс/расу обратно на $N/$C/$R.
function Collector:CharKey()
    local name = UnitName("player")
    local realm = GetNormalizedRealmName() or GetRealmName() or ""
    local key = name .. "-" .. realm
    local c = self.db.chars[key] or {}
    self.db.chars[key] = c
    local race, raceFile = UnitRace("player")
    local class, classFile = UnitClass("player")
    c.name = name
    c.sex = UnitSex("player")
    c.race, c.raceFile = race, raceFile
    c.class, c.classFile = class, classFile
    if LOCALIZED_CLASS_NAMES_MALE and classFile then
        c.classM = LOCALIZED_CLASS_NAMES_MALE[classFile]
        c.classF = LOCALIZED_CLASS_NAMES_FEMALE and LOCALIZED_CLASS_NAMES_FEMALE[classFile]
    end
    return key
end

local function MapPosition()
    local mapID = Util.Try(C_Map.GetBestMapForUnit, "player")
    if not mapID then
        return nil
    end
    local pos = Util.Try(C_Map.GetPlayerMapPosition, mapID, "player")
    if pos then
        local x, y = Util.Try(pos.GetXY, pos)
        if x and y then
            return mapID, math.floor(x * 1000 + 0.5) / 10, math.floor(y * 1000 + 0.5) / 10
        end
    end
    return mapID
end

function Collector:Npc(target)
    if not target or not target.key then
        return
    end
    local n = self.db.npcs[target.key] or {}
    self.db.npcs[target.key] = n
    n.name = target.name or n.name
    if target.sex then
        n.sex = target.sex
    end
    if target.display then
        n.display = target.display
    end
    local mapID, x, y = MapPosition()
    if mapID then
        n.map, n.x, n.y = mapID, x, y
    end
end

local function TargetKey(target)
    if not target then
        return nil
    end
    if target.key then
        return target.key
    end
    if target.kind == "P" then
        return "P"
    end
    if target.name then
        return "N:" .. target.name
    end
end

--- Текст окна квеста. event: "a" (описание), "p" (прогресс), "c" (награда).
function Collector:Quest(event, questID, title, text, objectives, target)
    if not self:Enabled() or not questID or questID == 0 or type(text) ~= "string" or text == "" then
        return
    end
    local q = self.db.quests[questID] or {}
    self.db.quests[questID] = q
    q.title = title or q.title
    q[event] = q[event] or {}

    local sex = Util.PlayerSexKey()
    local rec = q[event][sex]
    if rec and rec.text == text then
        rec.n = (rec.n or 1) + 1
    else
        q[event][sex] = {
            text = text,
            obj = objectives ~= "" and objectives or nil,
            npc = TargetKey(target),
            char = self:CharKey(),
            t = time(),
            n = 1,
        }
    end
    self:Npc(target)
end

--- Реплика NPC (GOSSIP_SHOW) или приветствие квестодателя (QUEST_GREETING).
function Collector:Gossip(kind, target, text)
    if not self:Enabled() or type(text) ~= "string" or text == "" then
        return
    end
    local npcKey = TargetKey(target) or "?"
    local list = self.db.gossip[npcKey] or {}
    self.db.gossip[npcKey] = list

    local fp = table.concat(Text.Fingerprint(text), " ")
    local rec = list[fp] or { kind = kind }
    list[fp] = rec
    local sex = Util.PlayerSexKey()
    if rec[sex] ~= text then
        rec[sex] = text
        rec["char" .. sex] = self:CharKey()
    end
    rec.n = (rec.n or 0) + 1
    rec.t = time()
    self:Npc(target)
end

--- Страница книги, письма или таблички без озвучки (Books.lua): текст — для озвучки в следующей версии.
function Collector:Book(title, page, text)
    if not self:Enabled() or type(text) ~= "string" or text == "" then
        return
    end
    local key = (title or "?") .. "|" .. tostring(page or 1)
    local rec = self.db.books[key] or {}
    self.db.books[key] = rec
    if rec.text ~= text then
        rec.title, rec.page, rec.text = title, page, text
        rec.char = self:CharKey()
    end
    rec.n = (rec.n or 0) + 1
    rec.t = time()
    rec.map = Util.Try(C_Map.GetBestMapForUnit, "player")
end

--- Встретили текст, для которого нет озвучки: список приоритетов для генерации.
function Collector:Missing(key)
    if self:Enabled() then
        self.db.missing[key] = (self.db.missing[key] or 0) + 1
    end
end

--- Текст квеста в игре разошёлся с озвученным: озвучку надо перегенерировать.
function Collector:Stale(key, score)
    if self:Enabled() then
        self.db.stale[key] = math.floor(score * 100 + 0.5) / 100
    end
end

function Collector:Stats()
    local function count(t)
        local n = 0
        for _ in pairs(t) do
            n = n + 1
        end
        return n
    end
    local db = self.db
    local gossipTexts = 0
    for _, list in pairs(db.gossip) do
        gossipTexts = gossipTexts + count(list)
    end
    return {
        quests = count(db.quests),
        npcs = count(db.npcs),
        gossip = gossipTexts,
        missing = count(db.missing),
        stale = count(db.stale),
    }
end
