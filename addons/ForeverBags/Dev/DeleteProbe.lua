local ADDON_NAME, ns = ...

if not ns.dev.enabled then
	return
end

-- Throwaway: answers whether the game lets an addon button delete a bag item at all, before
-- the window is built on it. One button in the middle of the screen that deletes the
-- cheapest stack. Removed when the window lands.

local button = CreateFrame("Button", nil, UIParent, "UIPanelButtonTemplate")
button:SetSize(160, 30)
button:SetPoint("CENTER", 0, 120)

local function Update()
	local entries = ns.Items.Scan()
	button.entry = entries[1]
	button:SetText(button.entry and (DELETE .. ": " .. button.entry.name) or DELETE)
	button:SetEnabled(button.entry ~= nil)
end

button:SetScript("OnClick", function()
	if button.entry then
		ns.log("DELETE", "probe click", button.entry.link, "quality", button.entry.quality)
		ns.Delete.Request(button.entry)
	end
end)

button:RegisterEvent("BAG_UPDATE_DELAYED")
button:RegisterEvent("PLAYER_ENTERING_WORLD")
button:SetScript("OnEvent", Update)
