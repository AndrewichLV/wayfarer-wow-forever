-- Wayfarer: путеводитель по Азероту — русская озвучка квестов и лора мест для World of Warcraft: Forever.
-- Ядро не содержит звуков: их поставляют модули (Wayfarer_Voices и будущие), которые
-- регистрируются через Wayfarer.RegisterPack (см. docs/PACK_FORMAT.md).
local ADDON_NAME, ns = ...

Wayfarer = ns

ns.ADDON_NAME = ADDON_NAME
ns.VERSION = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "dev"

-- Версия формата пакетов озвучки. Меняется только при несовместимых изменениях.
ns.PACK_FORMAT = 1

-- Коды событий. Для квестов совпадают с именами файлов в пакетах: q\<questID>-<код>.ogg
ns.Event = {
    QuestAccept = "a",   -- QUEST_DETAIL: описание квеста
    QuestProgress = "p", -- QUEST_PROGRESS: «Ну как, принёс?»
    QuestComplete = "c", -- QUEST_COMPLETE: текст награды
    Gossip = "g",        -- GOSSIP_SHOW / QUEST_GREETING: реплика NPC
}
