local ADDON_NAME, ns = ...

-- What the spell being cast will cost, as a dimmer stretch at the end of the power bar's fill, as
-- the power bar of Blizzard's player frame has it (UnitFrameManaCostPredictionBars_Update,
-- Blizzard_UnitFrame/Mainline/UnitFrame.lua): shown from the start of a cast with a cast time to
-- its end, for the cost in the power the bar shows.
--
-- Blizzard's bar shows the power less the cost and draws the cost beside it, sized by cost over
-- maximum. The power and its maximum are secret here, so nothing is subtracted or divided; status
-- bars do both:
--   ruler  unseen beside the bar, with the secret maximum as its range and the cost (not secret)
--          as its value: its fill is as wide as the cost.
--   mark   unseen, a copy of the fill moved left by ruler's fill, so it ends where the power less
--          the cost does.
--   kept   a copy of the fill in the fill's own place, at full brightness, masked off where mark
--          ends.
-- During a cast the fill itself goes dim, and shows only past kept: that stretch is the cost.
--
-- Two earlier builds, both seen in game on 2026-11-18. A dim stretch over the end of the fill,
-- hung from the fill's moving edge, trailed it while the fill slid: a pixel of bright fill showed
-- past it. So the fill's own end has to be the cost's end. And kept as the moved copy itself
-- showed the fill's art moved with it: the whole bar changed during a cast. So what is seen stays
-- in the fill's place, and what is moved stays unseen.
local fill = ns.PowerBar.fill

