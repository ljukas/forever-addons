local ADDON_NAME, ns = ...

-- Dev-only logging, probing and evidence through ForeverDev (addons/ForeverDev/ForeverDev.lua,
-- scripts/devlog.sh). Without ForeverDev, ns.dev is inert: ns.dev.enabled is false and every
-- call on it does nothing. ns.log(TAG, ...) logs a line tagged TAG, by file:
--   LOADED                Core.lua
--   COLOR LEVEL FACTION   Colors.lua
--   ANCHOR                Anchor.lua
--   HEALTHBAR             HealthBar.lua
--   SPELLSCALE            SpellLine.lua
local function Nop() end

-- Returns t (or a new table) with every missing field a function that does nothing.
function ns.Inert(t)
	return setmetatable(t or {}, {
		__index = function()
			return Nop
		end,
	})
end

ns.dev = ForeverDev and ForeverDev.For(ADDON_NAME) or ns.Inert({ enabled = false })

function ns.log(tag, ...)
	ns.dev:Log(tag, ...)
end

-- enUS only for now. Blizzard's own global strings are used where one exists.
ns.L = {
	CURSOR_ANCHOR = "Tooltip follows the cursor",
	CURSOR_ANCHOR_TOOLTIP = "Show tooltips for players, creatures and objects in the world next to the mouse cursor instead of at the tooltip position set in Edit Mode.",
	CURSOR_DIRECTION = "Tooltip grows towards",
	CURSOR_DIRECTION_TOOLTIP = "Which side of the mouse cursor the tooltip appears on.",
	DIRECTION_DOWN_RIGHT = "Down and right",
	DIRECTION_DOWN_LEFT = "Down and left",
	DIRECTION_UP_RIGHT = "Up and right",
	DIRECTION_UP_LEFT = "Up and left",
	SPELL_SCALING = "Show spell scaling in spell tooltips",
	SPELL_SCALING_TOOLTIP = "Adds a line to your own damage, healing and shield spells with how much of your spell power they get and what it adds.",
	-- The spell scaling line (Logic/SpellScaling.lua): "+20% SP per tick, 4 ticks: +34 = 86-92 damage".
	-- Plain ASCII: the tooltip font has no arrow (it drew a box in game).
	SCALING_SP = "+%s SP",
	SCALING_AP = "+%s AP",
	SCALING_TICKS = " per tick, %d ticks",
	SCALING_BONUS = ": +%d",
	SCALING_TOTAL = " = %s %s",
	SCALING_RANGE = "%d-%d",
	SCALING_DAMAGE = "damage",
	SCALING_HEAL = "healing",
	SCALING_ABSORB = "absorbed",
}

-- Modules register setup that needs ForeverTooltipDB. It runs in TOC order once the
-- SavedVariables have loaded.
local initializers = {}

function ns.OnInitialize(func)
	table.insert(initializers, func)
end

EventUtil.ContinueOnAddOnLoaded(ADDON_NAME, function()
	ForeverTooltipDB = ForeverTooltipDB or {}
	ns.db = ForeverTooltipDB
	ns.DB.Migrate(ns.db)

	for _, func in ipairs(initializers) do
		func()
	end
	ns.log("LOADED", "db version", ns.db.version)
end)
