local _, ns = ...
local Util, Packs, Queue = ns.Util, ns.Packs, ns.Queue

-- Кнопки на карте мира (M): «Послушать» лор зоны, которая сейчас открыта на карте, и подзоны,
-- в которой стоит игрок. Пока лор звучит, кнопка превращается в «Стоп».
-- Кнопка ▶ у мини-карты (просьба пользователя 2026-10-07: «чтобы карту не открывать»): слева от значка
-- отслеживания (бинокль) у названия места над мини-картой (MinimapCluster.Tracking / BorderTop, интерфейс
-- Mainline: Blizzard_Minimap\Mainline\Minimap.xml). Клик — лор места, где стоит игрок (подзона, иначе зона),
-- правый клик — лор всей зоны, повторный клик — остановить. Нет лора — кнопка блёклая. Настройка zoneButton.
local ZoneMap = {}
ns.ZoneMap = ZoneMap

local MEDIA = "Interface\\AddOns\\Wayfarer\\Media\\Player\\"

local function IsPlaying(key)
    local current = Queue:Current()
    return current ~= nil and current.zone == key
end

local function MakeButton(parent)
    local b = Util.ChildFrame("Button", parent, "UIPanelButtonTemplate")
    b:SetSize(220, 22)
    b:SetScript("OnClick", function(button)
        if not button.sound then
            return
        end
        if IsPlaying(button.key) then
            Queue:Clear()
        else
            ns.Zones:Play(button.sound, button.key, true)
        end
        ZoneMap:Refresh()
    end)
    b:Hide()
    return b
end

function ZoneMap:Attach()
    local map = WorldMapFrame
    if self.zoneButton or not map then
        return
    end
    local canvas = map.ScrollContainer or map
    self.zoneButton = MakeButton(canvas)
    self.zoneButton:SetPoint("TOPLEFT", canvas, "TOPLEFT", 10, -10)
    self.subButton = MakeButton(canvas)
    self.subButton:SetPoint("TOPLEFT", self.zoneButton, "BOTTOMLEFT", 0, -4)
    for _, b in ipairs({ self.zoneButton, self.subButton }) do
        if b.SetFrameLevel and canvas.GetFrameLevel then
            b:SetFrameLevel((canvas:GetFrameLevel() or 0) + 20)
        end
    end
    if map.HookScript then
        map:HookScript("OnShow", function() self:Refresh() end)
    end
    if map.OnMapChanged then
        hooksecurefunc(map, "OnMapChanged", function() self:Refresh() end)
    end
    self:Refresh()
end

local function SetButton(button, sound, key, label)
    if not sound then
        button:Hide()
        return
    end
    button.sound, button.key = sound, key
    button:SetText((IsPlaying(key) and "Стоп: " or "Послушать: ") .. label)
    button:Show()
end

-- Мини-карта ----------------------------------------------------------------------------------------

--- Лор места, где стоит игрок: here — подзона (если её лор есть), иначе зона; zone — сама зона.
local function HereTargets()
    local zoneSound, subSound, zoneMap, subzone = ns.Zones:Current()
    if not zoneMap then
        return nil, nil
    end
    local zone = zoneSound and { sound = zoneSound, key = tostring(zoneMap), name = zoneSound.name, zoneLevel = true }
    local here = subSound and {
        sound = subSound, key = zoneMap .. ":" .. subzone, name = subSound.name or subzone,
        places = ns.Zones:Twins(subSound, zoneMap, subzone),
    }
    return here or zone, zone
end

local function LorePlaying(target)
    local current = Queue:Current()
    return target ~= nil and current ~= nil and current.zone ~= nil
        and (current.zone == target.key or (current.places ~= nil and current.places[target.key] == true))
end

--- Клик по кнопке у мини-карты: лор места (wholeZone — всей зоны); звучит он сейчас — остановить.
function ZoneMap:PlayHere(wholeZone)
    local here, zone = HereTargets()
    local target = wholeZone and zone or here
    if not target then
        Util.Print("для этого места рассказа в пакетах пока нет.")
    elseif LorePlaying(target) then
        Queue:Skip()
    else
        ns.Zones:Play(target.sound, target.key, true, { places = target.places, zoneLevel = target.zoneLevel })
    end
    self:Refresh()
end

