local ADDON_NAME, ns = ...

local L = ns.L

-- World map button that shows or hides known nodes on the map, the same option as
-- "Show on World Map" in the options panel. It behaves like Blizzard's map pin button
-- (WorldMapTrackingPinButtonMixin).
---@class ForeverProfessionsWorldMapToggleMixin : Button
---@field Icon Texture
---@field IconOverlay Texture
---@field ActiveTexture Texture
ForeverProfessionsWorldMapToggleMixin = {}

function ForeverProfessionsWorldMapToggleMixin:OnLoad()
	ns.callbacks:RegisterCallback("OptionChanged", self.Refresh, self)
	self:Refresh()
end

-- Also called by the world map for every overlay frame when the map changes.
function ForeverProfessionsWorldMapToggleMixin:Refresh()
	self.ActiveTexture:SetShown(ns.Options.Get("showWorldMap"))
end

function ForeverProfessionsWorldMapToggleMixin:OnMouseDown()
	self.Icon:SetPoint("TOPLEFT", 8, -8)
	self.IconOverlay:Show()
end

function ForeverProfessionsWorldMapToggleMixin:OnMouseUp()
	self.Icon:SetPoint("TOPLEFT", 7, -6)
	self.IconOverlay:Hide()
end

function ForeverProfessionsWorldMapToggleMixin:OnClick()
	ns.Options.Toggle("showWorldMap")
	if ns.Options.Get("showWorldMap") then
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	else
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
	end
	self:OnEnter()
end

function ForeverProfessionsWorldMapToggleMixin:OnEnter()
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip_SetTitle(GameTooltip, L.KNOWN_NODES)
	GameTooltip_AddNormalLine(GameTooltip, L.SHOW_ON_WORLD_MAP_TOOLTIP)
	GameTooltip_AddBlankLineToTooltip(GameTooltip)
	GameTooltip_AddInstructionLine(GameTooltip, ns.Options.Get("showWorldMap") and L.CLICK_TO_HIDE or L.CLICK_TO_SHOW)
	GameTooltip:Show()
end

ns.OnInitialize(function()
	EventUtil.ContinueOnAddOnLoaded("Blizzard_WorldMap", function()
		local button = WorldMapFrame:AddOverlayFrame("ForeverProfessionsWorldMapToggleTemplate", "BUTTON")
		-- Forever puts the map pin button in the canvas's top-left corner
		-- (Blizzard_WorldMap/Camelot/Blizzard_WorldMap.lua, AdjustOverlayFrames).
		local pinButton = WorldMapFrame.WorldMapTrackingPinButton
		if pinButton then
			button:SetPoint("LEFT", pinButton, "RIGHT", 0, 0)
		else
			button:SetPoint("TOPLEFT", WorldMapFrame:GetCanvasContainer(), "TOPLEFT", 3, 0)
		end
	end)
end)
