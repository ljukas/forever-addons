local ADDON_NAME, ns = ...

local L = ns.L

-- Hovering the target or focus frame lists the player's DoTs or HoTs on that unit under
-- Blizzard's lines: spell, amount still to come and time left. UnitFrame_UpdateTooltip
-- rebuilds the whole tooltip while it's hovered, so the lines are added fresh every time.
local function AddEffects(frame)
	local host = ns.Hosts.ForFrame(frame)
	if not host or GameTooltip:GetOwner() ~= frame then
		return
	end
	local unit = host.unit
	local key = ns.Units.Key(unit)
	local now = GetTime()
	local added = false
	for _, module in ns.Modules.Enumerate() do
		for _, effect in ipairs(ns.Modules.GetEffects(module, unit, key) or {}) do
			if not added then
				GameTooltip_AddBlankLineToTooltip(GameTooltip)
				added = true
			end
			local amount, seconds = ns.Tracker.Remaining(effect, now)
			local text =
				L.REMAINING:format(BreakUpLargeNumbers(math.floor(amount + 0.5)), L.SECONDS:format(math.ceil(seconds)))
			GameTooltip_AddColoredDoubleLine(GameTooltip, effect.name, text, NORMAL_FONT_COLOR, HIGHLIGHT_FONT_COLOR)
		end
	end
	if added then
		GameTooltip:Show()
	end
end

ns.OnInitialize(function()
	EventUtil.ContinueOnAddOnLoaded("Blizzard_UnitFrame", function()
		hooksecurefunc("UnitFrame_UpdateTooltip", AddEffects)
	end)
end)
