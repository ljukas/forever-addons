local ADDON_NAME, ns = ...

-- A rogue's or Cat Form druid's combo points: a row of five slots on top of the frame (on the
-- druid's Other Powers row when it is in, else on the power bar) that fill left to right, in the red
-- of Blizzard's combo point gems around the target portrait. Only while the player has a target:
-- combo points sit on the target in Forever (GetComboPoints("player", "target"), as
-- Blizzard_UnitFrame/Camelot/ComboFrame.lua reads them), so there are none without one
-- (docs/superpowers/specs/2026-11-20-razzhuiresourcebars-combo-points-design.md).
--
-- Display only. The count can be secret (GetComboPoints is SecretWhenUnitPowerRestricted): it goes
-- straight into the slots and is never compared, logged or calculated with. Slot i's range is i-1 to
-- i, so the status bar's own clamping fills it or leaves it empty.
ns.ComboPoints = {}

local _, class = UnitClass("player")
-- False for every other class: no row, no events, and EditMode.lua adds no settings for it.
ns.ComboPoints.available = class == "ROGUE" or class == "DRUID"

-- Whether the row shows: for a rogue, or a druid whose power is energy (Cat Form, the rule of
-- Blizzard's DruidComboPointBarMixin:ShouldShowComboPointBar), with a target. Pure.
function ns.ComboPoints.ShouldShow(playerClass, powerType, hasTarget)
	if not hasTarget then
		return false
	end
	return playerClass == "ROGUE" or (playerClass == "DRUID" and powerType == Enum.PowerType.Energy)
end

if not ns.ComboPoints.available then
	function ns.ComboPoints.SetLayout() end
	return
end

local SLOTS = 5

-- As in OffFormPower.lua: how thick the cast bar border's line draws. Neighbouring cells overlap by
-- it, so they share one line, and the row's bottom line is the top line of the bar below.
local LINE = 2

-- The plain player-frame fill, tinted the red of Blizzard's gem (uf-roguecp-icon-red, sampled from
-- a screenshot of the target portrait, 2026-11-20). PowerBarColor's COMBO_POINTS is yellow.
local FILL_ATLAS = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana-Status"
local RED_R, RED_G, RED_B = 0.80, 0.20, 0.20

local holder = ns.PowerBar.holder
local border = ns.PowerBar.border

-- A child of the border's frame, so it hides when the power bar does. Level with the holder, whose
-- background the row's own continues upward.
local row = CreateFrame("Frame", nil, border)
row:SetFrameLevel(holder:GetFrameLevel())
row:Hide()

-- From a pixel past the row's top down to the background of the bar below.
local background = ns.PowerBar.CreateBackground(row)
background:SetPoint("TOPLEFT", -1, 1)
background:SetPoint("BOTTOMRIGHT", 1, -LINE)

-- The border sits level with the power bar's. The cast bar's border isn't sliced (in game,
-- 2026-11-12): squeezed into a fifth of the row its side lines would draw thin, so the row wears one
-- copy across its width, overlapping the border below by a line, and the slots are split by
-- separators cut from that border's own left side.
local cells = CreateFrame("Frame", nil, row)
cells:SetAllPoints()
cells:SetFrameLevel(border:GetFrameLevel())

local frame = cells:CreateTexture(nil, "OVERLAY")
frame:SetAtlas("ui-castingbar-frame")
frame:SetPoint("TOPLEFT", row, "TOPLEFT", -LINE, LINE)
frame:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", LINE, -LINE)

-- A strip LINE pixels wide off the border art's left side, from its middle third (clear of the
-- corners), to stretch down the row as a separator. Plain dark if the art can't be read.
local function CreateSeparator()
	local separator = cells:CreateTexture(nil, "OVERLAY")
	local info = C_Texture.GetAtlasInfo("ui-castingbar-frame")
	ns.dev:LogOnce("combo-separator", "COMBO", "separator art", info ~= nil and info.file ~= nil)
	if info and info.file and info.width > 0 then
		local u = info.leftTexCoord
		local du = (info.rightTexCoord - info.leftTexCoord) * LINE / info.width
		local dv = (info.bottomTexCoord - info.topTexCoord) / 3
		separator:SetTexture(info.file)
		separator:SetTexCoord(u, u + du, info.topTexCoord + dv, info.bottomTexCoord - dv)
	else
		separator:SetColorTexture(0, 0, 0, 0.9)
	end
	separator:SetWidth(LINE)
	return separator
end

local slots = {}
for index = 1, SLOTS do
	local slot = CreateFrame("StatusBar", nil, row)
	-- Under the border, level with the main bar's fill.
	slot:SetFrameLevel(holder:GetFrameLevel() + 1)
	slot:SetStatusBarTexture(FILL_ATLAS)
	slot:SetStatusBarColor(RED_R, RED_G, RED_B)
	slot:SetMinMaxValues(index - 1, index)
	slot:SetValue(0)
	-- On the slot's left edge, from the second slot on.
	if index > 1 then
		slot.separator = CreateSeparator()
	end
	slots[index] = slot
