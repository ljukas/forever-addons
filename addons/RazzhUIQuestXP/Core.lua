local ADDON_NAME, ns = ...

-- Dev-only logging, probing and evidence through ForeverDev (addons/ForeverDev/ForeverDev.lua,
-- scripts/devlog.sh). Without ForeverDev, ns.dev is inert: ns.dev.enabled is false and every
-- call on it does nothing. ns.log(TAG, ...) logs a line tagged TAG, by file:
--   LOADED          Core.lua
--   BONUS           XPBonus.lua
--   XP, TURNIN      Quests.lua
--   LINE            Text.lua
--   SAVE, EDITMODE  EditMode.lua
--   OPTIONS         Options.lua
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

-- enUS only for now. Plain ASCII: the client font may lack arrows and ellipses.
ns.L = {
	QUEST_XP = "Quest XP",
	LINE = "Quests: +%s XP (%d%%)",
	SAMPLE = "Quests: +4,250 XP (31%)",
	TITLE = "Quest turn-ins",
	COMPLETED_XP = "Completed quests: %d (+%s XP)",
	SHARE = "That is %d%% of level %d (%s XP).",
	BONUS = "Includes +%d%% from %s",
	LANDS = "Ends at %d%% of level %d",
	LEVEL_UP = "Level up!",
	PAST_LEVEL = "+%s XP past level %d",
	FONT_SIZE = "Font Size",
	EDIT_MODE = "Edit Mode",
	EDIT_MODE_TOOLTIP = "Move the quest XP line, and set how big it is, in Edit Mode.",
}

-- Modules register setup that needs RazzhUIQuestXPDB. It runs in TOC order once the
-- SavedVariables have loaded.
local initializers = {}

function ns.OnInitialize(func)
	table.insert(initializers, func)
end

EventUtil.ContinueOnAddOnLoaded(ADDON_NAME, function()
	RazzhUIQuestXPDB = RazzhUIQuestXPDB or {}
	ns.db = RazzhUIQuestXPDB
	ns.DB.Migrate(ns.db)

	for _, func in ipairs(initializers) do
		func()
	end
	ns.log("LOADED", "db version", ns.db.version)
end)