-- The share of its brightness the fill keeps under a cost. Blizzard's prediction colours
-- (PowerBarColor's predictionColor) are made for its player frame's black bar: on this bar's grey
-- background its mana colour read as empty, not as about to be spent (in game, 2026-11-18).
local DIM = 0.7

-- How long the cost stays after a cast succeeded without the power having changed.
local SPEND_TIMEOUT = 0.5

-- Keeps ruler, which lies wholly left of the bar, out of sight.
local clip = CreateFrame("Frame", nil, fill)
clip:SetAllPoints()
clip:SetClipsChildren(true)

-- As wide as the bar and ending where it starts, filling backwards: its fill starts the cost's
-- width left of the bar.
local ruler = CreateFrame("StatusBar", nil, clip)
ruler:SetPoint("TOPRIGHT", clip, "TOPLEFT")
ruler:SetPoint("BOTTOMRIGHT", clip, "BOTTOMLEFT")
ruler:SetReverseFill(true)

-- As wide as the bar and starting where ruler's fill does. Only measured by, never seen.
local mark = CreateFrame("StatusBar", nil, clip)
mark:SetAlpha(0)

-- Above the fill, below the numbers (PowerText.lua) and the border.
local kept = CreateFrame("StatusBar", nil, clip)
kept:SetAllPoints()
kept:SetFrameLevel(fill:GetFrameLevel() + 1)
kept:Hide()

-- Shows kept from the bar's start to mark's end; the wrap modes hide it everywhere else.
local mask = kept:CreateMaskTexture()
mask:SetAtlas("SquareMask", false, nil, nil, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
-- The texture of kept the mask is on, and the art the three bars wear.
local masked, art

clip:SetScript("OnSizeChanged", function(_, width)
	ruler:SetWidth(width)
	mark:SetWidth(width)
end)

-- The cast the cost is shown for (its castGUID) and the power it is in; nil when none is.
local activeCast, activePower
-- Whether that cast has succeeded, so the cost only waits for the power to drop by it.
local spent = false
-- When the bar's values last changed during that cast (GetTime, which stands still within a
-- frame): a change in the frame of the cast's success is its cost coming off.
local changedAt
-- Whether the next change of the bar's values is the cost of a cast before this one: the next
-- cast, queued, starts before the power drops (in game, 2026-11-18).
local landing = false

-- The fill jumps to the power without the cost instead of sliding there: the dim stretch was the
-- spend, so there is nothing left to animate.
local function Land(how)
	ns.log("COST", how)
	fill:SetToTargetValue()
end

local function Clear()
	activeCast, activePower, spent, changedAt = nil, nil, false, nil
	kept:Hide()
	ns.PowerBar.SetDim(1)
end

-- Feeds the copies what the fill was fed. The values are secret and only pass through.
local function Feed(powerType, valueInterpolation)
	local max = UnitPowerMax("player", powerType)
	local power = UnitPower("player", powerType)
	ruler:SetMinMaxValues(0, max)
	mark:SetMinMaxValues(0, max)
	mark:SetValue(power, valueInterpolation)
	kept:SetMinMaxValues(0, max)
	kept:SetValue(power, valueInterpolation)
end

-- Makes the copies jump to their values, as the fill does.
local function Snap()
	mark:SetToTargetValue()
	kept:SetToTargetValue()
end

local function Show(castGUID, spellID)
	if spent then
		landing = true
	end
	local powerType, powerToken, altR, altG, altB = UnitPowerType("player")
	local cost = powerType and ns.PowerBar.SpellCost(spellID, powerType) or 0
	-- A cost is not secret by the API docs; one that is can't be told from none.
	if issecretvalue(cost) then
		ns.dev:LogOnce("cost-secret-cost", "COST", "secret", "cost")
		cost = 0
	end
	ns.log("COST", "start", spellID, powerToken, cost)
	if cost <= 0 then
		Clear()
		return
	end
	activeCast, activePower, spent, changedAt = castGUID, powerType, false, nil

	local atlas, r, g, b = ns.PowerBar.Art(powerToken, altR, altG, altB)
	if atlas ~= art then
		art = atlas
		kept:SetStatusBarTexture(atlas)
		-- Never seen; a status bar has no fill to measure by without art.
		ruler:SetStatusBarTexture(atlas)
		mark:SetStatusBarTexture(atlas)
	end
	kept:SetStatusBarColor(r, g, b)
	-- A status bar's texture is the client's to replace, so the mask follows it.
	local texture = kept:GetStatusBarTexture()
	if texture ~= masked then
		masked = texture
		texture:AddMaskTexture(mask)
	end

	local width = clip:GetWidth()
	ruler:SetWidth(width)
	mark:SetWidth(width)
	-- All fills stand at the power, so they slide as one from here on.
	Feed(powerType, Enum.StatusBarInterpolation.Immediate)
	Snap()
	fill:SetToTargetValue()
	ruler:SetValue(cost)

	-- Anchored anew each time, for the same reason.
	local costStart = ruler:GetStatusBarTexture()
	mark:ClearAllPoints()
	mark:SetPoint("TOPLEFT", costStart, "TOPLEFT")
	mark:SetPoint("BOTTOMLEFT", costStart, "BOTTOMLEFT")
	mask:ClearAllPoints()
	mask:SetPoint("TOPLEFT", clip, "TOPLEFT")
	mask:SetPoint("BOTTOMRIGHT", mark:GetStatusBarTexture(), "BOTTOMRIGHT")

	ns.PowerBar.SetDim(DIM)
	kept:Show()
end

-- The bar's power or values changed (ns.PowerBar.OnChanged).
ns.PowerBar.OnChanged(function(powerType, _, valueInterpolation)
	local landed = landing
	if landed then
		landing = false
		Land("spent queued")
	end
	if not activeCast then
		return
	end
	if powerType ~= activePower then
		-- The bar shows another power now.
		ns.log("COST", "power")
		Clear()
	elseif spent then
		-- The cast's cost has come off the power.
		Land("spent after")
		Clear()
	else
		changedAt = GetTime()
		Feed(powerType, valueInterpolation)
		if landed then
			Snap()
		end
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
		landing = false
		Clear()
		return
	end
	-- The player's own casts are readable by the API docs (SecretWhenUnitSpellCastRestricted),
	-- unless a spell is flagged secret: then there is no cost to show, and nothing to tell casts
	-- apart by.
	if issecretvalue(castGUID) or issecretvalue(spellID) then
		ns.dev:LogOnce("cost-secret-cast", "COST", "secret", event)
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
		-- The client sends the success before the power without the cost (in game, 2026-11-18).
		-- Its source doesn't promise that order, so the other one is taken too: the power changed
		-- in this frame already, or the cost stays until it does.
		if changedAt == GetTime() then
			Land("spent before")
			Clear()
			return
		end
		spent = true
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
