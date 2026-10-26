local ADDON_NAME, ns = ...

local L = ns.L

-- DoT meter: on an enemy target or focus, one segment per DoT of the player's, eating into
-- the green from its right end like Blizzard's heal absorb bar does. Once they cover all of
-- it, the DoTs will kill: the bar's left end glows like an over-absorbed heal absorb.
ns.Modules.Register({
	key = "dot",
	kind = "dot",
	setting = "dotMeter",
	label = L.DOT_METER,
	tooltip = L.DOT_METER_TOOLTIP,
	-- Defined by the client, not in Lua; the fallback is its value.
	color = HEALTHBAR_HEAL_ABSORB_COLOR or CreateColor(0.424, 0.651, 0.051, 1),
	reverse = true,
	cue = {
		side = "LEFT",
		glowTemplate = "OverHealAbsorbGlowTemplate",
		GetMax = function(unit)
			return UnitHealth(unit)
		end,
	},
	GetAnchor = function(_, host)
		return host:GetHealthFill(), "fill"
	end,
})
