local _, ns = ...

-- Adds the spell scaling line to tooltips of the player's own damage, healing and absorb spells: the
-- spell power (or attack power) coefficient, what the player's stat adds and the resulting total,
-- e.g. "+57.1% SP: +34 = 86-92 damage". The maths is in Logic/SpellScaling.lua, the coefficients in
-- Data/.
--
-- Melee spells that deal weapon damage (Data/WeaponSpells.lua) get a line with the resulting range
-- instead, worked out from the white damage the character sheet shows:
-- "154% of 51-65 weapon damage + 41 = 119-141 damage".
--
-- A tooltip post-call, like Colors.lua, so the line comes back on every rebuild
-- (TOOLTIP_DATA_UPDATE), e.g. once the spell's description has loaded. Blizzard shows (and so
-- resizes) the tooltip itself right after the post-calls, so this never calls Show: from addon code
-- that would run the tooltip's OnShow tainted.
--
-- Only GameTooltip (spellbook, action bars), and only the spell the tooltip is about: not chat links
-- (ItemRefTooltip) and not spells appended to another tooltip, such as a talent's.
--
-- Secret values: when stats are secret (C_Secrets.ShouldUnitStatsBeSecret, or a stat reads secret),
-- the line shows only the coefficient. Nothing here compares or calculates with a secret value.

local SpellScaling = ns.SpellScaling

-- Whether this code may index t (see Colors.lua).
local function IsReadableTable(t)
	return type(t) == "table" and canaccesstable(t)
end

