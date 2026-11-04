local _, ns = ...

-- With the "Tooltip follows the cursor" option on, tooltips for things hovered in the world
-- (players, creatures, objects) sit below and to the right of the cursor instead of at the Edit
-- Mode tooltip position.
--
-- World hovers reach the tooltip as WORLD_CURSOR_TOOLTIP_UPDATE -> GameTooltip:SetWorldCursor,
-- which for Enum.WorldCursorAnchorType.Default calls GameTooltip_SetDefaultAnchor(GameTooltip,
-- UIParent) before filling the tooltip. Re-owning it here, before it is shown, means it never
-- appears at the default spot first. The minimap, XP bar and chat hyperlinks also anchor to
-- UIParent, so the mouse must also be over the world.
--
-- "ANCHOR_CURSOR_RIGHT" is a cursor anchor the client moves every frame itself (no OnUpdate), and
-- keeps the tooltip off the head and nameplate of the unit being hovered, unlike "ANCHOR_CURSOR",
-- which puts it above the pointer.

-- Clears the cursor arrow. Tuned at launch (launch check: ANCHOR).
local OFFSET_X, OFFSET_Y = 16, -16

local function IsMouseOverWorld()
	local focus = GetMouseFoci()[1]
	return focus == WorldFrame, focus
end

hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip, parent)
	if tooltip ~= GameTooltip or parent ~= UIParent or not ns.Options.Get("cursorAnchor") then
		return
	end
	local overWorld, focus = IsMouseOverWorld()
	if overWorld then
		tooltip:SetOwner(parent, "ANCHOR_CURSOR_RIGHT", OFFSET_X, OFFSET_Y)
		ns.dev:LogOnce("anchor", "ANCHOR", "world tooltip anchored to cursor")
	elseif ns.dev.enabled then
		local focusName = focus and focus:GetDebugName() or "nothing"
		ns.dev:LogChanged("anchor-skip", focusName, "ANCHOR", "kept default anchor for", focusName)
	end
end)
