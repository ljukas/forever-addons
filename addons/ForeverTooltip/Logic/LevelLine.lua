local ADDON_NAME, ns = ...

-- Text fallback for finding the "Level 60 Human Warrior" line of a unit tooltip, for when the
-- tooltip data doesn't tag it with Enum.TooltipDataLineType.UnitLevel (Colors.lua tries that
-- first). Built from the client's own UNIT_LEVEL_TEMPLATE rather than the English word "Level".
-- Pure string logic: no WoW API calls. Examples (the reviewer's check, there is no test runner):
--   LevelText("Level %d", 60) == "Level 60"
--   LevelText("Level %d", -1) == "Level ??"       (skull-level units)
--   LevelText("%d级", 12)     == "12级"
--   Find({ [2] = "<Horde>", [3] = "Level 60 Orc Shaman" }, "Level 60", 2, 3) == 3
--   Find({ [2] = "<Level 60 Club>", [3] = "Level 6 Orc" }, "Level 6", 2, 3) == 3  (line start only)
--   Find({ [2] = "Level 60 Orc" }, "Level 6", 2, 2) == nil       (a digit may not follow)
--   Find({ [2] = "|cffffffffLevel 6 Orc|r" }, "Level 6", 2, 2) == 2   (colour code skipped)
--   Find({ [2] = "A", [3] = "B" }, "Level 1", 2, 3) == nil
ns.LevelLine = {}

-- The level part of the line for a unit of this level. template is a %d format string.
function ns.LevelLine.LevelText(template, level)
	if level < 0 then
		return (template:gsub("%%d", "??"))
	end
	return template:format(level)
end

-- True when text starts with levelText (after an optional |cAARRGGBB colour code) and levelText
-- isn't followed by another digit, so "Level 6" doesn't match "Level 60".
local function StartsWithLevel(text, levelText)
	local start = text:match("^|c%x%x%x%x%x%x%x%x()") or 1
	if text:sub(start, start + #levelText - 1) ~= levelText then
		return false
	end
	return not text:sub(start + #levelText, start + #levelText):match("%d")
end

-- Index of the first of texts[first..last] that starts with levelText, or nil. Entries may be nil.
function ns.LevelLine.Find(texts, levelText, first, last)
	for i = first, last do
		local text = texts[i]
		if text and StartsWithLevel(text, levelText) then
			return i
		end
	end
	return nil
end
