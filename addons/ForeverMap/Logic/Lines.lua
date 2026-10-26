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

-- One name from a tooltip line, without its color and texture escapes and padding.
function ns.Lines.Clean(part)
	local name = part:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
	return name:match("^%s*(.-)%s*$")
end

-- Returns the known nodes named in one tooltip line, as a list of { name, gray }. A line can
-- hold several names, one per text line, each with its own color and texture escapes; r, g, b
-- is the line's own color, used for names without a color escape. Names not in ns.Nodes
-- (players, NPCs, "Peacebloom 3/8" quest progress) are left out, and each name comes once.
function ns.Lines.Parse(text, r, g, b)
	local found, seen = {}, {}
	for part in text:gmatch("[^\n]+") do
		local gray = ns.Lines.IsGray(r, g, b)
		local hexR, hexG, hexB = part:match("^%s*|c%x%x(%x%x)(%x%x)(%x%x)")
		if hexR then
			gray = ns.Lines.IsGray(tonumber(hexR, 16) / 255, tonumber(hexG, 16) / 255, tonumber(hexB, 16) / 255)
		end
		local name = ns.Lines.Clean(part)
		if ns.Nodes[name] and not seen[name] then
			seen[name] = true
			table.insert(found, { name = name, gray = gray })
		end
	end
	return found
end
