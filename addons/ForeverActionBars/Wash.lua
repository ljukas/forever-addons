local _, ns = ...

-- The out-of-range wash: a red, translucent texture over the icon plus a red edge, added to
-- each standard action button. Blizzard works out the range and calls the global
-- ActionButton_UpdateRangeIndicator(button, checksRange, inRange) for every bar
-- (Blizzard_ActionBar/Shared/ActionButton.lua); this post-hooks it.
--
-- checksRange and inRange may be secret values, so Lua never compares or branches on them.
-- Each texture takes checksRange through SetVertexColorFromBoolean (vertex alpha 1 or 0) and
-- inRange through SetAlphaFromBoolean (region alpha 0 or its opacity). The renderer multiplies
-- the two, so the texture shows only when checksRange and not inRange.
--
-- The wash sits on the button itself, just above the icon and below the button's frame art
-- and child frames (cooldown swipe, hotkey, count, proc glow). The edge is drawn exactly like
-- Blizzard's own Border (the green ring equipped items get), only red.
--
-- Staying in step with Blizzard: a button gets range updates only while it is registered with
-- ActionBarButtonRangeCheckFrame. Registering happens when the action changes or the button
-- is shown; unregistering when it changes or hides. Unregister clears the wash; register
-- re-reads the range, because the client may not resend an unchanged state.

ns.Wash = {}

local WASH_ALPHA = 0.38
local EDGE_ALPHA = 1
local EDGE_ATLAS = "UI-HUD-ActionBar-IconFrame-Border"

local r, g, b = RED_FONT_COLOR:GetRGB()
local SHOWN = CreateColor(r, g, b, 1)
local HIDDEN = CreateColor(r, g, b, 0)

-- button -> { wash = Texture, edge = Texture }. Kept here rather than on the button, so the
-- addon writes no fields onto Blizzard's secure frames.
local overlays = setmetatable({}, { __mode = "k" })

-- True only for standard action bar buttons. Pet buttons, Forever's gamepad bar buttons
-- (which have their own RefreshRange and range art) and the gamepad pet flyout also reach the
-- hooked functions; they are left alone.
function ns.Wash.IsActionButton(button)
	return button.action ~= nil
		and button.icon ~= nil
		and button.IconMask ~= nil
		and button.Border ~= nil
		and button.RefreshRange == nil
		and button.bar ~= PetActionBar
end

local function Create(button)
	local wash = button:CreateTexture(nil, "BACKGROUND", nil, 7)
	wash:SetColorTexture(1, 1, 1)
	wash:SetAllPoints(button.icon)
	wash:AddMaskTexture(button.IconMask)
	wash:SetAlpha(0)

	-- Same atlas, layer and rectangle as button.Border, so it fits every button size Blizzard
	-- fits its own ring to (including the smaller totem bar buttons).
	local edge = button:CreateTexture(nil, "OVERLAY", nil, 0)
	edge:SetAtlas(EDGE_ATLAS)
	edge:SetAllPoints(button.Border)
	edge:SetAlpha(0)

	local overlay = { wash = wash, edge = edge }
	overlays[button] = overlay
	return overlay
end

-- Shows the wash when checksRange and not inRange. Neither may be nil; both may be secret.
function ns.Wash.Apply(button, checksRange, inRange)
	local overlay = overlays[button] or Create(button)
	overlay.wash:SetVertexColorFromBoolean(checksRange, SHOWN, HIDDEN)
	overlay.wash:SetAlphaFromBoolean(inRange, 0, WASH_ALPHA)
	overlay.edge:SetVertexColorFromBoolean(checksRange, SHOWN, HIDDEN)
	overlay.edge:SetAlphaFromBoolean(inRange, 0, EDGE_ALPHA)
end

-- Hides the wash. cause is only logged.
function ns.Wash.Clear(button, cause)
	local overlay = overlays[button]
	if not overlay then
		return
	end
	overlay.wash:SetAlpha(0)
	overlay.edge:SetAlpha(0)
	if ns.dev.enabled then
		ns.dev:LogOnce("clear " .. cause, "RANGE", "clear", cause)
	end
end

-- True when v can go into a FromBoolean setter: a secret (never nil) or a non-nil value.
-- issecretvalue comes first, because even comparing a secret with nil is an error.
local function Present(v)
	return issecretvalue(v) or v ~= nil
end

-- Reads the button's range now instead of waiting for the next ACTION_RANGE_CHECK_UPDATE.
-- IsActionInRange returns nil when no range check can be made (no target, no range).
function ns.Wash.Refresh(button, cause)
	local action = button.action
	if not C_ActionBar.HasAction(action) then
		ns.Wash.Clear(button, cause .. " empty")
		return
	end
	local inRange = C_ActionBar.IsActionInRange(action)
	if Present(inRange) then
		ns.Wash.Apply(button, true, inRange)
	else
		ns.Wash.Clear(button, cause .. " nocheck")
	end
	if ns.dev.enabled then
		ns.dev:LogOnce("refresh " .. cause, "RANGE", "refresh", cause, "secret", issecretvalue(inRange))
	end
end

local function LogSecrets(kind, checksRange, inRange)
	local situation = InCombatLockdown() and "combat" or "idle"
	local secret = issecretvalue(checksRange) or issecretvalue(inRange)
	ns.dev:LogChanged("secret " .. kind .. " " .. situation, secret, "RANGE", kind, situation, "secret", secret)
end

hooksecurefunc("ActionButton_UpdateRangeIndicator", function(button, checksRange, inRange)
	if ns.Wash.IsActionButton(button) then
		if ns.dev.enabled then
			LogSecrets("action", checksRange, inRange)
		end
		-- Both setters reject nil.
		if not (Present(checksRange) and Present(inRange)) then
			ns.Wash.Clear(button, "nilArgs")
			return
		end
		ns.Wash.Apply(button, checksRange, inRange)
	elseif button.bar == PetActionBar then
		if ns.dev.enabled then
			LogSecrets("pet", checksRange, inRange)
		end
		ns.Knowledge.PetRange(button, checksRange, inRange)
	end
end)

-- Post-hooks on Blizzard's registry instance; they run after Blizzard's own method.
hooksecurefunc(ActionBarButtonRangeCheckFrame, "UnregisterFrame", function(_, _, button)
	if ns.Wash.IsActionButton(button) then
		ns.Wash.Clear(button, "unregister")
	end
end)

hooksecurefunc(ActionBarButtonRangeCheckFrame, "RegisterFrame", function(_, _, button)
	if ns.Wash.IsActionButton(button) then
		ns.Wash.Refresh(button, "register")
	end
end)

-- The buttons registered before this file ran (login, /reload) get their first state here.
EventUtil.RegisterOnceFrameEventAndCallback("PLAYER_ENTERING_WORLD", function()
	for _, buttons in pairs(ActionBarButtonRangeCheckFrame.actions) do
		for button in pairs(buttons) do
			if ns.Wash.IsActionButton(button) then
				ns.Wash.Refresh(button, "login")
			end
		end
	end
end)
