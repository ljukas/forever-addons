local ADDON_NAME, ns = ...

-- Skill-up odds in the professions window (docs/superpowers/specs/2026-11-09-skillup-odds-design.md):
-- text under the recipe schematic's Reagents (crafts, skill-ups, our chance and the wiki's) and a
-- % at the end of each recipe row. Only our own font strings are touched: Blizzard's frames get
-- hooksecurefunc and scroll box callbacks, never a new field or a moved widget.

local L = ns.L
local Difficulty = Enum.TradeskillRelativeDifficulty

-- Two 160 px reagent slots and their spacing (Blizzard's Camelot schematic override).
local TEXT_WIDTH = 325

local difficultyColors = {
	[Difficulty.Optimal] = DIFFICULT_DIFFICULTY_COLOR,
	[Difficulty.Medium] = FAIR_DIFFICULTY_COLOR,
	[Difficulty.Easy] = EASY_DIFFICULTY_COLOR,
}

local function AnySecret(...)
	for i = 1, select("#", ...) do
		if issecretvalue((select(i, ...))) then
			return true
		end
	end
	return false
end

local function Percent(chance)
	return math.floor(chance * 100 + 0.5)
end

-- Returns everything the displays need about a learned recipe, or nil (logged once) when a
-- value is missing or secret.
local function Read(recipeID)
	local recipe = C_TradeSkillUI.GetRecipeInfo(recipeID)
	local info = C_TradeSkillUI.GetProfessionInfoByRecipeID(recipeID)
	if not (recipe and info and recipe.learned and recipe.relativeDifficulty ~= nil) then
		return
	end
	if
		AnySecret(
			recipe.relativeDifficulty,
			recipe.maxTrivialLevel,
			recipe.canSkillUp,
			info.skillLevel,
			info.maxSkillLevel
		)
	then
		ns.dev:LogOnce("secret " .. recipeID, "ODDS", "recipe", recipeID, "has secret values, not shown")
		return
	end
	if info.maxSkillLevel <= 0 then
		return
	end

	local skill, difficulty, gray = info.skillLevel, recipe.relativeDifficulty, recipe.maxTrivialLevel
	local rows = ns.DB.GetCraftRows(recipeID)
	local odds = {
		recipeID = recipeID,
		skill = skill,
		difficulty = difficulty,
		canSkillUp = recipe.canSkillUp,
		capped = skill >= info.maxSkillLevel,
	}
	odds.yellowLo, odds.yellowHi = ns.Odds.LearnYellow(rows, skill, difficulty)
	odds.wikiLow, odds.wikiHigh = ns.Odds.Wiki(skill, difficulty, gray, odds.yellowLo, odds.yellowHi)
	odds.ours, odds.oursCrafts = ns.Odds.Ours(rows, skill, difficulty)

	if ns.dev.enabled then
		local modifier = info.skillModifier
		local summary = table.concat({
			"skill",
			skill,
			"modifier",
			issecretvalue(modifier) and "secret" or tostring(modifier),
			"difficulty",
			difficulty,
			"gray",
			gray,
			"yellow",
			tostring(odds.yellowLo) .. "-" .. tostring(odds.yellowHi),
			"ours",
			tostring(odds.ours),
			"n",
			tostring(odds.oursCrafts),
			"wiki",
			tostring(odds.wikiLow) .. "-" .. tostring(odds.wikiHigh),
			"capped",
			tostring(odds.capped),
		}, " ")
		ns.dev:LogChanged("odds " .. recipeID, summary, "ODDS", recipeID, summary)
	end
	return odds
end

-- The schematic form's text --------------------------------------------------------------------

local form, formText

local function Label(text)
	return NORMAL_FONT_COLOR:WrapTextInColorCode(text)
end

local function WikiText(odds)
	if not odds.wikiLow then
		return L.ODDS_UNKNOWN
	elseif Percent(odds.wikiLow) == Percent(odds.wikiHigh) then
		return L.ODDS_PERCENT:format(Percent(odds.wikiLow))
	end
	return L.ODDS_RANGE:format(Percent(odds.wikiLow), Percent(odds.wikiHigh))
end

local function CraftsLine(recipeID)
	local key = ns.GetCharacterKey()
	local crafts, skillUps = 0, 0
	if key then
		crafts, skillUps = ns.DB.GetCraftTotals(key, recipeID)
	end
	if crafts == 0 then
		return Label(L.NOT_CRAFTED)
	end
	return Label(crafts == 1 and L.CRAFTED_ONCE or L.CRAFTED_TIMES:format(crafts))
		.. ", "
		.. (skillUps == 1 and L.SKILL_UP_ONE or L.SKILL_UPS:format(skillUps))
end

local function ChanceLine(odds)
	if odds.capped then
		return Label(L.AT_SKILL_CAP)
	end
	local parts = {}
	if odds.ours then
		local crafts = odds.oursCrafts == 1 and L.ONE_CRAFT or L.CRAFTS:format(odds.oursCrafts)
		table.insert(parts, L.ODDS_YOURS:format(Percent(odds.ours), crafts))
	end
	table.insert(parts, L.ODDS_WIKI:format(WikiText(odds)))
	return Label(L.CHANCE_AT:format(odds.skill)) .. " " .. table.concat(parts, " · ")
end

local function UpdateForm()
	local recipeInfo = form:GetRecipeInfo()
	local odds = recipeInfo and form.Reagents:IsShown() and Read(recipeInfo.recipeID)
	if not odds then
		formText:Hide()
		return
	end
	local above = form.OptionalReagents:IsShown() and form.OptionalReagents or form.Reagents
	formText:ClearAllPoints()
	formText:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -10)
	formText:SetText(CraftsLine(odds.recipeID) .. "\n" .. ChanceLine(odds))
	formText:Show()
