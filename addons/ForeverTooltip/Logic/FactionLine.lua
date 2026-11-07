local ADDON_NAME, ns = ...

-- Finds the "Alliance" / "Horde" line of a player tooltip. The tooltip data has no line type for it
-- (Enum.TooltipDataLineType has UnitLevel but no faction type), so it's matched by text: the whole
-- line must be the faction's localized name, from UnitFactionGroup. Pure string logic: no WoW API
-- calls. Examples (the reviewer's check, there is no test runner):
--   Find({ [2] = "Level 60 Orc", [3] = "Horde" }, "Horde", 2, 3) == 3
--   Find({ [2] = "<Horde Raiders>", [3] = "Horde" }, "Horde", 2, 3) == 3   (whole line only)
--   Find({ [2] = "|cffff2020Horde|r" }, "Horde", 2, 2) == 2                (colour code skipped)
--   Find({ [2] = "Horde PvP" }, "Horde", 2, 2) == nil
--   Find({ [2] = "A", [3] = nil }, "Horde", 2, 3) == nil
ns.FactionLine = {}

-- text without a leading |cAARRGGBB colour code and a trailing |r.
local function StripColor(text)
	return (text:gsub("^|c%x%x%x%x%x%x%x%x", ""):gsub("|r$", ""))
end

-- Index of the first of texts[first..last] that is exactly factionName, or nil. Entries may be nil.
function ns.FactionLine.Find(texts, factionName, first, last)
	for i = first, last do
		local text = texts[i]
		if text and StripColor(text) == factionName then
			return i
		end
	end
	return nil
end
