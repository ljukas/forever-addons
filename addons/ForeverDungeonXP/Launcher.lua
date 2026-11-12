local _, ns = ...

-- The ways to open the journal: a button on the minimap's edge, the entry in Blizzard's addon
-- compartment (the TOC's AddonCompartmentFunc) and /fdxp.
--
-- The minimap button is built here rather than with LibDBIcon: that library and the two it needs
-- are published as SVN repositories, and scripts/libs.sh fetches git only. It uses the art every
-- minimap button has (MiniMap-TrackingBorder, UI-Minimap-Background, the zoom button's
-- highlight) at LibDBIcon's size, so it looks and sorts like the others, and ForeverMinimap's
-- button bag picks it up as a minimap child.

local L = ns.L

local ICON = "Interface\\Icons\\INV_Misc_Book_09"
local BUTTON_NAME = "ForeverDungeonXPMinimapButton"
local DEFAULT_ANGLE = 200 -- degrees, counter-clockwise from the minimap's right edge
local EDGE_OFFSET = 5 -- how far outside the minimap's edge the button's centre sits

local button

-- The button's offset from the minimap's centre for an angle in degrees, on a round minimap of
-- the given radius.
--   0, 70 -> 75, 0        90, 70 -> 0, 75        180, 70 -> -75, 0
local function EdgePosition(angle, radius)
	local distance = radius + EDGE_OFFSET
	return math.cos(math.rad(angle)) * distance, math.sin(math.rad(angle)) * distance
end

local function Place()
	local x, y = EdgePosition(ns.DB.Minimap().angle or DEFAULT_ANGLE, Minimap:GetWidth() / 2)
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- While dragged, the button follows the cursor around the minimap's edge.
local function OnDragUpdate()
	local centerX, centerY = Minimap:GetCenter()
	local scale = Minimap:GetEffectiveScale()
	local cursorX, cursorY = GetCursorPosition()
	ns.DB.Minimap().angle = math.deg(math.atan2(cursorY / scale - centerY, cursorX / scale - centerX)) % 360
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

	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(50, 50)
	border:SetPoint("TOPLEFT")

	button:SetScript("OnClick", ns.Journal.Toggle)
	button:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", OnDragUpdate)
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
	Place()
end

ns.OnInitialize(function()
	CreateButton()
	ns.log("UI", "minimap button", ns.DB.Minimap().angle or DEFAULT_ANGLE)
end)

function ForeverDungeonXP_OnAddonCompartmentClick()
	ns.Journal.Toggle()
end

SLASH_FOREVERDUNGEONXP1 = "/fdxp"
SlashCmdList.FOREVERDUNGEONXP = function()
	ns.Journal.Toggle()
end
