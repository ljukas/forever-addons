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

-- enUS only for now.
ns.L = {
	HERBALISM = "Herbalism",
	MINING = "Mining",
}

-- Events for the modules and, through API.lua, for other addons. Callbacks are called as
-- func(owner, ...).
--   NodesChanged(mapID) a node was recorded or gathered again on that map
--   SkillsChanged()     the player's profession ranks may have changed
ns.callbacks = CreateFromMixins(CallbackRegistryMixin)
ns.callbacks:OnLoad()
ns.callbacks:GenerateCallbackEvents({ "NodesChanged", "SkillsChanged" })

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
