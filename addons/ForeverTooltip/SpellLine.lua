local _, ns = ...

-- Adds the spell scaling line to tooltips of the player's own damage, healing and absorb spells: the
-- spell power (or attack power) coefficient, what the player's stat adds and the resulting total,
-- e.g. "+57.1% SP: +34 → 86–92 damage". The maths is in Logic/SpellScaling.lua, the coefficients in
-- Data/.
--
-- A tooltip post-call, like Colors.lua, so the line comes back on every rebuild
-- (TOOLTIP_DATA_UPDATE), e.g. once the spell's description has loaded.
--
-- Secret values: when stats are secret (C_Secrets.ShouldUnitStatsBeSecret, or a stat reads secret),
-- the line shows only the coefficient. Nothing here compares or calculates with a secret value.

local SpellScaling = ns.SpellScaling

-- Whether this code may index t (see Colors.lua).
local function IsReadableTable(t)
	return type(t) == "table" and canaccesstable(t)
end

-- The player's spell power for a spell of this school mask: bonus healing for heals and absorbs,
-- else the best bonus damage among the mask's schools. nil when it reads secret.
local function GetSpellPower(school, kind)
	if kind ~= "damage" then
		local healing = GetSpellBonusHealing()
		if issecretvalue(healing) then
			return nil
		end
		return healing
	end
	local best = 0
	-- GetSpellBonusDamage takes a school index: 1 physical, 2 holy, 3 fire, ... 7 arcane, the bits
	-- of the school mask in order.
	for index = 1, 7 do
		if bit.band(school, bit.lshift(1, index - 1)) ~= 0 then
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

-- The player's attack power, or nil when it reads secret.
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

-- The line for one row. stat nil: coefficient only. number false: the bonus without talents, no total.
local function FormatRow(spell, row, stat, expected, number)
	local effect = row.effect
	local ticks = SpellScaling.Ticks(spell, effect)
	if stat == nil then
		return SpellScaling.FormatLine(effect.kind, row.coefficient, ticks, nil, nil, nil, row.attackPower)
	end
	local talents = 1
	if number and expected > 0 then
		talents = (number.low + number.high) / 2 / expected
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

local function LogSpell(spellID, level, expected, found)
	if not ns.dev.enabled then
		return
	end
	local foundText = {}
	for index, number in ipairs(found) do
		foundText[index] = number and (number.low .. "-" .. number.high) or "none"
	end
	ns.dev:LogOnce(
		"spell" .. spellID,
		"SPELLSCALE",
		spellID,
		"level",
		level,
		"expected",
		table.concat(expected, ","),
		"found",
		table.concat(foundText, ",")
	)
end

local function AddScalingLines(tooltip, data)
	if not ns.Options.Get("spellScaling") or not IsReadableTable(data) then
		return
	end
	local spellID = data.id
	if issecretvalue(spellID) or type(spellID) ~= "number" then
		return
	end
	local spell = ns.SpellCoefficients[spellID]
	if not spell or not C_SpellBook.IsSpellKnown(spellID) then
		return
	end
	local rows = GetScaledEffects(spellID, spell)
	if #rows == 0 then
		return
	end

	local statsSecret = C_Secrets.ShouldUnitStatsBeSecret()
	ns.dev:LogChanged("stats", statsSecret, "SPELLSCALE", "stats secret", statsSecret)

	local level = GetPlayerLevel()
	local expected = {}
	for effectNumber, effect in ipairs(spell.effects) do
		expected[effectNumber] = level and SpellScaling.ExpectedBase(spell, effect, level) or 0
	end
	local found = SpellScaling.FindTooltipNumbers(GetDescription(spellID), expected)
	LogSpell(spellID, level, expected, found)

	for _, row in ipairs(rows) do
		local stat
		if not statsSecret then
			if row.attackPower then
				stat = GetAttackPower()
			else
				stat = GetSpellPower(spell.school, row.effect.kind)
			end
		end
		local line = FormatRow(spell, row, stat, expected[row.effectNumber], found[row.effectNumber])
		GameTooltip_AddColoredLine(tooltip, line, GREEN_FONT_COLOR)
	end
	tooltip:Show()
end

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, AddScalingLines)
