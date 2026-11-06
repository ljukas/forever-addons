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
-- The textures sit on the button itself, below its child frames (cooldown swipe, hotkey,
-- count, proc glow), so all of Blizzard's overlays stay on top.

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

-- True only for standard action bar buttons. Pet buttons and Forever's gamepad pet flyout
-- also reach the hooked function, but don't carry the action button mixin's UpdateAction.
function ns.Wash.IsActionButton(button)
	return button.UpdateAction ~= nil and button.UpdateAction == ActionBarActionButtonMixin.UpdateAction
end

local function Create(button)
	local wash = button:CreateTexture(nil, "BACKGROUND", nil, 7)
	wash:SetColorTexture(1, 1, 1)
	wash:SetAllPoints(button.icon)
	if button.IconMask then
		wash:AddMaskTexture(button.IconMask)
	end
	wash:SetAlpha(0)

	-- Blizzard's own icon-frame border (the green one equipped items get), desaturated so the
	-- vertex colour turns it red.
	local edge = button:CreateTexture(nil, "OVERLAY", nil, 1)
	edge:SetAtlas(EDGE_ATLAS, true)
	edge:SetDesaturated(true)
	edge:SetPoint("TOPLEFT")
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

-- Hides the wash. reason is only logged.
function ns.Wash.Clear(button, reason)
	local overlay = overlays[button]
	if not overlay then
		return
	end
	overlay.wash:SetAlpha(0)
	overlay.edge:SetAlpha(0)
	ns.dev:LogOnce("clear " .. reason, "RANGE", "clear", reason)
end

-- True when v can go into a FromBoolean setter: a secret (never nil) or a non-nil value.
-- issecretvalue comes first, because even comparing a secret with nil is an error.
local function Present(v)
	return issecretvalue(v) or v ~= nil
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
	elseif button:GetParent() == PetActionBar then
		if ns.dev.enabled then
			LogSecrets("pet", checksRange, inRange)
		end
		ns.Knowledge.PetRange(button, checksRange, inRange)
	end
end)

-- A new action in the slot (talent swap, paging, form change, an emptied slot): drop the old
-- wash. The next range update for the new action shows it again if needed.
EventRegistry:RegisterCallback("ActionButton.OnActionChanged", function(_, button)
	ns.Wash.Clear(button, "actionChanged")
end, ns)
