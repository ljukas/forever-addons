local ADDON_NAME, ns = ...

local L = ns.L

-- HoT meter: on a friendly target or focus (or the player), one segment per HoT of the
-- player's, extending the green past Blizzard's own incoming heal segments, in the color
-- Blizzard uses for the player's incoming heals. Once they reach the end of the bar, the HoTs
-- will heal to full: the bar's right end glows like an over-absorb.
ns.Modules.Register({
	key = "hot",
	kind = "hot",
	setting = "hotMeter",
	label = L.HOT_METER,
	tooltip = L.HOT_METER_TOOLTIP,
	-- Defined by the client, not in Lua; the fallback is its value.
	color = HEALTHBAR_MY_HEAL_PREDICTION_COLOR or CreateColor(0, 0.827, 0.765, 1),
	reverse = false,
	cue = {
		side = "RIGHT",
		glowTemplate = "OverAbsorbGlowTemplate",
		GetMax = function(unit)
			return UnitHealthMissing(unit)
		end,
	},
	GetAnchor = function(_, host)
		return host:GetIncomingHealEnd()
	end,
})
