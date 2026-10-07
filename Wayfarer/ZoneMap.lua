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
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
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
    local b = CreateFrame("Button", "WayfarerMinimapLore", cluster)
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

function ZoneMap:Init()
    Util.Try(function() self:AttachMinimap() end)
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
