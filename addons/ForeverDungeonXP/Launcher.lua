local _, ns = ...

-- The ways to open the journal: a button on the minimap's edge, the entry in Blizzard's addon
-- compartment (the TOC's AddonCompartmentFunc) and /fdxp.
--
-- The minimap button is built here rather than with LibDBIcon: that library and the two it needs
-- are published as SVN repositories, and scripts/libs.sh fetches git only. It is drawn like
-- every other addon's minimap button (and ForeverMinimap's bag button, UI/BagButton.xml): the
-- minimap's dark round background, the gold tracking-button ring and the zoom buttons'
-- highlight, at LibDBIcon's size. Forever's own minimap buttons use the Camelot
-- ui-hud-minimap-* art, which has no plain round button.

local L = ns.L

local ICON = "Interface\\Icons\\INV_Misc_Book_09"
local BUTTON_NAME = "ForeverDungeonXPMinimapButton"
local EDGE_OFFSET = 5 -- how far outside the minimap's edge the button's centre sits

local button

-- Another addon (ForeverMinimap's button bag, for one) may have taken the button off the
-- minimap. It is then that addon's to place, and dragging it would fight that.
local function OnMinimap()
	return button:GetParent() == Minimap
end

local function Place()
	if not OnMinimap() then
		return
	end
	local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
	local angle = ns.DB.Minimap().angle or ns.Edge.DEFAULT_ANGLE
	local x, y = ns.Edge.Offset(angle, Minimap:GetWidth() / 2 + EDGE_OFFSET, shape)
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- While dragged, the button follows the cursor around the minimap's edge.
local function OnDragUpdate()
	local centerX, centerY = Minimap:GetCenter()
	if not centerX or issecretvalue(centerX) or issecretvalue(centerY) then
		return
	end
	local scale = Minimap:GetEffectiveScale()
	local cursorX, cursorY = GetCursorPosition()
	ns.DB.Minimap().angle = ns.Edge.AngleTo(cursorX / scale - centerX, cursorY / scale - centerY)
	Place()
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

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(ICON)
	icon:SetSize(18, 18)
	icon:SetPoint("CENTER")
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	-- The ring texture's circle fills its top-left, so at 50 pixels anchored TOPLEFT it centres
	-- on the 31-pixel button.
	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(50, 50)
	border:SetPoint("TOPLEFT")

	button:SetScript("OnClick", ns.Journal.Toggle)
	button:SetScript("OnDragStart", function(self)
		if OnMinimap() then
			GameTooltip:Hide()
			self:SetScript("OnUpdate", OnDragUpdate)
		end
	end)
	button:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
	end)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText(L.TITLE)
		GameTooltip:AddLine(L.TOOLTIP_HINT, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, true)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)

	-- The minimap can be resized after this addon loads (by ForeverMinimap or Edit Mode).
	Minimap:HookScript("OnSizeChanged", Place)
	Place()
end

ns.OnInitialize(function()
	CreateButton()
	if ns.dev.enabled then
		ns.log("UI", "minimap button", ns.DB.Minimap().angle or ns.Edge.DEFAULT_ANGLE)
	end
end)

function ForeverDungeonXP_OnAddonCompartmentClick()
	ns.Journal.Toggle()
end

SLASH_FOREVERDUNGEONXP1 = "/fdxp"
SlashCmdList.FOREVERDUNGEONXP = function()
	ns.Journal.Toggle()
end
