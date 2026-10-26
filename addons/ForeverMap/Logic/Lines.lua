local ADDON_NAME, ns = ...

-- Reading the minimap's mouseover tooltip. Pure functions: no client API, so a reviewer can
-- check them by reading (and they run outside the game).
ns.Lines = {}

-- Gray text in the minimap tooltip marks a node in a cave (a launch check). Normal node names
-- are white or colored, so "gray" means all three channels nearly equal and not bright.
function ns.Lines.IsGray(r, g, b)
	if not (r and g and b) then
		return false
	end
	local high, low = math.max(r, g, b), math.min(r, g, b)
	return high - low < 0.06 and high < 0.9
end

-- Escapes that can wrap a name: |cAARRGGBB and |cnNAME: colors, |r, |T...|t textures and
-- |A...|a atlases.
local ESCAPES = { "|c%x%x%x%x%x%x%x%x", "|cn[^:]*:", "|r", "|T.-|t", "|A.-|a" }

-- One text line of a tooltip line: the bare name, and whether its own color escape (if it has
-- one) is gray. A named color counts as gray when its name says so (GRAY_FONT_COLOR); its
-- value can't be read outside the client. Returns the name and true, false or nil (no escape).
function ns.Lines.Split(part)
	local gray
	local red, green, blue = part:match("|c%x%x(%x%x)(%x%x)(%x%x)")
	if red then
		gray = ns.Lines.IsGray(tonumber(red, 16) / 255, tonumber(green, 16) / 255, tonumber(blue, 16) / 255)
	else
		local colorName = part:match("|cn([^:]*):")
		if colorName then
			gray = colorName:find("GRAY") ~= nil
		end
	end
	local name = part
	for _, escape in ipairs(ESCAPES) do
		name = name:gsub(escape, "")
	end
	return name:match("^%s*(.-)%s*$"), gray
end

-- The known nodes named in one tooltip line, as a list of { name, gray }. A line can hold
-- several names, one per text line; r, g, b is the line's own color, used where a name has no
-- color escape. Names not in ns.Nodes (players, NPCs, "Peacebloom 3/8" quest progress) are
-- left out, and each name comes once.
function ns.Lines.Parse(text, r, g, b)
	local nodes, listed = {}, {}
	for part in text:gmatch("[^\n]+") do
		local name, gray = ns.Lines.Split(part)
		if gray == nil then
			gray = ns.Lines.IsGray(r, g, b)
		end
		if ns.Nodes[name] and not listed[name] then
			listed[name] = true
			table.insert(nodes, { name = name, gray = gray })
		end
	end
	return nodes
end
