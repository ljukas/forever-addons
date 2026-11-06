local ADDON_NAME, ns = ...

-- A cue says the effects will finish the job: the DoTs kill, or the HoTs heal to full. That's
-- "total >= health", and health is secret, so addon code can't compare them. A StatusBar can:
-- a very long bar with max = health and value = total only fills to its end once
-- total >= health. A texture (the "rider") rides the end of that fill inside a clipping window
-- as wide as the rider, so it's only on screen at 100% (DoesItDie's kill icon trick).
--
-- Shapes:
--   CreateBarEnd  one of Blizzard's over-absorb glows at an end of the health bar, placed where
--                 Blizzard places it (UnitFrame_Initialize: 7px inside the bar's end)
--   CreatePortrait  the unit frame's round portrait washed red
ns.Cue = {}

-- A rider starts to show once the total is within this fraction of the health: each cue's bar
-- is its rider's width divided by it (10000px for the 16px glow), so every cue starts at the
-- same total and the portrait never shows before the glow.
local WIPE_FRACTION = 0.0016
-- The glow templates' size, and how far into the bar Blizzard puts them.
local GLOW_WIDTH = 16
local GLOW_INSET = 7
-- The target frame portrait's size in TargetFrameTemplate (Blizzard_UnitFrame/Mainline/TargetFrame.xml).
local PORTRAIT_SIZE = 58
-- How far inside the portrait's edge the red stops, clear of the gold ring (tune in game).
local PORTRAIT_MASK_INSET = 3
-- The gold ring (part of the frame's atlas) isn't centred on the portrait texture: its hole sits
-- a little right of and below it. Moves the red's circle by this much (tune in game).
local PORTRAIT_MASK_OFFSET_X = 1
local PORTRAIT_MASK_OFFSET_Y = -1
-- How strongly the red covers the portrait (tune in game).
local PORTRAIT_OVERLAY_ALPHA = 0.5

---@class ForeverCombatCue
---@field window Frame
---@field bar StatusBar
local CueMixin = {}

-- maxValue may be secret.
function CueMixin:Set(maxValue, total)
	self.bar:SetMinMaxValues(0, maxValue)
	self.bar:SetValue(total)
	self:RaiseAboveParent()
	self.window:Show()
end

-- A frame at its parent's level doesn't reliably draw above the parent's own textures: in game
-- the target frame's portrait and frame art covered the red. So the window sits one level up,
-- set again on every show because Blizzard re-layers the unit frames (Edit Mode) after load.
-- DoesItDie (swirllyman/DoesItDie, Display.lua) re-raises its kill skull for the same reason.
function CueMixin:RaiseAboveParent()
	local level = self.window:GetParent():GetFrameLevel()
	if not issecretvalue(level) and self.window:GetFrameLevel() ~= level + 1 then
		self.window:SetFrameLevel(level + 1)
	end
end

function CueMixin:Hide()
	self.window:Hide()
end

-- The clipping window (sized and anchored by the caller) and the long bar inside it. The
-- caller anchors its rider textures, riderWidth wide, with AttachRider.
local function NewCue(parent, riderWidth)
	local cue = CreateFromMixins(CueMixin)

	local window = CreateFrame("Frame", nil, parent)
	window:SetClipsChildren(true)
	window:Hide()
	cue.window = window

	-- The bar's own fill is invisible; only its end matters.
	local bar = CreateFrame("StatusBar", nil, window)
	bar:SetUsingParentLevel(true)
	bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	bar:SetStatusBarColor(0, 0, 0, 0)
	bar:SetWidth(riderWidth / WIPE_FRACTION)
	bar:SetPoint("TOPRIGHT", window, "TOPRIGHT")
	bar:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT")
	cue.bar = bar

	return cue
end

-- Rides texture on the end of the cue's fill.
local function AttachRider(cue, texture, width)
	local fill = cue.bar:GetStatusBarTexture()
	texture:ClearAllPoints()
	texture:SetPoint("TOPRIGHT", fill, "TOPRIGHT")
	texture:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT")
	texture:SetWidth(width)
end

-- side: "LEFT" or "RIGHT" end of the bar; glowTemplate: Blizzard's OverAbsorbGlowTemplate or
-- OverHealAbsorbGlowTemplate (Blizzard_UnitFrame/Shared/UnitFrame.xml).
function ns.Cue.CreateBarEnd(healthBar, mask, side, glowTemplate)
	local cue = NewCue(healthBar, GLOW_WIDTH)

	local glow = cue.bar:CreateTexture(nil, "ARTWORK", glowTemplate)
	AttachRider(cue, glow, GLOW_WIDTH)
	glow:AddMaskTexture(mask)

	local window = cue.window
	window:SetWidth(GLOW_WIDTH)
	if side == "LEFT" then
		window:SetPoint("TOPRIGHT", healthBar, "TOPLEFT", GLOW_INSET, 0)
		window:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMLEFT", GLOW_INSET, 0)
	else
		window:SetPoint("TOPLEFT", healthBar, "TOPRIGHT", -GLOW_INSET, 0)
		window:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMRIGHT", -GLOW_INSET, 0)
	end

	return cue
end

-- container: a unit frame's TargetFrameContainer. Washes its round portrait red: Blizzard's
-- red at PORTRAIT_OVERLAY_ALPHA, riding the fill as wide as the portrait, so it wipes in over
-- the same last 0.16% as the glow.
--
-- No MOD (multiply) tint: a mask works through the texture's alpha and MOD ignores alpha, so a
-- masked MOD texture still multiplies its whole square, ring and corners included (what the
-- game showed on 6 Nov 2026). None of Blizzard's own MOD textures is masked.
--
-- The ring is the next BACKGROUND sublevel above the portrait, so nothing of ours can sit
-- between them, and the frame's own PortraitMask is only 1px inside the ring. The red gets
-- its own circle, PORTRAIT_MASK_INSET further in, to keep it off the ring's inner edge.
function ns.Cue.CreatePortrait(container)
	local portrait = container.Portrait
	-- The template sizes it explicitly, so this is valid before the first layout.
	local width = portrait:GetWidth()
	if width <= 0 then
		width = PORTRAIT_SIZE
	end
	local cue = NewCue(container, width)
	cue.window:SetAllPoints(portrait)

	local mask = cue.window:CreateMaskTexture()
	mask:SetAtlas("CircleMask", false, nil, nil, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	local x, y = PORTRAIT_MASK_OFFSET_X, PORTRAIT_MASK_OFFSET_Y
	mask:SetPoint("TOPLEFT", portrait, "TOPLEFT", PORTRAIT_MASK_INSET + x, -PORTRAIT_MASK_INSET + y)
	mask:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", -PORTRAIT_MASK_INSET + x, PORTRAIT_MASK_INSET + y)

	local red = RED_FONT_COLOR
	local overlay = cue.bar:CreateTexture(nil, "ARTWORK")
	overlay:SetColorTexture(red.r, red.g, red.b, PORTRAIT_OVERLAY_ALPHA)
	AttachRider(cue, overlay, width)
	overlay:AddMaskTexture(mask)

	return cue
end
