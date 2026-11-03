local ADDON_NAME, ns = ...

-- The button on the minimap ring that opens and closes the button bag (the collector fills the
-- bag). Drag it round the minimap's edge; its angle is saved in ns.db.buttonBag.angle.
--   ns.BagButton:IsOpen()          whether the bag is open (not saved: it starts closed)
--   ns.BagButton:SetOpen(open)     opens or closes it and fires the BagToggled(open) callback
--   ns.BagButton.OnRightClick      set by the ignore menu, called on a right click

-- The icon is the first of these the client has. Keep the list in step with the ATLAS probe in
-- addons/ForeverDev/Probes.lua, and put the one that looks right first once launch shows which.
local ICON_ATLASES = { "uitools-icon-hamburger", "common-icon-hamburger", "friends-icon-menu", "OptionsIcon-Brown" }

-- Pixels the button's center sits outside the minimap's edge.
local RING_MARGIN = 5

---@class ForeverMapBagButtonMixin : Button
---@field Icon Texture
---@field open boolean
---@field angle number
---@field OnRightClick fun()?
ForeverMapBagButtonMixin = {}

local function ChooseIcon(icon)
	for _, atlas in ipairs(ICON_ATLASES) do
		if C_Texture.GetAtlasInfo(atlas) then
			ns.dev:LogOnce("icon", "BAG", "icon", atlas)
			icon:SetAtlas(atlas)
			icon:Show()
			return
		end
	end
	ns.dev:LogOnce("icon", "BAG", "icon", "none of the atlases exist")
	icon:Hide()
end

function ForeverMapBagButtonMixin:IsOpen()
	return self.open
end

function ForeverMapBagButtonMixin:SetOpen(open)
	open = open and true or false
	if self.open == open then
		return
	end
	self.open = open
	ns.callbacks:TriggerEvent("BagToggled", open)
end

-- Puts the button on the ring at `angle` degrees (Logic/Ring.lua).
function ForeverMapBagButtonMixin:SetAngle(angle)
	self.angle = angle
	local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
	self:ClearAllPoints()
	self:SetPoint("CENTER", Minimap, "CENTER", ns.Ring.Offset(angle, Minimap:GetWidth() / 2 + RING_MARGIN, shape))
end

-- The cursor's angle round the minimap's center. GetCursorPosition is in unscaled screen pixels.
local function CursorAngle()
	local scale = Minimap:GetEffectiveScale()
	local cursorX, cursorY = GetCursorPosition()
	local centerX, centerY = Minimap:GetCenter()
	return ns.Ring.AngleTo(cursorX / scale - centerX, cursorY / scale - centerY)
end

local function FollowCursor(self)
	self:SetAngle(CursorAngle())
end

function ForeverMapBagButtonMixin:OnDragStart()
	GameTooltip:Hide()
	self:SetScript("OnUpdate", FollowCursor)
end

function ForeverMapBagButtonMixin:OnDragStop()
	self:SetScript("OnUpdate", nil)
	ns.db.buttonBag.angle = self.angle
end

function ForeverMapBagButtonMixin:OnClick(mouseButton)
	if mouseButton == "RightButton" then
		if self.OnRightClick then
			self:OnRightClick()
		end
	else
		self:SetOpen(not self.open)
	end
end

function ForeverMapBagButtonMixin:OnEnter()
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip_SetTitle(GameTooltip, ADDON_NAME)
	GameTooltip:AddLine(ns.L.BAG_TOOLTIP_TOGGLE, 1, 1, 1)
	GameTooltip:AddLine(ns.L.BAG_TOOLTIP_KEEP, 1, 1, 1)
	GameTooltip:Show()
end

function ForeverMapBagButtonMixin:OnLeave()
	GameTooltip:Hide()
end

-- Shown only while the setting is on; turning it off closes the bag.
function ForeverMapBagButtonMixin:Refresh()
	local show = ns.Options.Get("showButtonBag")
	if not show then
		self:SetOpen(false)
	end
	self:SetShown(show)
end

ns.OnInitialize(function()
	local button = CreateFrame("Button", nil, Minimap, "ForeverMapBagButtonTemplate")
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(Minimap:GetFrameLevel() + 10)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	button.open = false
	ChooseIcon(button.Icon)
	button:SetAngle(ns.db.buttonBag.angle or ns.Ring.DEFAULT_ANGLE)
	button:Refresh()
	ns.BagButton = button
	ns.callbacks:RegisterCallback("OptionChanged", button.Refresh, button)
end)
