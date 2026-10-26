local ADDON_NAME, ns = ...

-- Dev-only logging, probing and evidence through ForeverDev (addons/ForeverDev/ForeverDev.lua,
-- scripts/devlog.sh). Without ForeverDev, ns.dev is inert: ns.dev.enabled is false and every
-- call on it does nothing. ns.log(TAG, ...) logs a line tagged TAG, by file:
--   LOADED            Core.lua
--   GATHER NEW AGAIN  Sources/GatherRecorder.lua
--   SKILL UNLISTED    Knowledge.lua, which keeps the evidence
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
	HERBS = "Herbs",
	MINERALS = "Minerals",
	HERBALISM = "Herbalism",
	MINING = "Mining",
	KNOWN_NODES = "Known Gathering Nodes",
	SHOW_ON_WORLD_MAP = "Show on World Map",
	SHOW_ON_WORLD_MAP_TOOLTIP = "Show the gathering nodes you have found on the world map.",
	SHOW_ON_MINIMAP = "Show on Minimap",
	SHOW_ON_MINIMAP_TOOLTIP = "Show the gathering nodes you have found on the minimap.",
	SHOW_LAYER_TOOLTIP = "Show the %s you have gathered before.",
	CLICK_TO_SHOW = "Click to show them on the map.",
	CLICK_TO_HIDE = "Click to hide them from the map.",
	REQUIRES_SKILL = TRAINER_REQ_SKILL_RANK or "Requires %s (%d)",
	CURRENT_SKILL = "Your skill: %d",
	NOT_LEARNED = "You have not learned %s.",
	TIMES_GATHERED = "Times gathered: %d",
}

-- Internal events between the modules. Callbacks are called as func(owner, ...).
--   NodesChanged(mapID) a node was recorded or gathered again on that map
--   OptionChanged()     a ForeverProfessionsDB.settings value changed
--   SkillsChanged()     the player's profession ranks may have changed
ns.callbacks = CreateFromMixins(CallbackRegistryMixin)
ns.callbacks:OnLoad()
ns.callbacks:GenerateCallbackEvents({ "NodesChanged", "OptionChanged", "SkillsChanged" })

-- Returns the player's map ID and normalized x, y on it, or nil where the client has
-- no map position (instances, for example).
function ns.GetPlayerMapPosition()
	local mapID = C_Map.GetBestMapForUnit("player")
	local position = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
	if position then
		local x, y = position:GetXY()
		return mapID, x, y
	end
end

-- Returns a map's width and height in yards, or nil when the client doesn't know them.
function ns.GetMapSize(mapID)
	local width, height = C_Map.GetMapWorldSize(mapID)
	if width and width > 0 and height > 0 then
		return width, height
	end
end

-- Modules register setup that needs ForeverProfessionsDB. It runs in TOC order once the
-- SavedVariables have loaded.
local initializers = {}

function ns.OnInitialize(func)
	table.insert(initializers, func)
end

EventUtil.ContinueOnAddOnLoaded(ADDON_NAME, function()
	ForeverProfessionsDB = ForeverProfessionsDB or {}
	ns.db = ForeverProfessionsDB
	ns.DB.Migrate(ns.db)

	for _, func in ipairs(initializers) do
		func()
	end
	ns.log("LOADED", "db version", ns.db.version)
end)
