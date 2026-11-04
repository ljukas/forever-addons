local ADDON_NAME, ns = ...

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
-- ClearAllPoints and SetPoint have no Lua side effects. Any SetOwner call on GameTooltip stops it
-- (Blizzard's default anchor calls SetOwner before the hook below restarts it), so tooltips that
-- other code positions (nameplate-anchored world tooltips, basic tooltips) are never dragged along.
-- It also stops when the tooltip hides or the option is turned off.

local driver = CreateFrame("Frame")
driver:Hide()

hooksecurefunc(GameTooltip, "SetOwner", function()
	driver:Hide()
end)

local function PinToCursor()
	local scale = GameTooltip:GetEffectiveScale()
	local cursorX, cursorY = GetCursorPosition()
	local screenScale = UIParent:GetEffectiveScale() / scale
	local point, x, y = ns.CursorAnchor.Place(
		ns.Options.Get("cursorDirection"),
		cursorX / scale,
		cursorY / scale,
		GameTooltip:GetWidth(),
		GameTooltip:GetHeight(),
		UIParent:GetWidth() * screenScale,
		UIParent:GetHeight() * screenScale
	)
	GameTooltip:ClearAllPoints()
	GameTooltip:SetPoint(point, UIParent, "BOTTOMLEFT", x, y)
end

-- Also stops when the tooltip was re-anchored without SetOwner (SetAnchorType, as the Encounter
-- Journal does): Blizzard's default anchor leaves it owned by UIParent with ANCHOR_NONE.
local function StillOurs()
	return GameTooltip:IsShown()
		and ns.Options.Get("cursorAnchor")
		and GameTooltip:GetOwner() == UIParent
		and GameTooltip:GetAnchorType() == "ANCHOR_NONE"
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
		if ns.dev.enabled then
			ns.dev:LogOnce(
				"anchor",
				"ANCHOR",
				"world tooltip follows the cursor, direction",
				ns.Options.Get("cursorDirection")
			)
		end
	else
		driver:Hide()
		if ns.dev.enabled then
			local focusName = focus and focus:GetDebugName() or "nothing"
			ns.dev:LogChanged("anchor-skip", focusName, "ANCHOR", "kept default anchor for", focusName)
		end
	end
end)
