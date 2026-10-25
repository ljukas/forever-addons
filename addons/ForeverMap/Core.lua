local ADDON_NAME, ns = ...

-- Dev-only logging: lands in ForeverDev's on-disk log (scripts/devlog.sh) when
-- ForeverDev is loaded, and is a no-op for players.
function ns.log(...)
	if ForeverDev_Log then
		ForeverDev_Log(ADDON_NAME, ...)
	end
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
--   OptionChanged()     a ForeverMapDB.settings value changed
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

-- Modules register setup that needs ForeverMapDB. It runs in TOC order once the
-- SavedVariables have loaded.
local initializers = {}

function ns.OnInitialize(func)
	table.insert(initializers, func)
end

EventUtil.ContinueOnAddOnLoaded(ADDON_NAME, function()
	ForeverMapDB = ForeverMapDB or {}
	ns.db = ForeverMapDB
	ns.DB.Migrate(ns.db)

	for _, func in ipairs(initializers) do
		func()
	end
	ns.log("loaded, db version", ns.db.version)
end)
