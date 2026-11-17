local ADDON_NAME, ns = ...

-- Dev-only logging, probing and evidence through ForeverDev (addons/ForeverDev/ForeverDev.lua,
-- scripts/devlog.sh). Without ForeverDev, ns.dev is inert: ns.dev.enabled is false and every
-- call on it does nothing. ns.log(TAG, ...) logs a line tagged TAG, by file:
--   LOADED          Core.lua
--   MODULES         Modules.lua
--   OPTIONS TOGGLE  Options.lua
--   MENU            GameMenu.lua
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

-- The core's one global; later files add its functions. Nothing here names a module.
RazzhForeverEnhanced = {}

-- enUS only for now.
ns.L = {
	TITLE = "Razzh Forever Enhanced",
	MODULE_PREFIX = "Razzh Forever Enhanced: ",
	MODULES = "Modules",
	NO_MODULES = "No Forever Enhanced addons are installed.",
	RELOAD_TOOLTIP = "Reload the interface to apply your changes.",
	-- Fallback for VIDEO_OPTIONS_NEED_UIRELOAD, which exists only in the running game.
	NEEDS_RELOAD = "Your changes need a reload of the interface to take effect.",
}

EventUtil.ContinueOnAddOnLoaded(ADDON_NAME, function()
	if ns.dev.enabled then
		-- Global strings later files lean on; they exist only in the running game.
		for _, name in ipairs({ "RELOADUI", "ADDONS", "VIDEO_OPTIONS_NEED_UIRELOAD", "ERR_NOT_IN_COMBAT" }) do
			ns.log("LOADED", name, _G[name] or "missing")
		end
	end
	ns.log("LOADED")
end)