local function MiniTooltip(button)
    if not GameTooltip then
        return
    end
    local here, zone = HereTargets()
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    GameTooltip:SetText("Рассказчик")
    if here then
        GameTooltip:AddLine((LorePlaying(here) and "Остановить: " or "Послушать: ") .. (here.name or ""), 1, 1, 1, true)
        if zone and zone ~= here then
            GameTooltip:AddLine("Правый клик — о всей зоне: " .. (zone.name or ""), 0.8, 0.8, 0.8, true)
        end
    else
        GameTooltip:AddLine("Об этом месте рассказа пока нет.", 1, 1, 1, true)
    end
    GameTooltip:AddLine("Wayfarer", 0.55, 0.55, 0.55)
    GameTooltip:Show()
end

function ZoneMap:AttachMinimap()
    local cluster = MinimapCluster
    if self.miniButton or not cluster then
        return
    end
    local b = Util.ChildFrame("Button", cluster, nil, "WayfarerMinimapLore")
    b:SetSize(16, 16)
    if b.SetFrameLevel and cluster.GetFrameLevel then
        b:SetFrameLevel((cluster:GetFrameLevel() or 0) + 10)
    end
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetHighlightTexture(MEDIA .. "btn-hl", "ADD")
    b:SetScript("OnClick", function(_, mouse) ZoneMap:PlayHere(mouse == "RightButton") end)
    b:SetScript("OnEnter", MiniTooltip)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    self.miniButton = b
    -- Место сменилось — кнопка блёклая или яркая (Zones обновляет её и сам, через очередь — не всегда).
    local watcher = CreateFrame("Frame")
    for _, event in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do
        watcher:RegisterEvent(event)
    end
    watcher:SetScript("OnEvent", function() ZoneMap:Refresh() end)
    self:Refresh()
end

function ZoneMap:RefreshMinimap()
    local b = self.miniButton
    if not b then
        return
    end
    if not (ns.db and ns.db.enabled and ns.db.zoneButton ~= false) then
        b:Hide()
        return
    end
    -- Слева от бинокля отслеживания; его нет (скрыт) — слева от полосы с названием места.
    local cluster = MinimapCluster
    local tracking, border = rawget(cluster, "Tracking"), rawget(cluster, "BorderTop")
    local anchor = (tracking and tracking:IsShown() and tracking) or border
    if anchor ~= b.anchor then
        b.anchor = anchor
        b:ClearAllPoints()
        if anchor then
            b:SetPoint("RIGHT", anchor, "LEFT", -3, 0)
        else
            b:SetPoint("TOPLEFT", cluster, "TOPLEFT", 4, -4)
        end
    end
    local here = HereTargets()
    b.available = here ~= nil
    b.playing = LorePlaying(here)
    b:SetNormalTexture(MEDIA .. (b.playing and "btn-stop" or "btn-play"))
    local tex = b.GetNormalTexture and b:GetNormalTexture()
    if tex and tex.SetDesaturated then
        tex:SetDesaturated(not b.available)
    end
    b:SetAlpha(b.available and 1 or 0.45)
    b:Show()
end

function ZoneMap:Refresh()
    self:RefreshMinimap()
    local zb, sb = self.zoneButton, self.subButton
    if not zb or not ns.db or not WorldMapFrame then
        return
    end
    if not WorldMapFrame:IsShown() or not ns.db.enabled then
        zb:Hide()
        sb:Hide()
        return
    end
    local shownMap = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
    local zoneSound, _, zoneMap = Packs:FindZone(shownMap, nil)
    SetButton(zb, zoneSound, zoneMap and tostring(zoneMap), zoneSound and zoneSound.name or "")

    -- Подзона — только если на карте открыта та зона, где стоит игрок.
    local _, subSound, playerZone, subzone = ns.Zones:Current()
    if playerZone and playerZone == zoneMap and subSound then
        SetButton(sb, subSound, playerZone .. ":" .. subzone, subSound.name or subzone)
    else
        sb:Hide()
    end
end

-- Кнопка Wayfarer на кольце мини-карты (просьба пользователя 2026-10-10: «управлять через команды неудобно») ------
-- Микрофон Wayfarer в золотом кольце, как кнопки других аддонов у края мини-карты; перетаскивается по кругу
-- (угол — ns.db.ringAngle). Клик — меню Blizzard_Menu: плеер, лор места, дневник, настройки и разделы модулей
-- (Ring:AddSection — так путевые истории Wayfarer_Radio кладут туда своё управление). Настройка ringButton.
local Ring = { sections = {} }
ns.Ring = Ring

