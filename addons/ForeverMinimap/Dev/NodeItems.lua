local ADDON_NAME, ns = ...

-- Dev only: logs the item each node in Data/Nodes.lua is given (ITEM tag), with the client's
-- name and icon for it, so a wrong item ID in ns.NodeItems shows as a name that doesn't match
-- its node. Also logs each herb or ore node that has no item (chests have none).
if not ns.dev.enabled then
	return
end

EventUtil.ContinueOnAddOnLoaded(ADDON_NAME, function()
	for name, kind in pairs(ns.Nodes) do
		local itemID = ns.NodeItems[name]
		if kind == "treasure" then
			-- No item: chests get Find Treasure's icon (UI/NodeIcons.lua).
			ns.dev:LogOnce("chest " .. name, "ITEM", name, "is a chest")
		elseif not itemID then
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
