local ADDON_NAME, ns = ...

-- Records a node when the player finishes gathering it. UNIT_SPELLCAST_SENT carries the
-- name of the object being cast on ("Copper Vein"), so a cast on a known node name is a
-- gather, without depending on the gathering spell IDs. The node is stored at the
-- player's position when the cast started, which is within a few yards of the node.

-- The gather in progress: { castGUID, name, mapID, x, y }.
local pending

local function IsPending(castGUID)
	return pending ~= nil and not issecretvalue(castGUID) and castGUID == pending.castGUID
end

local handlers = {}

function handlers.UNIT_SPELLCAST_SENT(_, target, castGUID, spellID)
	pending = nil
	if issecretvalue(target) or issecretvalue(castGUID) or not ns.Layers.GetNode(target) then
		return
	end

	local mapID, x, y = ns.GetPlayerMapPosition()
	-- Logged so the gathering spell IDs can be checked at launch.
	ns.log("gather started", target, "spellID", spellID, "map", mapID)
	if mapID then
		pending = { castGUID = castGUID, name = target, mapID = mapID, x = x, y = y }
	end
end

function handlers.UNIT_SPELLCAST_SUCCEEDED(_, castGUID, spellID)
	if not IsPending(castGUID) then
		return
	end
	local gather = pending
	pending = nil

	local isNew = ns.DB.Add(gather.mapID, gather.name, gather.x, gather.y)
	ns.log(isNew and "recorded" or "gathered again", gather.name, gather.mapID, gather.x, gather.y, "spellID", spellID)
end

function handlers.UNIT_SPELLCAST_FAILED(_, castGUID)
	if IsPending(castGUID) then
		pending = nil
	end
end
handlers.UNIT_SPELLCAST_INTERRUPTED = handlers.UNIT_SPELLCAST_FAILED

ns.OnInitialize(function()
	local frame = CreateFrame("Frame")
	for event in pairs(handlers) do
		frame:RegisterUnitEvent(event, "player")
	end
	frame:SetScript("OnEvent", function(_, event, ...)
		handlers[event](...)
	end)
end)
