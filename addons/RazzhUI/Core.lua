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

-- The core's API global; later files add its functions. Nothing here names a module. Its other
-- globals are RazzhUIDB (SavedVariables, Database.lua) and the minimap button's frame name.
RazzhUI = {}

-- The bronze Blizzard gave WoW Forever's own screens: the character select nav bar's text colour
-- (Blizzard_CharacterSelectNavBar/Camelot/CharacterSelectNavBar.lua:1, a local there). The TOC
-- titles carry the same colour as the literal d6b380.
local FOREVER_BRONZE = CreateColor(0.8392, 0.7020, 0.5020)

-- enUS only for now. TITLE stays plain because it is the Options category's name, which Options sorts
-- and searches by; TITLE_COLORED is for display (the whole name in Forever bronze).
ns.L = {
	TITLE = "RazzhUI",
	TITLE_COLORED = FOREVER_BRONZE:WrapTextInColorCode("RazzhUI"),
	MODULE_PREFIX = "RazzhUI ",
	MODULES = "Modules",
	NO_MODULES = "No RazzhUI modules are installed.",
	-- Fallback for RELOADUI, which exists only in the running game.
	RELOAD_UI = "Reload UI",
	RELOAD_TOOLTIP = "Reload the interface to apply your changes.",
	-- Fallback for VIDEO_OPTIONS_NEED_UIRELOAD, which exists only in the running game.
	NEEDS_RELOAD = "Your changes need a reload of the interface to take effect.",
}

-- Setup that needs RazzhUIDB registers here. It runs in TOC order once the SavedVariables have
-- loaded.
local initializers = {}

function ns.OnInitialize(func)
	table.insert(initializers, func)
end

EventUtil.ContinueOnAddOnLoaded(ADDON_NAME, function()
	-- A hand-edited file may hold anything under the name.
	if type(RazzhUIDB) ~= "table" then
		RazzhUIDB = {}
	end
	ns.db = RazzhUIDB
	ns.DB.Migrate(ns.db)

	for _, func in ipairs(initializers) do
		func()
	end
	ns.log("LOADED", "db version", ns.db.version)

	if ns.dev.enabled then
		-- Global strings later files lean on; they exist only in the running game.
		for _, name in ipairs({ "RELOADUI", "ADDONS", "VIDEO_OPTIONS_NEED_UIRELOAD", "ERR_NOT_IN_COMBAT" }) do
			ns.log("LOADED", name, _G[name] or "missing")
		end
		ns.log("LOADED", "modules", #ns.Modules.List())
	end
end)
