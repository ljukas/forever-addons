local ADDON_NAME, ns = ...

-- Opens the window when looting fails because the bags are full, and loots again once the
-- player has deleted something. The error is watched the way Blizzard's loot window watches
-- it (Blizzard_UIPanels_Game/Mainline/LootFrame.lua): UI_ERROR_MESSAGE with ERR_INV_FULL,
-- only while a loot window is open.

local Window = ns.Window

local looting = false
-- The player closed the window during this loot: it stays closed until the next one.
local dismissed = false
-- A stack was deleted during this loot: loot again once the bags have caught up.
local relootArmed = false

local driver = CreateFrame("Frame")

-- Takes everything still in the loot window, once. A slot that still doesn't fit raises the
-- full-inventory error again, which refreshes the window.
local function LootAgain()
	local slots = 0
	for slot = 1, GetNumLootItems() do
		if GetLootSlotInfo(slot) then
			slots = slots + 1
			LootSlot(slot)
		end
	end
	ns.log("RELOOT", "before", slots)
end

local function RemainingLoot()
	local slots = 0
	for slot = 1, GetNumLootItems() do
		if GetLootSlotInfo(slot) then
			slots = slots + 1
		end
	end
	return slots
end

local function OnEvent(_, event, ...)
	if event == "LOOT_OPENED" then
		local autoLoot = ...
		looting = true
		dismissed = false
		relootArmed = false
		driver.autoLoot = autoLoot
		driver:RegisterEvent("UI_ERROR_MESSAGE")
		driver:RegisterEvent("BAG_UPDATE_DELAYED")
	elseif event == "LOOT_CLOSED" then
		looting = false
		relootArmed = false
		driver:UnregisterEvent("UI_ERROR_MESSAGE")
		driver:UnregisterEvent("BAG_UPDATE_DELAYED")
		driver:UnregisterEvent("LOOT_SLOT_CLEARED")
		if Window.Owner() == "loot" then
			Window.Close()
		end
	elseif event == "UI_ERROR_MESSAGE" then
		local errorType, message = ...
		if message ~= ERR_INV_FULL then
			return
		end
		ns.log("FULL", errorType, "auto", driver.autoLoot, "dismissed", dismissed)
		if Window.IsOpen() then
			Window.Refresh()
		elseif not dismissed then
			Window.Open("loot", LootFrame)
		end
	elseif event == "BAG_UPDATE_DELAYED" then
		if relootArmed then
			relootArmed = false
			if ns.dev.enabled then
				driver:RegisterEvent("LOOT_SLOT_CLEARED")
			end
			LootAgain()
		end
	elseif event == "LOOT_SLOT_CLEARED" then
		-- Only registered with ForeverDev, after a re-loot: shows that it took something.
		ns.log("RELOOT", "after", RemainingLoot())
	end
end

driver:SetScript("OnEvent", OnEvent)
driver:RegisterEvent("LOOT_OPENED")
driver:RegisterEvent("LOOT_CLOSED")

Window.onDeleted = function()
	if looting then
		relootArmed = true
	end
end

Window.onClosedByPlayer = function()
	if looting then
		dismissed = true
	end
end
