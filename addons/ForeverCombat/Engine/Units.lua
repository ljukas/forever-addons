local ADDON_NAME, ns = ...

-- Mob keys: tracked effects are stored per mob, under
--   the GUID                where it's readable (players, and creatures in the open world),
--   "plate:nameplateN"     when it's secret but the mob has a nameplate (the token stays the
--                           mob's until NAME_PLATE_UNIT_REMOVED), or
--   "unit:target"/"unit:focus"  otherwise, which only lasts until that unit changes.
-- Creature GUIDs are secret in instances (DoesItDie, in a Forever dungeon), so tab-dotting a
-- pack there needs enemy nameplates on.
ns.Units = {}

local plates = {}

function ns.Units.AddPlate(token)
	plates[token] = true
end

function ns.Units.RemovePlate(token)
	plates[token] = nil
end

local function IsSame(unit, other)
	local same = UnitIsUnit(unit, other)
	return not issecretvalue(same) and same
end

-- Returns the mob key for a unit token and how it was found ("guid", "plate" or "unit"),
-- or nil when the unit doesn't exist.
function ns.Units.Key(unit)
	if not UnitExists(unit) then
		return nil
	end
	local guid = UnitGUID(unit)
	if guid and not issecretvalue(guid) then
		return guid, "guid"
	end
	if plates[unit] then
		return "plate:" .. unit, "plate"
	end
	for token in pairs(plates) do
		if IsSame(unit, token) then
			return "plate:" .. token, "plate"
		end
	end
	return "unit:" .. unit, "unit"
end

-- The unit a cast went on. UNIT_SPELLCAST_SENT names the cast's target; it's matched against
-- the units it could be, for the target the player tabbed away from or a [@focus] macro.
-- Falls back to the target (DoTs) or to the target if friendly, else the player (HoTs, which
-- the client casts on the player when the target can't be healed).
local CANDIDATES = {
	dot = { "target", "focus", "softenemy", "mouseover" },
	hot = { "target", "focus", "mouseover", "player" },
}

-- Whether a unit takes effects of that kind: DoTs on enemies, HoTs on everyone else.
function ns.Units.Fits(unit, kind)
	return UnitExists(unit) and UnitCanAttack("player", unit) == (kind == "dot")
end

-- Whether the unit is the one named. Players from other realms are named "Name-Realm".
local function IsNamed(unit, targetName)
	local name, realm = UnitName(unit)
	if not name or issecretvalue(name) then
		return false
	end
	if name == targetName then
		return true
	end
	return realm ~= nil and not issecretvalue(realm) and name .. "-" .. realm == targetName
end

function ns.Units.CastUnit(targetName, kind)
	if targetName and not issecretvalue(targetName) and targetName ~= "" then
		for _, unit in ipairs(CANDIDATES[kind]) do
			if IsNamed(unit, targetName) and ns.Units.Fits(unit, kind) then
				return unit
			end
		end
	end
	if ns.Units.Fits("target", kind) then
		return "target"
	end
	return kind == "hot" and "player" or nil
end
