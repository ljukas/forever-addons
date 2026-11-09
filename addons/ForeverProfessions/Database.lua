local ADDON_NAME, ns = ...

-- ForeverProfessionsDB layout (account-wide):
--   version  = schema version, see migrations below
--   settings = { [key] = boolean }, owned by Options.lua
--   nodes    = { [uiMapID] = { [profession] = { [nodeName] = { x1, y1, count1, x2, y2, count2, ... } } } }
-- profession is the node's key in Professions.lua. x, y are normalized positions on that zone
-- map, rounded to 4 decimals. count is how many times the node has been gathered.
--   crafts   = { [characterKey] = { [recipeID] = { made, gray, levels = { [skillRank] = row } } } },
--              written by Sources/CraftRecorder.lua
-- characterKey is "Name-Realm". made counts the items the recipe produced; gray is the recipe's
-- maxTrivialLevel, the rank it turns gray at. skillRank is the profession's base skill when the
-- craft finished, before its own skill-up (not counting racial or item bonuses), and row is
-- { attempts, skillUps, difficulty, capped }: completed casts at that rank, the skill points
-- they gave, the recipe's Enum.TradeskillRelativeDifficulty there, and casts made at the skill
-- cap, which can't give a point and so aren't attempts. Only this file knows the flat layouts.

ns.DB = {}

local DB_VERSION = 2
local STRIDE = 3

-- Indexes into a crafts row.
local ATTEMPTS, SKILL_UPS, DIFFICULTY, CAPPED = 1, 2, 3, 4

-- A gather within this distance of a known node of the same name is the same node.
local DEDUPE_YARDS = 10
-- Used for the dedupe distance when the client doesn't know a map's size.
local FALLBACK_MAP_YARDS = 1000

local migrations = {
	[1] = function(db)
		db.settings = db.settings or {}
		db.nodes = db.nodes or {}
	end,
	[2] = function(db)
		db.crafts = db.crafts or {}
	end,
}

function ns.DB.Migrate(db)
	-- Data from a newer version of the addon is left alone rather than downgraded.
	for version = (db.version or 0) + 1, DB_VERSION do
		migrations[version](db)
		db.version = version
	end
end

-- Calls func(name, index, x, y, count) for every node of the profession recorded on the
-- map. index is unique per name.
function ns.DB.ForEachNode(mapID, profession, func)
	local map = ns.db.nodes[mapID]
	local nodes = map and map[profession]
	if not nodes then
		return
	end
	for name, nodeData in pairs(nodes) do
		for i = 1, #nodeData, STRIDE do
			func(name, i, nodeData[i], nodeData[i + 1], nodeData[i + 2])
		end
	end
end

local function Round(value)
	return math.floor(value * 10000 + 0.5) / 10000
end

-- Records a gather of a known node. Returns true if the node was new, false if it was
-- an existing node gathered again.
function ns.DB.Add(mapID, name, x, y)
	local node = ns.Professions.GetNode(name)
	x, y = Round(x), Round(y)

	local width, height = ns.GetMapSize(mapID)
	width = width or FALLBACK_MAP_YARDS
	height = height or FALLBACK_MAP_YARDS

	local map = ns.db.nodes[mapID] or {}
	ns.db.nodes[mapID] = map
	local nodes = map[node.profession] or {}
	map[node.profession] = nodes
	local nodeData = nodes[name] or {}
	nodes[name] = nodeData

	local isNew = true
	for i = 1, #nodeData, STRIDE do
		local dx = (nodeData[i] - x) * width
		local dy = (nodeData[i + 1] - y) * height
		if dx * dx + dy * dy <= DEDUPE_YARDS * DEDUPE_YARDS then
			nodeData[i + 2] = nodeData[i + 2] + 1
			isNew = false
			break
		end
	end
	if isNew then
		table.insert(nodeData, x)
		table.insert(nodeData, y)
		table.insert(nodeData, 1)
	end

	ns.callbacks:TriggerEvent("NodesChanged", mapID)
	return isNew
end

local function GetRecipe(characterKey, recipeID)
	local character = ns.db.crafts[characterKey] or {}
	ns.db.crafts[characterKey] = character
	local recipe = character[recipeID]
	if not recipe then
		recipe = { made = 0, levels = {} }
		character[recipeID] = recipe
	end
	return recipe
end

-- Records a completed craft started at skillRank, with the recipe's difficulty and gray level
-- at that moment. A capped craft (made at the skill cap) is counted apart from the attempts.
-- Rows are only created here, so every row has its difficulty.
function ns.DB.RecordAttempt(characterKey, recipeID, skillRank, difficulty, gray, capped)
	local recipe = GetRecipe(characterKey, recipeID)
	if gray then
		recipe.gray = gray
	end
	local row = recipe.levels[skillRank]
	if not row then
		row = { 0, 0, difficulty, 0 }
		recipe.levels[skillRank] = row
	end
	if capped then
		row[CAPPED] = row[CAPPED] + 1
	else
		row[ATTEMPTS] = row[ATTEMPTS] + 1
	end
	row[DIFFICULTY] = difficulty
	ns.callbacks:TriggerEvent("CraftsChanged", recipeID)
end

-- Adds items a craft of the recipe produced.
function ns.DB.AddMade(characterKey, recipeID, quantity)
	local recipe = GetRecipe(characterKey, recipeID)
	recipe.made = recipe.made + quantity
end

-- Credits skill points to the craft of the recipe started at skillRank, which RecordAttempt
-- has recorded. Returns false, and records nothing, when there is no such craft.
function ns.DB.RecordSkillUp(characterKey, recipeID, skillRank, points)
	local character = ns.db.crafts[characterKey]
	local recipe = character and character[recipeID]
	local row = recipe and recipe.levels[skillRank]
	if not row then
		return false
	end
	row[SKILL_UPS] = row[SKILL_UPS] + points
	ns.callbacks:TriggerEvent("CraftsChanged", recipeID)
	return true
end

-- Returns how many times the character crafted the recipe (capped crafts included) and the
-- skill points those crafts gave; 0, 0 when it never has.
function ns.DB.GetCraftTotals(characterKey, recipeID)
	local character = ns.db.crafts[characterKey]
	local recipe = character and character[recipeID]
	local crafts, skillUps = 0, 0
	if recipe then
		for _, row in pairs(recipe.levels) do
			crafts = crafts + row[ATTEMPTS] + row[CAPPED]
			skillUps = skillUps + row[SKILL_UPS]
		end
	end
	return crafts, skillUps
end

-- Returns every character's rows of the recipe as a list of
-- { rank, attempts, skillUps, difficulty }, for the skill-up odds (Odds.lua). Capped crafts
-- aren't attempts and so aren't included.
function ns.DB.GetCraftRows(recipeID)
	local rows = {}
	for _, character in pairs(ns.db.crafts) do
		local recipe = character[recipeID]
		if recipe then
			for rank, row in pairs(recipe.levels) do
				table.insert(rows, {
					rank = rank,
					attempts = row[ATTEMPTS],
					skillUps = row[SKILL_UPS],
					difficulty = row[DIFFICULTY],
				})
			end
		end
	end
	return rows
end
