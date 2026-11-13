local _, ns = ...

-- Records who the run's kills were made with: the party members present when a kill is counted
-- (run.party, Database.lua). Party members' names and classes stay readable in a dungeon (the
-- API docs make them secret only for units outside the group); everything is still checked
-- with issecretvalue. The client has no talents to inspect on Forever, so there is no spec;
-- the group role is kept when one is assigned.
-- Unverified in game: all of it, until the first run. The PARTY log line shows each member.

ns.Party = {}

local MAX_PARTY_MEMBERS = 4
local ROLES = { TANK = true, HEALER = true, DAMAGER = true }

local function Secret(...)
	for index = 1, select("#", ...) do
		if issecretvalue((select(index, ...))) then
			return true
		end
	end
	return false
end

-- Tracker.lua calls this for each kill it counts.
function ns.Party.OnKill(run)
	for index = 1, MAX_PARTY_MEMBERS do
		local unit = "party" .. index
		local exists = UnitExists(unit)
		if not issecretvalue(exists) and exists then
			local name, realm = UnitName(unit)
			local _, class = UnitClass(unit)
			local level = UnitLevel(unit)
			local role = UnitGroupRolesAssigned(unit)
			if Secret(name, realm, class, level, role) then
				ns.dev:LogOnce("party secret", "PARTY", "a party member's details are secret")
			elseif
				type(name) == "string"
				and name ~= ""
				and name ~= _G["UNKNOWNOBJECT"]
				and type(class) == "string"
			then
				-- A member from another realm carries it; one from the player's own has none.
				local key = (realm and realm ~= "") and (name .. "-" .. realm) or name
				ns.DB.AddPartyMember(run, key, class, level, ROLES[role] and role or nil)
				if ns.dev.enabled then
					ns.dev:LogChanged("party " .. key, level, "PARTY", key, class, level, role)
				end
			end
		end
	end
end
