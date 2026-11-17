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
RazzhUI = {}

-- enUS only for now. TITLE stays plain because it is the Options category's name, which Options sorts
-- and searches by; TITLE_COLORED is for display (Battle.net blue "Razzh", white "UI").
ns.L = {
	TITLE = "RazzhUI",
	TITLE_COLORED = BATTLENET_FONT_COLOR:WrapTextInColorCode("Razzh") .. HIGHLIGHT_FONT_COLOR:WrapTextInColorCode("UI"),
	MODULE_PREFIX = "RazzhUI ",
	MODULES = "Modules",
	NO_MODULES = "No RazzhUI modules are installed.",
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
		ns.log("LOADED", "BATTLENET_FONT_COLOR", BATTLENET_FONT_COLOR:GenerateHexColorNoAlpha())
	end
	ns.log("LOADED")
end)
