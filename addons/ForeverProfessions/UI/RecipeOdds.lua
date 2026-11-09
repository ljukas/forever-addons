local ADDON_NAME, ns = ...

-- Skill-up odds in the professions window (docs/superpowers/specs/2026-11-09-skillup-odds-design.md):
-- text under the recipe schematic's Reagents (crafts, skill-ups, our chance and the wiki's) and a
-- % at the end of each recipe row. Only our own font strings are touched: Blizzard's frames get
-- hooksecurefunc and scroll box callbacks, never a new field or a moved widget. Blizzard's widgets
-- are only read.

local L = ns.L
local Difficulty = Enum.TradeskillRelativeDifficulty

-- Two 160 px reagent slots and their spacing (Blizzard's Camelot schematic override).
local TEXT_WIDTH = 325
-- A recipe row's name starts this far from the row's left edge: Blizzard anchors the skill-up
-- arrows (26 px wide) at LEFT -9 and the name 4 px to their right.
local ROW_LABEL_LEFT = 21
-- Space between the end of the name (or its [count]) and our %, and between our % and the row's
-- right edge.
local ROW_GAP = 6
local ROW_RIGHT_INSET = 4

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

-- Calls the C_TradeSkillUI flag if this client has it. These are used by Blizzard's own
-- professions code but missing from the generated API docs.
local function Flag(name)
	local func = C_TradeSkillUI[name]
	return func ~= nil and func() == true
end

-- Whether the window shows the player's own profession, where our history applies: not a linked
-- one, a guild's, or an NPC's. Blizzard hides the skill-up arrows for the last three too.
local function IsOwnProfession()
	return not (
		Flag("IsTradeSkillLinked")
		or Flag("IsTradeSkillGuild")
		or Flag("IsNPCCrafting")
		or Flag("IsRuneforging")
	)
end

-- Returns everything the displays need about a learned recipe, or nil (logged once per recipe)
-- when a value is missing or secret.
local function Read(recipeID)
	local recipe = C_TradeSkillUI.GetRecipeInfo(recipeID)
	local info = C_TradeSkillUI.GetProfessionInfoByRecipeID(recipeID)
	if not (recipe and info) then
		ns.dev:LogOnce("missing " .. recipeID, "ODDS", "recipe", recipeID, "has no recipe or profession info")
		return
	end
	if
		AnySecret(
			recipe.learned,
			recipe.disabled,
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
	if not recipe.learned then
		return
	end
	if recipe.relativeDifficulty == nil or not recipe.maxTrivialLevel or info.maxSkillLevel <= 0 then
		ns.dev:LogOnce("incomplete " .. recipeID, "ODDS", "recipe", recipeID, "has no colour or skill, not shown")
		return
	end

	local skill, difficulty, gray = info.skillLevel, recipe.relativeDifficulty, recipe.maxTrivialLevel
	local rows = ns.DB.GetCraftRows(recipeID)
	local odds = {
		recipeID = recipeID,
		skill = skill,
		difficulty = difficulty,
		canSkillUp = recipe.canSkillUp,
		disabled = recipe.disabled,
		capped = skill >= info.maxSkillLevel,
	}
	odds.yellowLo, odds.yellowHi = ns.Odds.LearnYellow(rows, skill, difficulty)
	if odds.canSkillUp then
		odds.wikiLow, odds.wikiHigh = ns.Odds.Wiki(skill, difficulty, gray, odds.yellowLo, odds.yellowHi)
		odds.ours, odds.oursCrafts = ns.Odds.Ours(rows, skill, difficulty)
	else
		-- The client says no point can come from it, whatever the colour.
		odds.wikiLow, odds.wikiHigh = 0, 0
	end

	if ns.dev.enabled then
		local key = ns.GetCharacterKey()
		local crafts, skillUps = 0, 0
		if key then
			crafts, skillUps = ns.DB.GetCraftTotals(key, recipeID)
		end
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
			"canSkillUp",
			tostring(odds.canSkillUp),
			"rows",
			#rows,
			"crafts",
			crafts,
			"skillUps",
			skillUps,
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
	-- The minimized view stacks Blizzard's finishing reagents where our text would go.
	local odds = recipeInfo
		and form.Reagents:IsShown()
		and not ProfessionsUtil.IsCraftingMinimized()
		and IsOwnProfession()
		and Read(recipeInfo.recipeID)
	if not odds then
		formText:Hide()
		return
	end
	local above = form.OptionalReagents:IsShown() and form.OptionalReagents or form.Reagents
	formText:ClearAllPoints()
	formText:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -10)
	formText:SetText(CraftsLine(odds.recipeID) .. "\n" .. ChanceLine(odds))
	formText:Show()

	if ns.dev.enabled then
		-- In-game check 1: whether the text runs past the form's bottom, onto the Create buttons.
		local bottom, formBottom = formText:GetBottom(), form:GetBottom()
		if bottom and formBottom then
			ns.dev:LogChanged(
				"form layout",
				odds.recipeID .. ":" .. math.floor(bottom - formBottom),
				"ODDS",
				"form text",
				odds.recipeID,
				"bottom above form bottom by",
				math.floor(bottom - formBottom),
				"optional reagents",
				form.OptionalReagents:IsShown()
			)
		end
	end
end

-- The recipe list's % ---------------------------------------------------------------------------

-- Our font string per recipe row frame. Rows are recycled, so each is set on every init.
local rowTexts = setmetatable({}, { __mode = "k" })

local function HideRow(row)
	if rowTexts[row] then
		rowTexts[row]:Hide()
	end
end

-- Returns the row's text and colour for the recipe, or nil when the row gets none.
local function RowLabel(odds)
	if odds.ours and odds.oursCrafts >= ns.Odds.LIST_MIN_CRAFTS then
		return L.ODDS_PERCENT:format(Percent(odds.ours)), difficultyColors[odds.difficulty], "ours"
	elseif odds.wikiLow then
		local low, high = Percent(odds.wikiLow), Percent(odds.wikiHigh)
		if low == high then
			return L.ODDS_PERCENT:format(low), DISABLED_FONT_COLOR, "wiki"
		end
		return L.ODDS_ABOUT:format(math.floor((low + high) / 2 + 0.5)), DISABLED_FONT_COLOR, "wiki range"
	end
end

local function UpdateRow(row, node)
	local data = node and node.GetData and node:GetData()
	if not (data and data.recipeInfo and IsOwnProfession()) then
		HideRow(row)
		return
	end
	-- The rank Blizzard's row shows (ProfessionsRecipeListRecipeMixin:Init).
	local recipeInfo = Professions.GetHighestLearnedRecipe(data.recipeInfo) or data.recipeInfo
	local odds = Read(recipeInfo.recipeID)
	-- Only where Blizzard shows skill-up arrows: not disabled (the lock sits there), not gray.
	if not odds or odds.disabled or not odds.canSkillUp or odds.capped or not difficultyColors[odds.difficulty] then
		HideRow(row)
		return
	end
	local label, color, source = RowLabel(odds)
	if not label then
		HideRow(row)
		return
	end

	local text = rowTexts[row]
	if not text then
		text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		-- Blizzard's row text has no shadow.
		text:SetShadowOffset(0, 0)
		text:SetPoint("RIGHT", row, "RIGHT", -ROW_RIGHT_INSET, 0)
		text:SetJustifyH("RIGHT")
		rowTexts[row] = text
	end
	text:SetText(label)

	-- Blizzard sizes the name without knowing about our %; a long name (or its [count]) would run
	-- under it, so the % is left out where it doesn't fit.
	local nameEnd = ROW_LABEL_LEFT + row.Label:GetWidth()
	if row.Count:IsShown() then
		nameEnd = nameEnd + row.Count:GetStringWidth()
	end
	local fits = nameEnd + ROW_GAP + text:GetStringWidth() + ROW_RIGHT_INSET <= row:GetWidth()
	if ns.dev.enabled then
		local key = label .. source .. tostring(fits)
		ns.dev:LogChanged(
			"row " .. recipeInfo.recipeID,
			key,
			"ODDS",
			"row",
			recipeInfo.recipeID,
			label,
			source,
			"fits",
			fits
		)
	end
	if not fits then
		text:Hide()
		return
	end
	text:SetTextColor(color:GetRGB())
	text:Show()
end

local function OnRowInitialized(_, row, node)
	UpdateRow(row, node)
end

-- -----------------------------------------------------------------------------------------------

-- Owner of our callback registrations.
local owner = {}

local function Setup()
	local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
	if not (page and page.SchematicForm and page.RecipeList) then
		ns.log("ODDS", "crafting page not found, odds not shown")
		return
	end
	form = page.SchematicForm
	formText = form:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall2")
	formText:SetWidth(TEXT_WIDTH)
	formText:SetJustifyH("LEFT")
	formText:SetJustifyV("TOP")
	formText:Hide()
	hooksecurefunc(form, "Init", UpdateForm)

	local scrollBox = page.RecipeList.ScrollBox
	ScrollUtil.AddInitializedFrameCallback(scrollBox, OnRowInitialized, owner)
	-- AddInitializedFrameCallback's iterateExisting calls back without the owner argument.
	scrollBox:ForEachFrame(UpdateRow)

	ns.callbacks:RegisterCallback("CraftsChanged", function(_, recipeID)
		local formVisible, listVisible = form:IsVisible(), scrollBox:IsVisible()
		ns.log("ODDS", "crafts changed", recipeID, "form", formVisible, "list", listVisible)
		if formVisible then
			UpdateForm()
		end
		if listVisible then
			scrollBox:ForEachFrame(UpdateRow)
		end
	end, owner)
end

ns.OnInitialize(function()
	EventUtil.ContinueOnAddOnLoaded("Blizzard_Professions", Setup)
end)
