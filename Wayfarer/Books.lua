local _, ns = ...
local Util = ns.Util

-- Книги, письма, таблички и надписи (окно ItemTextFrame, события ITEM_TEXT_*): страницу читает рассказчик
-- (просьба пользователя 2026-10-04, по образцу CatQuest). У страницы в API нет ID — звук ищем по названию книги
-- (ItemTextGetItem) и тексту страницы (Packs:FindBook: похожесть слов, номер страницы — подсказка).
-- Перелистнул — звучит новая страница, прежняя снимается. Страницы без озвучки сборщик пишет в
-- Wayfarer_Collected.books (vru ingest): так в озвучку попадут и книги, которых нет в базах, — новые книги Forever.
local Books = CreateFrame("Frame")
ns.Books = Books

local Event = ns.Event
local openItem

local function Trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Текст страницы без HTML-оформления книги (<HTML><BODY><H1>…</H1><P>…</P><BR/>): для окна плеера и поиска.
function Books.PlainText(text)
    if type(text) ~= "string" then
        return ""
    end
    text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
    local head = text:sub(1, 64):lower()
    if head:find("<html") or head:find("<body") then
        -- Переносы в исходнике HTML — форматирование; строки задают только теги.
        text = text:gsub("\n", " ")
        text = text:gsub("<%s*/%s*[PpHh]%d?%s*>", "\n"):gsub("<%s*[Bb][Rr][^>]*>", "\n")
        text = text:gsub("<%s*/?%s*%a+%d?[^>]*>", "")
        text = text:gsub("[ \t]*\n[ \t]*", "\n"):gsub("\n\n\n+", "\n\n")
    end
    return Trim(text)
end

local function Enabled()
    return ns.db.enabled and ns.db.playBooks ~= false
end

function Books:Show()
    local raw = ItemTextGetText and Util.Try(ItemTextGetText)
    if type(raw) ~= "string" or raw == "" then
        return
    end
    local title = ItemTextGetItem and Util.Try(ItemTextGetItem) or nil
    local page = ItemTextGetPage and Util.Try(ItemTextGetPage) or 1
    local text = Books.PlainText(raw)
    local sound = ns.Packs:FindBook(title, page, text)
    if not sound then
        ns.Collector:Book(title, page, text)
        ns.Collector:Missing("b:" .. (title or "?") .. "|" .. tostring(page))
        Util.Debug("нет озвучки страницы: %s, стр. %s", title or "?", tostring(page))
    end
    if not Enabled() then
        return
    end
    local current = ns.Queue:Current()
    if sound and current and current.sound.path == sound.path then
        return -- та же страница: событие пришло ещё раз
    end
    -- Перелистнули или открыли другую книгу: прежняя страница больше не нужна.
    ns.Queue:RemoveWhere(function(item) return item.event == Event.Book end)
    openItem = nil
    if not sound then
        return
    end
    local item = {
        sound = sound,
        event = Event.Book,
        title = title,
        name = title or "Рассказчик",
        text = text,
        delay = 0.2,
    }
    if ns.Queue:Add(item) then
        openItem = item
    end
end

function Books:Closed()
    if ns.db.stopOnClose and openItem then
        local item = openItem
        ns.Queue:RemoveWhere(function(queued) return queued == item end)
    end
    openItem = nil
end

Books:RegisterEvent("ITEM_TEXT_READY")
Books:RegisterEvent("ITEM_TEXT_CLOSED")
Books:SetScript("OnEvent", function(self, event)
    if not ns.db then
        return
    end
    local ok, err = pcall(event == "ITEM_TEXT_READY" and self.Show or self.Closed, self)
    if not ok then
        Util.Debug("книги: %s", tostring(err))
    end
end)
