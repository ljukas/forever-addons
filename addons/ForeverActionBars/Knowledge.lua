local _, ns = ...

-- Evidence on how the pet bar measures range, kept until it settles whether pet range is
-- measured from the pet (then the pet bar can get the wash) or from the player. Trace lines go
-- through ns.log with tag RANGE. Aggregates are kept across sessions in
-- ForeverDevDB.observed.ForeverActionBars (scripts/observed.sh ForeverActionBars) until
-- /fdev forget ForeverActionBars:
--   pet[spellID] = { name, lastSeen, results = { ["<result>/<player>"] = count } }
--     result: what the pet bar reported: "in", "out", "nocheck" (no range check) or "secret"
--     player: whether the player is in melee range of the target, from
--             C_Spell.IsSpellInRange(AUTO_ATTACK, "target"): "melee", "far", "unknown" (nil)
--             or "secret"
-- Counts are transitions per button, not the pet bar's ~0.2 s polls. A pet melee ability
-- counted "in/far" means the pet bar measures from the pet.

-- Players without ForeverDev record nothing.
if not ns.dev.enabled then
	ns.Knowledge = ns.Inert()
	return
end
ns.Knowledge = {}

local AUTO_ATTACK = 6603
local PET = { results = {} }

-- button -> the last "<result>/<player>" recorded for it.
local lastKey = setmetatable({}, { __mode = "k" })

local function PetResult(checksRange, inRange)
	if issecretvalue(checksRange) or issecretvalue(inRange) then
		return "secret"
	elseif not checksRange then
		return "nocheck"
	end
	return inRange and "in" or "out"
end

local function PlayerMelee()
	local inMelee = C_Spell.IsSpellInRange(AUTO_ATTACK, "target")
	if issecretvalue(inMelee) then
		return "secret"
	elseif inMelee == nil then
		return "unknown"
	end
	return inMelee and "melee" or "far"
end

-- The pet bar reported a range result for one of its buttons.
function ns.Knowledge.PetRange(button, checksRange, inRange)
	local name, _, _, _, _, _, spellID = GetPetActionInfo(button:GetID())
	-- Tokens (Attack, Follow, stances) may report 0 rather than nil.
	if spellID == nil or issecretvalue(spellID) or spellID == 0 then
		return
	end
	local key = PetResult(checksRange, inRange) .. "/" .. PlayerMelee()
	if lastKey[button] == key then
		return
	end
	lastKey[button] = key

	local pet = ns.dev:Observed(PET, "pet", spellID)
	if not issecretvalue(name) then
		pet.name = name
	end
	pet.lastSeen = time()
	ForeverDev.Count(pet.results, key)
	ns.log("RANGE", "pet", spellID, name, key)
end
