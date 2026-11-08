local ADDON_NAME, ns = ...

-- Launch-day probes, logged only (scripts/devlog.sh) and left out of releases (Dev/). The
-- ones every addon shares (restrictions, unit secrecy) are ForeverDev's own, in its Probes.lua.
--   AURA  whether a tracked spell's aura can be read on its unit after the cast, through the
--         two aura lookups without RequiresUnitAuraAccess (the others error in combat). They
--         return nothing for secret auras, but spells Blizzard flags as never secret would
--         read: those could be tracked from the aura instead of estimated. Once per spell and
--         situation.

if not ns.dev.enabled then
	return
end

-- Seconds after the cast before looking: projectiles and the aura's application take a moment.
local AURA_PROBE_DELAY = 1

-- A readable aura as text for the log. Its fields are checked one by one, since a readable
-- aura may still carry secret fields.
local function DescribeAura(aura)
	local points = aura.points and aura.points[1]
	if issecretvalue(aura.expirationTime) or issecretvalue(points) then
		return "secret fields"
	end
	local remaining = aura.expirationTime > 0 and string.format("%.1fs", aura.expirationTime - GetTime()) or "none"
	return string.format(
		"readable remaining %s points %s stacks %s",
		remaining,
		tostring(points),
		tostring(aura.applications)
	)
end

local function ProbeAura(name, spellID, kind)
	local unit = "target"
	if kind == "hot" and not ns.Units.Fits(unit, kind) then
		unit = "player"
	elseif kind == "dot" and not ns.Units.Fits(unit, kind) then
		return
	end
	local situation = spellID .. " " .. ForeverDev.Situation()
	local filter = (kind == "hot" and "HELPFUL" or "HARMFUL") .. "|PLAYER"
	local bySpellID, aura = pcall(C_UnitAuras.GetUnitAuraBySpellID, unit, spellID)
	local byName, namedAura = pcall(C_UnitAuras.GetAuraDataBySpellName, unit, name, filter)
	ns.dev:LogOnce(
		"aura " .. situation,
		"AURA",
		name,
		"on",
		unit,
		situation,
		"bySpellID",
		ForeverDev.Describe(bySpellID, aura, DescribeAura),
		"byName",
		ForeverDev.Describe(byName, namedAura, DescribeAura)
	)
end

local playerClass

ns.OnInitialize(function()
	playerClass = select(2, UnitClass("player"))
	local frame = CreateFrame("Frame")
	frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
	frame:SetScript("OnEvent", function(_, _, _, _, spellID)
		if issecretvalue(spellID) then
			return
		end
		local name = C_Spell.GetSpellName(spellID)
		local entry = name and ns.Spells.Lookup(name, playerClass)
		if entry then
			C_Timer.After(AURA_PROBE_DELAY, function()
				ProbeAura(name, spellID, entry.kind)
			end)
		end
	end)
end)

-- PORTRAIT: /fcprobe forces a copy of the red kill portrait onto the target frame, since the
-- real one only shows in kill range (secret, so it can't be logged). Each use steps through
-- masked → unmasked → off and logs the cue's geometry and visibility, which aren't secret
-- here (the probe's own bar runs 0..1). /fcprobe <x> <y> [inset] moves the circle live.
local probeCue
local probeStep = 0

local function ProbeOverlay(cue)
	local fill = cue.bar:GetStatusBarTexture()
	for _, region in ipairs({ cue.bar:GetRegions() }) do
		if region ~= fill then
			return region
		end
	end
end

-- Hosts.lua reads the same field; LuaLS has no type for it. Looked up when used: TargetFrame
-- comes with Blizzard_UnitFrame.
local function TargetContainer()
	---@diagnostic disable-next-line: undefined-field
	return TargetFrame.TargetFrameContainer
end

local function LogProbe(step, cue, overlay)
	local portrait = TargetContainer().Portrait
	local function rect(region)
		local left, bottom, width, height = region:GetRect()
		if issecretvalue(left) then
			return "secret rect"
		elseif not left then
			return "no rect"
		end
		return string.format("%.1f,%.1f %.1fx%.1f", left, bottom, width, height)
	end
	ns.log(
		"PORTRAIT",
		step,
		"window",
		tostring(cue.window:IsVisible()),
		rect(cue.window),
		"overlay",
		tostring(overlay:IsVisible()),
		rect(overlay),
		"alpha",
		overlay:GetAlpha(),
		"masks",
		overlay:GetNumMaskTextures(),
		"layer",
		overlay:GetDrawLayer(),
		"portrait",
		rect(portrait),
		"bar level",
		cue.bar:GetFrameLevel(),
		"container level",
		TargetContainer():GetFrameLevel()
	)
end

SLASH_FOREVERCOMBAT_PROBE1 = "/fcprobe"
-- /fcprobe <x> <y> [inset]: shows the masked red and moves its circle live, to tune
-- PORTRAIT_MASK_OFFSET_X/Y and PORTRAIT_MASK_INSET in UI/Cue.lua.
local function NudgeProbe(x, y, inset)
	if not probeCue then
		probeCue = ns.Cue.CreatePortrait(TargetContainer())
	end
	probeStep = 1
	probeCue:Set(1, 1)
	local mask = ProbeOverlay(probeCue):GetMaskTexture(1)
	local portrait = TargetContainer().Portrait
	mask:ClearAllPoints()
	mask:SetPoint("TOPLEFT", portrait, "TOPLEFT", inset + x, -inset + y)
	mask:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", -inset + x, inset + y)
	print(string.format("ForeverCombat probe: circle at x %s y %s inset %s.", x, y, inset))
	ns.log("PORTRAIT", "nudge x", x, "y", y, "inset", inset)
end

SlashCmdList.FOREVERCOMBAT_PROBE = function(input)
	local xText, yText, insetText = strsplit(" ", strtrim(input or ""))
	local x, y = tonumber(xText), tonumber(yText)
	if x and y then
		NudgeProbe(x, y, tonumber(insetText) or 3)
		return
	end
	if not probeCue then
		probeCue = ns.Cue.CreatePortrait(TargetContainer())
	end
	local overlay = ProbeOverlay(probeCue)
	probeStep = probeStep % 3 + 1
	if probeStep == 1 then
		probeCue:Set(1, 1)
		print("ForeverCombat probe: red portrait forced on, masked (as shipped). /fcprobe again for unmasked.")
	elseif probeStep == 2 then
		overlay:RemoveMaskTexture(overlay:GetMaskTexture(1))
		print("ForeverCombat probe: red portrait unmasked. /fcprobe again to turn it off.")
	else
		probeCue:Hide()
		probeCue = nil
		print("ForeverCombat probe: off.")
		return
	end
	-- Rects settle after the next layout pass.
	local cue, step = probeCue, probeStep
	C_Timer.After(0.1, function()
		LogProbe(step, cue, overlay)
	end)
end
