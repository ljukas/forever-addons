local ADDON_NAME, ns = ...

-- The player frame's health and mana bars are protected frames (they inherit
-- SecureFrameParentPropagationTemplate), and so is anything they are anchored into: addon code may
-- only re-parent, move or resize them out of combat. Every layout change goes through Request, which
-- runs it now, or once combat ends.
ns.Layout = {}

-- Requests waiting for combat to end, by name; a later request replaces an earlier one of the same
-- name, so each runs once with the latest state.
local pending = {}
local order = {}

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(self)
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	local names = order
	order = {}
	for _, name in ipairs(names) do
		local func = pending[name]
		pending[name] = nil
		ns.log("APPLY", name, "after combat")
		func()
	end
end)

-- Runs func now when out of combat, otherwise once PLAYER_REGEN_ENABLED fires.
function ns.Layout.Request(name, func)
	if not InCombatLockdown() then
		func()
		return
	end
	if not pending[name] then
		table.insert(order, name)
	end
	pending[name] = func
	events:RegisterEvent("PLAYER_REGEN_ENABLED")
	ns.log("DEFER", name)
end
