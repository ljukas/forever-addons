local ADDON_NAME, ns = ...

-- The DoTs and HoTs that are tracked, per player class: base class spells and talents the
-- player casts on one target. Racials, poisons and procs, channels, and ground or area
-- effects are left out on purpose. Any other cast is ignored, however its description reads.
--
-- Keyed by the English spell name (C_Spell.GetSpellName), since Forever keeps ranks with
-- their own spell IDs and none of them are verified yet; Engine/Knowledge.lua records the IDs
-- seen in game. Names and wording are from Forever's beta spellbook (foreverchanges.pro).
-- The description is still read on every cast for the amount and duration, which change
-- with rank and Forever's tuning. The rest isn't in the description:
--   kind      "dot" (damage, UNIT_COMBAT WOUND) or "hot" (healing, UNIT_COMBAT HEAL)
--   school    school mask as UNIT_COMBAT reports it: 1 Physical (bleeds), 2 Holy, 4 Fire,
--             8 Nature, 16 Frost, 32 Shadow, 64 Arcane
--   interval  seconds between ticks. From Classic and unchecked in Forever: the intervals
--             Engine/Knowledge.lua observes (scripts/combat-knowledge.sh) confirm or correct them.
--   shape     uneven ticks, see SHAPES (default even)
--   finisher  amount and duration depend on combo points (per-point table in the description)
--   stacks    the most applications that add up (each recast adds one)
-- Spells marked "talent" are learned from a talent.

ns.Spells = {}

local PHYSICAL, HOLY, FIRE, NATURE, FROST, SHADOW, ARCANE = 1, 2, 4, 8, 16, 32, 64
ns.Spells.PHYSICAL = PHYSICAL

local spellsByClass = {
	WARRIOR = {
		["Rend"] = { kind = "dot", school = PHYSICAL, interval = 3 },
	},
	HUNTER = {
		["Serpent Sting"] = { kind = "dot", school = NATURE, interval = 3 },
		["Black Arrow"] = { kind = "dot", school = SHADOW, interval = 3 },
		["Lacerate"] = { kind = "dot", school = PHYSICAL, interval = 3 },
	},
	ROGUE = {
		["Garrote"] = { kind = "dot", school = PHYSICAL, interval = 3 },
		["Rupture"] = { kind = "dot", school = PHYSICAL, interval = 2, finisher = true },
	},
	PRIEST = {
		["Shadow Word: Pain"] = { kind = "dot", school = SHADOW, interval = 3 },
		["Holy Fire"] = { kind = "dot", school = HOLY, interval = 2 },
		["Renew"] = { kind = "hot", school = HOLY, interval = 3 },
	},
	SHAMAN = {
		["Flame Shock"] = { kind = "dot", school = FIRE, interval = 3 },
		["Riptide"] = { kind = "hot", school = NATURE, interval = 3 }, -- talent
	},
	MAGE = {
		["Fireball"] = { kind = "dot", school = FIRE, interval = 2 },
		["Pyroblast"] = { kind = "dot", school = FIRE, interval = 3 }, -- talent
		["Frostfire Bolt"] = { kind = "dot", school = FIRE + FROST, interval = 3 },
	},
	WARLOCK = {
		["Corruption"] = { kind = "dot", school = SHADOW, interval = 3 },
		["Bane of Agony"] = { kind = "dot", school = SHADOW, interval = 2, shape = "ramping" },
		["Immolate"] = { kind = "dot", school = FIRE, interval = 3 },
		["Siphon Life"] = { kind = "dot", school = SHADOW, interval = 3 }, -- talent
		["Wrack"] = { kind = "dot", school = SHADOW, interval = 1 }, -- talent
	},
	DRUID = {
		["Moonfire"] = { kind = "dot", school = ARCANE, interval = 3 },
		["Insect Swarm"] = { kind = "dot", school = NATURE, interval = 2 }, -- talent
		["Rake"] = { kind = "dot", school = PHYSICAL, interval = 3 },
		["Rip"] = { kind = "dot", school = PHYSICAL, interval = 2, finisher = true },
		["Pounce"] = { kind = "dot", school = PHYSICAL, interval = 3 },
		["Lacerate"] = { kind = "dot", school = PHYSICAL, interval = 3, stacks = 5 },
		["Rejuvenation"] = { kind = "hot", school = NATURE, interval = 3 },
		["Regrowth"] = { kind = "hot", school = NATURE, interval = 3 },
		["Wild Growth"] = { kind = "hot", school = NATURE, interval = 1, shape = "decaying" }, -- talent
	},
}

-- Per-tick weights for uneven effects. They average 1, so a tick is the average tick
-- times its weight.
local SHAPES = {
	-- Bane of Agony: the first third of the ticks at half the average, the middle third at
	-- the average, the last third at one and a half (as Classic's Curse of Agony; DoesItDie
	-- confirmed that in game).
	ramping = function(index, count)
		return math.ceil(index * 3 / count) * 0.5
	end,
	-- Wild Growth: "applied quickly at first, and slows down". Assumed linear from 1.5x to
	-- 0.5x of the average until the observed ticks say otherwise.
	decaying = function(index, count)
		if count <= 1 then
			return 1
		end
		return 1 + 0.5 * (count + 1 - 2 * index) / (count - 1)
	end,
}

-- Returns the entry for a spell of the player's class, or nil if it isn't tracked.
function ns.Spells.Lookup(name, playerClass)
	local spells = spellsByClass[playerClass]
	return spells and spells[name]
end

-- Weight of tick index (1-based) out of count ticks.
function ns.Spells.TickWeight(entry, index, count)
	local shape = entry.shape and SHAPES[entry.shape]
	return shape and shape(index, count) or 1
end
