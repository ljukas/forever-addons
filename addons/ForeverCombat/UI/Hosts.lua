local ADDON_NAME, ns = ...

-- The Blizzard unit frames the meters draw on: the target, focus and player frames, whose
-- health bars Blizzard already overlays with heal prediction and absorb segments. Every module gets
-- its own segments and cue per host, parented to the health bar beside Blizzard's. Only this
-- file knows Blizzard's frame paths, so nameplates or party frames would be another host with
-- their own Get* paths.
--
-- Segments of a module chain from module:GetAnchor(host): reverse segments end at the
-- anchor's right edge and stack leftward, the others start at it and stack rightward. Each
-- one is as wide as the whole bar with max = the unit's max health, so its fill is exactly
-- its share of the bar.
ns.Hosts = {}

-- Segments per module and host, created up front so nothing is created in combat. Effects
-- past the last one are added to it.
local MAX_SEGMENTS = 6
-- Remaining amounts drop with every tick and the cue follows the health, so a host showing
-- effects refreshes this often.
local REFRESH_INTERVAL = 0.2

local hosts = {}
local hostsByFrame = {}

---@class ForeverCombatHost
---@field frame TargetFrame|PlayerFrame
---@field unit string
---@field setting string? ForeverCombatDB.settings key that turns the host on, if it has one
---@field healthBar TargetFrameHealthBar
---@field mask MaskTexture
local HostMixin = {}

---@param container TargetFrameHealthBarsContainer
function HostMixin:Init(frame, unit, container, setting)
	self.frame = frame
	self.unit = unit
	self.setting = setting
	self.healthBar = container.HealthBar
	self.mask = container.HealthBarMask
	self.meters = {}
	-- The round portrait the DoT meter washes red. Only the target and focus frames have this
	-- container; the player host goes without, since DoTs never draw on the player.
	local frameContainer = frame.TargetFrameContainer
	-- Blizzard's own segments carry the frame's atlas (PlayerFrameBarSegmentTemplate, ...).
	local fillAtlas = self.healthBar.MyHealPredictionBar.fillAtlas
	for _, module in ns.Modules.Enumerate() do
		local meter = { segments = {} }
		for index = 1, MAX_SEGMENTS do
			local segment = CreateFrame("StatusBar", nil, self.healthBar, "ForeverCombatSegmentTemplate")
			segment:Init(self.healthBar, self.mask, module.color, module.reverse, fillAtlas)
			meter.segments[index] = segment
		end
		meter.cue = ns.Cue.CreateBarEnd(self.healthBar, self.mask, module.cue.side, module.cue.glowTemplate)
		if module.portraitCue and frameContainer then
			meter.portraitCue = ns.Cue.CreatePortrait(frameContainer)
		end
		self.meters[module] = meter
	end
	self:UpdateWidth()
	self.healthBar:HookScript("OnSizeChanged", function()
		self:UpdateWidth()
	end)

	if ns.dev.enabled then
		local width = self.healthBar:GetWidth()
		local layer, subLevel = self.healthBar:GetStatusBarTexture():GetDrawLayer()
		ns.log("HOST", unit, "bar width", width, "secret", issecretvalue(width), "layer", layer, subLevel)

		-- For the portrait launch checks: its size and what draws around the red.
		if frameContainer then
			local portrait = frameContainer.Portrait
			local combo = ComboFrame
			ns.log(
				"HOST",
				unit,
				"portrait",
				portrait:GetWidth(),
				portrait:GetHeight(),
				"scale",
				frame:GetEffectiveScale(),
				"layer",
				portrait:GetDrawLayer(),
				"ring layer",
				frameContainer.FrameTexture:GetDrawLayer(),
				"container",
				frameContainer:GetFrameStrata(),
				frameContainer:GetFrameLevel(),
				"combo",
				combo and combo:GetFrameStrata(),
				combo and combo:GetFrameLevel()
			)
		end
	end
end

