local ADDON_NAME, ns = ...

-- Dev only: logs the item each node in Data/Nodes.lua is given (ITEM tag), with the client's
-- name and icon for it, so a wrong item ID in ns.NodeItems shows as a name that doesn't match
-- its node. Also logs each node that has no item.
if not ns.dev.enabled then
	return
end

EventUtil.ContinueOnAddOnLoaded(ADDON_NAME, function()
	for name in pairs(ns.Nodes) do
		local itemID = ns.NodeItems[name]
		if not itemID then
			ns.log("ITEM", name, "has no item")
		else
			local item = Item:CreateFromItemID(itemID)
			if item:IsItemEmpty() then
				ns.log("ITEM", name, itemID, "unknown item")
			else
				item:ContinueOnItemLoad(function()
					ns.log("ITEM", name, "->", item:GetItemName(), itemID, "icon", C_Item.GetItemIconByID(itemID))
				end)
			end
		end
	end
end)
