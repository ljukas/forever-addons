local ADDON_NAME, ns = ...

-- A druid's other powers: a row above the detached power bar with a thin bar for each of mana,
-- energy and rage that the current form doesn't use. Rage gets a bar once the druid knows a bear
-- form and energy once they know cat form: no bar before either, one bar across the row with one
-- of them, two side by side with both. Each wears the cast bar's border, overlapping the power bar's by a
-- line, over the power bar's background (ns.PowerBar.SetHeadroom), so they read as one frame
-- (docs/superpowers/specs/2026-11-12-foreverunitframes-off-form-power-design.md).
--
-- Display only. Power values are secret: they go from UnitPower straight into the status bars and
-- are never compared, logged or calculated with.
ns.OffFormPower = {}

local _, class = UnitClass("player")
-- False for every other class: no row, no events, and EditMode.lua adds no settings for it.
ns.OffFormPower.available = class == "DRUID"

if not ns.OffFormPower.available then
	function ns.OffFormPower.SetLayout() end
	return
end

local Mana, Energy, Rage = Enum.PowerType.Mana, Enum.PowerType.Energy, Enum.PowerType.Rage

-- Left to right; the current form's power is left out.
local ORDER = { Mana, Energy, Rage }

-- The power each form's spell brings. Bear Form and Dire Bear Form are the IDs Blizzard names in
-- Blizzard_ActionBar/Shared/SpellFlyout.lua; Cat Form is Vanilla's.
local FORM_POWER = {
	[5487] = Rage,
	[9634] = Rage,
	[768] = Energy,
}

-- Blizzard's player-frame bar art per power: UnitFrameManaBar_UpdateType builds these names from
-- PowerBarColor's atlasElementName (Blizzard_UnitFrame/Mainline/PowerBarColorUtil.lua).
local ATLAS = {
	[Mana] = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana",
	[Energy] = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Energy",
	[Rage] = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Rage",
}

-- For the devlog.
local NAME = { [Mana] = "mana", [Energy] = "energy", [Rage] = "rage" }

-- How far the cast bar's border reaches past the bar it frames (CastingBarFrame.xml), which is how
-- thick its line draws. Neighbouring bars sit this far apart and their borders overlap by it, so
-- they share one line.
local LINE = 2

-- The powers to show, left to right: those of ORDER the druid has (known[powerType]) other than
-- the one the current form uses. Returns up to two; either may be nil.
local function OtherPowers(current, known)
	local left, right
	for _, powerType in ipairs(ORDER) do
		if powerType ~= current and known[powerType] then
			if not left then
				left = powerType
			elseif not right then
				right = powerType
			end
		end
	end
	return left, right
end

-- Which powers the druid has: mana, and the power of every form on the stance bar.
local function KnownPowers()
	local known = { [Mana] = true }
	for index = 1, GetNumShapeshiftForms() do
		local _, _, _, spellID = GetShapeshiftFormInfo(index)
		local powerType = spellID and FORM_POWER[spellID]
		if powerType then
			known[powerType] = true
		end
		if ns.dev.enabled then
			ns.dev:LogOnce("offform-form-" .. index .. "-" .. tostring(spellID), "OFFFORM", "form", index, spellID)
		end
	end
	return known
end

local holder = ns.PowerBar.holder
local border = ns.PowerBar.border

-- A child of the border's frame, so it hides with the power bar's backdrop.
local row = CreateFrame("Frame", nil, border)
row:SetPoint("BOTTOMLEFT", holder, "TOPLEFT", 0, LINE)
row:SetPoint("BOTTOMRIGHT", holder, "TOPRIGHT", 0, LINE)
row:Hide()

local function CreateBar()
	local bar = CreateFrame("StatusBar", nil, row)
	-- Under the border, level with the main bar's fill.
	bar:SetFrameLevel(holder:GetFrameLevel() + 1)
	return bar
end

-- The left bar takes the whole row when it is the only one. Two bars meet at the row's centre,
-- under the line their borders share. The other ends are placed by SetBars.
local leftBar, rightBar = CreateBar(), CreateBar()
rightBar:SetPoint("TOPLEFT", row, "TOP")

-- Each bar wears the cast bar's border, like the main bar, drawn with it on the border's frame. The
-- borders overlap the main bar's and each other's by a line, so the lot reads as one frame with
-- thin lines between its bars, and no border is stretched far from the height it was drawn for.
local function CreateCell()
	local cell = border:CreateTexture(nil, "OVERLAY")
	cell:SetAtlas("ui-castingbar-frame")
	return cell
end

local leftCell, rightCell = CreateCell(), CreateCell()
leftCell:SetPoint("TOPLEFT", row, "TOPLEFT", -LINE, LINE)
rightCell:SetPoint("TOPLEFT", row, "TOP", -LINE / 2, LINE)
rightCell:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", LINE, -LINE)