-- GetWidth is SecretWhenAnchoringSecret: while anything the bar is anchored through is secret,
-- the width is too, and SetWidth refuses a secret from addon code. Blizzard sets the bar's
-- width itself (126 on target and focus, 124 on the player), so a secret reading keeps the
-- segments at the last width they got.
function HostMixin:UpdateWidth()
	local width = self.healthBar:GetWidth()
	if issecretvalue(width) then
		ns.dev:LogOnce("secret width " .. self.unit, "HOST", self.unit, "bar width secret, kept the last one")
		return
	end
	for _, meter in pairs(self.meters) do
		for _, segment in ipairs(meter.segments) do
			segment:SetWidth(width)
		end
	end
end

-- Why the host draws nothing now, or nil when it draws: it's turned off, its frame is hidden,
-- the frame shows another unit (the player frame shows the vehicle while the player is in
-- one), or the unit is dead.
function HostMixin:GetHiddenReason()
	if self.setting and not ns.Options.Get(self.setting) then
		return "off"
	elseif not self.frame:IsVisible() then
		return "hidden"
	elseif self.frame.unit ~= self.unit then
		return "shows " .. tostring(self.frame.unit)
	elseif UnitIsDeadOrGhost(self.unit) then
		return "dead"
	end
end

function HostMixin:IsShowing()
	return not self:GetHiddenReason()
end

-- The green health fill.
function HostMixin:GetHealthFill()
	return self.healthBar:GetStatusBarTexture()
end

-- The right end of the health fill plus Blizzard's incoming heal segments, whichever of them
-- is shown (UnitFrameHealPredictionBars_Update hides the empty ones).
function HostMixin:GetIncomingHealEnd()
	local bar = self.healthBar
	if bar.OtherHealPredictionBar:IsShown() then
		return bar.OtherHealPredictionBar.FillMask, "OtherHealPrediction"
	elseif bar.MyHealPredictionBar:IsShown() then
		return bar.MyHealPredictionBar.FillMask, "MyHealPrediction"
	end
	return self:GetHealthFill(), "fill"
end

local function HideMeter(meter)
	for _, segment in ipairs(meter.segments) do
		segment:Hide()
	end
	meter.cue:Hide()
	if meter.portraitCue then
		meter.portraitCue:Hide()
	end
end

-- Draws one module's effects. Returns their remaining total and where the segments start.
function HostMixin:Render(module, meter, effects, now)
	local maxHealth = UnitHealthMax(self.unit)
	local anchor, anchorName = module:GetAnchor(self)
	local point = module.reverse and "RIGHT" or "LEFT"
	local edge = "RIGHT"
	local total = 0
	for index, segment in ipairs(meter.segments) do
		if effects[index] then
			local amount = 0
			local last = index == MAX_SEGMENTS and #effects or index
			for effectIndex = index, last do
				amount = amount + ns.Tracker.Remaining(effects[effectIndex], now)
			end
			total = total + amount
			segment:ClearAllPoints()
			segment:SetPoint("TOP" .. point, anchor, "TOP" .. edge)
			segment:SetPoint("BOTTOM" .. point, anchor, "BOTTOM" .. edge)
			segment:SetAmount(maxHealth, amount)
			segment:Show()
			anchor = segment.Fill
			edge = module.reverse and "LEFT" or "RIGHT"
		else
			segment:Hide()
		end
	end
	local maxValue = module.cue.GetMax(self.unit)
	meter.cue:Set(maxValue, total)
	if meter.portraitCue then
		if ns.Options.Get(module.portraitCue.setting) then
			meter.portraitCue:Set(maxValue, total)
		else
			meter.portraitCue:Hide()
		end
	end
	return total, anchorName
end

