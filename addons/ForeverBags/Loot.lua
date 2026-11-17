local ADDON_NAME, ns = ...

-- Opens the window when looting fails because the bags are full, and loots again once the
-- player has deleted something. The error is watched the way Blizzard's loot window watches
-- it (Blizzard_UIPanels_Game/Mainline/LootFrame.lua): UI_ERROR_MESSAGE with ERR_INV_FULL,
-- only while a loot window is open.

local Window = ns.Window

local looting = false
-- The player closed the window during this loot: it stays closed until the next one.
local dismissed = false
-- A stack was deleted during this loot: loot again once a bag slot is free.
local relootArmed = false
-- A re-loot ran and its outcome hasn't been logged yet.
local relootUnlogged = false

local driver = CreateFrame("Frame")

local function RemainingLoot()
	local slots = 0
	for slot = 1, GetNumLootItems() do
		if GetLootSlotInfo(slot) then
			slots = slots + 1
		end
	end
	return slots
end

-- Takes everything still in the loot window, once. A slot that still doesn't fit raises the
-- full-inventory error again, which refreshes the window.
local function LootAgain()
	ns.log("RELOOT", "before", RemainingLoot(), "free", ns.Items.FreeSlots())
	relootUnlogged = true
	for slot = 1, GetNumLootItems() do
		if GetLootSlotInfo(slot) then
			LootSlot(slot)
		end
	end
end

-- outcome: "took" (a loot slot emptied), "full" (the bags were full again) or "closed".
local function LogReloot(outcome, remaining)
	if relootUnlogged then
		relootUnlogged = false
		ns.log("RELOOT", "after", remaining, outcome)
	end
end

local function OnEvent(_, event, ...)
	if event == "LOOT_OPENED" then
		local autoLoot = ...
		looting = true
		dismissed = false
		relootArmed = false
		relootUnlogged = false
		driver.autoLoot = autoLoot
		driver:RegisterEvent("UI_ERROR_MESSAGE")
		driver:RegisterEvent("BAG_UPDATE_DELAYED")
		driver:RegisterEvent("LOOT_SLOT_CLEARED")
	elseif event == "LOOT_CLOSED" then
		LogReloot("closed", 0)
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
		ns.log("FULL", errorType, "autoloot", driver.autoLoot, "dismissed", dismissed)
		LogReloot("full", RemainingLoot())
		if Window.IsOpen() then
			Window.Refresh()
		elseif not dismissed then
			Window.Open("loot", LootFrame)
		end
	elseif event == "BAG_UPDATE_DELAYED" then
		-- Bag updates arrive for other reasons too, some before the delete has reached the
		-- server. The one that counts is the first with a free slot.
		if relootArmed and ns.Items.FreeSlots() > 0 then
			relootArmed = false
			LootAgain()
		end
	elseif event == "LOOT_SLOT_CLEARED" then
		LogReloot("took", RemainingLoot())
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
