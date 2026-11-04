local _, ns = ...

-- With the "Tooltip follows the cursor" option on, tooltips for things hovered in the world
-- (players, creatures, objects) follow the cursor instead of sitting at the Edit Mode tooltip
-- position, growing in the direction chosen in the options (Logic/CursorAnchor.lua).
--
-- World hovers reach the tooltip as WORLD_CURSOR_TOOLTIP_UPDATE -> GameTooltip:SetWorldCursor,
-- which for Enum.WorldCursorAnchorType.Default calls GameTooltip_SetDefaultAnchor(GameTooltip,
-- UIParent) before filling the tooltip. Taking over the position here, before it is shown, means
-- it never appears at the default spot first. The minimap, XP bar and chat hyperlinks also anchor
-- to UIParent, so the mouse must also be over the world.
--
-- How it moves: the client's own cursor anchors can only grow upward, so for all four directions
-- the addon's own driver frame pins a corner of the tooltip to the cursor every frame (smooth: it
-- runs once per rendered frame). It never calls SetOwner (which clears the tooltip and runs
-- GameTooltip's OnTooltipCleared script under this hook's taint) and hooks no GameTooltip script;
-- ClearAllPoints and SetPoint have no Lua side effects. It stops as soon as the tooltip hides or
-- anything re-anchors it (another owner, or an anchor type other than Blizzard's ANCHOR_NONE).

local driver = CreateFrame("Frame")
driver:Hide()

local function PinToCursor()
	local point, offsetX, offsetY = ns.CursorAnchor.Point(ns.Options.Get("cursorDirection"))
	local scale = GameTooltip:GetEffectiveScale()
	local x, y = GetCursorPosition()
	GameTooltip:ClearAllPoints()
	GameTooltip:SetPoint(point, UIParent, "BOTTOMLEFT", x / scale + offsetX, y / scale + offsetY)
end

local function StillOurs()
	return GameTooltip:IsShown() and GameTooltip:GetOwner() == UIParent and GameTooltip:GetAnchorType() == "ANCHOR_NONE"
end

driver:SetScript("OnUpdate", function(self)
	if not StillOurs() then
		self:Hide()
		return
	end
	PinToCursor()
end)

local function IsMouseOverWorld()
	local focus = GetMouseFoci()[1]
	return focus == WorldFrame, focus
end

hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip, parent)
	if tooltip ~= GameTooltip or parent ~= UIParent then
		return
	end
	if not ns.Options.Get("cursorAnchor") then
		driver:Hide()
		return
	end
	local overWorld, focus = IsMouseOverWorld()
	if overWorld then
		-- Position now, so the first frame the tooltip shows is already at the cursor.
		PinToCursor()
		driver:Show()
		ns.dev:LogOnce(
			"anchor",
			"ANCHOR",
			"world tooltip follows the cursor, direction",
			ns.Options.Get("cursorDirection")
		)
	else
		driver:Hide()
		if ns.dev.enabled then
			local focusName = focus and focus:GetDebugName() or "nothing"
			ns.dev:LogChanged("anchor-skip", focusName, "ANCHOR", "kept default anchor for", focusName)
		end
	end
end)
