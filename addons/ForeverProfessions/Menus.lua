local ADDON_NAME, ns = ...

local L = ns.L

-- Adds a "Known Gathering Nodes" section with one checkbox per layer to Blizzard's
-- minimap tracking menu and world map filter menu, styled like each menu's own rows.

local function IsSelected(layer)
	return ns.Options.Get(layer.setting)
end

local function SetSelected(layer)
	ns.Options.Toggle(layer.setting)
end

-- Same tooltip as the world map filter rows (Blizzard_WorldMapTemplates.lua, AddFilter).
local function ShowRowTooltip(button, layer)
	GameTooltip:ClearAllPoints()
	GameTooltip:SetPoint("RIGHT", button, "LEFT", -3, 0)
	GameTooltip:SetOwner(button, "ANCHOR_PRESERVE")
	GameTooltip_SetTitle(GameTooltip, layer.label)
	GameTooltip_AddNormalLine(GameTooltip, layer.tooltip)
	GameTooltip:Show()
end

-- Right-justified icon, as on the tracking menu's "Find Herbs" / "Find Minerals" rows
-- (Blizzard_Minimap/Mainline/Minimap.lua, CreateCheckboxWithIcon).
local function AttachIcon(checkbox, atlas)
	checkbox:AddInitializer(function(button)
		local icon = button:AttachTexture()
		icon:SetSize(20, 20)
		icon:SetPoint("RIGHT")
		icon:SetAtlas(atlas)
		button.fontString:SetPoint("RIGHT", icon, "LEFT")
		return button.fontString:GetUnboundedStringWidth() + 60, 20
	end)
end

local function AddLayerToggles(rootDescription, withIcons)
	-- Queued, so the section break only appears above the rows that follow it.
	rootDescription:QueueSpacer()
	rootDescription:QueueDivider()
	rootDescription:QueueSpacer()
	rootDescription:CreateTitle(L.KNOWN_NODES)

	for _, layer in ns.Layers.Enumerate() do
		local checkbox = rootDescription:CreateCheckbox(layer.label, IsSelected, SetSelected, layer)
		checkbox:SetOnEnter(function(button)
			ShowRowTooltip(button, layer)
		end)
		checkbox:SetOnLeave(function()
			GameTooltip:Hide()
		end)
		if withIcons then
			AttachIcon(checkbox, layer.atlas)
		end
	end
end

ns.OnInitialize(function()
	Menu.ModifyMenu("MENU_MINIMAP_TRACKING", function(_, rootDescription)
		AddLayerToggles(rootDescription, true)
	end)
	Menu.ModifyMenu("MENU_WORLD_MAP_TRACKING", function(_, rootDescription)
		AddLayerToggles(rootDescription, false)
	end)
end)
