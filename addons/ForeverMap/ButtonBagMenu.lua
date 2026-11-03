local ADDON_NAME, ns = ...

-- The "Keep on minimap" menu of the button bag: one checkbox per button found, ticked while the
-- button stays out of the bag. Opened by right-clicking the bag button and from Options.
--   ns.ButtonBag.OpenIgnoreMenu(owner)  opens the menu next to the region `owner`
local L = ns.L

local IsKept = ns.ButtonBag.IsIgnored

-- Refresh keeps the menu open and redraws the ticks, so several buttons can be chosen in one go.
local function ToggleKept(key)
	ns.ButtonBag.SetIgnored(key, not IsKept(key))
	return MenuResponse.Refresh
end

function ns.ButtonBag.OpenIgnoreMenu(owner)
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle(L.KEEP_ON_MINIMAP)
		local list = ns.ButtonBag.Found()
		if #list == 0 then
			root:CreateButton(L.NO_BUTTONS_FOUND):SetEnabled(false)
			return
		end
		-- Hidden buttons are listed too, so a button can be kept before it shows up.
		for _, entry in ipairs(list) do
			root:CreateCheckbox(entry.label, IsKept, ToggleKept, entry.key)
		end
	end)
end

-- The bag button's right click (UI/BagButton.lua) opens it. That file's initializer runs first.
ns.OnInitialize(function()
	ns.BagButton.OnRightClick = function(button)
		ns.ButtonBag.OpenIgnoreMenu(button)
	end
end)
