local ADDON_NAME, ns = ...

-- The API other addons use, after listing ForeverProfessions under ## Dependencies (as
-- ForeverMap does). Call it from the dependent addon's own ADDON_LOADED on, by when
-- ForeverProfessionsDB has loaded.
ForeverProfessions = {}

-- Calls func(owner, ...) on an event from Core.lua: NodesChanged(mapID) or
-- SkillsChanged(). Same as CallbackRegistryMixin:RegisterCallback.
function ForeverProfessions.RegisterCallback(event, func, owner)
	return ns.callbacks:RegisterCallback(event, func, owner)
end

-- Calls func(name, index, x, y, count) for every gathered node of the profession
-- ("herbalism", "mining") on the zone map: x, y normalized on that map, count the times it
-- has been gathered. index is unique per name.
ForeverProfessions.ForEachNode = ns.DB.ForEachNode

-- Returns true if name ("Copper Vein") is a known gathering node.
function ForeverProfessions.IsNode(name)
	return ns.Professions.GetNode(name) ~= nil
end

-- Returns the node's required skill, the player's effective rank (nil if not learned),
-- the localized profession name and whether the player is too low to gather it, or nil
-- for unknown node names.
ForeverProfessions.GetRequirement = ns.Professions.GetRequirement

-- Returns true if the player's skill is too low to gather the node.
ForeverProfessions.IsTooLow = ns.Professions.IsTooLow