end

-- Where slot index ends, in whole pixels from the row's left, so the separators and fill edges
-- stay sharp at any width. Pure.
function ns.ComboPoints.SlotEdge(width, index)
	return math.floor(index * width / SLOTS + 0.5)
end

-- Places the slots and separators across the row's width. Two slots meet under the separator
-- between them; the end slots reach past the row under the border's ends, as far as the main bar's
-- fill does (its art starts and stops short).
local function LayoutSlots()
	local width = row:GetWidth()
	if width <= 0 then
		return
	end
	local outLeft, outRight = ns.PowerBar.fillOutset.left, ns.PowerBar.fillOutset.right
	for index, slot in ipairs(slots) do
		local left, right = ns.ComboPoints.SlotEdge(width, index - 1), ns.ComboPoints.SlotEdge(width, index)
		slot:ClearAllPoints()
		slot:SetPoint("TOPLEFT", row, "TOPLEFT", left - (index == 1 and outLeft or 0), 0)
		slot:SetPoint("BOTTOMRIGHT", row, "BOTTOMLEFT", right + (index == SLOTS and outRight or 0), 0)
		if slot.separator then
			slot.separator:ClearAllPoints()
			slot.separator:SetPoint("TOPLEFT", row, "TOPLEFT", left - LINE / 2, 0)
			slot.separator:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", left - LINE / 2, 0)
		end
	end
end
row:SetScript("OnSizeChanged", LayoutSlots)

-- Fills the slots from the points on the target. The count is secret at times and only passes
-- through.
local function UpdateValues(interpolation)
	local points = GetComboPoints("player", "target")
	if ns.dev.enabled then
		local combat = InCombatLockdown()
		local secret = issecretvalue(points)
		ns.dev:LogOnce(
			"combo-secret-" .. tostring(secret) .. tostring(combat),
			"COMBO",
			"secret",
			secret,
			"combat",
			combat
		)
	end
	for _, slot in ipairs(slots) do
		slot:SetValue(points, interpolation)
	end
end

-- Sits the row on the Other Powers row when that is in, else on the power bar.
local function Place()
	local below = ns.OffFormPower.Row() or holder
	row:ClearAllPoints()
	row:SetPoint("BOTTOMLEFT", below, "TOPLEFT", 0, LINE)
	row:SetPoint("BOTTOMRIGHT", below, "TOPRIGHT", 0, LINE)
	ns.dev:LogChanged("combo-anchor", below == holder, "COMBO", "anchor", below == holder and "bar" or "offform")
end

-- The settings (SetLayout).
local enabled = false

-- Shows the row when it should, with the slots filled at once (a new target's points, like
-- Blizzard's suppressTransitions). Everything touched is ours and unprotected, so this is safe in
-- combat.
local function Refresh()
	local shown = enabled and ns.ComboPoints.ShouldShow(class, UnitPowerType("player"), UnitExists("target"))
	row:SetShown(shown)
	ns.dev:LogChanged("combo-shown", shown, "COMBO", "shown", shown)
	UpdateValues(Enum.StatusBarInterpolation.Immediate)
	for _, slot in ipairs(slots) do
		slot:SetToTargetValue()
	end
end

ns.OffFormPower.OnRowChanged(Place)

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
	if
		event == "UNIT_POWER_FREQUENT"
		or event == "UNIT_POWER_UPDATE"
		or event == "UNIT_MAXPOWER"
		or event == "COMBO_TARGET_CHANGED"
	then
		-- Every energy and mana tick lands here too; a hidden row is filled when it shows (Refresh).
		if row:IsShown() then
			UpdateValues(ns.PowerBar.Interpolation())
		end
	else
		-- A new target, a form change, or the world loaded.
		Refresh()
	end
end)

-- Turns the row on or off, at this height.
function ns.ComboPoints.SetLayout(shown, height)
	ns.log("COMBO", "layout", shown, height)
	enabled = shown
	row:SetHeight(height)
	if shown then
		events:RegisterEvent("PLAYER_ENTERING_WORLD")
		events:RegisterEvent("PLAYER_TARGET_CHANGED")
		events:RegisterEvent("COMBO_TARGET_CHANGED")
		events:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
		events:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
		-- Blizzard's ComboFrame listens for both (Camelot/ComboFrame.lua).
		events:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
		events:RegisterUnitEvent("UNIT_MAXPOWER", "player")
	else
		events:UnregisterAllEvents()
	end
	Place()
	LayoutSlots()
	Refresh()
end
