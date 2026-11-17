local ADDON_NAME, ns = ...

-- Which bag stacks could be thrown away, cheapest first. An entry is one bag slot:
--   { bag, slot, itemID, link, name, count, quality, icon, value }
-- value is the vendor sell price of the whole stack, in copper.

ns.Items = {}

local Items = ns.Items

Items.HEARTHSTONE = 6948

-- The backpack and the four equipped bags. The reagent bag is left out.
local FIRST_BAG = Enum.BagIndex.Backpack
local LAST_BAG = Enum.BagIndex.Bag_4

-- Pure. info is C_Container.GetContainerItemInfo's table, questInfo is
-- C_Container.GetContainerItemQuestInfo's, sellPrice the price of one item (nil when the item's
-- data isn't loaded) and ignored whether the player ignored the item.
function Items.Qualifies(info, questInfo, sellPrice, ignored)
	if ignored or info.isLocked or info.hasNoValue then
		return false
	end
	if not sellPrice or sellPrice <= 0 then
		return false
	end
	if info.itemID == Items.HEARTHSTONE then
		return false
	end
	if questInfo and (questInfo.isQuestItem or questInfo.questID) then
		return false
	end
	return true
end

local function Cheaper(a, b)
	if a.value ~= b.value then
		return a.value < b.value
	end
	if a.bag ~= b.bag then
		return a.bag < b.bag
	end
	return a.slot < b.slot
end

-- Pure. Sorts in place: by value, then bag, then slot.
function Items.Sort(entries)
	table.sort(entries, Cheaper)
end

-- Specialty bags (quivers, herb bags, ...) report a bag family other than 0. Loot can't go
-- into them, so emptying a slot there doesn't help.
local function IsGeneralBag(bag)
	local _, family = C_Container.GetContainerNumFreeSlots(bag)
	return not family or family == 0
end

-- How many slots loot could go into.
function Items.FreeSlots()
	local free = 0
	for bag = FIRST_BAG, LAST_BAG do
		local count, family = C_Container.GetContainerNumFreeSlots(bag)
		if not family or family == 0 then
			free = free + count
		end
	end
	return free
end

-- Returns the entries, cheapest first, and whether any stack was skipped because its item
-- data hasn't loaded yet (GET_ITEM_INFO_RECEIVED follows).
function Items.Scan()
	local entries = {}
	local pending = false
	for bag = FIRST_BAG, LAST_BAG do
		if IsGeneralBag(bag) then
			for slot = 1, C_Container.GetContainerNumSlots(bag) do
				local info = C_Container.GetContainerItemInfo(bag, slot)
				if info then
					-- By link, not item ID: a random-suffix item ("of the Bear") has its own price.
					local sellPrice = select(11, C_Item.GetItemInfo(info.hyperlink))
					if ns.dev.enabled and sellPrice then
						ns.dev:LogOnce(
							"scan-secret-" .. tostring(InCombatLockdown()),
							"SCAN",
							"combat",
							InCombatLockdown(),
							"secret sellPrice",
							issecretvalue(sellPrice),
							"hasNoValue",
							issecretvalue(info.hasNoValue)
						)
					end
					if not sellPrice then
						pending = true
					elseif
						Items.Qualifies(
							info,
							C_Container.GetContainerItemQuestInfo(bag, slot),
							sellPrice,
							ns.DB.IsIgnored(info.itemID)
						)
					then
						table.insert(entries, {
							bag = bag,
							slot = slot,
							itemID = info.itemID,
							link = info.hyperlink,
							name = info.itemName,
							count = info.stackCount,
							quality = info.quality,
							icon = info.iconFileID,
							value = sellPrice * info.stackCount,
						})
					end
				end
			end
		end
	end
	Items.Sort(entries)

	if ns.dev.enabled then
		local cheapest = entries[1]
		ns.log(
			"SCAN",
			#entries,
			"pending",
			pending,
			"cheapest",
			cheapest and cheapest.link,
			cheapest and cheapest.value
		)
	end
	return entries, pending
end
