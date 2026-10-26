local ADDON_NAME, ns = ...

-- A module is one meter drawn on the unit frame health bars (UI/Hosts.lua). The hosts,
-- options and tooltip iterate the registered modules, so a new meter takes a Register call
-- and a file under Modules/.
--   key        unique name, used in log lines
--   kind       which tracked effects it shows ("dot" or "hot", see Data/Spells.lua); it draws
--              on the units that take them (ns.Units.Fits)
--   setting    ForeverCombatDB.settings key that turns it on
--   label, tooltip  shown in the options panel
--   color      segment color, one of Blizzard's health bar colors
--   reverse    true when the segments grow leftward from their anchor
--   cue        { side = "LEFT" | "RIGHT", glowTemplate = Blizzard's glow texture template,
--              GetMax = function(unit) }: the glow at that end of the bar lights up once the
--              effects' total reaches GetMax(unit), which may be secret
--   GetAnchor  function(module, host): the region whose right edge the first segment starts
--              from, and a name for it in the DISPLAY log line
ns.Modules = {}

local modules = {}
local modulesByKey = {}

function ns.Modules.Register(module)
	assert(not modulesByKey[module.key], "duplicate module " .. module.key)
	table.insert(modules, module)
	modulesByKey[module.key] = module
end

function ns.Modules.Enumerate()
	return ipairs(modules)
end

-- The player's effects the module shows on a unit (key: its mob key), or nil when there are
-- none or the module is off or doesn't draw on that unit.
function ns.Modules.GetEffects(module, unit, key)
	if key and ns.Options.Get(module.setting) and ns.Units.Fits(unit, module.kind) then
		return ns.Tracker.GetEffects(key, module.kind)
	end
end
