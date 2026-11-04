local _, ns = ...

-- Finds the "Level 60 Human Warrior" line of a unit tooltip. That line has no tooltip line type
-- of its own (it arrives as Enum.TooltipDataLineType.None), so it is found by its text, built
-- from the client's own UNIT_LEVEL_TEMPLATE so that it works in every language.
-- Pure string logic: no WoW API calls. Examples (the reviewer's check, there is no test runner):
--   LevelText("Level %d", 60) == "Level 60"
--   LevelText("Level %d", -1) == "Level ??"       (skull-level units)
--   LevelText("%d级", 12)     == "12级"
--   Find({ "Thrall", "<Horde>", "Level 60 Orc Shaman" }, "Level 60", 2) == 3
--   Find({ "Thrall", "Level 60 Orc" }, "Level 6", 2) == 2   (plain substring; line 1 is skipped)
--   Find({ "A", "B" }, "Level 1", 2) == nil
ns.LevelLine = {}

-- The level part of the line for a unit of this level. template is a %d format string.
function ns.LevelLine.LevelText(template, level)
	if level < 0 then
		return (template:gsub("%%d", "??"))
	end
	return template:format(level)
end

-- Index of the first of texts[first..] that contains levelText as plain text, or nil.
-- texts may have holes (nil entries), so it walks up to table.maxn rather than #texts.
function ns.LevelLine.Find(texts, levelText, first)
	for i = first, table.maxn(texts) do
		local text = texts[i]
		if text and text:find(levelText, 1, true) then
			return i
		end
	end
	return nil
end
