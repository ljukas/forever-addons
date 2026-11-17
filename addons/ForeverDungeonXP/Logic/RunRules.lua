local _, ns = ...

-- Decides whether entering a dungeon continues its open run or starts a new one. Pure: no events,
-- no client state. The caller guarantees no argument is secret.

ns.RunRules = {}

-- Longer than this since the open run's last kill, and a visit starts a new run.
ns.RunRules.MAX_GAP = 30 * 60

-- The instance copy number in a creature's GUID: the zoneUID field of
-- "Creature-0-<server>-<instanceID>-<zoneUID>-<npcID>-<spawnUID>". Two copies of the same dungeon
-- differ in it; one copy keeps it until it is reset. Nil for any other GUID.
--   "Creature-0-4460-36-12345-634-00001A2B3C" -> "12345"
--   "Vehicle-0-4460-36-777-40000-0000112233"  -> "777"
--   "Player-4460-00ABCDEF"                    -> nil
--   "Pet-0-4460-36-12345-417-0100000001"      -> nil (a player's pet is not the dungeon's)
function ns.RunRules.Copy(guid)
	local kind, _, _, _, zoneUID = strsplit("-", guid)
	if (kind == "Creature" or kind == "Vehicle") and zoneUID and zoneUID ~= "" then
		return zoneUID
	end
end

-- open is the dungeon's open run ({ copy, died, lastKill }) or nil. entry describes the visit:
-- { copy = the copy number if already read, reload = true when entering by /reload or login,
-- now = GetServerTime() }. Returns "continue" or "new", and the reason:
--   no open run                                   -> "new", "first"
--   both copy numbers known and equal             -> "continue", "copy"
--   both copy numbers known and different         -> "new", "copy"
--   entered by /reload or login                   -> "continue", "reload"
--   last kill more than MAX_GAP ago               -> "new", "gap"
--   the player died since the last kill           -> "continue", "died" (a corpse run)
--   otherwise (walked out alive and back in)      -> "new", "alive"
function ns.RunRules.Decide(open, entry)
	if not open then
		return "new", "first"
	end
	if open.copy and entry.copy then
		return open.copy == entry.copy and "continue" or "new", "copy"
	end
	if entry.reload then
		return "continue", "reload"
	end
	if open.lastKill and entry.now - open.lastKill > ns.RunRules.MAX_GAP then
		return "new", "gap"
	end
	if open.died then
		return "continue", "died"
	end
	return "new", "alive"
end
