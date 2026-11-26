local ADDON_NAME, ns = ...

-- The five-second rule as a spark: after a spell spends mana, mana stops regenerating for five
-- seconds. A spark crosses the mana bar from its left edge to its right in that time and is gone
-- when it arrives (docs/superpowers/specs/2026-11-25-razzhuiresourcebars-regen-spark-design.md).
--
-- Mana is secret, so its drop can't be seen. The spark starts on the player's casts that cost mana
-- instead, and its place is the clock's alone: nothing is read from the bar.
ns.RegenSpark = {}

local _, class = UnitClass("player")
-- False for the classes without mana: no spark, no events, and EditMode.lua adds no setting for it.
ns.RegenSpark.available = class ~= "WARRIOR" and class ~= "ROGUE"

if not ns.RegenSpark.available then
	function ns.RegenSpark.SetEnabled() end
	return
end

local Mana = Enum.PowerType.Mana

-- How long mana waits after a spell before it regenerates again, in seconds.
local DURATION = 5

-- The cast bar's spark is 8 by 20 on a bar 11 high (CastingBarFrame.xml): this much taller than
-- its bar. Thinner for its height than there (0.4), where it read as too heavy on this bar (user,
-- 2026-11-25).
local HEIGHT_SHARE = 1.8
local WIDTH_SHARE = 0.15

-- How far the spark may reach past the top and the bottom of the Other Powers row's bar: the row
-- is cut off a border's line below it and little more above (OffFormPower.lua's clip), so a spark
-- in the cast bar's proportions would lose its ends there, more below than above.
local ROW_OVERHANG = 2

-- Parented to the bar the spark is on (Host), so it scales, slides and fades with it.
local spark = CreateFrame("Frame", nil, ns.PowerBar.fill)
spark:Hide()
local texture = spark:CreateTexture(nil, "OVERLAY")
texture:SetAtlas("ui-castingbar-pip")

-- Runs the clock. Apart from the spark, which stops updating with a bar that hides (the Other
-- Powers row on a form change) and would never learn of the bar that shows mana next.
local clock = CreateFrame("Frame")

-- When the mana was spent (GetTime); nil while no spark runs.
local startedAt
-- The bar the spark is on; nil when no bar shows mana, false before a spark has looked for one.
---@type table|false|nil
local host = false

-- The bar that shows mana now, its name for the devlog, and how far the spark may reach past its
-- top and bottom (nil for as far as it likes): the power bar, or the mana bar of a druid's Other
-- Powers row.
local function Host()
	if UnitPowerType("player") == Mana then
		return ns.PowerBar.fill, "bar", nil
	end
	local bar = ns.OffFormPower.BarFor(Mana)
	return bar, bar and "offform" or "none", ROW_OVERHANG
end

-- The spark's width and height on a bar this high, in whole units so its edges don't shimmer as it
-- moves. Pure.
local function Size(barHeight, overhang)
	local height = barHeight * HEIGHT_SHARE
	if overhang then
		height = math.min(height, barHeight + 2 * overhang)
	end
	height = math.floor(height + 0.5)
	return math.max(1, math.floor(height * WIDTH_SHARE + 0.5)), height
end

-- How far along a bar this wide the spark is after this long, from the bar's left edge: the fill
-- reaches past the border's ends (ns.PowerBar.fillOutset), and the spark travels between them.
-- Pure.
local function Offset(elapsed, width)
	local left, right = ns.PowerBar.fillOutset.left, ns.PowerBar.fillOutset.right
	return left + (width - left - right) * elapsed / DURATION
end

-- The player's mana regeneration, for the devlog: does it change over the five seconds?
local function LogRegen(when)
	if not ns.dev.enabled then
		return
	end
	local base, casting = GetManaRegen()
	if issecretvalue(base) or issecretvalue(casting) then
		ns.log("REGEN", "regen", when, "secret")
	else
		ns.log("REGEN", "regen", when, base, casting)
	end
end

local function Stop(why)
	if not startedAt then
		return
	end
	startedAt, host = nil, false
	clock:SetScript("OnUpdate", nil)
	spark:Hide()
	ns.log("REGEN", "stop", why)
	LogRegen(why)
end

local function OnUpdate()
	local elapsed = GetTime() - startedAt
	if elapsed >= DURATION then
		Stop("done")
		return
	end
	local bar, name, overhang = Host()
	if bar ~= host then
		host = bar
		ns.log("REGEN", "host", name)
		if bar then
			spark:SetParent(bar)
			spark:ClearAllPoints()
			spark:SetAllPoints(bar)
			-- Above the border, as the cast bar's spark is, and above the lines that split a row
			-- (ns.PowerBar.CreateSeparator), which are a level above the border.
			spark:SetFrameLevel(ns.PowerBar.border:GetFrameLevel() + 2)
		end
		spark:SetShown(bar ~= nil)
	end
	if bar then
		texture:SetSize(Size(bar:GetHeight(), overhang))
		texture:SetPoint("CENTER", spark, "LEFT", Offset(elapsed, bar:GetWidth()), 0)
	end
end

-- Starts the spark from the left, also when one is under way: the five seconds count from the
-- last mana spent.
local function Start()
	startedAt = GetTime()
	clock:SetScript("OnUpdate", OnUpdate)
	OnUpdate()
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, _, _, spellID)
	if event ~= "UNIT_SPELLCAST_SUCCEEDED" then
		-- A loading screen or death: whatever regenerates after it, the count is over.
		Stop(event)
		return
	end
	-- The player's own casts are readable by the API docs (SecretWhenUnitSpellCastRestricted),
	-- unless a spell is flagged secret: then there is no cost to tell by.
	if issecretvalue(spellID) then
		ns.dev:LogOnce("regen-secret-cast", "REGEN", "secret", "spell")
		return
	end
	local cost = ns.PowerBar.SpellCost(spellID, Mana)
	-- A cost is not secret by the API docs; one that is can't be told from none.
	if issecretvalue(cost) then
		ns.dev:LogOnce("regen-secret-cost", "REGEN", "secret", "cost")
		return
	end
	if cost <= 0 then
		return
	end
	ns.log("REGEN", "start", spellID, cost)
	LogRegen("start")
	Start()
end)

-- Turns the spark on or off. One under way stops when it is turned off.
function ns.RegenSpark.SetEnabled(enabled)
	if enabled then
		events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
		events:RegisterEvent("PLAYER_ENTERING_WORLD")
		events:RegisterEvent("PLAYER_DEAD")
	else
		events:UnregisterAllEvents()
		Stop("off")
	end
end
