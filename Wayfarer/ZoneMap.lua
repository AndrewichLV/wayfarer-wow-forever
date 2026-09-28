local _, ns = ...
local Util, Packs, Queue = ns.Util, ns.Packs, ns.Queue

-- Кнопки на карте мира (M): «Послушать» лор зоны, которая сейчас открыта на карте, и подзоны,
-- в которой стоит игрок. Пока лор звучит, кнопка превращается в «Стоп».
local ZoneMap = {}
ns.ZoneMap = ZoneMap

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

function ZoneMap:Refresh()
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
