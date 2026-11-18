local ADDON_NAME, ns = ...

-- The player's power as numbers on the power bar, the way the bar's Edit Mode dialog says
-- (EditMode.lua's Numbers dropdown, kept per layout as "text"): off, while the mouse is over the
-- bar, always as value, always as percent, or both. Laid out like the text on Blizzard's
-- player-frame bar (PlayerFrame.xml: one line in the middle, or one at each end).
--
-- Power values are secret: they go from the API through AbbreviateLargeNumbers and
-- SetFormattedText, which take them as they are, and are never compared, joined or logged. So
-- there is no zero text and no hiding at an empty maximum, as Blizzard's bar has.
ns.PowerText = {}

-- The values of "text", in the dropdown's order.
ns.PowerText.MODES = { "none", "hover", "value", "percent", "both" }

local holder = ns.PowerBar.holder

-- Above the fill, below the border.
local frame = CreateFrame("Frame", nil, holder)
frame:SetAllPoints()
frame:SetFrameLevel(holder:GetFrameLevel() + 3)

local function CreateText(point, x)
	local text = frame:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
	text:SetPoint(point, x, 0)
	return text
end

local centre, left, right = CreateText("CENTER", 0), CreateText("LEFT", 2), CreateText("RIGHT", -2)

local mode = ns.PowerBar.DEFAULTS.text

-- Whether the mouse is over the bar; only followed in "hover".
local hovering = false

local function Clear()
	centre:SetText("")
	left:SetText("")
	right:SetText("")
end

local function SetPercent(text, powerType)
	text:SetFormattedText("%.0f%%", UnitPowerPercent("player", powerType, false, CurveConstants.ScaleTo100))
end

-- Writes the numbers for the power the bar shows. Runs after every update of the bar
-- (ns.PowerBar.OnChanged); powerType is nil until the client knows the player's power.
local function Update(powerType, powerToken)
	if mode == "none" or not powerType or (mode == "hover" and not hovering) then
		return
	end
	if mode == "percent" then
		SetPercent(centre, powerType)
	elseif mode == "both" then
		-- Blizzard's bar shows the percentage beside the value for mana only; rage and energy run
		-- 0-100, where it would repeat the value.
		if powerToken == "MANA" then
			SetPercent(left, powerType)
		else
			left:SetText("")
		end
		right:SetFormattedText("%s", AbbreviateLargeNumbers(UnitPower("player", powerType)))
	else
		centre:SetFormattedText(
			"%s / %s",
			AbbreviateLargeNumbers(UnitPower("player", powerType)),
			AbbreviateLargeNumbers(UnitPowerMax("player", powerType))
		)
	end
end

local function Refresh()
	Clear()
	Update(UnitPowerType("player"))
end

ns.PowerBar.OnChanged(Update)

holder:SetScript("OnEnter", function()
	hovering = true
	Refresh()
end)
holder:SetScript("OnLeave", function()
	hovering = false
	Clear()
end)

-- Shows the numbers the way mode says (one of MODES). The bar takes the mouse's motion only in
-- "hover", and never its clicks, which go through to the world.
function ns.PowerText.SetMode(newMode)
	mode = newMode
	holder:SetMouseClickEnabled(false)
	holder:SetMouseMotionEnabled(mode == "hover")
	hovering = mode == "hover" and holder:IsMouseOver()
	Refresh()
	ns.log("POWER", "text", mode)
end
