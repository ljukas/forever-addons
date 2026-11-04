local _, ns = ...

-- With the "Tooltip follows the cursor" option on, tooltips for things hovered in the world
-- (players, creatures, objects) follow the cursor instead of sitting at the Edit Mode tooltip
-- position.
--
-- World hovers reach the tooltip as WORLD_CURSOR_TOOLTIP_UPDATE -> GameTooltip:SetWorldCursor,
-- which for Enum.WorldCursorAnchorType.Default calls GameTooltip_SetDefaultAnchor(GameTooltip,
-- UIParent) before filling the tooltip. Re-anchoring here, before it is shown, means it never
-- appears at the default spot first. The minimap, XP bar and chat hyperlinks also anchor to
-- UIParent, so the mouse must also be over the world.
--
-- SetAnchorType, not SetOwner: SetOwner clears the tooltip, which runs GameTooltip's
-- OnTooltipCleared script (it writes self.insertedFrames) under this hook's taint, and Blizzard's
-- secure tooltip build reads that field later. SetAnchorType only changes the anchor; Blizzard
-- uses it on GameTooltip itself (Blizzard_FrameXML/Camelot/EquipmentFlyout.lua).
--
-- "ANCHOR_CURSOR_RIGHT" is a cursor anchor the client moves every frame itself (no OnUpdate).
-- Which way the tooltip grows from the pointer, and so whether it covers the hovered unit's head,
-- isn't in the source: launch check ANCHOR.

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
		tooltip:ClearAllPoints()
		tooltip:SetAnchorType("ANCHOR_CURSOR_RIGHT", OFFSET_X, OFFSET_Y)
		ns.dev:LogOnce("anchor", "ANCHOR", "world tooltip anchored to cursor")
	elseif ns.dev.enabled then
		local focusName = focus and focus:GetDebugName() or "nothing"
		ns.dev:LogChanged("anchor-skip", focusName, "ANCHOR", "kept default anchor for", focusName)
	end
end)
