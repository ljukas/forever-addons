local ADDON_NAME, ns = ...

-- A button on the minimap's edge that opens the RazzhUI options page. Drag it round the edge; the
-- "Show minimap button" checkbox on that page (Options.lua) hides it. Its angle and whether it is
-- hidden are kept in RazzhUIDB.minimap (Database.lua). ns.log tag: MINIMAP.
--   ns.MinimapButton.IsShown()         whether the button is set to show (true before the settings load)
--   ns.MinimapButton.SetShown(shown)   shows or hides it and remembers that
--
-- It is a plain frame, not LibDBIcon's: that library and the two it needs are published as SVN
-- repositories, which scripts/libs.sh can't fetch. It is drawn like every other addon's minimap
-- button: the minimap's dark round background, the gold tracking-button ring and the zoom buttons'
-- highlight, at LibDBIcon's size. Forever's own minimap buttons use the Camelot ui-hud-minimap-*
-- art, which has no plain round button.
--
-- The frame has a global name because that is how addons that gather minimap buttons into one
-- place recognize a button. Such an addon reparents the button; while its parent isn't Minimap the
-- button is that addon's to place, so placing and dragging do nothing here.

local L = ns.L

local BUTTON_NAME = "RazzhUIMinimapButton"
local EDGE_OFFSET = 5 -- how far outside the minimap's edge the button's centre sits

ns.MinimapButton = {}

local button
-- What RazzhUIDB.minimap says, read once the settings have loaded and written back on a change.
local angle = ns.Edge.DEFAULT_ANGLE
local shown = true
local dragging = false
-- From a drag's end until the next frame: the mouse-up that ends a drag must not also click.
local dragged = false

-- Whether a saved angle can be used: a hand-edited file may hold anything.
local function IsAngle(value)
	return type(value) == "number" and value == value and math.abs(value) ~= math.huge
end

local function OnMinimap()
	local parent = button:GetParent()
	return not issecretvalue(parent) and parent == Minimap
end

local function Place()
	if not button or not OnMinimap() then
		return
	end
	local width = Minimap:GetWidth()
	if issecretvalue(width) then
		return
	end
	local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
	local x, y = ns.Edge.Offset(angle, width / 2 + EDGE_OFFSET, shape)
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- Ends a drag and saves where it ended. A no-op when no drag is running.
local function StopDrag()
	if not dragging then
		return
	end
	dragging = false
	button:SetScript("OnUpdate", nil)
	local saved = ns.DB.Minimap()
	if saved then
		saved.angle = angle
	end
	ns.log("MINIMAP", "angle", angle)
end

-- While dragged, the button follows the cursor round the minimap's edge.
local function OnDragUpdate()
	-- Taken off the minimap mid-drag: the drag is over.
	if not OnMinimap() then
		StopDrag()
		return
	end
	local centerX, centerY = Minimap:GetCenter()
	local scale = Minimap:GetEffectiveScale()
	-- Secrecy first: a secret value can't even be tested for nil.
	if issecretvalue(centerX) or issecretvalue(centerY) or issecretvalue(scale) or not centerX then
		return
	end
	-- GetCursorPosition is in unscaled screen pixels.
	local cursorX, cursorY = GetCursorPosition()
	angle = ns.Edge.AngleTo(cursorX / scale - centerX, cursorY / scale - centerY)
	Place()
end

local function OnEnter(self)
	if dragging then
		return
	end
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip_SetTitle(GameTooltip, L.TITLE_COLORED)
	GameTooltip_AddInstructionLine(GameTooltip, L.MINIMAP_TOOLTIP_CLICK)
	if OnMinimap() then
		GameTooltip_AddInstructionLine(GameTooltip, L.MINIMAP_TOOLTIP_DRAG)
	end
	GameTooltip:Show()
end

local function CreateButton()
	button = CreateFrame("Button", BUTTON_NAME, Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:RegisterForClicks("LeftButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")

	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	background:SetSize(24, 24)
	background:SetPoint("CENTER")

	-- The TOC's icon, which the Addon Compartment entry shows too.
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(C_AddOns.GetAddOnMetadata(ADDON_NAME, "IconTexture"))
	icon:SetSize(18, 18)
	icon:SetPoint("CENTER")
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	-- The ring texture's circle fills its top-left, so at 50 pixels anchored TOPLEFT it centres
	-- on the 31-pixel button.
	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(50, 50)
	border:SetPoint("TOPLEFT")

	-- OpenOptions decides what happens in combat (a red error line instead of the page).
	button:SetScript("OnClick", function()
		if dragged then
			dragged = false
			return
		end
		ns.log("MINIMAP", "click")
		RazzhUI.OpenOptions()
	end)
	button:SetScript("OnDragStart", function(self)
		if OnMinimap() then
			GameTooltip:Hide()
			dragging = true
			self:SetScript("OnUpdate", OnDragUpdate)
		end
	end)
	button:SetScript("OnDragStop", function()
		if not dragging then
			return
		end
		StopDrag()
		dragged = true
		-- Cleared next frame in case no click follows.
		C_Timer.After(0, function()
			dragged = false
		end)
	end)
	-- Hidden mid-drag (the checkbox, a UI hide): don't keep following the cursor.
	button:SetScript("OnHide", StopDrag)
	button:SetScript("OnEnter", OnEnter)
	button:SetScript("OnLeave", GameTooltip_Hide)

	-- The minimap can be resized after this addon loads (by another addon or Edit Mode).
	Minimap:HookScript("OnSizeChanged", Place)
	Place()
	button:SetShown(shown)
end

function ns.MinimapButton.IsShown()
	return shown
end

function ns.MinimapButton.SetShown(value)
	shown = value and true or false
	local saved = ns.DB.Minimap()
	if saved then
		saved.hide = not shown or nil
	end
	if button then
		button:SetShown(shown)
	end
	ns.log("MINIMAP", "shown", shown)
end

ns.OnInitialize(function()
	local saved = ns.DB.Minimap()
	if saved then
		if IsAngle(saved.angle) then
			angle = saved.angle % 360
		end
		shown = saved.hide ~= true
	end
	CreateButton()
	ns.log("MINIMAP", "created", angle, shown)
end)
