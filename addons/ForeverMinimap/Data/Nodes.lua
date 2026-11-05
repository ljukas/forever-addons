local ADDON_NAME, ns = ...

-- The herb and ore nodes Find Herbs and Find Minerals show, by enUS name: which tracking icon
-- each gets. Only names in this list get an icon, so party members, NPCs and quest objects under
-- a minimap probe are left alone. A deliberate copy of the names in ForeverProfessions'
-- Data/GatherNodes.lua: the addons don't depend on each other (ADR 0001).
ns.Nodes = {
	-- Mining
	["Copper Vein"] = "ore",
	["Poor Copper Vein"] = "ore", -- Forever-only (seen in game 2026-11-05)
	["Tin Vein"] = "ore",
	["Incendicite Mineral Vein"] = "ore",
	["Silver Vein"] = "ore",
	["Ooze Covered Silver Vein"] = "ore",
	["Lesser Bloodstone Deposit"] = "ore",
	["Iron Deposit"] = "ore",
	["Indurium Mineral Vein"] = "ore",
	["Gold Vein"] = "ore",
	["Ooze Covered Gold Vein"] = "ore",
	["Mithril Deposit"] = "ore",
	["Ooze Covered Mithril Deposit"] = "ore",
	["Truesilver Deposit"] = "ore",
	["Ooze Covered Truesilver Deposit"] = "ore",
	["Dark Iron Deposit"] = "ore",
	["Small Thorium Vein"] = "ore",
	["Ooze Covered Thorium Vein"] = "ore",
	["Rich Thorium Vein"] = "ore",
	["Ooze Covered Rich Thorium Vein"] = "ore",
	["Small Obsidian Chunk"] = "ore",
	["Large Obsidian Chunk"] = "ore",

	-- Herbalism
	["Peacebloom"] = "herb",
	["Silverleaf"] = "herb",
	["Earthroot"] = "herb",
	["Mageroyal"] = "herb",
	["Briarthorn"] = "herb",
	["Stranglekelp"] = "herb",
	["Bruiseweed"] = "herb",
	["Wild Steelbloom"] = "herb",
	["Grave Moss"] = "herb",
	["Kingsblood"] = "herb",
	["Liferoot"] = "herb",
	["Fadeleaf"] = "herb",
	["Goldthorn"] = "herb",
	["Khadgar's Whisker"] = "herb",
	["Wintersbite"] = "herb",
	["Firebloom"] = "herb",
	["Purple Lotus"] = "herb",
	["Arthas' Tears"] = "herb",
	["Sungrass"] = "herb",
	["Blindweed"] = "herb",
	["Ghost Mushroom"] = "herb",
	["Gromsblood"] = "herb",
	["Golden Sansam"] = "herb",
	["Dreamfoil"] = "herb",
	["Mountain Silversage"] = "herb",
	["Plaguebloom"] = "herb",
	["Icecap"] = "herb",
	["Black Lotus"] = "herb",
}

-- The item each node gives, by the same names: its icon marks the node on the minimap
-- (UI/NodeIcons.lua). From Classic Era item IDs; Dev/NodeItems.lua logs each one's name in game
-- to check them. A name missing here, or an item whose icon the client can't give, keeps the
-- herb or ore tracking icon.
ns.NodeItems = {
	-- Mining
	["Copper Vein"] = 2770, -- Copper Ore
	["Poor Copper Vein"] = 2770,
	["Tin Vein"] = 2771, -- Tin Ore
	["Incendicite Mineral Vein"] = 3340, -- Incendicite Ore
	["Silver Vein"] = 2775, -- Silver Ore
	["Ooze Covered Silver Vein"] = 2775,
	["Lesser Bloodstone Deposit"] = 4278, -- Lesser Bloodstone Ore
	["Iron Deposit"] = 2772, -- Iron Ore
	["Indurium Mineral Vein"] = 5833, -- Indurium Ore
	["Gold Vein"] = 2776, -- Gold Ore
	["Ooze Covered Gold Vein"] = 2776,
	["Mithril Deposit"] = 3858, -- Mithril Ore
	["Ooze Covered Mithril Deposit"] = 3858,
	["Truesilver Deposit"] = 7911, -- Truesilver Ore
	["Ooze Covered Truesilver Deposit"] = 7911,
	["Dark Iron Deposit"] = 11370, -- Dark Iron Ore
	["Small Thorium Vein"] = 10620, -- Thorium Ore
	["Ooze Covered Thorium Vein"] = 10620,
	["Rich Thorium Vein"] = 10620,
	["Ooze Covered Rich Thorium Vein"] = 10620,
	["Small Obsidian Chunk"] = 22202, -- Small Obsidian Shard
	["Large Obsidian Chunk"] = 22203, -- Large Obsidian Shard

	-- Herbalism: each herb is named after its node
	["Peacebloom"] = 2447,
	["Silverleaf"] = 765,
	["Earthroot"] = 2449,
	["Mageroyal"] = 785,
	["Briarthorn"] = 2450,
	["Stranglekelp"] = 3820,
	["Bruiseweed"] = 2453,
	["Wild Steelbloom"] = 3355,
	["Grave Moss"] = 3369,
	["Kingsblood"] = 3356,
	["Liferoot"] = 3357,
	["Fadeleaf"] = 3818,
	["Goldthorn"] = 3821,
	["Khadgar's Whisker"] = 3358,
	["Wintersbite"] = 3819,
	["Firebloom"] = 4625,
	["Purple Lotus"] = 8831,
	["Arthas' Tears"] = 8836,
	["Sungrass"] = 8838,
	["Blindweed"] = 8839,
	["Ghost Mushroom"] = 8845,
	["Gromsblood"] = 8846,
	["Golden Sansam"] = 13464,
	["Dreamfoil"] = 13463,
	["Mountain Silversage"] = 13465,
	["Plaguebloom"] = 13466,
	["Icecap"] = 13467,
	["Black Lotus"] = 13468,
}
