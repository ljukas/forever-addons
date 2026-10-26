local ADDON_NAME, ns = ...

-- Dev-only logging, probing and evidence through ForeverDev (addons/ForeverDev/ForeverDev.lua,
-- scripts/devlog.sh). Without ForeverDev, ns.dev is inert: ns.dev.enabled is false and every
-- call on it does nothing. ns.log(TAG, ...) logs a line tagged TAG, by file:
--   LOADED                                           Core.lua
--   SENT COMBO SCHOOL0 SECRET                        Engine/Tracker.lua
--   SEEN TRACK TICK MISS AVOID END UNLISTED NOTREAD  Engine/Knowledge.lua, which keeps the aggregates
--   HOST DISPLAY                                     UI/Hosts.lua
--   AURA                                             Dev/Probes.lua
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
	DOT_METER = "DoT Meter",
	DOT_METER_TOOLTIP = "Mark the damage your damage over time spells still have to deal on your target's and focus's health bar. When the marks cover all of the remaining health, your spells will finish it off.",
	HOT_METER = "HoT Meter",
	HOT_METER_TOOLTIP = "Show the healing your heal over time spells still have to do past your target's and focus's health. When it reaches the end of the bar, they will heal it to full.",
	SECONDS = INT_SPELL_DURATION_SEC or "%d sec",
	REMAINING = "%s (%s)",
}

-- Internal events between the modules. Callbacks are called as func(owner, ...).
--   EffectsChanged(mobKey) a tracked DoT or HoT on that mob started, ticked, ended or was dropped
--   OptionChanged()        a ForeverCombatDB.settings value changed
ns.callbacks = CreateFromMixins(CallbackRegistryMixin)
ns.callbacks:OnLoad()
ns.callbacks:GenerateCallbackEvents({ "EffectsChanged", "OptionChanged" })

-- Modules register setup that needs ForeverCombatDB. It runs in TOC order once the
-- SavedVariables have loaded.
local initializers = {}

function ns.OnInitialize(func)
	table.insert(initializers, func)
end

EventUtil.ContinueOnAddOnLoaded(ADDON_NAME, function()
	ForeverCombatDB = ForeverCombatDB or {}
	ns.db = ForeverCombatDB
	ns.DB.Migrate(ns.db)

	for _, func in ipairs(initializers) do
		func()
	end
	ns.log("LOADED", "db version", ns.db.version)
end)