end

-- The recipe list's % ---------------------------------------------------------------------------

-- Our font string per recipe row frame. Rows are recycled, so each is set on every init.
local rowTexts = setmetatable({}, { __mode = "k" })

local function UpdateRow(row, node)
	local data = node and node.GetData and node:GetData()
	local recipeInfo = data and data.recipeInfo
	local text = rowTexts[row]
	local odds = recipeInfo and Read(recipeInfo.recipeID)
	if
		not odds
		or not odds.canSkillUp
		or odds.capped
		or odds.difficulty == Difficulty.Trivial
		or not difficultyColors[odds.difficulty]
	then
		if text then
			text:Hide()
		end
		return
	end

	local label, color
	if odds.ours and odds.oursCrafts >= ns.Odds.LIST_MIN_CRAFTS then
		label, color = L.ODDS_PERCENT:format(Percent(odds.ours)), difficultyColors[odds.difficulty]
	elseif odds.wikiLow then
		local low, high = Percent(odds.wikiLow), Percent(odds.wikiHigh)
		label = low == high and L.ODDS_PERCENT:format(low) or L.ODDS_ABOUT:format(math.floor((low + high) / 2 + 0.5))
		color = DISABLED_FONT_COLOR
	else
		if text then
			text:Hide()
		end
		return
	end

	if not text then
		text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
		text:SetJustifyH("RIGHT")
		rowTexts[row] = text
	end
	text:SetText(label)
	text:SetTextColor(color:GetRGB())
	text:Show()
end

local function OnRowInitialized(_, row, node)
	UpdateRow(row, node)
end

-- -----------------------------------------------------------------------------------------------

local function Setup()
	local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
	if not (page and page.SchematicForm and page.RecipeList) then
		ns.log("ODDS", "crafting page not found, odds not shown")
		return
	end
	form = page.SchematicForm
	formText = form:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	formText:SetWidth(TEXT_WIDTH)
	formText:SetJustifyH("LEFT")
	formText:SetJustifyV("TOP")
	formText:Hide()
	hooksecurefunc(form, "Init", UpdateForm)

	local scrollBox = page.RecipeList.ScrollBox
	ScrollUtil.AddInitializedFrameCallback(scrollBox, OnRowInitialized, rowTexts)
	-- AddInitializedFrameCallback's iterateExisting calls back without the owner argument.
	scrollBox:ForEachFrame(UpdateRow)

	ns.callbacks:RegisterCallback("CraftsChanged", function()
		if form:IsShown() then
			UpdateForm()
		end
		if scrollBox:IsShown() then
			scrollBox:ForEachFrame(UpdateRow)
		end
	end, rowTexts)
end

ns.OnInitialize(function()
	EventUtil.ContinueOnAddOnLoaded("Blizzard_Professions", Setup)
end)
