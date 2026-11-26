local _, ns = ...

-- Dev-only: records the numbers in each of the player's spell descriptions against their attack
-- power and form, to show which tooltips already move with attack power (Victory Rush does) and
-- which hide their scaling (Thunder Clap, Rake, Swipe). Read with scripts/observed.sh
-- ForeverTooltip; scripts/devlog.sh --tag SPELLNUM shows when a reading was taken.
--
-- Evidence, kept across sessions (ForeverDevDB.observed.ForeverTooltip):
--   tooltipNumbers[spellID] = {
--     name = "Thunder Clap",
--     readings = { ["ap 552 sp 0 form 2"] = "23 10 30 4", ... },  -- the description's numbers, in order
--   }
-- A reading is taken a moment after login and after gear, attack power, form or spells change, out
-- of combat only. A spell keeps at most MAX_READINGS stat combinations.
if not ns.dev.enabled then
	return
end

local MAX_READINGS = 16
local DELAY = 1.5

-- "ap 552 sp 0 form 2", or nil when a stat reads secret.
local function GetStatKey()
	local base, positive, negative = UnitAttackPower("player")
	local spellPower = GetSpellBonusHealing()
	local form = GetShapeshiftForm()
	if
		issecretvalue(base)
		or issecretvalue(positive)
		or issecretvalue(negative)
		or issecretvalue(spellPower)
		or issecretvalue(form)
	then
		return nil
	end
	return ("ap %d sp %d form %d"):format(base + positive + negative, spellPower, form)
end

-- The whole numbers in description, in order: "23 10 30 4". "" when there are none.
local function GetNumbers(description)
	local numbers = {}
	for number in description:gsub("(%d),(%d%d%d)", "%1%2"):gmatch("%d+") do
		table.insert(numbers, number)
	end
	return table.concat(numbers, " ")
end

local function CountKeys(t)
	local count = 0
	for _ in pairs(t) do
		count = count + 1
	end
	return count
end

local function Record()
	if InCombatLockdown() then
		return
	end
	local statKey = GetStatKey()
	if not statKey then
		ns.dev:LogChanged("spellnum", "secret", "SPELLNUM", "stats secret, nothing recorded")
		return
	end
	local recorded = 0
	for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
		local lineInfo = C_SpellBook.GetSpellBookSkillLineInfo(line)
		for slot = lineInfo.itemIndexOffset + 1, lineInfo.itemIndexOffset + lineInfo.numSpellBookItems do
			local item = C_SpellBook.GetSpellBookItemInfo(slot, Enum.SpellBookSpellBank.Player)
			if item and item.itemType == Enum.SpellBookItemType.Spell and item.spellID and not item.isPassive then
				local description = C_Spell.GetSpellDescription(item.spellID)
				local numbers = description and not issecretvalue(description) and GetNumbers(description) or ""
				if numbers ~= "" then
					local evidence = ns.dev:Observed({ readings = {} }, "tooltipNumbers", item.spellID)
					evidence.name = item.name
					if evidence.readings[statKey] or CountKeys(evidence.readings) < MAX_READINGS then
						evidence.readings[statKey] = numbers
						recorded = recorded + 1
					end
				end
			end
		end
	end
	ns.dev:LogChanged("spellnum", statKey .. " " .. recorded, "SPELLNUM", statKey, "spells recorded", recorded)
end

-- One reading per burst of events: a gear swap fires several.
local pending = false

local function Schedule()
	if pending then
		return
	end
	pending = true
	C_Timer.After(DELAY, function()
		pending = false
		Record()
	end)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
frame:RegisterEvent("SPELLS_CHANGED")
frame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterUnitEvent("UNIT_ATTACK_POWER", "player")
frame:SetScript("OnEvent", Schedule)
