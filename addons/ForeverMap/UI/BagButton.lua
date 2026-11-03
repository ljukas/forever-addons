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
---@field dragging boolean? while a drag is moving it
---@field dragged boolean? from a drag's end until the click that may follow it
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
	self.dragging = true
	self:SetScript("OnUpdate", FollowCursor)
end

-- Ends a drag and saves where it ended. A no-op when no drag is running.
function ForeverMapBagButtonMixin:EndDrag()
	if not self.dragging then
		return
	end
	self.dragging = false
	self:SetScript("OnUpdate", nil)
	ns.db.buttonBag.angle = self.angle
end

function ForeverMapBagButtonMixin:OnDragStop()
	self:EndDrag()
	-- The mouse-up that ends a drag may also click: OnClick skips that one click. The flag is
	-- cleared next frame in case no click follows.
	self.dragged = true
	C_Timer.After(0, function()
		self.dragged = false
	end)
end

-- Hidden mid-drag or mid-press (the bag turned off, a UI hide): stop following the cursor, and
-- don't wait for a mouse-up that won't come.
function ForeverMapBagButtonMixin:OnHide()
	self:EndDrag()
	self:OnMouseUp()
end

-- The minimap's shape may have changed while hidden.
function ForeverMapBagButtonMixin:OnShow()
	if self.angle then
		self:SetAngle(self.angle)
	end
end

-- The icon sinks 1px down-right while the button is held, as Blizzard's buttons do.
function ForeverMapBagButtonMixin:OnMouseDown()
	self.Icon:SetPoint("CENTER", 1, -1)
end

function ForeverMapBagButtonMixin:OnMouseUp()
	self.Icon:SetPoint("CENTER", 0, 0)
end

function ForeverMapBagButtonMixin:OnClick(mouseButton)
	if self.dragged then
		self.dragged = false
		return
	end
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
	-- A hand-edited angle that isn't a number falls back to the default spot.
	local angle = ns.db.buttonBag.angle
	if type(angle) ~= "number" then
		angle = ns.Ring.DEFAULT_ANGLE
	end
	button:SetAngle(angle % 360)
	button:Refresh()
	ns.BagButton = button
	ns.callbacks:RegisterCallback("OptionChanged", button.Refresh, button)
	-- A resized minimap moves its ring.
	Minimap:HookScript("OnSizeChanged", function()
		button:SetAngle(button.angle)
	end)
end)
