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

-- One line per kind of node in a merged pin: "2x Copper Vein" and the skill it requires, red
-- when the player is too low; then the player's skill once per profession.
local function AddMergedNodes(tooltip, nodes)
	local names, perName = {}, {}
	for _, node in ipairs(nodes) do
		if not perName[node.name] then
			perName[node.name] = 0
			table.insert(names, node.name)
		end
		perName[node.name] = perName[node.name] + 1
	end
	table.sort(names, function(a, b)
		if perName[a] ~= perName[b] then
			return perName[a] > perName[b]
		end
		return a < b
	end)

	local skills, professions = {}, {}
	for _, name in ipairs(names) do
		local required, rank, profession, tooLow = ns.Professions.GetRequirement(name)
		local left = L.NODE_COUNT:format(perName[name], name)
		if required then
			local color = tooLow and RED_FONT_COLOR or HIGHLIGHT_FONT_COLOR
			GameTooltip_AddColoredDoubleLine(
				tooltip,
				left,
				L.REQUIRES_SKILL:format(profession, required),
				HIGHLIGHT_FONT_COLOR,
				color
			)
			-- false: not learned, so only nil means the profession hasn't been listed yet.
			if skills[profession] == nil then
				skills[profession] = rank or false
				table.insert(professions, profession)
			end
		else
			GameTooltip_AddHighlightLine(tooltip, left)
		end
	end
	for _, profession in ipairs(professions) do
		local rank = skills[profession]
		if rank then
			GameTooltip_AddNormalLine(tooltip, L.CURRENT_SKILL:format(rank))
		else
			GameTooltip_AddNormalLine(tooltip, L.NOT_LEARNED:format(profession))
		end
	end
end

-- Full tooltip for one of our pins, which stands for one node or for several merged.
---@param nodes ForeverProfessionsPinNode[]
function ns.Tooltip.ShowNodes(tooltip, owner, anchor, nodes)
	tooltip:SetOwner(owner, anchor)
	local timesGathered = 0
	for _, node in ipairs(nodes) do
		timesGathered = timesGathered + node.count
	end
	if #nodes == 1 then
		GameTooltip_SetTitle(tooltip, nodes[1].name)
		ns.Tooltip.AddRequirement(tooltip, nodes[1].name)
	else
		GameTooltip_SetTitle(tooltip, L.NODES_HERE:format(#nodes))
		AddMergedNodes(tooltip, nodes)
	end
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