local ICON = "Interface\\AddOns\\Wayfarer\\Media\\Icon"
local RING_PAD = 10 -- центр кнопки — на столько пикселей снаружи от края мини-карты

--- Раздел меню от модуля: build(root) добавляет пункты (root:CreateTitle / CreateButton / CreateCheckbox /
--- CreateRadio; у пункта — вложенное меню через его же Create*). order — место среди разделов (меньше — выше).
function Ring:AddSection(key, order, build)
    for i, section in ipairs(self.sections) do
        if section.key == key then
            table.remove(self.sections, i)
            break
        end
    end
    self.sections[#self.sections + 1] = { key = key, order = order or 50, build = build }
    table.sort(self.sections, function(a, b) return a.order < b.order end)
end

--- Настройка из меню — так же, как из панели (Settings знает новое значение и зовёт свои обработчики).
function Ring.SetOption(key, value)
    ns.db[key] = value
    if Settings and Settings.SetValue then
        pcall(Settings.SetValue, "WAYFARER_" .. key, value)
    end
end

local function Place(button)
    local minimap = Minimap
    local angle = math.rad(tonumber(ns.db.ringAngle) or ns.DEFAULTS.ringAngle)
    local x, y = math.cos(angle), math.sin(angle)
    local w = (minimap:GetWidth() or 140) / 2 + RING_PAD
    local h = (minimap:GetHeight() or 140) / 2 + RING_PAD
    local shape = GetMinimapShape and Util.Try(GetMinimapShape) or "ROUND"
    if shape ~= "ROUND" then
        -- Квадратная мини-карта: по описанной окружности, прижато к сторонам квадрата.
        x = math.max(-w, math.min(w, x * w * 1.4142))
        y = math.max(-h, math.min(h, y * h * 1.4142))
    else
        x, y = x * w, y * h
    end
    button:ClearAllPoints()
    button:SetPoint("CENTER", minimap, "CENTER", x, y)
end

local function Drag(button)
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale() or 1
    if not (mx and px) then
        return
    end
    px, py = px / scale, py / scale
    ns.db.ringAngle = math.floor(math.deg(math.atan2(py - my, px - mx)) % 360 + 0.5)
    Place(button)
end

local function RingTooltip(button)
    if not GameTooltip or button.dragging then
        return
    end
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    GameTooltip:SetText("Wayfarer")
    local current = Queue:Current()
    if current then
        GameTooltip:AddLine((Queue.paused and "Пауза: " or "Звучит: ") .. (current.name or current.title or ""),
            1, 1, 1, true)
    end
    if rawget(ns, "Journal") then
        GameTooltip:AddLine(rawget(ns, "Radio") and "Клик — дневник путника: путевые истории и атлас мест."
            or "Клик — дневник путника: атлас мест.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Правый клик — быстрое меню: пауза, дальше, стоп, эфир, настройки.", 0.8, 0.8, 0.8, true)
    else
        GameTooltip:AddLine("Клик — меню: плеер, рассказ о месте, путевые истории, настройки.", 0.8, 0.8, 0.8, true)
    end
    GameTooltip:AddLine("Перетащить — сдвинуть по краю мини-карты.", 0.55, 0.55, 0.55, true)
    GameTooltip:Show()
end

function Ring:Create()
    if self.button or not Minimap then
        return
    end
    local b = Util.ChildFrame("Button", Minimap, nil, "WayfarerMinimapButton")
    b:SetSize(31, 31)
    pcall(b.SetFrameStrata, b, "MEDIUM")
    pcall(b.SetFrameLevel, b, 8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    -- Разметка — как у кнопок других аддонов (LibDBIcon): подложка, значок и кольцо слежения клиента.
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetPoint("TOPLEFT", 7, -5)
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", 6, -5)
    icon:SetTexture(ICON)
    icon:SetTexCoord(0.1, 0.9, 0.06, 0.86) -- микрофон без бронзовой рамки иконки
    local mask = b.CreateMaskTexture and b:CreateMaskTexture()
    if mask and icon.AddMaskTexture then
        mask:SetAllPoints(icon)
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE",
            "CLAMPTOBLACKADDITIVE")
        icon:AddMaskTexture(mask)
    end
    b.icon = icon
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")

    -- Левый клик — окно (дневник, вкладка «Истории»: просьба пользователя 2026-10-10 «окно, а не меню»), правый —
    -- быстрое меню. Без дневника (выпуск для игроков) — меню на любой клик.
    b:SetScript("OnClick", function(button, mouse)
        if mouse ~= "RightButton" and rawget(ns, "Journal") then
            Ring:OpenWindow()
        else
            Ring:OpenMenu(button)
        end
    end)
    b:SetScript("OnEnter", RingTooltip)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    b:SetScript("OnDragStart", function(button)
        button.dragging = true
        if GameTooltip then
            GameTooltip:Hide()
        end
        button:LockHighlight()
        button:SetScript("OnUpdate", Drag)
    end)
    b:SetScript("OnDragStop", function(button)
        button.dragging = nil
        button:SetScript("OnUpdate", nil)
        button:UnlockHighlight()
    end)
    self.button = b
    -- Размер мини-карты меняется в «Режиме редактирования» — кнопка остаётся на кольце.
    pcall(Minimap.HookScript, Minimap, "OnSizeChanged", function() Ring:Refresh() end)
    self:Refresh()
end

function Ring:Refresh()
    local b = self.button
    if not b then
        return
    end
    if not (ns.db and ns.db.ringButton ~= false) then
        b:Hide()
        return
    end
    Place(b)
    b.icon:SetDesaturated(not ns.db.enabled)
    b:Show()
end

--- Окно Wayfarer: дневник; первый раз — на вкладке «Истории» (если стоит модуль путевых историй), потом — где был.
function Ring:OpenWindow()
    local journal = ns.Journal
    local frame = rawget(journal, "frame")
    if frame and frame:IsShown() then
        frame:Hide()
        return
    end
    journal:Show(rawget(journal, "tab") or (rawget(ns, "Radio") and "stories") or nil)
end

function Ring:OpenMenu(owner)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        Util.Print("меню недоступно — команды: /wf help.")
        return
    end
    if GameTooltip then
        GameTooltip:Hide()
    end
    MenuUtil.CreateContextMenu(owner, function(_, root) Ring:Build(root) end)
end

--- Содержимое меню: собирается заново при каждом открытии — показывает то, что звучит сейчас.
function Ring:Build(root)
    root:CreateTitle("Wayfarer")
    local current = Queue:Current()
    if current then
        root:CreateButton(Queue.paused and "Играть" or "Пауза", function() Queue:TogglePause() end)
        root:CreateButton("Дальше", function() Queue:Skip() end)
        root:CreateButton("Стоп", function() Queue:Clear() end)
    elseif Queue.last then
        root:CreateButton("Повторить последнее", function() Queue:Replay() end)
    end
    local here, zone = HereTargets()
    local place = root:CreateButton(here and ("Рассказ о месте: " .. (here.name or "")) or "Рассказ о месте",
        function() ZoneMap:PlayHere(false) end)
    if not here then
        place:SetEnabled(false)
    end
    if zone and zone ~= here then
        root:CreateButton("Рассказ о зоне: " .. (zone.name or ""), function() ZoneMap:PlayHere(true) end)
    end
    for _, section in ipairs(self.sections) do
        root:CreateDivider()
        local ok, err = pcall(section.build, root)
        if not ok then
            Util.Trace("menu", section.key .. ": " .. tostring(err))
        end
    end
    root:CreateDivider()
    if ns.Journal then
        root:CreateButton("Дневник путника", function() ns.Journal:Toggle() end)
    end
    root:CreateCheckbox("Озвучка включена", function() return ns.db.enabled end, function()
        Ring.SetOption("enabled", not ns.db.enabled)
        if not ns.db.enabled then
            Queue:Clear()
        end
        Ring:Refresh()
    end)
    root:CreateButton("Настройки…", function() ns.Options:Open() end)
end

function ZoneMap:Init()
    Util.Try(function() self:AttachMinimap() end)
    Util.Try(function() Ring:Create() end)
    if WorldMapFrame then
        self:Attach()
        return
    end
    -- Карта мира может загрузиться позже (Blizzard_WorldMap по требованию).
    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("ADDON_LOADED")
    watcher:SetScript("OnEvent", function(frame, _, name)
        if name == "Blizzard_WorldMap" and WorldMapFrame then
            frame:UnregisterEvent("ADDON_LOADED")
            Util.Try(function() self:Attach() end)
        end
    end)
end
