local ADDON_NAME, ns = ...

-- Classic (1.12) gathering nodes by enUS name: the profession that gathers them, the skill
-- needed to gather them, and the item they give, whose icon marks the node on the maps
-- (UI/Pin.lua). Taken from Classic Era data; not yet checked against Forever. The item IDs are a
-- deliberate copy of ForeverMinimap's Data/Nodes.lua (the addons don't depend on each other,
-- ADR 0001), whose Dev/NodeItems.lua probe checks them in game.
ns.GatherNodes = {
	-- Mining
	["Copper Vein"] = { profession = "mining", skill = 1, item = 2770 }, -- Copper Ore
	["Poor Copper Vein"] = { profession = "mining", skill = 1, item = 2770 }, -- Forever-only; skill assumed from Copper Vein
	["Tin Vein"] = { profession = "mining", skill = 65, item = 2771 }, -- Tin Ore
	["Incendicite Mineral Vein"] = { profession = "mining", skill = 65, item = 3340 }, -- Incendicite Ore
	["Silver Vein"] = { profession = "mining", skill = 75, item = 2775 }, -- Silver Ore
	["Ooze Covered Silver Vein"] = { profession = "mining", skill = 75, item = 2775 },
	["Lesser Bloodstone Deposit"] = { profession = "mining", skill = 75, item = 4278 }, -- Lesser Bloodstone Ore
	["Iron Deposit"] = { profession = "mining", skill = 125, item = 2772 }, -- Iron Ore
	["Indurium Mineral Vein"] = { profession = "mining", skill = 150, item = 5833 }, -- Indurium Ore
	["Gold Vein"] = { profession = "mining", skill = 155, item = 2776 }, -- Gold Ore
	["Ooze Covered Gold Vein"] = { profession = "mining", skill = 155, item = 2776 },
	["Mithril Deposit"] = { profession = "mining", skill = 175, item = 3858 }, -- Mithril Ore
	["Ooze Covered Mithril Deposit"] = { profession = "mining", skill = 175, item = 3858 },
	["Truesilver Deposit"] = { profession = "mining", skill = 230, item = 7911 }, -- Truesilver Ore
	["Ooze Covered Truesilver Deposit"] = { profession = "mining", skill = 230, item = 7911 },
	["Dark Iron Deposit"] = { profession = "mining", skill = 230, item = 11370 }, -- Dark Iron Ore
	["Small Thorium Vein"] = { profession = "mining", skill = 245, item = 10620 }, -- Thorium Ore
	["Ooze Covered Thorium Vein"] = { profession = "mining", skill = 245, item = 10620 },
	["Rich Thorium Vein"] = { profession = "mining", skill = 275, item = 10620 },
	["Ooze Covered Rich Thorium Vein"] = { profession = "mining", skill = 275, item = 10620 },
	["Small Obsidian Chunk"] = { profession = "mining", skill = 305, item = 22202 }, -- Small Obsidian Shard
	["Large Obsidian Chunk"] = { profession = "mining", skill = 305, item = 22203 }, -- Large Obsidian Shard

	-- Herbalism: each herb is named after its node
	["Peacebloom"] = { profession = "herbalism", skill = 1, item = 2447 },
	["Silverleaf"] = { profession = "herbalism", skill = 1, item = 765 },
	["Earthroot"] = { profession = "herbalism", skill = 15, item = 2449 },
	["Mageroyal"] = { profession = "herbalism", skill = 50, item = 785 },
	["Briarthorn"] = { profession = "herbalism", skill = 70, item = 2450 },
	["Stranglekelp"] = { profession = "herbalism", skill = 85, item = 3820 },
	["Bruiseweed"] = { profession = "herbalism", skill = 100, item = 2453 },
	["Wild Steelbloom"] = { profession = "herbalism", skill = 115, item = 3355 },
	["Grave Moss"] = { profession = "herbalism", skill = 120, item = 3369 },
	["Kingsblood"] = { profession = "herbalism", skill = 125, item = 3356 },
	["Liferoot"] = { profession = "herbalism", skill = 150, item = 3357 },
	["Fadeleaf"] = { profession = "herbalism", skill = 160, item = 3818 },
	["Goldthorn"] = { profession = "herbalism", skill = 170, item = 3821 },
	["Khadgar's Whisker"] = { profession = "herbalism", skill = 185, item = 3358 },
	["Wintersbite"] = { profession = "herbalism", skill = 195, item = 3819 },
	["Firebloom"] = { profession = "herbalism", skill = 205, item = 4625 },
	["Purple Lotus"] = { profession = "herbalism", skill = 210, item = 8831 },
	["Arthas' Tears"] = { profession = "herbalism", skill = 220, item = 8836 },
	["Sungrass"] = { profession = "herbalism", skill = 230, item = 8838 },
	["Blindweed"] = { profession = "herbalism", skill = 235, item = 8839 },
	["Ghost Mushroom"] = { profession = "herbalism", skill = 245, item = 8845 },
	["Gromsblood"] = { profession = "herbalism", skill = 250, item = 8846 },
	["Golden Sansam"] = { profession = "herbalism", skill = 260, item = 13464 },
	["Dreamfoil"] = { profession = "herbalism", skill = 270, item = 13463 },
	["Mountain Silversage"] = { profession = "herbalism", skill = 280, item = 13465 },
	["Plaguebloom"] = { profession = "herbalism", skill = 285, item = 13466 },
	["Icecap"] = { profession = "herbalism", skill = 290, item = 13467 },
	["Black Lotus"] = { profession = "herbalism", skill = 300, item = 13468 },
}
