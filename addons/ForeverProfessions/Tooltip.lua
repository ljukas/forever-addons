local ADDON_NAME, ns = ...

local L = ns.L

ns.Tooltip = {}

-- Adds "Requires <Profession> (<skill>)", red when the player is too low, followed by
-- the player's current skill.
function ns.Tooltip.AddRequirement(tooltip, nodeName, withName)
	local required, rank, profession, tooLow = ns.Professions.GetRequirement(nodeName)
	if not required then
		return
	end

	local text = L.REQUIRES_SKILL:format(profession, required)
	if withName then
		text = nodeName .. ": " .. text
	end
	if tooLow then
		GameTooltip_AddErrorLine(tooltip, text)
	else
		GameTooltip_AddHighlightLine(tooltip, text)
	end

	if rank then
		GameTooltip_AddNormalLine(tooltip, L.CURRENT_SKILL:format(rank))
	else
		GameTooltip_AddNormalLine(tooltip, L.NOT_LEARNED:format(profession))
	end
end

-- Full tooltip for one of our pins.
function ns.Tooltip.ShowNode(tooltip, owner, anchor, nodeName, timesGathered)
	tooltip:SetOwner(owner, anchor)
	GameTooltip_SetTitle(tooltip, nodeName)
	ns.Tooltip.AddRequirement(tooltip, nodeName)
	GameTooltip_AddNormalLine(tooltip, L.TIMES_GATHERED:format(timesGathered))
	tooltip:Show()
end

-- Minimap tooltip text can carry colour and texture escapes around the node name.
local function StripEscapes(text)
	return strtrim((text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")))
end

local matchedNames = {}

-- Hovering the engine's own tracking blips. The client rebuilds this tooltip every
-- frame (Minimap_OnUpdate), so this appends fresh lines on each rebuild and keeps no
-- state between calls. Several overlapping blips arrive as one line per name.
local function OnMinimapMouseover(tooltip, data)
	if tooltip ~= GameTooltip or not data or not data.lines then
		return
	end

	wipe(matchedNames)
	for _, line in ipairs(data.lines) do
		local text = line.leftText
		if text and not issecretvalue(text) then
			for part in text:gmatch("[^\n]+") do
				local name = StripEscapes(part)
				if ns.Professions.GetNode(name) and not tContains(matchedNames, name) then
					table.insert(matchedNames, name)
				end
			end
		end
	end

	local withName = #matchedNames > 1
	for _, name in ipairs(matchedNames) do
		ns.Tooltip.AddRequirement(tooltip, name, withName)
	end
end

ns.OnInitialize(function()
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.MinimapMouseover, OnMinimapMouseover)
end)