-- Lays the row out for this many bars (0, 1 or 2) at this height, and fits the frame around it.
local function SetBars(count, height)
	row:SetShown(count > 0)
	leftCell:SetShown(count > 0)
	rightBar:SetShown(count > 1)
	rightCell:SetShown(count > 1)
	if count == 0 then
		ns.PowerBar.SetHeadroom(0)
		return
	end
	row:SetHeight(height)
	ns.PowerBar.SetHeadroom(height + LINE)
	-- The fills reach past the row under the border's ends, as far as the main bar's fill does:
	-- their art starts and stops short.
	local left, right = ns.PowerBar.barOutset.left, ns.PowerBar.fillOutset.right
	leftBar:SetPoint("TOPLEFT", row, "TOPLEFT", -left, 0)
	rightBar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", right, 0)
	if count > 1 then
		leftBar:SetPoint("BOTTOMRIGHT", row, "BOTTOM")
		leftCell:SetPoint("BOTTOMRIGHT", row, "BOTTOM", LINE / 2, -LINE)
	else
		leftBar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", right, 0)
		leftCell:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", LINE, -LINE)
	end
end
SetBars(0)

-- Fills a bar from its power. The values are secret and only pass through.
local function UpdateBar(bar, interpolation)
	if not bar.powerType then
		return
	end
	bar:SetMinMaxValues(0, UnitPowerMax("player", bar.powerType))
	bar:SetValue(UnitPower("player", bar.powerType), interpolation)
end

local function UpdateValues()
	local interpolation = ns.PowerBar.Interpolation()
	UpdateBar(leftBar, interpolation)
	UpdateBar(rightBar, interpolation)
end

-- Gives a bar its power, or none. A bar that changes power jumps to the new one's value rather
-- than sliding there from the old one's.
local function SetPower(bar, powerType)
	if bar.powerType == powerType then
		return
	end
	bar.powerType = powerType
	if powerType then
		bar:SetStatusBarTexture(ATLAS[powerType])
		UpdateBar(bar, Enum.StatusBarInterpolation.Immediate)
		bar:SetToTargetValue()
	end
end

-- The settings (SetLayout).
local enabled, rowHeight = false, 0

-- Picks the bars' powers from the forms the druid knows and the one they are in, and lays the row
-- out for them. Everything touched is ours and unprotected, so this is safe in combat.
local function Refresh()
	if not enabled then
		SetPower(leftBar, nil)
		SetPower(rightBar, nil)
		SetBars(0)
		return
	end
	local current = UnitPowerType("player")
	local left, right = OtherPowers(current, KnownPowers())
	SetPower(leftBar, left)
	SetPower(rightBar, right)
	SetBars((left and 1 or 0) + (right and 1 or 0), rowHeight)
	if ns.dev.enabled then
		local key = tostring(left) .. "/" .. tostring(right)
		ns.dev:LogChanged("offform", key, "OFFFORM", "powers", current, NAME[left], NAME[right])
	end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, _, powerToken)
	if event == "UNIT_POWER_FREQUENT" or event == "UNIT_MAXPOWER" then
		-- Which powers the game sends updates for, in each form.
		if ns.dev.enabled then
			local key = event .. tostring(powerToken) .. tostring(UnitPowerType("player"))
			ns.dev:LogOnce(key, "OFFFORM", "event", event, powerToken, "in", UnitPowerType("player"))
		end
		UpdateValues()
	else
		-- A new form in use, or a form learned.
		Refresh()
		UpdateValues()
	end
end)

-- Turns the row on or off, at this height.
function ns.OffFormPower.SetLayout(shown, height)
	ns.log("OFFFORM", "layout", shown, height)
	enabled, rowHeight = shown, height
	if shown then
		events:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
		events:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
		events:RegisterUnitEvent("UNIT_MAXPOWER", "player")
		events:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
		events:RegisterEvent("SPELLS_CHANGED")
	else
		events:UnregisterAllEvents()
	end
	Refresh()
	UpdateValues()
	-- With smooth fills just turned off, a bar still sliding jumps to its value.
	if ns.PowerBar.Interpolation() == Enum.StatusBarInterpolation.Immediate then
		leftBar:SetToTargetValue()
		rightBar:SetToTargetValue()
	end
	if ns.dev.enabled then
		-- Does the art exist, and can the border stretch taller without thickening?
		local frame = C_Texture.GetAtlasInfo("ui-castingbar-frame")
		ns.dev:LogOnce(
			"offform-art",
			"OFFFORM",
			"art",
			"energy",
			C_Texture.GetAtlasInfo(ATLAS[Energy]) ~= nil,
			"rage",
			C_Texture.GetAtlasInfo(ATLAS[Rage]) ~= nil,
			"border sliced",
			frame ~= nil and frame.sliceData ~= nil
		)
	end
end
