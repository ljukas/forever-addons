local ADDON_NAME, ns = ...

-- What the spell being cast will cost, as a darker stretch at the end of the power bar's fill, as
-- the power bar of Blizzard's player frame has it (UnitFrameManaCostPredictionBars_Update,
-- Blizzard_UnitFrame/Mainline/UnitFrame.lua): shown from the start of a cast with a cast time to
-- its end, for the cost in the power the bar shows.
--
-- Blizzard's bar shows the power less the cost and draws the cost beside it, sized by cost over
-- maximum. The power and its maximum are secret here, so nothing is subtracted or divided: the
-- cost is a status bar of its own that fills backwards from the right edge of the power bar's
-- fill, with the secret maximum as its range and the cost (not secret) as its value.
local fill = ns.PowerBar.fill

-- Blizzard's art for the cost on the player frame's bar, tinted with the power's prediction colour.
local ATLAS = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana-Status"

-- How long the cost stays after a cast succeeded without the power having changed.
local SPEND_TIMEOUT = 0.5

-- Keeps the cost inside the bar: it is as wide as the bar and hangs from the fill's right edge,
-- so most of it lies left of the bar.
local clip = CreateFrame("Frame", nil, fill)
clip:SetAllPoints()
clip:SetFrameLevel(fill:GetFrameLevel() + 1)
clip:SetClipsChildren(true)

local bar = CreateFrame("StatusBar", nil, clip)
bar:SetStatusBarTexture(ATLAS)
bar:SetReverseFill(true)
bar:Hide()

clip:SetScript("OnSizeChanged", function(_, width)
	bar:SetWidth(width)
end)

-- The cast the cost is shown for (its castGUID) and the power it is in; nil when none is.
local activeCast, activePower
-- Whether that cast has succeeded, so the cost only waits for the power to drop by it.
local spent = false

local function Clear()
	activeCast, activePower, spent = nil, nil, false
	bar:Hide()
end

-- What the spell costs in the given power; 0 when nothing.
local function CostOf(spellID, powerType)
	local costs = C_Spell.GetSpellPowerCost(spellID)
	if costs then
		for _, info in ipairs(costs) do
			if info.type == powerType then
				return info.cost
			end
		end
	end
	return 0
end

local function Show(castGUID, spellID)
	local powerType, powerToken = UnitPowerType("player")
	local cost = powerType and CostOf(spellID, powerType) or 0
	-- A cost is not secret by the API docs; one that is can't be told from none.
	if issecretvalue(cost) then
		ns.dev:LogOnce("cost-secret", "COST", "secret", "cost")
		cost = 0
	end
	ns.log("COST", "start", spellID, powerToken, cost)
	if cost <= 0 then
		Clear()
		return
	end
	activeCast, activePower, spent = castGUID, powerType, false

	local info = PowerBarColor[powerToken]
	local colour = info and info.predictionColor or POWERBAR_PREDICTION_COLOR_MANA
	bar:SetStatusBarColor(colour:GetRGBA())

	-- Anchored anew each time: the fill's texture is the client's to replace when its art changes.
	local texture = fill:GetStatusBarTexture()
	bar:ClearAllPoints()
	bar:SetPoint("TOPRIGHT", texture, "TOPRIGHT")
	bar:SetPoint("BOTTOMRIGHT", texture, "BOTTOMRIGHT")
	bar:SetWidth(clip:GetWidth())
	bar:SetMinMaxValues(0, UnitPowerMax("player", powerType))
	bar:SetValue(cost)
	bar:Show()
end

-- The bar's power or values changed (ns.PowerBar.OnChanged).
ns.PowerBar.OnChanged(function(powerType)
	if not activeCast then
		return
	end
	if spent or powerType ~= activePower then
		-- The cast's cost has come off the power, or the bar shows another power now.
		ns.log("COST", spent and "spent" or "power")
		Clear()
	else
		bar:SetMinMaxValues(0, UnitPowerMax("player", powerType))
	end
end)

local events = CreateFrame("Frame")
events:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function(_, event, _, castGUID, spellID)
	if event == "PLAYER_ENTERING_WORLD" then
		Clear()
		return
	end
	-- The player's own casts are readable by the API docs (SecretWhenUnitSpellCastRestricted),
	-- unless a spell is flagged secret: then there is no cost to show, and nothing to tell casts
	-- apart by.
	if issecretvalue(castGUID) or issecretvalue(spellID) then
		ns.dev:LogOnce("cost-secret", "COST", "secret", event)
		Clear()
		return
	end
	if event == "UNIT_SPELLCAST_START" then
		Show(castGUID, spellID)
	elseif castGUID ~= activeCast or spent then
		-- Another spell tried while this one is cast (its failure says nothing about ours), or the
		-- stop that follows a success.
		return
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		-- The cost stays until the power drops by it, and the fill jumps there instead of sliding:
		-- the darker stretch was the spend, so there is nothing left to animate.
		spent = true
		ns.PowerBar.SnapNextValue()
		C_Timer.After(SPEND_TIMEOUT, function()
			if activeCast == castGUID then
				ns.log("COST", "timeout", spellID)
				Clear()
			end
		end)
	else
		ns.log("COST", "end", event, spellID)
		Clear()
	end
end)
