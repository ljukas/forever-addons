local ADDON_NAME, ns = ...

-- The Blizzard unit frames the meters draw on: the target and focus frames, whose health
-- bars Blizzard already overlays with heal prediction and absorb segments. Every module gets
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
---@field frame TargetFrame
---@field unit string
---@field healthBar TargetFrameHealthBar
---@field mask MaskTexture
local HostMixin = {}

function HostMixin:Init(frame, unit)
	self.frame = frame
	self.unit = unit
	local container = frame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer
	self.healthBar = container.HealthBar
	self.mask = container.HealthBarMask
	self.meters = {}
	for _, module in ns.Modules.Enumerate() do
		local meter = { segments = {} }
		for index = 1, MAX_SEGMENTS do
			local segment = CreateFrame("StatusBar", nil, self.healthBar, "ForeverCombatSegmentTemplate")
			segment:Init(self.healthBar, self.mask, module.color, module.reverse)
			meter.segments[index] = segment
		end
		meter.cue = ns.Cue.Create(self.healthBar, self.mask, module.cue.side, module.cue.glowTemplate)
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
	end
end

function HostMixin:UpdateWidth()
	local width = self.healthBar:GetWidth()
	for _, meter in pairs(self.meters) do
		for _, segment in ipairs(meter.segments) do
			segment:SetWidth(width)
		end
	end
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
	meter.cue:Set(module.cue.GetMax(self.unit), total)
	return total, anchorName
end

-- Returns true while any effect is shown.
function HostMixin:Refresh(now)
	local unit = self.unit
	local key = self.frame:IsVisible() and not UnitIsDeadOrGhost(unit) and ns.Units.Key(unit)
	local anyShown = false
	-- For the DISPLAY log only: what's shown, with the signature leaving out the totals so it's
	-- logged when what's shown changes, not on every refresh.
	local signature, shown
	if ns.dev.enabled then
		signature, shown = key or "none", {}
	end
	for _, module in ns.Modules.Enumerate() do
		local meter = self.meters[module]
		local effects = ns.Modules.GetEffects(module, unit, key)
		if effects then
			local total, anchorName = self:Render(module, meter, effects, now)
			anyShown = true
			if shown then
				local counts = string.format("%s=%d from %s", module.key, #effects, anchorName)
				signature = signature .. " " .. counts
				table.insert(shown, string.format("%s (%d)", counts, total))
			end
		else
			HideMeter(meter)
		end
	end

	if shown then
		ns.dev:LogChanged("display " .. unit, signature, "DISPLAY", unit, key or "none", table.concat(shown, " "))
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

local function AddHost(frame, unit)
	local host = CreateFromMixins(HostMixin)
	host:Init(frame, unit)
	table.insert(hosts, host)
	hostsByFrame[frame] = host

	-- The cue follows the health; Blizzard re-anchors the bar on target changes.
	host.healthBar:HookScript("OnValueChanged", MarkDirty)
	hooksecurefunc(frame, "UpdateHealthBarVisuals", MarkDirty)
end

function ns.Hosts.ForFrame(frame)
	return hostsByFrame[frame]
end

ns.OnInitialize(function()
	EventUtil.ContinueOnAddOnLoaded("Blizzard_UnitFrame", function()
		AddHost(TargetFrame, "target")
		AddHost(FocusFrame, "focus")
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
