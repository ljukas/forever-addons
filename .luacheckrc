-- Luacheck config. CodeRabbit runs luacheck on every PR (see .coderabbit.yaml); LuaLS in
-- scripts/lint.sh covers types and the WoW API. Run it locally with `luacheck addons template`.
std = "lua51"

-- Reading WoW's API globals is LuaLS's job, so undefined-global reads (113) aren't checked here.
-- Mutating a global table (112, e.g. SlashCmdList.X = ...), whitespace (611) and line length
-- (631) are left to the client API and StyLua. CodeRabbit always ignores these four anyway.
ignore = {
	"113",
	"112",
	"611",
	"631",
	-- Every file starts with `local ADDON_NAME, ns = ...` (CLAUDE.md), used or not.
	"211/ADDON_NAME",
	"211/ns",
}

-- Mixin methods keep their implicit self even when they don't use it.
self = false

-- types/ holds LuaLS annotations, not code that runs.
exclude_files = { "types/**", ".cache/**", ".release/**" }

-- Globals an addon sets on purpose: SavedVariables, mixins named in XML, slash commands,
-- bindings and functions the TOC names. Anything else assigned globally is an accident (111).
-- A new addon adds its own entry here.
files["template/Addon/**"].globals = { "__ADDON__DB" }

files["addons/ForeverCombat/**"].globals = {
	"ForeverCombatDB",
	"ForeverCombatSegmentMixin",
}

files["addons/ForeverDev/**"].globals = {
	"ForeverDev",
	"ForeverDevDB",
	"ForeverDev_OnAddonCompartmentClick",
	"BINDING_HEADER_FOREVERDEV",
	"BINDING_NAME_FOREVERDEV_RELOADUI",
	"SLASH_FOREVERDEV1",
	"SLASH_FOREVERDEV_RELOAD1",
}

files["addons/ForeverMap/**"].globals = {
	"ForeverMapDB",
}

files["addons/ForeverProfessions/**"].globals = {
	"ForeverProfessionsDB",
	"ForeverProfessionsPinMixin",
	"ForeverProfessionsWorldPinMixin",
	"ForeverProfessionsWorldMapToggleMixin",
}