-- The player's spell power for effect: bonus healing, or the best bonus damage among the spell's
-- schools. nil when it reads secret.
local function GetSpellPower(spell, effect)
	if SpellScaling.UsesHealing(spell, effect) then
		local healing = GetSpellBonusHealing()
		if issecretvalue(healing) then
			return nil
		end
		return healing
	end
	local best = 0
	-- GetSpellBonusDamage takes a school index: 2 holy, 3 fire, ... 7 arcane, the bits of the school
	-- mask in order. 1 is physical, which has no spell power (Blizzard's own loops start at 2).
	for index = 2, 7 do
		if bit.band(spell.school, bit.lshift(1, index - 1)) ~= 0 then
			local power = GetSpellBonusDamage(index)
			if issecretvalue(power) then
				return nil
			end
			if power and power > best then
				best = power
			end
		end
	end
	return best
end

-- The player's melee attack power, or nil when it reads secret.
local function GetAttackPower()
	local base, positive, negative = UnitAttackPower("player")
	if issecretvalue(base) or issecretvalue(positive) or issecretvalue(negative) then
		return nil
	end
	return base + positive + negative
end

-- The player's level, or nil when it reads secret.
local function GetPlayerLevel()
	local level = UnitLevel("player")
	if issecretvalue(level) then
		return nil
	end
	return level
end

-- The spell's description, "" when it isn't loaded, can't be found or reads secret.
local function GetDescription(spellID)
	local description = C_Spell.GetSpellDescription(spellID)
	if description == nil or issecretvalue(description) then
		return ""
	end
	return description
end

-- One row per effect and stat it scales with: { effect, effectNumber, coefficient, attackPower }.
local function GetScaledEffects(spellID, spell)
	local rows = {}
	for effectNumber, effect in ipairs(spell.effects) do
		local spellPower = SpellScaling.Coefficient(spell, effect)
		if spellPower > 0 then
			table.insert(rows, { effect = effect, effectNumber = effectNumber, coefficient = spellPower })
		end
		local attackPower = SpellScaling.APCoefficient(spellID, effect)
		if attackPower > 0 then
			table.insert(
				rows,
				{ effect = effect, effectNumber = effectNumber, coefficient = attackPower, attackPower = true }
			)
		end
	end
	return rows
end

-- What the description should hold for each effect, for FindTooltipNumbers. An effect with variance
-- is written as a range. A secret level leaves nothing to match (value 0).
local function GetExpected(spell, level)
	local expected = {}
	for effectNumber, effect in ipairs(spell.effects) do
		expected[effectNumber] = {
			value = level and SpellScaling.ExpectedBase(spell, effect, level) or 0,
			range = effect.variance > 0 and not effect.periodic,
		}
	end
	return expected
end

-- The line for one row. stat nil: coefficient only. number false: the bonus without talents, no total.
local function FormatRow(spell, row, stat, expected, number)
	local effect = row.effect
	local ticks = SpellScaling.Ticks(spell, effect)
	if stat == nil then
		return SpellScaling.FormatLine(effect.kind, row.coefficient, ticks, nil, nil, nil, row.attackPower)
	end
	local talents = 1
	if number and expected.value > 0 then
		talents = (number.low + number.high) / 2 / expected.value
	end
	local bonus = SpellScaling.Bonus(row.coefficient, stat, ticks, talents)
	if not number then
		return SpellScaling.FormatLine(effect.kind, row.coefficient, ticks, bonus, nil, nil, row.attackPower)
	end
	return SpellScaling.FormatLine(
		effect.kind,
		row.coefficient,
		ticks,
		bonus,
		number.low + bonus,
		number.high + bonus,
		row.attackPower
	)
end

-- The weapon damage line for spellID, or nil: when the spell isn't one, the white damage reads secret,
-- or the description's percentage or amount can't be found (no guessing).
local function GetWeaponLine(spellID)
	local weapon = ns.WeaponSpells[spellID]
	if not weapon or C_Secrets.ShouldUnitStatsBeSecret() then
		return nil
	end
	local minDamage, maxDamage = UnitDamage("player")
	if issecretvalue(minDamage) or issecretvalue(maxDamage) then
		return nil
	end
	local description = GetDescription(spellID)
	local percent
	if weapon.percent > 0 then
		percent = SpellScaling.FindTooltipPercent(description, weapon.percent)
		if not percent then
			return nil
		end
	end
	local flat = 0
	if weapon.flat > 0 then
		local expected = { { value = SpellScaling.ExpectedWeaponFlat(weapon.flat, percent), range = false } }
		local number = SpellScaling.FindTooltipNumbers(description, expected)[1]
		if not number then
			return nil
		end
		flat = number.low
	end
	local low, high = SpellScaling.WeaponDamage(minDamage, maxDamage, percent, flat)
	return SpellScaling.FormatWeaponLine(minDamage, maxDamage, percent, flat, low, high)
end

local function AddScalingLines(tooltip, data)
	if tooltip ~= GameTooltip or not ns.Options.Get("spellScaling") or not IsReadableTable(data) then
		return
	end
	local info = tooltip:GetProcessingTooltipInfo()
	if IsReadableTable(info) and info.append then
		return
	end
	local spellID = data.id
	if issecretvalue(spellID) or type(spellID) ~= "number" then
		return
	end
	if not C_SpellBook.IsSpellKnown(spellID) then
		return
	end
	local weaponLine = GetWeaponLine(spellID)
	if weaponLine then
		GameTooltip_AddColoredLine(tooltip, weaponLine, GREEN_FONT_COLOR)
		ns.dev:LogChanged("weapon" .. spellID, weaponLine, "SPELLSCALE", spellID, weaponLine)
	end
	local spell = ns.SpellCoefficients[spellID]
	if not spell then
		return
	end
	local rows = GetScaledEffects(spellID, spell)
	if #rows == 0 then
		return
	end

	local statsSecret = C_Secrets.ShouldUnitStatsBeSecret()
	ns.dev:LogChanged("stats", statsSecret, "SPELLSCALE", "stats secret", statsSecret)

	-- With secret stats only the coefficient shows, so there is nothing to match.
	local expected, found = {}, {}
	if not statsSecret then
		expected = GetExpected(spell, GetPlayerLevel())
		found = SpellScaling.FindTooltipNumbers(GetDescription(spellID), expected)
	end

	local lines = {}
	for _, row in ipairs(rows) do
		local stat
		if not statsSecret then
			if row.attackPower then
				stat = GetAttackPower()
			else
				stat = GetSpellPower(spell, row.effect)
			end
		end
		local line = FormatRow(spell, row, stat, expected[row.effectNumber], found[row.effectNumber] or false)
		GameTooltip_AddColoredLine(tooltip, line, GREEN_FONT_COLOR)
		if ns.dev.enabled then
			-- The stat is not secret here: FormatRow just did arithmetic with it, or it is nil.
			table.insert(lines, ("[stat %s] %s"):format(tostring(stat), line))
		end
	end

	if ns.dev.enabled then
		-- Logged again whenever the lines change: a description that loads late, new gear, a level.
		local text = table.concat(lines, " | ")
		ns.dev:LogChanged("spell" .. spellID, text, "SPELLSCALE", spellID, text)
	end
end

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, AddScalingLines)