-- Returns true while any effect is shown.
function HostMixin:Refresh(now)
	local unit = self.unit
	local hiddenReason = self:GetHiddenReason()
	local key = not hiddenReason and ns.Units.Key(unit)
	local anyShown = false
	-- For the DISPLAY log only: what's shown, with the signature leaving out the totals so it's
	-- logged when what's shown changes, not on every refresh.
	local state, signature, shown
	if ns.dev.enabled then
		state = key or ("none (" .. (hiddenReason or "no unit") .. ")")
		signature, shown = state, {}
	end
	for _, module in ns.Modules.Enumerate() do
		local meter = self.meters[module]
		local effects = ns.Modules.GetEffects(module, unit, key)
		if effects then
			local total, anchorName = self:Render(module, meter, effects, now)
			anyShown = true
			if shown then
				local counts = string.format("%s=%d from %s", module.key, #effects, anchorName)
				-- Whether the portrait cue is armed; if it's lit depends on the secret health.
				if module.portraitCue then
					local armed = ns.Options.Get(module.portraitCue.setting) and "on" or "off"
					counts = counts .. " portrait=" .. armed
				end
				signature = signature .. " " .. counts
				table.insert(shown, string.format("%s (%d)", counts, total))
			end
		else
			HideMeter(meter)
		end
	end

	if shown then
		ns.dev:LogChanged("display " .. unit, signature, "DISPLAY", unit, state, table.concat(shown, " "))
	end
	return anyShown
end

local dirty = true
local active = false
local sinceRefresh = 0

local function MarkDirty()
	dirty = true
end

local function OnUpdate(_, elapsed)
	sinceRefresh = sinceRefresh + elapsed
	if not dirty and not (active and sinceRefresh >= REFRESH_INTERVAL) then
		return
	end
	dirty, active, sinceRefresh = false, false, 0
	local now = GetTime()
	for _, host in ipairs(hosts) do
		active = host:Refresh(now) or active
	end
end

-- hookVisuals(func) hooks func to where Blizzard re-anchors and resizes the frame's health bar.
local function AddHost(frame, unit, container, hookVisuals, setting)
	local host = CreateFromMixins(HostMixin)
	host:Init(frame, unit, container, setting)
	table.insert(hosts, host)
	hostsByFrame[frame] = host

	-- The cue follows the health. The player frame comes back (Alt+Z, cinematics) with no
	-- event that would redraw it.
	host.healthBar:HookScript("OnValueChanged", MarkDirty)
	frame:HookScript("OnShow", MarkDirty)
	hookVisuals(MarkDirty)
end

-- Blizzard re-anchors the target and focus health bars on unit changes.
local function AddTargetHost(frame, unit)
	local container = frame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer
	AddHost(frame, unit, container, function(func)
		hooksecurefunc(frame, "UpdateHealthBarVisuals", func)
	end)
end

function ns.Hosts.ForFrame(frame)
	return hostsByFrame[frame]
end

ns.OnInitialize(function()
	EventUtil.ContinueOnAddOnLoaded("Blizzard_UnitFrame", function()
		AddTargetHost(TargetFrame, "target")
		AddTargetHost(FocusFrame, "focus")
		-- On the player frame it's a global function, not a method. Blizzard calls it entering
		-- and leaving a vehicle, which also changes PlayerFrame.unit.
		AddHost(PlayerFrame, "player", PlayerFrame_GetHealthBarContainer(), function(func)
			hooksecurefunc("PlayerFrame_UpdateHealthBarVisuals", func)
		end, "hotPlayerFrame")
		-- HoT segments follow Blizzard's incoming heal segments, which it shows and hides here.
		hooksecurefunc("UnitFrameHealPredictionBars_Update", MarkDirty)

		ns.callbacks:RegisterCallback("EffectsChanged", MarkDirty)
		ns.callbacks:RegisterCallback("OptionChanged", MarkDirty)
		EventRegistry:RegisterFrameEventAndCallback("PLAYER_TARGET_CHANGED", MarkDirty)
		EventRegistry:RegisterFrameEventAndCallback("PLAYER_FOCUS_CHANGED", MarkDirty)

		local driver = CreateFrame("Frame")
		driver:SetScript("OnUpdate", OnUpdate)
	end)
end)
